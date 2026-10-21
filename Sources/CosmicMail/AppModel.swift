import AppKit
import MailCore
import SwiftUI
import UniformTypeIdentifiers

final class Cancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var stopped = false
  func cancel() {
    lock.lock()
    stopped = true
    lock.unlock()
  }
  var cancelled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return stopped
  }
}
@MainActor final class AppModel: ObservableObject {
  static let shared = AppModel()
  @Published var collections: [MailCollection] = []
  @Published var selectedCollection: UUID?
  @Published var selectedEntry: Int?
  @Published var capture: MailtoCapture?
  @Published var message: MailMessage?
  @Published var rendered: RenderedMail?
  @Published var error: String?
  @Published var busy = false
  @Published var reading = false
  @Published var progress = 0
  @Published var query = "" { didSet { scheduleSearch() } }
  @Published private var filteredEntries: [MessageEntry] = []
  @Published var showDetails = false
  @Published var selectionVersion = UUID()
  var mailListWidth: CGFloat = 310
  private var token: Cancellation?
  private var readToken: Cancellation?
  private var searchToken: Cancellation?
  private var searchTask: Task<Void, Never>?
  private var searchRefresh = false
  private var scopes: [URL: ScopedMailFile] = [:]
  private var openingID: UUID?
  private var preferredOpeningID: UUID?
  var active: MailCollection? { collections.first { $0.id == selectedCollection } }
  var entries: [MessageEntry] {
    query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? active?.entries ?? [] : filteredEntries
  }
  var entry: MessageEntry? {
    guard let values = active?.entries, let id = selectedEntry, values.indices.contains(id),
      values[id].id == id
    else { return nil }
    return values[id]
  }
  private func scheduleSearch(restart: Bool = true) {
    if !restart, searchTask != nil {
      searchRefresh = true
      return
    }
    searchToken?.cancel()
    searchTask?.cancel()
    searchTask = nil
    searchRefresh = false
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, let collectionID = selectedCollection else {
      filteredEntries = []
      return
    }
    if restart { filteredEntries = [] }
    let operation = Cancellation()
    searchToken = operation
    searchTask = Task {
      do {
        try await Task.sleep(for: .milliseconds(restart ? 180 : 0))
        guard !operation.cancelled, selectedCollection == collectionID else { return }
        let values = active?.entries ?? []
        let result = try await ArchiveWork.search(values, query: text, token: operation)
        guard !operation.cancelled, selectedCollection == collectionID else { return }
        filteredEntries = result
        searchTask = nil
        if searchRefresh { scheduleSearch(restart: false) }
      } catch {
        guard !operation.cancelled else { return }
        searchTask = nil
      }
    }
  }
  func chooseFiles() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.prompt = L("Open", "打开")
    panel.message = L(
      "Choose email files, a mailbox archive, or a Maildir folder.", "选择邮件文件、邮箱存档或 Maildir 文件夹。")
    panel.allowedContentTypes = MailReader.extensions.compactMap { UTType(filenameExtension: $0) }
    if panel.runModal() == .OK { open(panel.urls) }
  }
  func open(_ urls: [URL]) {
    for url in urls.prefix(20) {
      if url.scheme?.lowercased() == "mailto" {
        receive(url)
        return
      }
    }
    var seen = Set<URL>()
    let files = Array(urls.filter { $0.isFileURL && seen.insert($0).inserted }.prefix(20))
    guard !files.isEmpty else { return }
    cancel()
    let operation = Cancellation()
    token = operation
    busy = true
    progress = 0
    error = nil
    // Scope lifetime follows collections and worker tasks, including cancellation/close races.
    let sources = files.map { scopes[$0] ?? ScopedMailFile($0) }
    Task { [self] in
      var failures: [String] = []
      for (position, source) in sources.enumerated() {
        guard !operation.cancelled else { break }
        if let existing = collections.first(where: { $0.url == source.url }),
          await ArchiveWork.isCurrent(existing, scope: source, token: operation)
        {
          guard !operation.cancelled else { break }
          if position == 0 { selectCollection(existing.id) }
          continue
        }
        guard !operation.cancelled else { break }
        let available =
          Limits.indexBytes
          - collections.filter { $0.url != source.url }
          .reduce(0) { $0 + $1.metadataBytes }
        guard available > 0 else {
          failures.append(L("Close an archive to free index memory.", "请关闭存档以释放索引内存。"))
          break
        }
        var placeholder = MailCollection(
          url: source.url, entries: [], kind: source.url.pathExtension.uppercased(),
          isIndexing: true)
        if placeholder.kind.isEmpty { placeholder.kind = "Maildir" }
        let stub = placeholder
        let id = stub.id
        openingID = id
        if position == 0 { preferredOpeningID = id }
        let delivery = IndexDelivery { [weak self] values in
          guard let self, self.token === operation, !operation.cancelled else { return }
          self.receiveBatch(values, collection: stub, scope: source)
        }
        do {
          var collection = try await ArchiveWork.index(
            source, limits: IndexLimits(bytes: available), token: operation, delivery: delivery)
          delivery.flush()
          guard !operation.cancelled else { break }
          collection.id = id
          // Reuse the accumulated array; never republish a full snapshot for each batch.
          if let existing = collections.firstIndex(where: { $0.id == id }) {
            collections[existing].isIndexing = false
            collections[existing].kind = collection.kind
            collections[existing].indexLimitReached = collection.indexLimitReached
          } else {
            collections.removeAll { $0.url == collection.url }
            collections.append(collection)
            scopes[source.url] = source
          }
          if preferredOpeningID == id {
            preferredOpeningID = nil
            selectedCollection = id
            capture = nil
            query = ""
            select(collection.entries.first?.id)
          }
        } catch {
          delivery.flush()
          guard !operation.cancelled else { break }
          if let existing = collections.firstIndex(where: { $0.id == id }) {
            collections[existing].isIndexing = false
            collections[existing].indexInterrupted = true
          }
          failures.append(source.url.lastPathComponent + ": " + errorText(error))
        }
      }
      guard token === operation else { return }
      busy = false
      openingID = nil
      preferredOpeningID = nil
      releaseUnusedScopes()
      if !operation.cancelled, !failures.isEmpty { error = failures.joined(separator: "\n\n") }
    }
  }
  private func receiveBatch(
    _ values: [MessageEntry], collection: MailCollection, scope: ScopedMailFile
  ) {
    let replacesSelection = collections.contains {
      $0.url == collection.url && $0.id != collection.id && $0.id == selectedCollection
    }
    if !collections.contains(where: { $0.id == collection.id }) {
      collections.removeAll { $0.url == collection.url }
      collections.append(collection)
      scopes[collection.url] = scope
    }
    guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
    collections[index].entries.append(contentsOf: values)
    collections[index].metadataBytes += values.reduce(0) { $0 + $1.metadataBytes }
    progress = collections[index].entries.count
    if preferredOpeningID == collection.id || replacesSelection {
      preferredOpeningID = nil
      selectedCollection = collection.id
      capture = nil
      query = ""
      select(values.first?.id)
    } else if selectedCollection == collection.id, !query.isEmpty {
      scheduleSearch(restart: false)
    }
  }
  private func releaseUnusedScopes() {
    let retained = Set(collections.map(\.url))
    scopes = scopes.filter { retained.contains($0.key) }
  }
  func cancel() {
    token?.cancel()
    if let index = collections.firstIndex(where: { $0.id == openingID }) {
      collections[index].isIndexing = false
      collections[index].indexInterrupted = true
    }
    preferredOpeningID = nil
    openingID = nil
    busy = false
  }
  func selectCollection(_ id: UUID?) {
    preferredOpeningID = nil
    selectedCollection = id
    capture = nil
    query = ""
    select(active?.entries.first?.id)
  }
  func select(_ id: Int?) {
    readToken?.cancel()
    selectedEntry = id
    message = nil
    rendered = nil
    showDetails = false
    selectionVersion = UUID()
    guard let entry, entry.length <= Limits.message else {
      reading = false
      return
    }
    let operation = Cancellation()
    readToken = operation
    let scope = active.flatMap { scopes[$0.url] }
    reading = true
    Task {
      do {
        let result = try await ArchiveWork.read(entry, scope: scope, token: operation)
        guard !operation.cancelled else { return }
        message = result.0
        rendered = result.1
        reading = false
      } catch {
        guard !operation.cancelled else { return }
        reading = false
        self.error = errorText(error)
      }
    }
  }
  func receive(_ url: URL) {
    do {
      let captured = try MailtoCapture(url.absoluteString)
      cancel()
      capture = captured
      readToken?.cancel()
      reading = false
      message = nil
      rendered = nil
      selectedCollection = nil
      selectedEntry = nil
      query = ""
      showDetails = false
      NSApp.activate(ignoringOtherApps: true)
      NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    } catch { self.error = errorText(error) }
  }
  func closeAll() {
    cancel()
    reading = false
    showDetails = false
    error = nil
    progress = 0
    readToken?.cancel()
    collections = []
    selectedCollection = nil
    selectedEntry = nil
    message = nil
    rendered = nil
    capture = nil
    query = ""
    scopes = [:]
  }
  func exportOriginal() {
    guard let entry else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue =
      ["msg", "oft"].contains(entry.file.pathExtension.lowercased())
      ? entry.file.lastPathComponent
      : safeFilename(entry.subject.isEmpty ? "Message" : entry.subject) + ".eml"
    if panel.runModal() == .OK, let url = panel.url {
      do {
        let data = try MailReader.original(entry)
        try data.write(to: url, options: .atomic)
      } catch { self.error = errorText(error) }
    }
  }
  func saveAttachment(_ attachment: MailAttachment) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = safeFilename(attachment.name)
    if panel.runModal() == .OK, let url = panel.url {
      do { try attachment.bytes.write(to: url, options: .atomic) } catch {
        self.error = errorText(error)
      }
    }
  }
  func external(_ raw: String) {
    guard let safe = SafeHTML.safeLink(raw), let url = URL(string: safe) else { return }
    if url.scheme?.lowercased() == "mailto" {
      receive(url)
      return
    }
    let alert = NSAlert()
    alert.messageText = L("Open this link?", "打开此链接？")
    alert.informativeText = String(safe.prefix(2048))
    alert.addButton(withTitle: L("Copy link", "复制链接"))
    let web = ["https", "http"].contains(url.scheme?.lowercased() ?? "")
    if web { alert.addButton(withTitle: L("Open in browser", "在浏览器中打开")) }
    alert.addButton(withTitle: L("Cancel", "取消"))
    let result = alert.runModal()
    if result == .alertFirstButtonReturn {
      copyText(safe)
    } else if web && result == .alertSecondButtonReturn {
      NSWorkspace.shared.open(url)
    }
  }
  func errorText(_ error: Error) -> String {
    if let mail = error as? MailError {
      switch mail {
      case .tooLarge:
        return L(
          "This message exceeds the 32 MiB reading or parsing limit. Other archive messages remain available.",
          "这封邮件超过 32 MiB 读取或解析上限，不影响存档中的其他邮件。")
      case .unsupported:
        return L(
          "Choose an EML, EMLX, MSG/OFT, MBOX/MBX, or Maildir file.",
          "请选择 EML、EMLX、MSG/OFT、MBOX/MBX 或 Maildir 文件。")
      case .tooMany:
        return L(
          "This file contains more messages or parts than can be opened safely.",
          "文件包含过多邮件或 MIME 部分，无法安全打开。")
      case .cancelled: return L("Opening cancelled.", "已取消打开。")
      case .sourceChanged:
        return L(
          "The source file changed. Reopen it to update the message list.",
          "源文件已发生变化，请重新打开以更新邮件列表。")
      case .malformed:
        return L(
          "This file could not be read. Check that it is a complete, supported email file.",
          "未能读取文件，请确认它是完整且受支持的邮件文件。")
      }
    }
    return L(
      "Could not read or save the file. Check its location and access permissions.",
      "未能读取或保存文件，请检查位置及访问权限。")
  }
}
