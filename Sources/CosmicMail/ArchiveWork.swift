import Foundation
import MailCore

/// An opened document and in-flight reads share one balanced security scope.
final class ScopedMailFile: @unchecked Sendable {
  let url: URL
  private let accessed: Bool
  init(_ url: URL) {
    self.url = url
    accessed = url.startAccessingSecurityScopedResource()
  }
  deinit { if accessed { url.stopAccessingSecurityScopedResource() } }
}

/// Coalesces deltas into one pending main-actor delivery, rather than queuing a snapshot per mail.
final class IndexDelivery: @unchecked Sendable {
  private let lock = NSLock()
  private var pending: [MessageEntry] = []
  private var scheduled = false
  private let receive: @MainActor @Sendable ([MessageEntry]) -> Void
  init(receive: @escaping @MainActor @Sendable ([MessageEntry]) -> Void) { self.receive = receive }
  func push(_ entries: [MessageEntry]) {
    lock.lock()
    pending.append(contentsOf: entries)
    let start = !scheduled
    scheduled = true
    lock.unlock()
    if start { Task { @MainActor in self.flush() } }
  }
  @MainActor func flush() {
    lock.lock()
    let values = pending
    pending = []
    scheduled = false
    lock.unlock()
    if !values.isEmpty { receive(values) }
  }
}

/// Serial lanes bound simultaneous parse/index/search work; cancelled queued work exits immediately.
enum ArchiveWork {
  private static let indexing = DispatchQueue(
    label: "org.songming.cosmic-mail.index", qos: .userInitiated)
  private static let reading = DispatchQueue(
    label: "org.songming.cosmic-mail.read", qos: .userInitiated)
  private static let searching = DispatchQueue(
    label: "org.songming.cosmic-mail.search", qos: .userInitiated)
  static func index(
    _ source: ScopedMailFile, limits: IndexLimits, token: Cancellation, delivery: IndexDelivery
  ) async throws -> MailCollection {
    try await withCheckedThrowingContinuation { continuation in
      indexing.async {
        continuation.resume(
          with: Result {
            try withExtendedLifetime(source) {
              try MailReader.collection(
                source.url, cancelled: { token.cancelled }, limits: limits,
                batch: { delivery.push($0) })
            }
          })
      }
    }
  }
  static func isCurrent(_ collection: MailCollection, scope: ScopedMailFile, token: Cancellation)
    async -> Bool
  {
    await withCheckedContinuation { continuation in
      indexing.async {
        let current = withExtendedLifetime(scope) {
          !token.cancelled && MailReader.isCurrent(collection)
        }
        continuation.resume(returning: current)
      }
    }
  }
  static func read(
    _ entry: MessageEntry, scope: ScopedMailFile?, token: Cancellation
  ) async throws -> (MailMessage, RenderedMail) {
    try await withCheckedThrowingContinuation { continuation in
      reading.async {
        continuation.resume(
          with: Result {
            try withExtendedLifetime(scope) {
              if token.cancelled { throw MailError.cancelled }
              let mail = try MailReader.message(entry, cancelled: { token.cancelled })
              if token.cancelled { throw MailError.cancelled }
              let rendered = SafeHTML.render(mail)
              if token.cancelled { throw MailError.cancelled }
              return (mail, rendered)
            }
          })
      }
    }
  }
  static func attachment(_ attachment: MailAttachment, token: Cancellation) async throws -> (
    MailMessage, RenderedMail
  ) {
    try await withCheckedThrowingContinuation { continuation in
      reading.async {
        continuation.resume(
          with: Result {
            if token.cancelled { throw MailError.cancelled }
            let mail: MailMessage
            if let embedded = attachment.embedded.first {
              mail = embedded
            } else if attachment.type.lowercased() == "application/vnd.ms-outlook"
              || ["msg", "oft"].contains((attachment.name as NSString).pathExtension.lowercased())
            {
              mail = try Outlook.parse(attachment.bytes)
            } else {
              mail = try MIME.parse(attachment.bytes, cancelled: { token.cancelled })
            }
            let rendered = SafeHTML.render(mail)
            if token.cancelled { throw MailError.cancelled }
            return (mail, rendered)
          })
      }
    }
  }
  static func export(
    _ entry: MessageEntry, to destination: URL, scope: ScopedMailFile?, token: Cancellation
  ) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      reading.async {
        continuation.resume(
          with: Result {
            try withExtendedLifetime(scope) {
              try MailReader.exportOriginal(entry, to: destination, cancelled: { token.cancelled })
            }
          })
      }
    }
  }
  static func search(
    _ entries: [MessageEntry], query: String, newestFirst: Bool, scopes: [ScopedMailFile],
    token: Cancellation
  ) async throws -> MailSearch.Results {
    try await withCheckedThrowingContinuation { continuation in
      searching.async {
        continuation.resume(
          with: Result {
            if token.cancelled { throw MailError.cancelled }
            return try withExtendedLifetime(scopes) {
              var result = try MailSearch.scan(
                entries, query: query, cancelled: { token.cancelled })
              if token.cancelled { throw MailError.cancelled }
              result.entries = MailSearch.ordered(result.entries, newestFirst: newestFirst)
              if token.cancelled { throw MailError.cancelled }
              return result
            }
          })
      }
    }
  }
}
