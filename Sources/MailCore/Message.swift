import Foundation

public enum MailError: Error, LocalizedError, Equatable {
  case tooLarge, malformed, unsupported, tooMany, cancelled, sourceChanged
  public var errorDescription: String? {
    switch self {
    case .tooLarge: return "The file exceeds the safe reading limit."
    case .malformed: return "This file could not be read as a supported email."
    case .unsupported: return "This file format is not supported."
    case .tooMany: return "This archive contains too many messages to open safely."
    case .cancelled: return "Opening was cancelled."
    case .sourceChanged: return "The source file changed. Reopen it to update the index."
    }
  }
}
public enum Limits {
  public static let message = 32 * 1024 * 1024
  public static let messages = 200_000
  public static let indexBytes = 64 * 1024 * 1024
  public static let headers = 256 * 1024
  public static let parts = 500
  public static let rendered = 4 * 1024 * 1024
}
public struct Header: Sendable, Equatable {
  public var name: String
  public var value: String
}
public struct MailAttachment: Identifiable, Sendable {
  public var id = UUID()
  public var name: String
  public var type: String
  public var bytes: Data
  public var contentID: String
}
public struct MailMessage: Sendable {
  public var subject: String = ""
  public var from: String = ""
  public var to: String = ""
  public var cc: String = ""
  public var date: String = ""
  public var plain: String = ""
  public var html: String = ""
  public var headers: [Header] = []
  public var attachments: [MailAttachment] = []
  public init() {}
  public var summary: String {
    plain.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
public struct MessageEntry: Identifiable, Sendable {
  public var id: Int
  public var subject: String
  public var from: String
  public var date: String
  public var offset: UInt64
  public var length: Int
  public var file: URL
  public var revision: FileRevision? = nil
  public var metadataBytes: Int {
    MemoryLayout<Self>.stride + 160 + subject.utf8.count + from.utf8.count + date.utf8.count
  }
}
public struct MailCollection: Identifiable, Sendable {
  public var id = UUID()
  public var url: URL
  public var entries: [MessageEntry]
  public var kind: String
  public var isIndexing = false
  public var indexInterrupted = false
  public var indexLimitReached = false
  public var metadataBytes: Int = 0
  public init(
    url: URL, entries: [MessageEntry], kind: String, isIndexing: Bool = false,
    indexInterrupted: Bool = false, indexLimitReached: Bool = false, metadataBytes: Int = 0
  ) {
    self.url = url
    self.entries = entries
    self.kind = kind
    self.isIndexing = isIndexing
    self.indexInterrupted = indexInterrupted
    self.indexLimitReached = indexLimitReached
    self.metadataBytes = metadataBytes
  }
}

/// A bounded in-memory index; tests can lower these budgets without making large fixtures.
public struct IndexLimits: Sendable {
  public var messages: Int
  public var bytes: Int
  public init(messages: Int = Limits.messages, bytes: Int = Limits.indexBytes) {
    self.messages = max(0, min(messages, Limits.messages))
    self.bytes = max(0, min(bytes, Limits.indexBytes))
  }
}

public enum MailSearch {
  public static func matching(
    _ entries: [MessageEntry], query: String, cancelled: () -> Bool = { false }
  ) throws -> [MessageEntry] {
    let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return entries }
    var result: [MessageEntry] = []
    for (position, entry) in entries.enumerated() {
      if position % 128 == 0, cancelled() { throw MailError.cancelled }
      if entry.subject.localizedCaseInsensitiveContains(text)
        || entry.from.localizedCaseInsensitiveContains(text)
      {
        result.append(entry)
      }
    }
    if cancelled() { throw MailError.cancelled }
    return result
  }
}
public struct MailtoCapture: Sendable, Equatable {
  public var to: String = ""
  public var cc: String = ""
  public var bcc: String = ""
  public var subject: String = ""
  public var body: String = ""
  public var original: String
  public init(_ raw: String) throws {
    guard raw.utf8.count <= 128 * 1024, raw.lowercased().hasPrefix("mailto:") else {
      throw MailError.malformed
    }
    original = raw
    let payload = String(raw.dropFirst(7))
    let pieces = payload.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    func decode(_ value: String) -> String {
      (value.removingPercentEncoding ?? value).replacingOccurrences(of: "\0", with: "")
    }
    to = decode(String(pieces.first ?? ""))
    if pieces.count > 1 {
      for item in pieces[1].split(separator: "&", omittingEmptySubsequences: false) {
        let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let key = decode(String(pair.first ?? "")).lowercased()
        let value = decode(pair.count > 1 ? String(pair[1]) : "")
        switch key {
        case "to": to += (to.isEmpty ? "" : ", ") + value
        case "cc": cc += (cc.isEmpty ? "" : ", ") + value
        case "bcc": bcc += (bcc.isEmpty ? "" : ", ") + value
        case "subject": subject = value
        case "body": body = value
        default: break
        }
      }
    }
    for key in [\Self.to, \.cc, \.bcc, \.subject] {
      self[keyPath: key] = self[keyPath: key].replacingOccurrences(
        of: "[\\r\\n]+", with: " ", options: .regularExpression)
    }
  }
  public var text: String {
    [("To", to), ("Cc", cc), ("Bcc", bcc), ("Subject", subject)].filter { !$0.1.isEmpty }.map {
      "\($0.0): \($0.1)"
    }.joined(separator: "\n") + (body.isEmpty ? "" : "\n\n" + body)
  }
}
public func safeFilename(_ name: String) -> String {
  let value = name.components(
    separatedBy: CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
  ).joined(separator: "_")
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  return String(
    (trimmed.isEmpty || trimmed == "." || trimmed == ".." ? "Attachment" : trimmed).prefix(180))
}
