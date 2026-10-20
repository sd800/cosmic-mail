import Foundation

// Bounded CFB/MS-OXMSG reader. Streams are data only; no OLE activation or RTF execution.
struct Compound {
  let data: Data
  var sector = 512, miniSector = 64
  var fat: [UInt32] = [], miniFat: [UInt32] = [], mini = Data()
  var paths: [String: Int] = [:]
  struct Node {
    var name: String
    var kind: UInt8
    var left: UInt32
    var right: UInt32
    var child: UInt32
    var start: UInt32
    var size: Int
  }
  var nodes: [Node] = []
  func u16(_ p: Int) throws -> UInt16 {
    guard p >= 0, p + 2 <= data.count else { throw MailError.malformed }
    return UInt16(data[p]) | UInt16(data[p + 1]) << 8
  }
  func u32(_ p: Int) throws -> UInt32 {
    guard p >= 0, p + 4 <= data.count else { throw MailError.malformed }
    return (0..<4).reduce(0) { $0 | UInt32(data[p + $1]) << ($1 * 8) }
  }
  func sectorData(_ id: UInt32) throws -> Data {
    let p = (Int(id) + 1) * sector
    guard p >= sector, p + sector <= data.count else { throw MailError.malformed }
    return Data(data[p..<p + sector])
  }
  init(_ input: Data) throws {
    data = input
    guard input.count >= 512,
      input.prefix(8) == Data([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]),
      try u16(28) == 0xfffe
    else { throw MailError.malformed }
    let shift = try u16(30)
    guard [9, 12].contains(shift), try u16(32) == 6 else { throw MailError.malformed }
    sector = 1 << Int(shift)
    let fatCount = Int(try u32(44))
    guard fatCount > 0, fatCount <= input.count / sector else { throw MailError.malformed }
    var ids: [UInt32] = []
    for p in stride(from: 76, to: 512, by: 4) {
      let n = try u32(p)
      if n < 0xffff_fffa { ids.append(n) }
    }
    var dif = try u32(68)
    var seen = Set<UInt32>()
    let difCount = Int(try u32(72))
    guard difCount <= input.count / sector else { throw MailError.malformed }
    for _ in 0..<difCount {
      guard dif < 0xffff_fffa, seen.insert(dif).inserted else { throw MailError.malformed }
      let part = try sectorData(dif)
      func n(_ p: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(part[p + $1]) << ($1 * 8) } }
      for p in stride(from: 0, to: sector - 4, by: 4) {
        let id = n(p)
        if id < 0xffff_fffa { ids.append(id) }
      }
      dif = n(sector - 4)
    }
    guard ids.count >= fatCount else { throw MailError.malformed }
    for id in ids.prefix(fatCount) {
      let part = try sectorData(id)
      for p in stride(from: 0, to: sector, by: 4) {
        fat.append((0..<4).reduce(0) { $0 | UInt32(part[p + $1]) << ($1 * 8) })
      }
    }
    let directory = try chain(try u32(48), table: fat, source: nil, max: Limits.message)
    guard directory.count / 128 <= 20000 else { throw MailError.tooMany }
    func n32(_ p: Int) -> UInt32 {
      (0..<4).reduce(0) { $0 | UInt32(directory[p + $1]) << ($1 * 8) }
    }
    for p in stride(from: 0, through: max(0, directory.count - 128), by: 128) {
      guard p + 128 <= directory.count else { break }
      let length = Int(directory[p + 64]) | Int(directory[p + 65]) << 8
      let name =
        length >= 2 && length <= 64
        ? String(data: directory[p..<p + length - 2], encoding: .utf16LittleEndian) ?? "" : ""
      let low = n32(p + 120)
      let high = n32(p + 124)
      guard high == 0 else { throw MailError.tooLarge }
      nodes.append(
        Node(
          name: name, kind: directory[p + 66], left: n32(p + 68), right: n32(p + 72),
          child: n32(p + 76), start: n32(p + 116), size: Int(low)))
    }
    guard nodes.first?.kind == 5 else { throw MailError.malformed }
    let mfCount = Int(try u32(64))
    guard mfCount <= input.count / sector else { throw MailError.malformed }
    if mfCount > 0 {
      let bytes = try chain(
        try u32(60), table: fat, source: nil, max: min(Limits.message, mfCount * sector))
      for p in stride(from: 0, to: bytes.count - 3, by: 4) {
        miniFat.append((0..<4).reduce(0) { $0 | UInt32(bytes[p + $1]) << ($1 * 8) })
      }
    }
    if nodes[0].size > 0 {
      mini = try chain(nodes[0].start, table: fat, source: nil, max: Limits.message).prefix(
        nodes[0].size)
    }
    var visited = Set<UInt32>()
    func walk(_ id: UInt32, _ prefix: String, _ depth: Int) throws {
      if id == 0xffff_ffff { return }
      guard Int(id) < nodes.count, depth <= 100, visited.insert(id).inserted else {
        throw MailError.malformed
      }
      let node = nodes[Int(id)]
      try walk(node.left, prefix, depth + 1)
      let path = prefix + node.name.lowercased()
      paths[path] = Int(id)
      if node.kind == 1 { try walk(node.child, path + "/", depth + 1) }
      try walk(node.right, prefix, depth + 1)
    }
    try walk(nodes[0].child, "", 0)
  }
  func chain(_ first: UInt32, table: [UInt32], source: Data?, max: Int) throws -> Data {
    var out = Data()
    var id = first
    var seen = Set<UInt32>()
    let step = source == nil ? sector : miniSector
    while id != 0xffff_fffe {
      guard Int(id) < table.count, seen.insert(id).inserted, out.count <= max - step else {
        throw MailError.malformed
      }
      if let source {
        let p = Int(id) * step
        guard p + step <= source.count else { throw MailError.malformed }
        out.append(source[p..<p + step])
      } else {
        out.append(try sectorData(id))
      }
      id = table[Int(id)]
    }
    return out
  }
  func stream(_ path: String) throws -> Data? {
    guard let index = paths[path.lowercased()] else { return nil }
    let node = nodes[index]
    guard node.kind == 2, node.size <= Limits.message else { return nil }
    if node.size == 0 { return Data() }
    let bytes = try chain(
      node.start, table: node.size < 4096 ? miniFat : fat, source: node.size < 4096 ? mini : nil,
      max: Limits.message)
    guard bytes.count >= node.size else { throw MailError.malformed }
    return Data(bytes.prefix(node.size))
  }
}
public enum Outlook {
  public static func parse(_ data: Data) throws -> MailMessage {
    guard data.count <= Limits.message else { throw MailError.tooLarge }
    let c = try Compound(data)
    func string(_ property: String, prefix: String = "") throws -> String {
      if let d = try c.stream(prefix + "__substg1.0_" + property + "001f") {
        return MIME.decode(d, charset: "utf-16le").trimmingCharacters(in: .controlCharacters)
      }
      if let d = try c.stream(prefix + "__substg1.0_" + property + "001e") {
        return MIME.decode(d, charset: "windows-1252").trimmingCharacters(in: .controlCharacters)
      }
      return ""
    }
    var mail = MailMessage()
    let rawHeaders = try string("007d")
    mail.headers = MIME.split(Data((rawHeaders + "\r\n\r\n").utf8)).headers
    mail.subject = try string("0037")
    mail.from = try string("0c1a")
    let address = try string("5d01")
    if !address.isEmpty { mail.from += mail.from.isEmpty ? address : " <\(address)>" }
    mail.to = try string("0e04")
    mail.cc = try string("0e03")
    mail.plain = try string("1000")
    if let html = try c.stream("__substg1.0_10130102") { mail.html = MIME.decode(html) }
    if mail.html.isEmpty { mail.html = try string("1013") }
    if mail.subject.isEmpty {
      mail.subject = MIME.headerText(MIME.value("Subject", in: mail.headers))
    }
    if mail.from.isEmpty { mail.from = MIME.headerText(MIME.value("From", in: mail.headers)) }
    mail.date = MIME.value("Date", in: mail.headers)
    let prefixes = Set(
      c.paths.keys.filter { $0.hasPrefix("__attach_version1.0_") }.compactMap {
        $0.split(separator: "/").first.map(String.init)
      })
    var attachmentBytes = 0
    for prefix in prefixes.sorted().prefix(500) {
      guard let bytes = try c.stream(prefix + "/__substg1.0_37010102") else { continue }
      attachmentBytes += bytes.count
      guard attachmentBytes <= Limits.message else { throw MailError.tooLarge }
      let long = try string("3707", prefix: prefix + "/")
      let short = try string("3704", prefix: prefix + "/")
      mail.attachments.append(
        MailAttachment(
          name: safeFilename(long.isEmpty ? short : long),
          type: try string("370e", prefix: prefix + "/"), bytes: bytes,
          contentID: try string("3712", prefix: prefix + "/")))
    }
    guard !mail.subject.isEmpty || !mail.plain.isEmpty || !mail.html.isEmpty || !mail.from.isEmpty
    else { throw MailError.malformed }
    mail.plain = String(mail.plain.prefix(Limits.rendered))
    mail.html = String(mail.html.prefix(Limits.rendered))
    return mail
  }
}
