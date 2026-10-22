import CoreFoundation
import Foundation

public enum MIME {
  public static func decode(_ bytes: Data, charset: String = "utf-8") -> String {
    MailEncoding.decode(bytes, charset: charset)
  }
  public static func decodeHTML(_ bytes: Data, charset: String? = nil) -> String {
    if bytes.starts(with: [0xff, 0xfe]) { return decode(bytes.dropFirst(2), charset: "utf-16le") }
    if bytes.starts(with: [0xfe, 0xff]) { return decode(bytes.dropFirst(2), charset: "utf-16be") }
    if bytes.starts(with: [0xef, 0xbb, 0xbf]) { return decode(bytes.dropFirst(3)) }
    let prefix = String(decoding: bytes.prefix(8192), as: UTF8.self)
    let declared = charset?.trimmingCharacters(in: .whitespacesAndNewlines)
    let meta = try! NSRegularExpression(
      pattern: #"(?i)<meta\b[^>]{0,1024}\bcharset\s*=\s*["']?\s*([a-zA-Z0-9._-]+)"#)
    let match = meta.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix))
    let hint = match.map { (prefix as NSString).substring(with: $0.range(at: 1)) }
    return decode(bytes, charset: declared.flatMap { $0.isEmpty ? nil : $0 } ?? hint ?? "utf-8")
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
    var pending = Data()
    var pendingCharset: String?
    func flush() {
      if let charset = pendingCharset { output += decode(pending, charset: charset) }
      pending.removeAll(keepingCapacity: true)
      pendingCharset = nil
    }
    var previousEncoded = false
    for match in matches {
      let gap = ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
      let adjacent = previousEncoded && gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      let charset = ns.substring(with: match.range(at: 1)).lowercased()
      if !adjacent || pendingCharset != charset { flush() }
      if !adjacent { output += gap }
      let encoded = ns.substring(with: match.range(at: 3))
      let mode = ns.substring(with: match.range(at: 2)).lowercased()
      let bytes =
        mode == "b"
        ? Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
        : quotedPrintable(Data(encoded.utf8), header: true)
      if let bytes {
        pendingCharset = charset
        pending.append(bytes)
      } else {
        flush()
        output += ns.substring(with: match.range)
      }
      cursor = match.range.location + match.range.length
      previousEncoded = bytes != nil
    }
    flush()
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
  private static let parameterPattern = try! NSRegularExpression(
    pattern: #"(?:^|;)\s*([a-zA-Z0-9_*-]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^;\s]+))"#)
  private static func parameters(in value: String) -> [String: String] {
    let ns = value as NSString
    var result: [String: String] = [:]
    for match in parameterPattern.matches(in: value, range: NSRange(location: 0, length: ns.length))
      .prefix(256)
    {
      let key = ns.substring(with: match.range(at: 1)).lowercased()
      guard result[key] == nil else { continue }
      let range = match.range(at: match.range(at: 2).location != NSNotFound ? 2 : 3)
      result[key] = ns.substring(with: range).replacingOccurrences(
        of: #"\\(.)"#, with: "$1", options: .regularExpression)
    }
    return result
  }
  public static func parameter(_ key: String, in value: String) -> String? {
    parameters(in: value)[key.lowercased()]
  }
  static func filename(_ fields: [Header]) -> String {
    let disposition = value("Content-Disposition", in: fields)
    let type = value("Content-Type", in: fields)
    for source in [disposition, type] {
      let values = parameters(in: source)
      for key in ["filename", "name"] {
        var pieces: [String] = []
        var encoded = false
        for index in 0..<64 {
          if let value = values["\(key)*\(index)*"] {
            pieces.append(value)
            encoded = true
          } else if let value = values["\(key)*\(index)"] {
            // Encode literal segments before joining so '%' in them stays literal.
            pieces.append(value.utf8.map { String(format: "%%%02X", $0) }.joined())
          } else {
            break
          }
        }
        if !pieces.isEmpty {
          let joined = pieces.joined()
          return safeFilename(encoded ? extendedParameter(joined) : headerText(percentText(joined)))
        }
        if let value = values[key + "*"] {
          return safeFilename(extendedParameter(value))
        }
      }
      for key in ["filename", "name"] {
        if let v = values[key] { return safeFilename(headerText(v)) }
      }
    }
    return ""
  }
  private static func percentBytes(_ text: String) -> Data {
    let bytes = Array(text.utf8)
    var result = Data()
    var i = 0
    while i < bytes.count {
      if bytes[i] == 37, i + 2 < bytes.count,
        let value = UInt8(String(decoding: bytes[(i + 1)...(i + 2)], as: UTF8.self), radix: 16)
      {
        result.append(value)
        i += 3
      } else {
        result.append(bytes[i])
        i += 1
      }
    }
    return result
  }
  private static func percentText(_ text: String) -> String { decode(percentBytes(text)) }
  private static func extendedParameter(_ value: String) -> String {
    let pieces = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
    return pieces.count == 3
      ? decode(percentBytes(String(pieces[2])), charset: String(pieces[0])) : percentText(value)
  }
  private static func append(_ text: String, to target: inout String, separator: String) {
    let remaining = max(0, Limits.rendered - target.utf8.count - separator.utf8.count)
    guard remaining > 0 else { return }
    if !target.isEmpty { target += separator }
    target += String(decoding: text.utf8.prefix(remaining), as: UTF8.self)
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
      func consume(_ bytes: Data) throws {
        var child = MailMessage()
        try part(
          bytes, depth: depth + 1, count: &count, budget: &budget,
          message: &child, cancelled: cancelled)
        message.attachments.append(contentsOf: child.attachments)
        if type == "multipart/alternative" {
          if !child.html.isEmpty { message.html = child.html }
          if !child.plain.isEmpty { message.plain = child.plain }
        } else {
          if !child.html.isEmpty {
            if message.html.isEmpty && !message.plain.isEmpty {
              message.html =
                "<div style=\"white-space:pre-wrap\">" + SafeHTML.escape(message.plain) + "</div>"
            }
            append(child.html, to: &message.html, separator: "\n")
          } else if !child.plain.isEmpty && !message.html.isEmpty {
            append(
              "<div style=\"white-space:pre-wrap\">" + SafeHTML.escape(child.plain) + "</div>",
              to: &message.html, separator: "\n")
          }
          append(child.plain, to: &message.plain, separator: "\n\n")
        }
      }
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
              try consume(Data(raw[begin..<end]))
            }
            if suffix.starts(with: [45, 45]) { return }
            start = lineEnd
          }
        }
        position = lineEnd
      }
      if let begin = start, begin < raw.endIndex {
        try consume(Data(raw[begin...]))
      }
      return
    }
    let transfer = value("Content-Transfer-Encoding", in: fields).lowercased()
    let bytes =
      transfer == "base64"
      ? Data(base64Encoded: raw, options: .ignoreUnknownCharacters)
      : transfer == "quoted-printable" ? quotedPrintable(raw) : raw
    let cid = value("Content-ID", in: fields).trimmingCharacters(
      in: CharacterSet(charactersIn: "<> "))
    if !name.isEmpty || disposition.hasPrefix("attachment")
      || (!["text/plain", "text/html", ""].contains(type))
    {
      let defaults = [
        "message/rfc822": "Attached message.eml", "message/global": "Attached message.eml",
        "text/calendar": "Calendar.ics", "text/plain": "Attachment.txt",
        "text/html": "Attachment.html",
        "application/pdf": "Attachment.pdf", "image/png": "Image.png", "image/jpeg": "Image.jpg",
        "image/gif": "Image.gif",
      ]
      var attachment = MailAttachment(
        name: name.isEmpty ? defaults[type] ?? "Attachment" : name,
        type: type, bytes: bytes ?? Data(), contentID: cid)
      attachment.available = bytes != nil
      message.attachments.append(attachment)
      return
    }
    guard let bytes else { throw MailError.malformed }
    let charset = parameter("charset", in: contentType)
    let text =
      type == "text/html"
      ? decodeHTML(bytes, charset: charset) : decode(bytes, charset: charset ?? "utf-8")
    if type == "text/html" {
      append(text, to: &message.html, separator: "\n")
    } else if type == "text/plain" || type.isEmpty {
      append(text, to: &message.plain, separator: "\n\n")
    }
  }
}
