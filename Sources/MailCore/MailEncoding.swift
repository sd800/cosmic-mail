import CoreFoundation
import Darwin
import Foundation

/// Recover invalid sequences within the declared charset, without reinterpreting valid text.
enum MailEncoding {
  static func decode(_ data: Data, charset: String) -> String {
    let requested = charset.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let name: String
    switch requested {
    case "gb2312", "gb_2312-80", "chinese", "gbk", "cp936", "windows-936", "x-gbk": name = "GB18030"
    case "utf8", "utf-8", "": return String(decoding: data, as: UTF8.self)
    default: name = requested
    }
    guard name.utf8.count < 80, !name.contains("\0") else {
      return String(decoding: data, as: UTF8.self)
    }
    let converter = iconv_open("UTF-8", name)
    guard converter != OpaquePointer(bitPattern: -1), let converter else {
      let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
      if cf != kCFStringEncodingInvalidId,
        let text = String(
          data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(cf)))
      {
        return text
      }
      return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
        ?? String(decoding: data, as: UTF8.self)
    }
    defer { iconv_close(converter) }
    var input = Array(data)
    var result = Data()
    input.withUnsafeMutableBytes { raw in
      var cursor = raw.baseAddress?.assumingMemoryBound(to: CChar.self)
      var remaining = raw.count
      var buffer = [CChar](repeating: 0, count: 8192)
      while remaining > 0 {
        let before = remaining
        var written = 0
        let status = buffer.withUnsafeMutableBufferPointer { output -> Int in
          var destination = output.baseAddress
          var space = output.count
          let status = iconv(converter, &cursor, &remaining, &destination, &space)
          written = output.count - space
          return status
        }
        result.append(contentsOf: buffer.prefix(written).map { UInt8(bitPattern: $0) })
        if status == -1 && errno != E2BIG {
          result.append(contentsOf: [0xef, 0xbf, 0xbd])
          // A truncated trailing sequence is one replacement; an illegal byte does not discard its neighbors.
          if errno == EINVAL { break }
          cursor = cursor?.advanced(by: 1)
          remaining -= 1
          _ = iconv(converter, nil, nil, nil, nil)
        } else if remaining == before && written == 0 {
          break
        }
      }
    }
    return String(decoding: result, as: UTF8.self)
  }
  static func charset(codepage: UInt64?) -> String? {
    guard let codepage, codepage > 0 else { return nil }
    switch codepage {
    case 65001: return "utf-8"
    case 1200: return "utf-16le"
    case 1201: return "utf-16be"
    case 936: return "GB18030"
    case 950: return "BIG5"
    case 20127: return "US-ASCII"
    case 28591...28599: return "ISO-8859-\(codepage - 28590)"
    default: return "CP\(codepage)"
    }
  }
}
