import Foundation

/// Reconstruct passive mail styles. No source URLs, imports, variables, generated content, or positioning survive.
final class MailStyles {
  private var rules: [String] = []
  private var colors: [(String, String)] = []
  private var colorIDs: [String: Int] = [:]
  private var ruleBytes = 0
  static func identifier(_ value: String) -> String? {
    guard value.utf8.count <= 100,
      value.range(of: #"^[a-zA-Z_][a-zA-Z0-9_-]*$"#, options: .regularExpression) != nil
    else { return nil }
    return value
  }
  var stylesheet: String {
    let light = colors.enumerated().map { "--mail-color-\($0.offset):\($0.element.0)" }.joined(
      separator: ";")
    let dark = colors.enumerated().map { "--mail-color-\($0.offset):\($0.element.1)" }.joined(
      separator: ";")
    return ":root{\(light)}:root[data-theme=dark]{\(dark)}" + rules.joined()
  }
  private func color(_ input: String, background: Bool) -> String? {
    let names = [
      "black": "000000", "white": "ffffff", "red": "ff0000", "blue": "0000ff", "green": "008000",
      "gray": "808080", "grey": "808080", "silver": "c0c0c0", "navy": "000080", "maroon": "800000",
      "purple": "800080", "teal": "008080", "olive": "808000", "yellow": "ffff00", "lime": "00ff00",
      "aqua": "00ffff", "cyan": "00ffff", "fuchsia": "ff00ff", "magenta": "ff00ff",
      "orange": "ffa500", "brown": "a52a2a", "pink": "ffc0cb", "beige": "f5f5dc", "ivory": "fffff0",
      "whitesmoke": "f5f5f5", "lightgray": "d3d3d3", "lightgrey": "d3d3d3", "darkgray": "a9a9a9",
      "darkgrey": "a9a9a9", "darkred": "8b0000", "darkblue": "00008b", "rebeccapurple": "663399",
    ]
    let text = input.lowercased()
    if ["transparent", "currentcolor", "inherit"].contains(text) { return text }
    var channels: [Double] = []
    var alpha = 1.0
    if let hex = names[text] ?? (text.hasPrefix("#") ? String(text.dropFirst()) : nil) {
      let expanded = hex.count == 3 || hex.count == 4 ? hex.map { "\($0)\($0)" }.joined() : hex
      guard [6, 8].contains(expanded.count), let value = UInt64(expanded, radix: 16) else {
        return nil
      }
      let rgb = expanded.count == 8 ? value >> 8 : value
      channels = [Double(rgb >> 16 & 255), Double(rgb >> 8 & 255), Double(rgb & 255)]
      if expanded.count == 8 { alpha = Double(value & 255) / 255 }
    } else if text.range(of: #"^rgba?\([0-9.,%\s]+\)$"#, options: .regularExpression) != nil {
      let pieces = text.drop(while: { $0 != "(" }).dropFirst().dropLast().split(separator: ",").map
      { $0.trimmingCharacters(in: .whitespaces) }
      guard pieces.count == 3 || pieces.count == 4 else { return nil }
      for part in pieces.prefix(3) {
        guard let number = Double(part.replacingOccurrences(of: "%", with: "")), number.isFinite
        else { return nil }
        channels.append(min(255, max(0, number * (part.hasSuffix("%") ? 2.55 : 1))))
      }
      if pieces.count == 4 {
        guard let a = Double(pieces[3]), a.isFinite else { return nil }
        alpha = min(1, max(0, a))
      }
    } else {
      return nil
    }
    func css(_ values: [Double]) -> String {
      "rgba(\(Int(values[0].rounded())),\(Int(values[1].rounded())),\(Int(values[2].rounded())),\(alpha))"
    }
    let original = css(channels)
    let brightness = 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    // Keep authored hues and distinctions, with readable foregrounds on the dark reading surface.
    let adapted: [Double]
    if background {
      adapted = brightness > 65 ? channels.map { 24 + $0 * 0.12 } : channels
    } else {
      adapted = brightness < 180 ? channels.map { 145 + $0 * 0.40 } : channels
    }
    let key = original + (background ? "b" : "f")
    if let id = colorIDs[key] { return "var(--mail-color-\(id))" }
    guard colors.count < 1024 else { return background ? "var(--paper)" : "var(--ink)" }
    let id = colors.count
    colors.append((original, css(adapted)))
    colorIDs[key] = id
    return "var(--mail-color-\(id))"
  }
  private func length(_ text: String, negative: Bool = false) -> String? {
    if ["auto", "inherit", "initial", "normal", "0"].contains(text) { return text }
    guard
      text.range(
        of: #"^-?(?:[0-9]+(?:\.[0-9]+)?|\.[0-9]+)(?:px|pt|em|rem|%|in|cm|mm)$"#,
        options: .regularExpression) != nil,
      let number = Double(text.prefix(while: { $0.isNumber || $0 == "." || $0 == "-" })),
      number.isFinite, number >= (negative ? -100 : 0), number <= 4096
    else { return nil }
    return text
  }
  private func declaration(_ key: String, _ value: String) -> String? {
    let choices: [String: Set<String>] = [
      "text-align": ["left", "right", "center", "justify", "start", "end"],
      "vertical-align": [
        "top", "middle", "bottom", "baseline", "text-top", "text-bottom", "sub", "super",
      ],
      "font-style": ["normal", "italic", "oblique"],
      "font-weight": [
        "normal", "bold", "bolder", "lighter", "100", "200", "300", "400", "500", "600", "700",
        "800", "900",
      ],
      "text-decoration": ["none", "underline", "line-through", "underline line-through"],
      "white-space": ["normal", "pre", "pre-wrap", "pre-line", "nowrap", "break-spaces"],
      "word-break": ["normal", "break-all", "keep-all", "break-word"],
      "overflow-wrap": ["normal", "anywhere", "break-word"],
      "display": [
        "none", "block", "inline", "inline-block", "table", "table-row", "table-cell",
        "table-row-group", "table-header-group", "table-footer-group", "flex",
      ],
      "visibility": ["visible", "hidden", "collapse"], "border-collapse": ["collapse", "separate"],
      "table-layout": ["auto", "fixed"], "direction": ["ltr", "rtl"],
      "list-style-type": [
        "none", "disc", "circle", "square", "decimal", "lower-alpha", "upper-alpha", "lower-roman",
        "upper-roman",
      ],
      "flex-direction": ["row", "column"], "flex-wrap": ["wrap", "nowrap"],
      "align-items": ["start", "end", "center", "stretch", "baseline"],
      "justify-content": ["start", "end", "center", "space-between", "space-around"],
    ]
    if let allowed = choices[key] {
      return allowed.contains(value.lowercased()) ? value.lowercased() : nil
    }
    if key == "color" || key == "background-color" {
      return color(value, background: key == "background-color")
    }
    if key == "background" {
      return color(value, background: true).map { "background-color:" + $0 }
    }
    if key == "font-family" {
      let fonts = value.split(separator: ",").prefix(8).compactMap { item -> String? in
        let name = item.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
        guard !name.isEmpty, name.utf8.count <= 80,
          name.unicodeScalars.allSatisfy({
            CharacterSet.alphanumerics.contains($0) || " -_".unicodeScalars.contains($0)
          })
        else { return nil }
        return "'" + name + "'"
      }
      return fonts.isEmpty ? nil : fonts.joined(separator: ",") + ",-apple-system,sans-serif"
    }
    if key == "font-size" {
      if ["small", "medium", "large", "x-small", "x-large", "xx-large", "smaller", "larger"]
        .contains(value)
      {
        return value
      }
      guard let size = length(value), !["auto", "normal", "initial"].contains(size) else {
        return nil
      }
      return size.hasSuffix("px") || size.hasSuffix("pt")
        ? "calc(\(size) * var(--mail-scale))" : size
    }
    if key == "line-height", let number = Double(value), number >= 0.5, number <= 5 { return value }
    if [
      "width", "height", "min-width", "max-width", "min-height", "max-height", "line-height",
      "text-indent", "letter-spacing", "word-spacing",
    ].contains(key) {
      return length(value, negative: key == "text-indent")
    }
    if ["margin", "padding", "border-spacing", "gap"].contains(key) || key.hasPrefix("margin-")
      || key.hasPrefix("padding-")
    {
      let parts = value.split(whereSeparator: { $0.isWhitespace })
      guard !parts.isEmpty, parts.count <= 4,
        parts.allSatisfy({ length(String($0), negative: key.hasPrefix("margin")) != nil })
      else { return nil }
      return parts.joined(separator: " ")
    }
    if [
      "border-width", "border-top-width", "border-right-width", "border-bottom-width",
      "border-left-width",
    ].contains(key) {
      let parts = value.split(whereSeparator: { $0.isWhitespace })
      guard !parts.isEmpty, parts.count <= 4, parts.allSatisfy({ length(String($0)) != nil }) else {
        return nil
      }
      return parts.joined(separator: " ")
    }
    if [
      "border-style", "border-top-style", "border-right-style", "border-bottom-style",
      "border-left-style",
    ].contains(key) {
      let parts = value.split(whereSeparator: { $0.isWhitespace })
      guard !parts.isEmpty, parts.count <= 4,
        parts.allSatisfy({
          ["solid", "dashed", "dotted", "double", "none", "hidden"].contains(String($0))
        })
      else { return nil }
      return parts.joined(separator: " ")
    }
    if [
      "border-color", "border-top-color", "border-right-color", "border-bottom-color",
      "border-left-color",
    ].contains(key) {
      return color(value, background: false)
    }
    if key == "border"
      || ["border-top", "border-right", "border-bottom", "border-left"].contains(key)
    {
      if value == "0" || value == "none" { return "0" }
      let parts = value.split(whereSeparator: { $0.isWhitespace }).map(String.init)
      guard parts.count <= 3 else { return nil }
      var result: [String] = []
      for part in parts {
        if ["solid", "dashed", "dotted", "double", "none", "hidden"].contains(part) {
          result.append(part)
        } else if let n = length(part), !["auto", "normal", "inherit", "initial"].contains(n) {
          result.append(n)
        } else if let c = color(part, background: false) {
          result.append(c)
        } else {
          return nil
        }
      }
      return result.isEmpty ? nil : result.joined(separator: " ")
    }
    if key == "border-radius" { return length(value) }
    if key == "mso-hide", value == "all" { return "display:none" }
    return nil
  }
  func declarations(_ input: String) -> String {
    guard input.utf8.count <= 16384, !input.contains("\\"), !input.contains("/*"),
      !input.contains("<")
    else { return "" }
    var result: [String] = []
    for raw in input.split(separator: ";").prefix(100) {
      let pair = raw.split(separator: ":", maxSplits: 1)
      guard pair.count == 2 else { continue }
      let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
      guard key.range(of: #"^[a-z-]+$"#, options: .regularExpression) != nil else { continue }
      var value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
      let important = value.lowercased().hasSuffix("!important")
      if important { value = String(value.dropLast(10)).trimmingCharacters(in: .whitespaces) }
      guard value.utf8.count <= 512, let safe = declaration(key, value) else { continue }
      let replacement = key == "background" || key == "mso-hide"
      result.append((replacement ? safe : key + ":" + safe) + (important ? "!important" : ""))
    }
    return result.joined(separator: ";")
  }
  func inline(_ attrs: [String: String], tag: String) -> String {
    var legacy: [String] = []
    for key in ["width", "height"] {
      if let raw = attrs[key] {
        let value = Int(raw).map { "\($0)px" } ?? raw
        if let safe = length(value) { legacy.append(key + ":" + safe) }
      }
    }
    if tag == "table", let spacing = attrs["cellspacing"], let number = Int(spacing),
      (0...100).contains(number)
    {
      legacy.append("border-collapse:separate;border-spacing:\(number)px")
    }
    if let raw = attrs["bgcolor"], let safe = color(raw, background: true) {
      legacy.append("background-color:" + safe)
    }
    if let raw = attrs["color"], let safe = color(raw, background: false) {
      legacy.append("color:" + safe)
    }
    if let raw = attrs["face"], let safe = declaration("font-family", raw) {
      legacy.append("font-family:" + safe)
    }
    if tag == "font", let raw = attrs["size"], let number = Int(raw), (1...7).contains(number) {
      legacy.append("font-size:calc(\([10,13,16,18,24,32,48][number-1])px * var(--mail-scale))")
    }
    if let raw = attrs["align"], let safe = declaration("text-align", raw) {
      legacy.append("text-align:" + safe)
    }
    if let raw = attrs["valign"], let safe = declaration("vertical-align", raw) {
      legacy.append("vertical-align:" + safe)
    }
    if attrs["hidden"] != nil { legacy.append("display:none!important") }
    legacy.append(declarations(attrs["style"] ?? ""))
    return legacy.filter { !$0.isEmpty }.joined(separator: ";")
  }
  private func selector(_ input: String) -> String? {
    let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard value.utf8.count <= 300, !value.isEmpty,
      value.range(of: #"^[a-zA-Z0-9_.#* >+~,-]+$"#, options: .regularExpression) != nil
    else { return nil }
    let pattern = try! NSRegularExpression(pattern: #"([.#])([a-zA-Z_][a-zA-Z0-9_-]*)"#)
    var result = pattern.stringByReplacingMatches(
      in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "$1m-$2")
    if result == "html" || result == "body" || result == "html body" { return ".mail-content" }
    result = result.replacingOccurrences(
      of: #"^(?:html\s+)?body\b"#, with: ".mail-content", options: .regularExpression)
    return result.hasPrefix(".mail-content") ? result : ".mail-content " + result
  }
  func addStylesheet(_ input: String, depth: Int = 0) {
    guard depth < 4, input.utf8.count <= 128 * 1024, rules.count < 512 else { return }
    let source = input.replacingOccurrences(
      of: #"(?s)/\*.*?\*/"#, with: "", options: .regularExpression)
    var cursor = source.startIndex
    while cursor < source.endIndex, rules.count < 512, ruleBytes < 128 * 1024,
      let open = source[cursor...].firstIndex(of: "{")
    {
      let header = String(source[cursor..<open]).trimmingCharacters(in: .whitespacesAndNewlines)
      var end = source.index(after: open)
      var level = 1
      while end < source.endIndex {
        if source[end] == "{" { level += 1 }
        if source[end] == "}" {
          level -= 1
          if level == 0 { break }
        }
        end = source.index(after: end)
      }
      guard end < source.endIndex else { break }
      let body = String(source[source.index(after: open)..<end])
      cursor = source.index(after: end)
      if header.hasPrefix("@media"),
        header.range(
          of: #"^@media\s+(?:only\s+)?(?:screen\s+and\s+)?\((?:max|min)-width:\s*[0-9]{1,4}px\)$"#,
          options: .regularExpression) != nil
      {
        let before = rules.count
        addStylesheet(body, depth: depth + 1)
        if rules.count > before {
          let nested = rules[before...].joined()
          rules.removeSubrange(before...)
          rules.append(header + "{" + nested + "}")
        }
      } else if !header.hasPrefix("@") {
        let selectors = header.split(separator: ",").prefix(16).compactMap { selector(String($0)) }
        let safe = declarations(body)
        if !selectors.isEmpty && !safe.isEmpty {
          let rule = selectors.joined(separator: ",") + "{" + safe + "}"
          if rule.utf8.count <= 128 * 1024 - ruleBytes {
            rules.append(rule)
            ruleBytes += rule.utf8.count
          }
        }
      }
    }
  }
}
