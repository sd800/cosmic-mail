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
  @Published var query = ""
  @Published var showDetails = false
  @Published var selectionVersion = UUID()
  private var token: Cancellation?
  private var readGeneration = UUID()
  private var scopes: [URL] = []
  var active: MailCollection? { collections.first { $0.id == selectedCollection } }
  var entries: [MessageEntry] {
    let values = active?.entries ?? []
    if query.isEmpty { return values }
    return values.filter {
      $0.subject.localizedCaseInsensitiveContains(query)
        || $0.from.localizedCaseInsensitiveContains(query)
    }
  }
  var entry: MessageEntry? { active?.entries.first { $0.id == selectedEntry } }
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
    guard !urls.isEmpty else { return }
    token?.cancel()
    let operation = Cancellation()
    token = operation
    busy = true
    progress = 0
    error = nil
    let files = Array(urls.filter { $0.isFileURL }.prefix(20))
    for url in files { if url.startAccessingSecurityScopedResource() { scopes.append(url) } }
    Task {
      do {
        let result = try await Task.detached(priority: .userInitiated) {
          try files.map { url in
            try MailReader.collection(
              url, cancelled: { operation.cancelled },
              progress: { count in
                Task { @MainActor in if !operation.cancelled { self.progress = count } }
              })
          }
        }.value
        guard !operation.cancelled else { return }
        busy = false
        for collection in result {
          if let existing = collections.first(where: { $0.url == collection.url }) {
            collections.removeAll { $0.id == existing.id }
          }
          collections.append(collection)
        }
        if let first = result.first {
          selectedCollection = first.id
          query = ""
          capture = nil
          select(first.entries.first?.id)
        }
      } catch {
        guard !operation.cancelled else { return }
        busy = false
        self.error = errorText(error)
      }
    }
  }
  func cancel() {
    token?.cancel()
    busy = false
  }
  func selectCollection(_ id: UUID?) {
    selectedCollection = id
    capture = nil
    query = ""
    select(active?.entries.first?.id)
  }
  func select(_ id: Int?) {
    selectedEntry = id
    message = nil
    rendered = nil
    showDetails = false
    let run = UUID()
    readGeneration = run
    selectionVersion = run
    guard let entry else {
      reading = false
      return
    }
    reading = true
    Task {
      do {
        let result = try await Task.detached(priority: .userInitiated) {
          let mail = try MailReader.message(entry)
          return (mail, SafeHTML.render(mail))
        }.value
        guard readGeneration == run else { return }
        message = result.0
        rendered = result.1
        reading = false
      } catch {
        guard readGeneration == run else { return }
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
      readGeneration = UUID()
      reading = false
      message = nil
      rendered = nil
      selectedCollection = nil
      selectedEntry = nil
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
    readGeneration = UUID()
    collections = []
    selectedCollection = nil
    selectedEntry = nil
    message = nil
    rendered = nil
    capture = nil
    query = ""
    for url in scopes { url.stopAccessingSecurityScopedResource() }
    scopes = []
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
          "This file exceeds the safe reading limit (32 MB per message, 1 GB per archive).",
          "文件超过安全读取上限（单封邮件 32 MB、存档 1 GB）。")
      case .unsupported:
        return L(
          "Choose an EML, EMLX, MSG/OFT, MBOX/MBX, or Maildir file.",
          "请选择 EML、EMLX、MSG/OFT、MBOX/MBX 或 Maildir 文件。")
      case .tooMany:
        return L(
          "This file contains more messages or parts than can be opened safely.",
          "文件包含过多邮件或 MIME 部分，无法安全打开。")
      case .cancelled: return L("Opening cancelled.", "已取消打开。")
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
