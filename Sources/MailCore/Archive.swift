import Foundation

public enum MailReader {
  public static let extensions = ["eml", "emlx", "msg", "oft", "mbox", "mbx", "mbo", "mime"]
  public static func collection(
    _ url: URL, cancelled: () -> Bool = { false }, progress: (Int) -> Void = { _ in }
  ) throws -> MailCollection {
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else {
      throw MailError.malformed
    }
    if directory.boolValue {
      let mbox = url.appendingPathComponent("mbox")
      if FileManager.default.fileExists(atPath: mbox.path) {
        var result = try indexMbox(mbox, cancelled: cancelled, progress: progress)
        result.url = url
        return result
      }
      var files: [URL] = []
      for sub in ["cur", "new"] {
        let folder = url.appendingPathComponent(sub)
        if let items = try? FileManager.default.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
          options: [.skipsHiddenFiles])
        {
          files += items
        }
      }
      guard !files.isEmpty, files.count <= Limits.messages else { throw MailError.unsupported }
      var entries: [MessageEntry] = []
      for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        if cancelled() { throw MailError.cancelled }
        let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        if info.isRegularFile != true || info.isSymbolicLink == true { continue }
        let size = try length(file)
        guard size <= Limits.message else { throw MailError.tooLarge }
        entries.append(try entry(file, id: entries.count, offset: 0, length: size))
        if entries.count % 100 == 0 { progress(entries.count) }
      }
      return MailCollection(url: url, entries: entries, kind: "Maildir")
    }
    let ext = url.pathExtension.lowercased()
    let size = try length(url)
    if ["mbox", "mbx", "mbo"].contains(ext) {
      return try indexMbox(url, cancelled: cancelled, progress: progress)
    }
    guard extensions.contains(ext), size > 0 else { throw MailError.unsupported }
    guard size <= Limits.message else { throw MailError.tooLarge }
    let data = try read(url, offset: 0, count: size)
    if ["msg", "oft"].contains(ext) {
      let mail = try Outlook.parse(data)
      return MailCollection(
        url: url,
        entries: [
          MessageEntry(
            id: 0, subject: mail.subject, from: mail.from, date: mail.date, offset: 0, length: size,
            file: url)
        ], kind: ext.uppercased())
    }
    let content = try emlx(data, extension: ext)
    let fields = MIME.split(content).headers
    guard !fields.isEmpty else { throw MailError.malformed }
    return MailCollection(
      url: url, entries: [makeEntry(fields, url, 0, 0, size)], kind: ext.uppercased())
  }
  public static func message(_ entry: MessageEntry) throws -> MailMessage {
    guard entry.length <= Limits.message else { throw MailError.tooLarge }
    let data = try read(entry.file, offset: entry.offset, count: entry.length)
    if ["msg", "oft"].contains(entry.file.pathExtension.lowercased()) {
      return try Outlook.parse(data)
    }
    return try MIME.parse(emlx(data, extension: entry.file.pathExtension.lowercased()))
  }
  public static func original(_ entry: MessageEntry) throws -> Data {
    try emlx(
      read(entry.file, offset: entry.offset, count: entry.length),
      extension: entry.file.pathExtension.lowercased())
  }
  static func emlx(_ data: Data, extension ext: String) throws -> Data {
    guard ext == "emlx" else { return data }
    guard let end = data.firstIndex(of: 10), end < 30,
      let count = Int(
        String(decoding: data[..<end], as: UTF8.self).trimmingCharacters(
          in: .whitespacesAndNewlines)), count > 0, count <= Limits.message,
      count <= data.count - end - 1
    else { throw MailError.malformed }
    return Data(data[(end + 1)..<(end + 1 + count)])
  }
  static func length(_ url: URL) throws -> Int {
    Int(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0)
  }
  static func read(_ url: URL, offset: UInt64, count: Int) throws -> Data {
    guard count >= 0, count <= Limits.message else { throw MailError.tooLarge }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    try file.seek(toOffset: offset)
    let data = try file.read(upToCount: count) ?? Data()
    guard data.count == count else { throw MailError.malformed }
    return data
  }
  static func makeEntry(_ fields: [Header], _ url: URL, _ id: Int, _ offset: UInt64, _ length: Int)
    -> MessageEntry
  {
    MessageEntry(
      id: id, subject: MIME.headerText(MIME.value("Subject", in: fields)),
      from: MIME.headerText(MIME.value("From", in: fields)), date: MIME.value("Date", in: fields),
      offset: offset, length: length, file: url)
  }
  static func entry(_ url: URL, id: Int, offset: UInt64, length: Int) throws -> MessageEntry {
    let data = try read(url, offset: offset, count: min(length, Limits.headers))
    return makeEntry(MIME.split(data).headers, url, id, offset, length)
  }
  static func indexMbox(_ url: URL, cancelled: () -> Bool, progress: (Int) -> Void) throws
    -> MailCollection
  {
    let size = try length(url)
    guard size > 0, size <= Limits.archive else { throw MailError.tooLarge }
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    var pending = Data()
    var fileOffset: UInt64 = 0
    var start: UInt64?
    var entries: [MessageEntry] = []
    let envelope = try! NSRegularExpression(
      pattern: "^From (?:\\S+ (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun) |-(?: |$))")
    func append(_ end: UInt64) throws {
      guard let begin = start, end > begin else { return }
      let count = Int(end - begin)
      guard count <= Limits.message else { throw MailError.tooLarge }
      guard entries.count < Limits.messages else { throw MailError.tooMany }
      entries.append(try entry(url, id: entries.count, offset: begin, length: count))
      if entries.count % 100 == 0 { progress(entries.count) }
    }
    while true {
      if cancelled() { throw MailError.cancelled }
      let chunk = try file.read(upToCount: 128 * 1024) ?? Data()
      if chunk.isEmpty { break }
      pending.append(chunk)
      var consumed = 0
      while let newline = pending[consumed...].firstIndex(of: 10) {
        let end = newline + 1
        let line = pending[consumed..<end]
        if line.starts(with: [70, 114, 111, 109, 32]), line.count <= 1000 {
          let text = String(decoding: line, as: UTF8.self)
          if envelope.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            try append(fileOffset + UInt64(consumed))
            start = fileOffset + UInt64(end)
          }
        }
        consumed = end
      }
      if consumed > 0 {
        pending = Data(pending.dropFirst(consumed))
        fileOffset += UInt64(consumed)
      }
      if pending.count > Limits.message { throw MailError.tooLarge }
    }
    try append(UInt64(size))
    if entries.isEmpty {
      guard size <= Limits.message else { throw MailError.malformed }
      let candidate = try entry(url, id: 0, offset: 0, length: size)
      guard !candidate.subject.isEmpty || !candidate.from.isEmpty else { throw MailError.malformed }
      entries = [candidate]
    }
    progress(entries.count)
    return MailCollection(url: url, entries: entries, kind: "MBOX")
  }
}
