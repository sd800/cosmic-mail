import Darwin
import Foundation

/// Identity of the opened source, not a bookmark or persistent cache.
public struct FileRevision: Sendable, Equatable {
  var device: Int32
  var inode: UInt64
  var size: Int64
  var seconds: Int
  var nanoseconds: Int

  static func capture(_ file: FileHandle) throws -> Self {
    var value = stat()
    guard fstat(file.fileDescriptor, &value) == 0, value.st_size >= 0 else {
      throw MailError.malformed
    }
    return Self(
      device: value.st_dev, inode: value.st_ino, size: value.st_size,
      seconds: value.st_mtimespec.tv_sec, nanoseconds: value.st_mtimespec.tv_nsec)
  }
  func verify(_ file: FileHandle) throws {
    guard try Self.capture(file) == self else { throw MailError.sourceChanged }
  }
}

public enum MailReader {
  public static let extensions = ["eml", "emlx", "msg", "oft", "mbox", "mbx", "mbo", "mime"]
  public static func collection(
    _ url: URL, cancelled: @escaping () -> Bool = { false },
    progress: @escaping (Int) -> Void = { _ in },
    limits: IndexLimits = IndexLimits(), batch: @escaping ([MessageEntry]) -> Void = { _ in }
  ) throws -> MailCollection {
    if cancelled() { throw MailError.cancelled }
    var directory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) else {
      throw MailError.malformed
    }
    if directory.boolValue {
      let mbox = url.appendingPathComponent("mbox")
      if FileManager.default.fileExists(atPath: mbox.path) {
        var result = try indexMbox(
          mbox, cancelled: cancelled, progress: progress, limits: limits, batch: batch)
        result.url = url
        return result
      }
      let index = MemoryIndex(url: url, limits: limits, progress: progress, batch: batch)
      // Enumeration does not materialize/sort the entire directory before indexing.
      for sub in ["cur", "new"] {
        let folder = url.appendingPathComponent(sub)
        guard
          let files = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
        else { continue }
        for case let file as URL in files {
          if cancelled() { throw MailError.cancelled }
          let info = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
          if info.isRegularFile != true || info.isSymbolicLink == true { continue }
          let handle = try FileHandle(forReadingFrom: file)
          defer { try? handle.close() }
          let revision = try FileRevision.capture(handle)
          let fields = try headerFields(handle, cancelled: cancelled).fields
          try revision.verify(handle)
          let item = makeEntry(fields, file, index.count, 0, Int(revision.size), revision)
          if !index.append(item) { return index.finish(kind: "Maildir") }
        }
      }
      guard index.count > 0 else { throw MailError.unsupported }
      return index.finish(kind: "Maildir")
    }
    let ext = url.pathExtension.lowercased()
    if ["mbox", "mbx", "mbo"].contains(ext) {
      return try indexMbox(
        url, cancelled: cancelled, progress: progress, limits: limits, batch: batch)
    }
    guard extensions.contains(ext) else { throw MailError.unsupported }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let revision = try FileRevision.capture(handle)
    let size = Int(revision.size)
    guard size > 0 else { throw MailError.malformed }
    let fields: [Header]
    if ["msg", "oft"].contains(ext), size > Limits.message {
      fields = [Header(name: "Subject", value: url.lastPathComponent)]
    } else if ["msg", "oft"].contains(ext) {
      let data = try read(handle, count: size, cancelled: cancelled)
      let mail = try Outlook.parse(data)
      fields = [
        Header(name: "Subject", value: mail.subject), Header(name: "From", value: mail.from),
        Header(name: "Date", value: mail.date), Header(name: "To", value: mail.to),
        Header(name: "Cc", value: mail.cc),
      ]
    } else if ext == "emlx" {
      let range = try emlxRange(handle, offset: 0, length: size)
      try handle.seek(toOffset: range.0)
      fields = try headerFields(handle, cancelled: cancelled).fields
    } else {
      fields = try headerFields(handle, cancelled: cancelled).fields
    }
    try revision.verify(handle)
    guard !fields.isEmpty else { throw MailError.malformed }
    let index = MemoryIndex(url: url, limits: limits, progress: progress, batch: batch)
    _ = index.append(makeEntry(fields, url, 0, 0, size, revision))
    return index.finish(kind: ext.uppercased())
  }

  /// Reuse an already-open complete RAM index only while its source identity still matches.
  public static func isCurrent(_ collection: MailCollection) -> Bool {
    guard collection.kind != "Maildir", !collection.isIndexing,
      !collection.indexInterrupted, !collection.indexLimitReached,
      let entry = collection.entries.first, let revision = entry.revision,
      let file = try? FileHandle(forReadingFrom: entry.file)
    else { return false }
    defer { try? file.close() }
    return (try? FileRevision.capture(file)) == revision
  }

  public static func message(
    _ entry: MessageEntry, cancelled: () -> Bool = { false }
  ) throws -> MailMessage {
    let data = try source(entry, cancelled: cancelled)
    let mail: MailMessage
    if ["msg", "oft"].contains(entry.file.pathExtension.lowercased()) {
      mail = try Outlook.parse(data)
    } else {
      mail = try MIME.parse(
        emlx(data, extension: entry.file.pathExtension.lowercased()), cancelled: cancelled)
    }
    if cancelled() { throw MailError.cancelled }
    return mail
  }
  public static func original(_ entry: MessageEntry) throws -> Data {
    try emlx(source(entry, cancelled: { false }), extension: entry.file.pathExtension.lowercased())
  }
  public static func validateDestination(_ destination: URL, protecting sources: [URL]) throws {
    guard destination.isFileURL else { throw MailError.malformed }
    let target = destination.standardizedFileURL.resolvingSymlinksInPath()
    var output = stat()
    let exists = stat(target.path, &output) == 0
    for source in sources where source.isFileURL {
      let path = source.standardizedFileURL.resolvingSymlinksInPath()
      var original = stat()
      guard stat(path.path, &original) == 0 else { continue }
      let directory = (original.st_mode & S_IFMT) == S_IFDIR
      if path == target || directory && target.path.hasPrefix(path.path + "/")
        || exists && original.st_dev == output.st_dev && original.st_ino == output.st_ino
      {
        throw MailError.unsafeDestination
      }
    }
  }
  private static func emlxRange(_ file: FileHandle, offset: UInt64, length: Int) throws -> (
    UInt64, Int
  ) {
    try file.seek(toOffset: offset)
    let prefix = try file.read(upToCount: min(length, 30)) ?? Data()
    guard let end = prefix.firstIndex(of: 10),
      let count = Int(String(decoding: prefix[..<end], as: UTF8.self)),
      count > 0, count <= length - end - 1
    else { throw MailError.malformed }
    return (offset + UInt64(end + 1), count)
  }
  /// An explicit export streams to a single temporary output; parsing and its RAM ceiling are independent.
  public static func exportOriginal(
    _ entry: MessageEntry, to destination: URL,
    cancelled: () -> Bool = { false }, chunkSize: Int = 128 * 1024
  ) throws {
    guard entry.length >= 0, destination.isFileURL else { throw MailError.malformed }
    let input = try FileHandle(forReadingFrom: entry.file)
    defer { try? input.close() }
    try entry.revision?.verify(input)
    let sourceRevision = try FileRevision.capture(input)
    func protectSource() throws {
      if destination.standardizedFileURL.resolvingSymlinksInPath()
        == entry.file.standardizedFileURL.resolvingSymlinksInPath()
      {
        throw MailError.unsafeDestination
      }
      if let target = try? FileHandle(forReadingFrom: destination) {
        defer { try? target.close() }
        let revision = try FileRevision.capture(target)
        guard revision.device != sourceRevision.device || revision.inode != sourceRevision.inode
        else { throw MailError.unsafeDestination }
      }
    }
    try protectSource()
    let range =
      entry.file.pathExtension.lowercased() == "emlx"
      ? try emlxRange(input, offset: entry.offset, length: entry.length)
      : (entry.offset, entry.length)
    guard range.0 <= UInt64(sourceRevision.size),
      UInt64(range.1) <= UInt64(sourceRevision.size) - range.0
    else { throw MailError.malformed }
    let temporary = destination.deletingLastPathComponent().appendingPathComponent(
      ".CosmicMail-" + UUID().uuidString)
    let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
    guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
    let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer {
      try? output.close()
      try? FileManager.default.removeItem(at: temporary)
    }
    try input.seek(toOffset: range.0)
    var remaining = range.1
    while remaining > 0 {
      if cancelled() { throw MailError.cancelled }
      let chunk =
        try input.read(upToCount: min(remaining, min(128 * 1024, max(1, chunkSize)))) ?? Data()
      guard !chunk.isEmpty else { throw MailError.malformed }
      try output.write(contentsOf: chunk)
      remaining -= chunk.count
    }
    try sourceRevision.verify(input)
    try protectSource()
    if cancelled() { throw MailError.cancelled }
    try output.close()
    guard Darwin.rename(temporary.path, destination.path) == 0 else {
      throw CocoaError(.fileWriteUnknown)
    }
  }
  private static func source(_ entry: MessageEntry, cancelled: () -> Bool) throws -> Data {
    guard entry.length >= 0, entry.length <= Limits.message else { throw MailError.tooLarge }
    let file = try FileHandle(forReadingFrom: entry.file)
    defer { try? file.close() }
    try entry.revision?.verify(file)
    try file.seek(toOffset: entry.offset)
    let data = try read(file, count: entry.length, cancelled: cancelled)
    try entry.revision?.verify(file)
    return data
  }
  private static func read(_ file: FileHandle, count: Int, cancelled: () -> Bool) throws -> Data {
    var data = Data()
    data.reserveCapacity(count)
    while data.count < count {
      if cancelled() { throw MailError.cancelled }
      let chunk = try file.read(upToCount: min(128 * 1024, count - data.count)) ?? Data()
      guard !chunk.isEmpty else { throw MailError.malformed }
      data.append(chunk)
    }
    return data
  }
  static func emlx(_ data: Data, extension ext: String) throws -> Data {
    guard ext == "emlx" else { return data }
    guard let end = data.firstIndex(of: 10), end < 30,
      let count = Int(
        String(decoding: data[..<end], as: UTF8.self).trimmingCharacters(
          in: .whitespacesAndNewlines)),
      count > 0, count <= Limits.message, count <= data.count - end - 1
    else { throw MailError.malformed }
    return Data(data[(end + 1)..<(end + 1 + count)])
  }
  private static func makeEntry(
    _ fields: [Header], _ url: URL, _ id: Int, _ offset: UInt64, _ length: Int,
    _ revision: FileRevision
  ) -> MessageEntry {
    MessageEntry(
      id: id, subject: String(MIME.headerText(MIME.value("Subject", in: fields)).prefix(1024)),
      from: String(MIME.headerText(MIME.value("From", in: fields)).prefix(1024)),
      date: String(MIME.value("Date", in: fields).prefix(256)), offset: offset, length: length,
      file: url, revision: revision,
      recipients: String(
        MIME.headerText(
          ["To", "Cc", "Bcc"].map { MIME.value($0, in: fields) }.joined(separator: " ")
        ).prefix(2048)),
      timestamp: MailDate.timestamp(MIME.value("Date", in: fields)))
  }

  private static let envelope = try! NSRegularExpression(
    pattern: #"^From (?:\S+ (?:Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s|-(?:\s|$))"#)
  private static func isEnvelope(_ line: ArchiveLine) -> Bool {
    guard !line.truncated, line.prefix.count <= 1000,
      line.prefix.starts(with: [70, 114, 111, 109, 32])
    else { return false }
    let text = String(decoding: line.prefix, as: UTF8.self)
    return envelope.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  private static func headerFields(
    _ file: FileHandle, cancelled: @escaping () -> Bool
  ) throws -> (fields: [Header], end: UInt64?) {
    try headers(ArchiveLines(file, cancelled: cancelled))
  }
  private static func headers(_ lines: ArchiveLines) throws -> (fields: [Header], end: UInt64?) {
    var data = Data()
    var end: UInt64?
    while data.count < Limits.headers,
      let line = try lines.next(limit: Limits.headers - data.count)
    {
      let bytes = line.prefix
      if !line.truncated && (bytes == Data([10]) || bytes == Data([13, 10])) {
        end = line.end
        break
      }
      // Stop on non-header content; allow the scanner to reconsider a following envelope.
      if !bytes.starts(with: [32]), !bytes.starts(with: [9]), !bytes.contains(58) {
        lines.putBack(line)
        break
      }
      data.append(bytes)
      if line.truncated { break }
    }
    return (MIME.split(data).headers, end)
  }
  private static func indexMbox(
    _ url: URL, cancelled: @escaping () -> Bool, progress: @escaping (Int) -> Void,
    limits: IndexLimits,
    batch: @escaping ([MessageEntry]) -> Void
  ) throws -> MailCollection {
    let file = try FileHandle(forReadingFrom: url)
    defer { try? file.close() }
    let revision = try FileRevision.capture(file)
    guard revision.size > 0 else { throw MailError.malformed }
    let lines = ArchiveLines(file, cancelled: cancelled)
    let index = MemoryIndex(url: url, limits: limits, progress: progress, batch: batch)
    var start: UInt64?
    var fields: [Header] = []
    var bodyEnd: UInt64 = 0
    func append(_ end: UInt64) -> Bool {
      guard let begin = start, end > begin else { return true }
      return index.append(makeEntry(fields, url, index.count, begin, Int(end - begin), revision))
    }
    while let line = try lines.next(limit: 1000) {
      guard line.start >= bodyEnd, isEnvelope(line) else { continue }
      let candidate = try headers(lines)
      // A From-looking line in prose is not enough to split a message.
      guard
        candidate.fields.contains(where: {
          ["from", "subject", "date", "to", "message-id", "content-type"].contains(
            $0.name.lowercased())
        })
      else { continue }
      if !append(line.start) { break }
      start = line.end
      fields = candidate.fields
      bodyEnd = 0
      let lengths = fields.filter {
        $0.name.caseInsensitiveCompare("Content-Length") == .orderedSame
      }
      if lengths.count == 1, let end = candidate.end,
        let count = UInt64(lengths[0].value), end <= UInt64(revision.size),
        count <= UInt64(revision.size) - end
      {
        bodyEnd = end + count
      }
    }
    if !index.limitReached { _ = append(UInt64(revision.size)) }
    if start == nil {
      try file.seek(toOffset: 0)
      let candidate = try headerFields(file, cancelled: cancelled).fields
      guard candidate.contains(where: { ["from", "subject"].contains($0.name.lowercased()) }) else {
        throw MailError.malformed
      }
      _ = index.append(makeEntry(candidate, url, 0, 0, Int(revision.size), revision))
    }
    if cancelled() { throw MailError.cancelled }
    try revision.verify(file)
    return index.finish(kind: "MBOX")
  }
}

/// Holds only bounded line prefixes, even for huge unbroken attachment/body lines.
private struct ArchiveLine {
  var start: UInt64
  var end: UInt64
  var prefix: Data
  var truncated: Bool
}
private final class ArchiveLines {
  private let file: FileHandle
  private let cancelled: () -> Bool
  private var chunk = Data()
  private var cursor = 0
  private var offset: UInt64 = 0
  private var saved: ArchiveLine?
  init(_ file: FileHandle, cancelled: @escaping () -> Bool) {
    self.file = file
    self.cancelled = cancelled
  }
  func putBack(_ line: ArchiveLine) { saved = line }
  func next(limit: Int) throws -> ArchiveLine? {
    if cancelled() { throw MailError.cancelled }
    if let line = saved {
      saved = nil
      return line
    }
    let start = offset
    var prefix = Data()
    while true {
      if cursor == chunk.count {
        if cancelled() { throw MailError.cancelled }
        chunk = try file.read(upToCount: 128 * 1024) ?? Data()
        cursor = 0
        if chunk.isEmpty {
          return offset == start
            ? nil
            : ArchiveLine(
              start: start, end: offset, prefix: prefix,
              truncated: UInt64(prefix.count) < offset - start)
        }
      }
      let amount = chunk.withUnsafeBytes { bytes -> Int in
        let base = bytes.baseAddress!.advanced(by: cursor)
        if let found = memchr(base, 10, chunk.count - cursor) {
          return base.distance(to: UnsafeRawPointer(found)) + 1
        }
        return chunk.count - cursor
      }
      let keep = min(amount, max(0, limit - prefix.count))
      if keep > 0 { prefix.append(chunk[cursor..<(cursor + keep)]) }
      cursor += amount
      offset += UInt64(amount)
      if chunk[cursor - 1] == 10 {
        return ArchiveLine(
          start: start, end: offset, prefix: prefix,
          truncated: UInt64(prefix.count) < offset - start)
      }
    }
  }
}

final class MemoryIndex {
  private let url: URL
  private let limits: IndexLimits
  private let progress: (Int) -> Void
  private let batch: ([MessageEntry]) -> Void
  private var entries: [MessageEntry] = []
  private var bytes = 0
  private var delivered = 0
  private var lastDelivery = ProcessInfo.processInfo.systemUptime
  private(set) var limitReached = false
  var count: Int { entries.count }
  init(
    url: URL, limits: IndexLimits, progress: @escaping (Int) -> Void,
    batch: @escaping ([MessageEntry]) -> Void
  ) {
    self.url = url
    self.limits = limits
    self.progress = progress
    self.batch = batch
  }
  func append(_ entry: MessageEntry) -> Bool {
    guard entries.count < limits.messages, entry.metadataBytes <= limits.bytes - bytes else {
      limitReached = true
      return false
    }
    entries.append(entry)
    bytes += entry.metadataBytes
    if entries.count == 1 || ProcessInfo.processInfo.systemUptime - lastDelivery >= 0.15 {
      deliver()
    }
    return true
  }
  private func deliver() {
    if delivered < entries.count {
      batch(Array(entries[delivered...]))
      delivered = entries.count
    }
    progress(entries.count)
    lastDelivery = ProcessInfo.processInfo.systemUptime
  }
  func finish(kind: String) -> MailCollection {
    deliver()
    return MailCollection(
      url: url, entries: entries, kind: kind, indexLimitReached: limitReached, metadataBytes: bytes)
  }
}
