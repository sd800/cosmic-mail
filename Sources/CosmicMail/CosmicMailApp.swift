import AppKit
import MailCore
import SwiftUI

@main struct CosmicMailApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  @ObservedObject private var prefs = Preferences.shared
  @ObservedObject private var model = AppModel.shared
  var body: some Scene {
    Window("Cosmic Mail", id: "main") {
      ContentView().font(.system(size: 14)).preferredColorScheme(prefs.colorScheme)
        .frame(minWidth: 860, minHeight: 580)
        .background(MainWindowLifecycle(close: model.closeAll).frame(width: 0, height: 0))
    }.defaultSize(width: 1120, height: 760)
      .commands {
        CommandGroup(replacing: .newItem) {
          Button(L("Open…", "打开…")) { AppModel.shared.chooseFiles() }.keyboardShortcut("o")
          Button(L("Close all files", "关闭所有文件")) { AppModel.shared.closeAll() }.keyboardShortcut(
            "w", modifiers: [.command, .shift])
        }
        CommandGroup(after: .saveItem) {
          Button(L("Export original…", "导出原始邮件…")) { AppModel.shared.exportOriginal() }
            .keyboardShortcut("s", modifiers: [.command, .shift]).disabled(model.entry == nil)
        }
        CommandGroup(replacing: .appInfo) {
          Button(L("About Cosmic Mail", "关于 Cosmic Mail")) {
            NSApp.orderFrontStandardAboutPanel(options: [
              .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"]
                as? String ?? ""
            ])
          }
        }
      }
    Settings { SettingsView() }
  }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, open urls: [URL]) { AppModel.shared.open(urls) }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    if !flag {
      for window in sender.windows where window.canBecomeMain {
        window.makeKeyAndOrderFront(nil)
        break
      }
    }
    return true
  }
  func applicationWillTerminate(_ notification: Notification) { AppModel.shared.closeAll() }
}
