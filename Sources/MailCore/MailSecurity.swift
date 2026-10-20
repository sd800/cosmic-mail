import Foundation

public enum MailSecurity {
  /// WebKit's content blocker uses a restricted regex dialect: keep each scheme separate.
  public static let contentRules =
    #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^ftp://"},"action":{"type":"block"}},{"trigger":{"url-filter":"^file://"},"action":{"type":"block"}}]"#
}
