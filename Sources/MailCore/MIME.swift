import CoreFoundation
import Foundation

public enum MIME {
  public static func decode(_ bytes: Data, charset: String = "utf-8") -> String {
    let cf = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
    if cf != kCFStringEncodingInvalidId {
      let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
      if let text = String(data: bytes, encoding: encoding) { return text }
    }
    return String(data: bytes, encoding: .utf8) ?? String(data: bytes, encoding: .windowsCP1252)
      ?? String(decoding: bytes, as: UTF8.self)
  }
  public static func quotedPrintable(_ data: Data, header: Bool = false) -> Data {
    let bytes = [UInt8](data)
    var out = Data()
    var i = 0
    func hex(_ b: UInt8) -> UInt8? {
      switch b {
      case 48...57: return b - 48
      case 65...70: return b - 55
      case 97...102: return b - 87
      default: return nil
      }
    }
    while i < bytes.count {
      if header && bytes[i] == 95 {
        out.append(32)
        i += 1
        continue
      }
      if bytes[i] == 61 {
        if i + 1 < bytes.count && bytes[i + 1] == 10 {
          i += 2
          continue
        }
        if i + 2 < bytes.count && bytes[i + 1] == 13 && bytes[i + 2] == 10 {
          i += 3
          continue
        }
        if i + 2 < bytes.count, let a = hex(bytes[i + 1]), let b = hex(bytes[i + 2]) {
          out.append(a * 16 + b)
          i += 3
          continue
        }
      }
      out.append(bytes[i])
      i += 1
    }
    return out
  }
  private static let encodedWords = try! NSRegularExpression(
    pattern: "=\\?([^?\\s]+)\\?([bBqQ])\\?([^?]*)\\?=")
  public static func headerText(_ value: String) -> String {
    let ns = value as NSString
    let matches = encodedWords.matches(in: value, range: NSRange(location: 0, length: ns.length))
    var output = ""
    var cursor = 0
    var previousEncoded = false
    for match in matches {
      let gap = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
      if !previousEncoded || !gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        output += gap
      }
      let encoded = ns.substring(with: match.range(at: 3))
      let mode = ns.substring(with: match.range(at: 2)).lowercased()
      let bytes =
        mode == "b"
        ? Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
        : quotedPrintable(Data(encoded.utf8), header: true)
      output +=
        bytes.map { decode($0, charset: ns.substring(with: match.range(at: 1))) }
        ?? ns.substring(with: match.range)
      cursor = match.range.location + match.range.length
      previousEncoded = true
    }
    output += ns.substring(from: cursor)
    return output
  }
  public static func split(_ data: Data) -> (headers: [Header], body: Data) {
    let crlf = data.range(of: Data([13, 10, 13, 10]))
    let lf = data.range(of: Data([10, 10]))
    let separator = [crlf, lf].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound }
    let end = min(
      separator?.lowerBound ?? data.endIndex, data.startIndex + min(data.count, Limits.headers))
    let raw = decode(Data(data[data.startIndex..<end])).replacingOccurrences(of: "\r\n", with: "\n")
    var fields: [Header] = []
    for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
      if line.hasPrefix(" ") || line.hasPrefix("\t") {
        if !fields.isEmpty {
          fields[fields.count - 1].value += " " + line.trimmingCharacters(in: .whitespaces)
        }
        continue
      }
      guard let colon = line.firstIndex(of: ":"), fields.count < 2000 else { continue }
      let name = String(line[..<colon])
      guard !name.isEmpty, name.utf8.allSatisfy({ $0 > 32 && $0 < 127 }) else { continue }
      fields.append(
        Header(
          name: name,
          value: String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)))
    }
    return (fields, separator.map { Data(data[$0.upperBound...]) } ?? Data())
  }
  public static func value(_ name: String, in fields: [Header]) -> String {
    fields.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
  }
  public static func parameter(_ key: String, in value: String) -> String? {
    let regex = try! NSRegularExpression(
      pattern: "(?:^|;)\\s*" + NSRegularExpression.escapedPattern(for: key)
        + "\\s*=\\s*(?:\"((?:[^\"\\\\]|\\\\.)*)\"|([^;\\s]+))", options: .caseInsensitive)
    let ns = value as NSString
    guard let m = regex.firstMatch(in: value, range: NSRange(location: 0, length: ns.length)) else {
      return nil
    }
    return ns.substring(with: m.range(at: m.range(at: 1).location != NSNotFound ? 1 : 2))
      .replacingOccurrences(of: "\\\"", with: "\"")
  }
  static func filename(_ fields: [Header]) -> String {
    let disposition = value("Content-Disposition", in: fields)
    let type = value("Content-Type", in: fields)
    for source in [disposition, type] {
      for key in ["filename*", "name*"] {
        if let v = parameter(key, in: source) {
          let bits = v.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
          if bits.count == 3 {
            return safeFilename(String(bits[2]).removingPercentEncoding ?? String(bits[2]))
          }
        }
      }
      for key in ["filename", "name"] {
        if let v = parameter(key, in: source) { return safeFilename(headerText(v)) }
      }
    }
    return ""
  }
  public static func parse(_ data: Data, cancelled: () -> Bool = { false }) throws -> MailMessage {
    if cancelled() { throw MailError.cancelled }
    guard data.count <= Limits.message else { throw MailError.tooLarge }
    let envelope = split(data)
    guard !envelope.headers.isEmpty else { throw MailError.malformed }
    var message = MailMessage()
    message.headers = envelope.headers
    message.subject = headerText(value("Subject", in: envelope.headers))
    message.from = headerText(value("From", in: envelope.headers))
    message.to = headerText(value("To", in: envelope.headers))
    message.cc = headerText(value("Cc", in: envelope.headers))
    message.date = value("Date", in: envelope.headers)
    var count = 0
    var budget = 96 * 1024 * 1024
    try part(
      data, depth: 0, count: &count, budget: &budget, message: &message, cancelled: cancelled)
    return message
  }
  static func part(
    _ data: Data, depth: Int, count: inout Int, budget: inout Int, message: inout MailMessage,
    cancelled: () -> Bool
  ) throws {
    if cancelled() { throw MailError.cancelled }
    budget -= data.count
    guard budget >= 0 else { throw MailError.tooLarge }
    count += 1
    guard depth <= 16, count <= Limits.parts else { throw MailError.tooMany }
    let (fields, raw) = split(data)
    let contentType = value("Content-Type", in: fields)
    let type =
      contentType.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased()
      ?? "text/plain"
    let disposition = value("Content-Disposition", in: fields).lowercased()
    let name = filename(fields)
    if type.hasPrefix("multipart/"), let boundary = parameter("boundary", in: contentType),
      !boundary.isEmpty, boundary.utf8.count < 200
    {
      let marker = Data(("--" + boundary).utf8)
      var start: Int?
      var position = raw.startIndex
      while position < raw.endIndex {
        if cancelled() { throw MailError.cancelled }
        let lineEnd = raw[position...].firstIndex(of: 10).map { $0 + 1 } ?? raw.endIndex
        let line = raw[position..<lineEnd]
        if line.starts(with: marker) {
          let suffix = line.dropFirst(marker.count)
          if suffix.starts(with: [45, 45]) || suffix.allSatisfy({ [32, 9, 10, 13].contains($0) }) {
            if let begin = start, begin < position {
              var end = position
              if end > begin && raw[end - 1] == 10 { end -= 1 }
              if end > begin && raw[end - 1] == 13 { end -= 1 }
              try part(
                Data(raw[begin..<end]), depth: depth + 1, count: &count, budget: &budget,
                message: &message, cancelled: cancelled)
            }
            if suffix.starts(with: [45, 45]) { return }
            start = lineEnd
          }
        }
        position = lineEnd
      }
      if let begin = start, begin < raw.endIndex {
        try part(
          Data(raw[begin...]), depth: depth + 1, count: &count, budget: &budget, message: &message,
          cancelled: cancelled)
      }
      return
    }
    let transfer = value("Content-Transfer-Encoding", in: fields).lowercased()
    let bytes =
      transfer == "base64"
      ? (Data(base64Encoded: raw, options: .ignoreUnknownCharacters) ?? Data())
      : transfer == "quoted-printable" ? quotedPrintable(raw) : raw
    let cid = value("Content-ID", in: fields).trimmingCharacters(
      in: CharacterSet(charactersIn: "<> "))
    if !name.isEmpty || disposition.hasPrefix("attachment")
      || (!type.hasPrefix("text/") && !type.isEmpty)
    {
      message.attachments.append(
        MailAttachment(
          name: name.isEmpty ? "Attachment" : name, type: type, bytes: bytes, contentID: cid))
      return
    }
    let text = decode(bytes, charset: parameter("charset", in: contentType) ?? "utf-8")
    if type == "text/html" {
      if message.html.isEmpty { message.html = String(text.prefix(Limits.rendered)) }
    } else if type == "text/plain" || type.isEmpty {
      if !message.plain.isEmpty { message.plain += "\n\n" }
      message.plain += String(text.prefix(max(0, Limits.rendered - message.plain.utf8.count)))
    }
  }
}
