import Foundation
import ImageIO

public struct RenderedMail: Sendable {
  public var body: String
  public var links: [String: String]
  public var stylesheet: String
  public init(body: String, links: [String: String], stylesheet: String = "") {
    self.body = body
    self.links = links
    self.stylesheet = stylesheet
  }
  public func page(dark: Bool, scale: Double = 1, backgroundRGB: UInt32? = nil) -> String {
    let paper =
      backgroundRGB.map { String(format: "#%06X", $0 & 0xFFFFFF) }
      ?? (dark ? "#232426" : "#FFFFFF")
    return """
      <!doctype html><html data-theme="\(dark ? "dark" : "light")" style="--paper:\(paper);--mail-scale:\(scale)"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"><style>
      :root{color-scheme:light dark;--ink:#252629;--muted:#74777d;--line:#e3e5e8;--quote:#f4f5f7;--link:#2864be}
      :root[data-theme=dark]{--ink:#e5e5e7;--muted:#a3a5ab;--line:#404246;--quote:#2c2e31;--link:#90baff}
      *{box-sizing:border-box}html,body{margin:0;background:var(--paper);color:var(--ink)}body{padding:12px 0 32px;font:\(16*scale)px/1.7 -apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif;overflow-wrap:anywhere;-webkit-font-smoothing:antialiased}
      p{margin:0 0 1em}h1,h2,h3,h4,h5,h6{line-height:1.35;margin:1em 0 .6em}h1{font-size:1.6em}h2{font-size:1.35em}h3{font-size:1.15em}a{color:var(--link);text-decoration:none}a:hover{text-decoration:underline}img{max-width:100%;height:auto}table{border-collapse:collapse;max-width:100%}td,th{vertical-align:top}caption{text-align:inherit}table[border="0"]{border:0}blockquote{margin:18px 0;padding:10px 18px;border-left:3px solid var(--line);background:var(--quote);color:var(--muted)}pre{white-space:pre-wrap;overflow-wrap:anywhere;font: .9em/1.6 ui-monospace,monospace;padding:14px;background:var(--quote);border-radius:8px}code{font-family:ui-monospace,monospace}hr{border:0;border-top:1px solid var(--line);margin:24px 0}.plain{white-space:break-spaces}.image-placeholder{color:var(--muted);font-size:.85em}ul,ol{padding-left:1.6em}li{margin:.25em 0}
      </style><style id="mail-styles">\(stylesheet)</style></head><body><div class="mail-content">\(body)</div></body></html>
      """
  }
}
public enum SafeHTML {
  public static func escape(_ text: String) -> String {
    text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&#39;")
  }
  static let tags: Set<String> = [
    "p", "div", "span", "br", "hr", "h1", "h2", "h3", "h4", "h5", "h6", "strong", "b", "em", "i",
    "u", "s", "del", "blockquote", "pre", "code", "table", "thead", "tbody", "tfoot", "tr", "td",
    "th", "ul", "ol", "li", "dl", "dt", "dd", "a", "img", "sup", "sub", "center", "font", "caption",
    "colgroup", "col", "address", "small", "big", "mark", "section", "article", "header", "footer",
    "body",
  ]
  // Raw-text/active containers are removed; inert wrappers are flattened instead of swallowing following text.
  static let blocked: Set<String> = ["script", "iframe", "object", "svg", "math", "template"]
  static let entityPattern = try! NSRegularExpression(
    pattern: "&(?:#(x[0-9a-fA-F]+|[0-9]+)|([a-zA-Z][a-zA-Z0-9]+));")
  static func entities(_ text: String) -> String {
    let regex = entityPattern
    let ns = text as NSString
    var result = ""
    var cursor = 0
    for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
      result += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
      var value: String?
      if m.range(at: 1).location != NSNotFound {
        let n = ns.substring(with: m.range(at: 1))
        let number = n.lowercased().hasPrefix("x") ? UInt32(n.dropFirst(), radix: 16) : UInt32(n)
        if let number, let scalar = UnicodeScalar(number), number != 0 { value = String(scalar) }
      } else {
        value = HTMLEntities.named[ns.substring(with: m.range(at: 2))]
      }
      result += value ?? ns.substring(with: m.range)
      cursor = m.range.location + m.range.length
    }
    result += ns.substring(from: cursor)
    return result
  }
  static let attributePattern = try! NSRegularExpression(
    pattern: #"([a-zA-Z][a-zA-Z0-9:-]*)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?"#)
  static func attributes(_ text: String) -> [String: String] {
    let regex = attributePattern
    let ns = text as NSString
    var values: [String: String] = [:]
    for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).prefix(80) {
      let key = ns.substring(with: m.range(at: 1)).lowercased()
      guard values[key] == nil else { continue }
      let index = (2...4).first { m.range(at: $0).location != NSNotFound }
      values[key] = index.map { entities(ns.substring(with: m.range(at: $0))) } ?? ""
    }
    return values
  }
  public static func safeLink(_ value: String) -> String? {
    guard value.utf8.count <= 8192,
      !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
      let url = URL(string: value), let scheme = url.scheme?.lowercased(),
      ["https", "http", "mailto", "tel", "sms"].contains(scheme), url.user == nil,
      url.password == nil
    else { return nil }
    if ["https", "http"].contains(scheme) && (url.host?.isEmpty != false) { return nil }
    return url.absoluteString
  }
  public static func render(_ message: MailMessage) -> RenderedMail {
    guard !message.html.isEmpty else {
      return RenderedMail(
        body: "<div class=\"plain\">" + escape(message.plain) + "</div>", links: [:])
    }
    let source = String(message.html.prefix(Limits.rendered))
    var output = ""
    var outputBytes = 0
    var links: [String: String] = [:]
    let styles = MailStyles()
    var cursor = source.startIndex
    var stack: [String] = []
    var nodes = 0
    var imageBytes = 0
    let void: Set<String> = ["img", "br", "hr", "col"]
    func emit(_ value: String) {
      guard value.utf8.count <= 8 * 1024 * 1024 - outputBytes else { return }
      output += value
      outputBytes += value.utf8.count
    }
    while cursor < source.endIndex && nodes < 50000 && outputBytes < 8 * 1024 * 1024 {
      guard let open = source[cursor...].firstIndex(of: "<") else {
        emit(escape(entities(String(source[cursor...]))))
        break
      }
      emit(escape(entities(String(source[cursor..<open]))))
      if source[open...].hasPrefix("<!--") {
        guard let end = source[open...].range(of: "-->") else { break }
        cursor = end.upperBound
        continue
      }
      var end = source.index(after: open)
      var quote: Character?
      while end < source.endIndex {
        let c = source[end]
        if let q = quote {
          if c == q { quote = nil }
        } else if c == "\"" || c == "'" {
          quote = c
        } else if c == ">" {
          break
        }
        end = source.index(after: end)
      }
      guard end < source.endIndex else {
        emit(escape(String(source[open...])))
        break
      }
      cursor = source.index(after: end)
      nodes += 1
      let token = String(source[source.index(after: open)..<end]).trimmingCharacters(
        in: .whitespacesAndNewlines)
      let closing = token.hasPrefix("/")
      let trimmed = closing ? String(token.dropFirst()) : token
      let name = String(trimmed.prefix(while: { $0.isASCII && ($0.isLetter || $0.isNumber) }))
        .lowercased()
      if name.isEmpty { continue }
      if !closing && (blocked.contains(name) || ["style", "title"].contains(name)) {
        // Match an actual end tag, not a prefix such as </scripted>. No source active content is emitted.
        let pattern = "(?i)</" + name + #"\s*>"#
        let regex = try! NSRegularExpression(pattern: pattern)
        if let match = regex.firstMatch(in: source, range: NSRange(cursor..., in: source)),
          let range = Range(match.range, in: source)
        {
          if name == "style" { styles.addStylesheet(String(source[cursor..<range.lowerBound])) }
          cursor = range.upperBound
        } else if ["script", "style", "title"].contains(name) {
          break
        }
        continue
      }
      guard tags.contains(name) else { continue }
      let tag = name == "body" ? "div" : name
      if closing {
        if let index = stack.lastIndex(of: name) {
          for item in stack[index...].reversed() { emit("</\(item == "body" ? "div" : item)>") }
          stack.removeSubrange(index...)
        }
        continue
      }
      guard stack.count < 100 else { continue }
      let attrs = attributes(String(trimmed.dropFirst(name.count)))
      var extra = ""
      let declarations = styles.inline(attrs, tag: name)
      if !declarations.isEmpty { extra += " style=\"\(escape(declarations))\"" }
      if let value = attrs["class"] {
        let classes = value.split(whereSeparator: { $0.isWhitespace }).prefix(24).compactMap {
          MailStyles.identifier(String($0))
        }
        if !classes.isEmpty {
          extra += " class=\"\(classes.map { "m-" + $0 }.joined(separator: " "))\""
        }
      }
      if let value = attrs["id"], let id = MailStyles.identifier(value) {
        extra += " id=\"m-\(id)\""
      }
      if let dir = attrs["dir"]?.lowercased(), ["ltr", "rtl", "auto"].contains(dir) {
        extra += " dir=\"\(dir)\""
      }
      for key in [
        "colspan", "rowspan", "span", "start", "value", "cellpadding", "cellspacing", "border",
      ] {
        if let raw = attrs[key], let n = Int(raw), n >= 0,
          n <= (key == "start" || key == "value" ? 100000 : 100)
        {
          extra += " \(key)=\"\(n)\""
        }
      }
      if name == "img" {
        let src = attrs["src"] ?? ""
        let cid =
          src.lowercased().hasPrefix("cid:")
          ? String(src.dropFirst(4)).removingPercentEncoding ?? String(src.dropFirst(4)) : ""
        if !cid.isEmpty, let image = message.attachments.first(where: { $0.contentID == cid }),
          image.bytes.count <= 4 * 1024 * 1024, imageBytes + image.bytes.count <= 4 * 1024 * 1024,
          let type = rasterType(image.bytes), safeRaster(image.bytes)
        {
          imageBytes += image.bytes.count
          emit(
            "<img\(extra) alt=\"\(escape(attrs["alt"] ?? ""))\" src=\"data:\(type);base64,\(image.bytes.base64EncodedString())\">"
          )
        } else {
          emit("<span class=\"image-placeholder\">\(escape(attrs["alt"] ?? ""))</span>")
        }
        continue
      }
      if name == "a", let href = attrs["href"], let url = safeLink(href) {
        let id = UUID().uuidString.lowercased()
        links[id] = url
        extra += " href=\"cosmic-link://\(id)\""
      }
      emit("<\(tag)\(extra)>")
      if !void.contains(name) { stack.append(name) }
    }
    for item in stack.reversed() { emit("</\(item == "body" ? "div" : item)>") }
    return RenderedMail(body: output, links: links, stylesheet: styles.stylesheet)
  }
  /// Plain text for local searching, never a second browser parsing path.
  public static func searchableText(_ html: String) -> String {
    let bounded = String(decoding: html.utf8.prefix(Limits.rendered), as: UTF8.self)
    let inert = bounded.replacingOccurrences(
      of: #"(?is)<(script|style|head)\b[^>]*>.*?</\1\s*>"#, with: " ", options: .regularExpression)
    return entities(
      inert.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression))
  }
  static func safeRaster(_ data: Data) -> Bool {
    guard
      let source = CGImageSourceCreateWithData(
        data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
      let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = props[kCGImagePropertyPixelWidth] as? Int,
      let height = props[kCGImagePropertyPixelHeight] as? Int,
      width > 0, height > 0, width <= 8192, height <= 8192, width * height <= 12_000_000
    else { return false }
    // Do not decode animations or accept unbounded image dimensions.
    return CGImageSourceGetCount(source) == 1
  }
  static func rasterType(_ data: Data) -> String? {
    if data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) { return "image/png" }
    if data.starts(with: [255, 216, 255]) { return "image/jpeg" }
    if data.starts(with: Data("GIF8".utf8)) { return "image/gif" }
    return nil
  }
}
