import AppKit
import SwiftUI

/// Hiding/reparenting SwiftUI content is not a close-document event.
struct MainWindowLifecycle: NSViewRepresentable {
  let close: @MainActor () -> Void
  func makeNSView(context: Context) -> Anchor {
    let anchor = Anchor()
    anchor.close = close
    return anchor
  }
  func updateNSView(_ anchor: Anchor, context: Context) { anchor.close = close }

  @MainActor final class Anchor: NSView {
    var close: (@MainActor () -> Void)?
    private weak var observedWindow: NSWindow?
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if observedWindow === window { return }
      NotificationCenter.default.removeObserver(
        self, name: NSWindow.willCloseNotification, object: observedWindow)
      observedWindow = window
      if let window {
        NotificationCenter.default.addObserver(
          self, selector: #selector(windowClosing), name: NSWindow.willCloseNotification,
          object: window)
      }
    }
    @objc private func windowClosing(_ notification: Notification) { close?() }
    deinit { NotificationCenter.default.removeObserver(self) }
  }
}
