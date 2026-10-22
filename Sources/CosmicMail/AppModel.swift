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
  @Published var newestFirst = true { didSet { scheduleSearch() } }
  @Published private(set) var searchUnreadable = 0
  @Published private(set) var searching = false
  private var displayedQuery = ""
  private var memoryMessages: [UUID: MailMessage] = [:]
  private var memoryRendered: [UUID: RenderedMail] = [:]
  private var memoryAttachments: [UUID: UUID] = [:]
  private var memoryOriginals: [UUID: Data] = [:]
  private var orderedCollection: UUID?
  @Published private var filteredEntries: [MessageEntry] = []
  @Published var showDetails = false
  @Published var selectionVersion = UUID()
  @Published private(set) var readRequest = UUID()
  @Published private(set) var readerFailed = false
  private let linkPopover = LinkPopoverPresenter()
  private var displayedCollection: UUID?
  private var displayedEntry: Int?
  var currentMessageReady: Bool {
    !reading && !readerFailed && message != nil && displayedCollection == selectedCollection
      && displayedEntry == selectedEntry
  }
  var mailListWidth: CGFloat = 305
  private var token: Cancellation?
  private var readToken: Cancellation?
  private var searchToken: Cancellation?
  private var searchTask: Task<Void, Never>?
  private var searchRefresh = false
  private var scopes: [URL: ScopedMailFile] = [:]
  private var openingID: UUID?
  private var preferredOpeningID: UUID?
  private var rememberedSelections: [UUID: Int] = [:]
  var active: MailCollection? { collections.first { $0.id == selectedCollection } }
  var entries: [MessageEntry] {
    orderedCollection == selectedCollection ? filteredEntries : active?.entries ?? []
  }
  var canExportOriginal: Bool {
    guard let id = selectedCollection, entry != nil else { return false }
    return memoryMessages[id] == nil || memoryOriginals[id] != nil
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
    guard let collectionID = selectedCollection else {
      filteredEntries = []
      orderedCollection = nil
      searchUnreadable = 0
      searching = false
      displayedQuery = ""
      return
    }
    if restart { searchUnreadable = 0 }
    if text != displayedQuery {
      filteredEntries = []
      orderedCollection = collectionID
      displayedQuery = text
    }
    searching = !text.isEmpty
    let operation = Cancellation()
    searchToken = operation
    searchTask = Task {
      do {
        try await Task.sleep(for: .milliseconds(restart ? 180 : 0))
        guard !operation.cancelled, selectedCollection == collectionID else { return }
        let values = active?.entries ?? []
        let result = try await ArchiveWork.search(
          values, query: text, newestFirst: newestFirst,
          scopes: Array(scopes.values), token: operation)
        guard !operation.cancelled, selectedCollection == collectionID else { return }
        filteredEntries = result.entries
        orderedCollection = collectionID
        searchUnreadable = result.unreadable
        searching = false
        searchTask = nil
        if searchRefresh { scheduleSearch(restart: false) }
      } catch {
        guard !operation.cancelled else { return }
        searchTask = nil
        searching = false
        self.error = errorText(error)
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
        let ext = source.url.pathExtension.lowercased()
        let kind =
          ["mbox", "mbx", "mbo"].contains(ext)
          ? "MBOX" : source.url.hasDirectoryPath ? "Maildir" : ext.uppercased()
        var placeholder = MailCollection(
          url: source.url, entries: [], kind: kind, isIndexing: true)
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
          if selectedCollection == id { scheduleSearch(restart: false) }
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
    } else if selectedCollection == collection.id {
      scheduleSearch(restart: false)
    }
  }
  private func releaseUnusedScopes() {
    let retained = Set(collections.map(\.url))
    scopes = scopes.filter { retained.contains($0.key) }
    let retainedIDs = Set(collections.map(\.id))
    rememberedSelections = rememberedSelections.filter { retainedIDs.contains($0.key) }
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
    let saved = id.flatMap { rememberedSelections[$0] }
    select(saved ?? active?.entries.first?.id)
  }
  func closeCollection(_ id: UUID) {
    guard let position = collections.firstIndex(where: { $0.id == id }) else { return }
    if openingID == id { cancel() }
    let wasSelected = selectedCollection == id
    collections.remove(at: position)
    rememberedSelections[id] = nil
    memoryMessages[id] = nil
    memoryOriginals[id] = nil
    memoryRendered[id] = nil
    memoryAttachments = memoryAttachments.filter { $0.value != id }
    if wasSelected {
      let next = collections.isEmpty ? nil : collections[min(position, collections.count - 1)].id
      selectCollection(next)
    }
    releaseUnusedScopes()
  }
  func select(_ id: Int?) {
    linkPopover.dismiss()
    if id == selectedEntry, currentMessageReady, error == nil { return }
    readToken?.cancel()
    selectedEntry = id
    if let collection = selectedCollection, let id { rememberedSelections[collection] = id }
    readRequest = UUID()
    guard let entry, entry.length <= Limits.message else {
      clearPresentation()
      reading = false
      return
    }
    if let id = selectedCollection, let mail = memoryMessages[id] {
      message = mail
      rendered = memoryRendered[id]
      displayedCollection = id
      displayedEntry = entry.id
      selectionVersion = UUID()
      showDetails = false
      reading = false
      readerFailed = false
      return
    }
    let operation = Cancellation()
    readToken = operation
    let collectionID = selectedCollection
    let scope = active.flatMap { scopes[$0.url] }
    reading = true
    Task {
      do {
        let result = try await ArchiveWork.read(entry, scope: scope, token: operation)
        guard !operation.cancelled else { return }
        // Keep the old presentation mounted during the read; publish a complete replacement.
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
          readerFailed = false
          message = result.0
          rendered = result.1
          displayedCollection = collectionID
          displayedEntry = entry.id
          selectionVersion = UUID()
          showDetails = false
          reading = false
        }
      } catch {
        guard !operation.cancelled else { return }
        clearPresentation()
        reading = false
        self.error = errorText(error)
      }
    }
  }
  func readingViewFailed(_ identity: UUID?, explanation: String) {
    guard identity == selectionVersion, message != nil, !reading else { return }
    readerFailed = true
    error = explanation
  }
  private func clearPresentation() {
    linkPopover.dismiss()
    readerFailed = false
    message = nil
    rendered = nil
    displayedCollection = nil
    displayedEntry = nil
    showDetails = false
    selectionVersion = UUID()
  }
  func receive(_ url: URL) {
    do {
      let captured = try MailtoCapture(url.absoluteString)
      cancel()
      capture = captured
      readToken?.cancel()
      reading = false
      clearPresentation()
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
    clearPresentation()
    capture = nil
    query = ""
    scopes = [:]
    rememberedSelections = [:]
    memoryMessages = [:]
    memoryOriginals = [:]
    memoryRendered = [:]
    memoryAttachments = [:]
  }
  func exportOriginal() {
    guard !reading, canExportOriginal, let entry else { return }
    let collectionID = selectedCollection
    let panel = NSSavePanel()
    panel.nameFieldStringValue =
      ["msg", "oft"].contains(entry.file.pathExtension.lowercased())
      ? entry.file.lastPathComponent
      : safeFilename(entry.subject.isEmpty ? "Message" : entry.subject) + ".eml"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do { try MailReader.validateDestination(url, protecting: collections.map(\.url)) } catch {
      self.error = errorText(error)
      return
    }
    if let id = collectionID, let data = memoryOriginals[id] {
      do { try data.write(to: url, options: .atomic) } catch { self.error = errorText(error) }
      return
    }
    let scope = active.flatMap { scopes[$0.url] }
    let operation = Cancellation()
    Task {
      do { try await ArchiveWork.export(entry, to: url, scope: scope, token: operation) } catch {
        self.error = errorText(error)
      }
    }
  }
  func previewAttachment(_ attachment: MailAttachment) {
    guard currentMessageReady, attachment.available, attachment.canPreview,
      message?.attachments.contains(where: { $0.id == attachment.id }) == true
    else { return }
    if let existing = memoryAttachments[attachment.id],
      collections.contains(where: { $0.id == existing })
    {
      selectCollection(existing)
      return
    }
    guard memoryMessages.count < 20 else {
      error = errorText(MailError.tooMany)
      return
    }
    let identity = selectionVersion
    let operation = Cancellation()
    Task {
      do {
        let result = try await ArchiveWork.attachment(attachment, token: operation)
        guard currentMessageReady, identity == selectionVersion else { return }
        let name = safeFilename(attachment.name)
        let url = URL(string: "cosmic-mail-message://" + UUID().uuidString + "/")!
          .appendingPathComponent(name)
        let mail = result.0
        let entry = MessageEntry(
          id: 0, subject: mail.subject, from: mail.from, date: mail.date,
          offset: 0, length: attachment.bytes.count, file: url, recipients: mail.to + " " + mail.cc,
          timestamp: MailDate.timestamp(mail.date))
        let collection = MailCollection(url: url, entries: [entry], kind: "Message")
        memoryMessages[collection.id] = mail
        memoryRendered[collection.id] = result.1
        memoryAttachments[attachment.id] = collection.id
        if attachment.embedded.isEmpty { memoryOriginals[collection.id] = attachment.bytes }
        collections.append(collection)
        selectCollection(collection.id)
      } catch { self.error = errorText(error) }
    }
  }
  func saveAttachment(_ attachment: MailAttachment) {
    guard currentMessageReady, attachment.available, attachment.embedded.isEmpty,
      message?.attachments.contains(where: { $0.id == attachment.id }) == true
    else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = safeFilename(attachment.name)
    if panel.runModal() == .OK, let url = panel.url {
      do {
        try MailReader.validateDestination(url, protecting: collections.map(\.url))
        try attachment.bytes.write(to: url, options: .atomic)
      } catch {
        self.error = errorText(error)
      }
    }
  }
  func external(
    _ raw: String, from identity: UUID, in view: NSView? = nil, at rectangle: NSRect = .zero
  ) {
    guard identity == selectionVersion, currentMessageReady, let view,
      let capture = CapturedMailLink(raw)
    else { return }
    linkPopover.show(capture, in: view, at: rectangle)
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
      case .unsafeDestination:
        return L(
          "Choose another destination to keep open source files unchanged.",
          "请选择其他保存位置，以保留正在打开的源文件。")
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
