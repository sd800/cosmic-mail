import Foundation

/// RFC email dates keep their stated numeric offset. Comments such as CST do not override it.
public enum MailDate {
  private static let offsetPattern = try! NSRegularExpression(
    pattern: #"(?:^|\s)([+-])(\d{2}):?(\d{2})$"#)

  private static let cache: NSCache<NSString, NSString> = {
    let value = NSCache<NSString, NSString>()
    value.countLimit = 1024
    value.totalCostLimit = 1024 * 1024
    return value
  }()
  public static func display(_ raw: String, locale: Locale = .current) -> String {
    guard raw.utf8.count <= 4096 else { return raw }
    let key = (locale.identifier + "\u{0}" + raw) as NSString
    if let result = cache.object(forKey: key) { return result as String }
    let result = formatted(raw, locale: locale)
    cache.setObject(result as NSString, forKey: key, cost: key.length * 2 + result.utf8.count)
    return result
  }
  private static func formatted(_ raw: String, locale: Locale) -> String {
    guard raw.utf8.count <= 4096, let cleaned = withoutComments(raw) else { return raw }
    let text = cleaned.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let ns = text as NSString
    var offset: Int
    var prefix: String
    if let match = offsetPattern.firstMatch(
      in: text, range: NSRange(location: 0, length: ns.length)),
      let hours = Int(ns.substring(with: match.range(at: 2))),
      let minutes = Int(ns.substring(with: match.range(at: 3))), hours <= 23, minutes < 60
    {
      let sign = ns.substring(with: match.range(at: 1)) == "-" ? -1 : 1
      offset = sign * (hours * 3600 + minutes * 60)
      prefix = ns.substring(to: match.range.location).trimmingCharacters(in: .whitespaces)
    } else if let last = text.split(separator: " ").last,
      ["UT", "UTC", "GMT", "Z"].contains(last.uppercased())
    {
      offset = 0
      prefix = String(text.dropLast(last.count)).trimmingCharacters(in: .whitespaces)
    } else {
      // A lone ambiguous abbreviation does not establish a reliable numeric offset.
      return raw
    }
    let absolute = abs(offset)
    let sign = offset < 0 ? "-" : "+"
    let zoneLabel =
      "UTC\(sign)\(absolute / 3600)"
      + (absolute % 3600 == 0 ? "" : String(format: ":%02d", absolute / 60 % 60))
    let numericZone = String(format: "%@%02d%02d", sign, absolute / 3600, absolute / 60 % 60)
    guard let zone = TimeZone(secondsFromGMT: offset) else { return prefix + " " + zoneLabel }
    let parser = DateFormatter()
    parser.locale = Locale(identifier: "en_US_POSIX")
    parser.calendar = Calendar(identifier: .gregorian)
    parser.timeZone = zone
    parser.isLenient = false
    for (pattern, seconds) in [
      ("EEE, d MMM yyyy HH:mm:ss Z", true), ("d MMM yyyy HH:mm:ss Z", true),
      ("EEE, d MMM yyyy HH:mm Z", false), ("d MMM yyyy HH:mm Z", false),
    ] {
      parser.dateFormat = pattern
      guard let date = parser.date(from: prefix + " " + numericZone) else { continue }
      let output = DateFormatter()
      output.locale = locale
      output.calendar = Calendar(identifier: .gregorian)
      output.timeZone = zone
      output.dateStyle = .medium
      output.timeStyle = seconds ? .medium : .short
      return output.string(from: date) + " " + zoneLabel
    }
    return prefix + " " + zoneLabel
  }

  private static func withoutComments(_ raw: String) -> String? {
    var output = ""
    var depth = 0
    var escaped = false
    for character in raw {
      if escaped {
        if depth == 0 { output.append(character) }
        escaped = false
      } else if character == "\\" && depth > 0 {
        escaped = true
      } else if character == "(" {
        depth += 1
        guard depth <= 16 else { return nil }
        if depth == 1 { output.append(" ") }
      } else if character == ")" {
        guard depth > 0 else { return nil }
        depth -= 1
      } else if depth == 0 {
        output.append(character)
      }
    }
    return depth == 0 ? output : nil
  }
}
