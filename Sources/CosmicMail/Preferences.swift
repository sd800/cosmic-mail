import AppKit
import SwiftUI

@MainActor final class Preferences: ObservableObject {
  static let shared = Preferences()
  @Published var language: String {
    didSet { UserDefaults.standard.set(language, forKey: "language") }
  }
  @Published var appearance: String {
    didSet { UserDefaults.standard.set(appearance, forKey: "appearance") }
  }
  @Published var textSize: Double {
    didSet { UserDefaults.standard.set(textSize, forKey: "textSize") }
  }
  init() {
    language = UserDefaults.standard.string(forKey: "language") ?? "auto"
    appearance = UserDefaults.standard.string(forKey: "appearance") ?? "auto"
    textSize = UserDefaults.standard.object(forKey: "textSize") as? Double ?? 16
  }
  var chinese: Bool {
    language == "zh-CN"
      || language == "auto" && (Locale.preferredLanguages.first?.hasPrefix("zh") ?? false)
  }
  var colorScheme: ColorScheme? {
    appearance == "dark" ? .dark : appearance == "light" ? .light : nil
  }
}
@MainActor func L(_ english: String, _ chinese: String) -> String {
  Preferences.shared.chinese ? chinese : english
}
func copyText(_ value: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.setString(value, forType: .string)
}
struct SettingsView: View {
  @ObservedObject var prefs = Preferences.shared
  @State private var defaultStatus = ""
  var body: some View {
    Form {
      Section {
        Picker(L("Language", "语言"), selection: $prefs.language) {
          Text(L("Automatic", "自动")).tag("auto")
          Text("English").tag("en-US")
          Text("简体中文").tag("zh-CN")
        }
        Picker(L("Appearance", "外观"), selection: $prefs.appearance) {
          Text(L("Automatic", "自动")).tag("auto")
          Text(L("Light", "浅色")).tag("light")
          Text(L("Dark", "深色")).tag("dark")
        }
        Picker(L("Reading text size", "正文字号"), selection: $prefs.textSize) {
          ForEach([14.0, 16, 18, 20], id: \.self) { Text("\(Int($0)) pt").tag($0) }
        }
      } header: {
        Text(L("Reading", "阅读"))
      }
      Section {
        VStack(alignment: .leading, spacing: 12) {
          Text(
            L(
              "Open email links here, without opening a compose window or connecting an account.",
              "在此接住邮件链接，无需打开撰写窗口或连接邮箱账号。")
          ).foregroundStyle(.secondary)
          Button(L("Use Cosmic Mail for email links…", "使用 Cosmic Mail 打开邮件链接…")) {
            let alert = NSAlert()
            alert.messageText = L("Use Cosmic Mail for email links?", "使用 Cosmic Mail 打开邮件链接？")
            alert.informativeText = L(
              "This changes the default app for mailto links. You can change it later in another email app.",
              "这将更改 mailto 链接的默认打开应用。之后可在其他邮件应用中重新设置。")
            alert.addButton(withTitle: L("Use Cosmic Mail", "使用 Cosmic Mail"))
            alert.addButton(withTitle: L("Cancel", "取消"))
            if alert.runModal() == .alertFirstButtonReturn {
              NSWorkspace.shared.setDefaultApplication(
                at: Bundle.main.bundleURL, toOpenURLsWithScheme: "mailto"
              ) { error in
                DispatchQueue.main.async {
                  defaultStatus =
                    error == nil
                    ? L("Cosmic Mail now opens email links.", "邮件链接现在由 Cosmic Mail 打开。")
                    : L(
                      "Could not change the default app. Try after moving Cosmic Mail to Applications.",
                      "未能更改默认应用，请将 Cosmic Mail 移至应用程序文件夹后重试。")
                }
              }
            }
          }
          if !defaultStatus.isEmpty {
            Text(defaultStatus).font(.system(size: 14)).foregroundStyle(.secondary)
          }
        }.padding(.vertical, 4)
      } header: {
        Text(L("Email links", "邮件链接"))
      }
      Section {
        Label(L("Mail stays on your Mac.", "邮件留在你的 Mac 上。"), systemImage: "lock.shield")
        Text(
          L(
            "Remote images, scripts, and automatic attachment opening are blocked. No accounts, sending, tracking, or cloud uploads.",
            "不加载远程图片，不运行脚本，不自动打开附件。不连接账号、不发送邮件，也无追踪或云端上传。")
        ).foregroundStyle(.secondary)
      } header: {
        Text(L("Privacy", "隐私"))
      }
      HStack {
        Text(
          "Cosmic Mail \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "26.1020.1")"
        )
        Spacer()
        Text("© 2026 Songming.org")
      }.font(.system(size: 13)).foregroundStyle(.secondary)
    }.font(.system(size: 14)).formStyle(.grouped).frame(width: 560).padding(.vertical, 8)
      .preferredColorScheme(
        prefs.colorScheme)
  }
}
