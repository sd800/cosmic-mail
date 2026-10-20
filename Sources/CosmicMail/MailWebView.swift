import MailCore
import SwiftUI
import WebKit

/// Only app-generated, sanitized markup enters this view. Three independent barriers:
/// allowlist reconstruction, a restrictive CSP, and a WebKit resource block list.
struct MailWebView: NSViewRepresentable {
  let rendered: RenderedMail
  let identity: UUID
  let dark: Bool
  let scale: Double
  let open: (String) -> Void
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
    configuration.preferences.isElementFullscreenEnabled = false
    let web = WKWebView(frame: .zero, configuration: configuration)
    let coordinator = context.coordinator
    web.navigationDelegate = coordinator
    web.allowsBackForwardNavigationGestures = false
    // Do not load any message until this independent network barrier is installed.
    let rules = MailSecurity.contentRules
    WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: "CosmicMail.LocalOnly.v2", encodedContentRuleList: rules
    ) { [weak web, weak coordinator] list, _ in
      guard let web, let coordinator else { return }
      if let list {
        web.configuration.userContentController.add(list)
        coordinator.ready = true
        coordinator.load(web)
      } else {
        // Fail closed: show only escaped plain text, without resource references.
        coordinator.failed = true
        coordinator.load(web)
      }
    }
    return web
  }
  func updateNSView(_ web: WKWebView, context: Context) {
    let coordinator = context.coordinator
    let (paperColor, paperRGB) = Self.paperColor(dark: dark)
    let paperCSS = String(format: "#%06X", paperRGB)
    coordinator.open = open
    coordinator.links = rendered.links
    coordinator.html = rendered.page(dark: dark, scale: scale, backgroundRGB: paperRGB)
    coordinator.fallback = RenderedMail(
      body: "<div class=\"plain\">" + SafeHTML.escape(AppModel.shared.message?.plain ?? "")
        + "</div>", links: [:]
    ).page(dark: dark, scale: scale, backgroundRGB: paperRGB)
    let changed = coordinator.identity != identity || coordinator.scale != scale
    coordinator.identity = identity
    coordinator.scale = scale
    if changed {
      coordinator.load(web)
    } else if coordinator.dark != dark || coordinator.paperRGB != paperRGB {
      // Fixed app-owned code only; the source message never supplies JavaScript.
      web.evaluateJavaScript(
        "document.documentElement.dataset.theme='\(dark ? "dark" : "light")';document.documentElement.style.setProperty('--paper','\(paperCSS)')"
      )
    }
    coordinator.dark = dark
    coordinator.paperRGB = paperRGB
    web.underPageBackgroundColor = paperColor
  }
  private static func paperColor(dark: Bool) -> (NSColor, UInt32) {
    var resolved = dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor.white
    NSAppearance(named: dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
      resolved = NSColor.textBackgroundColor.usingColorSpace(.sRGB) ?? resolved
    }
    let color = resolved.usingColorSpace(.sRGB) ?? resolved
    func byte(_ value: CGFloat) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
    let rgb =
      byte(color.redComponent) << 16 | byte(color.greenComponent) << 8 | byte(color.blueComponent)
    return (color, rgb)
  }
  static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
    web.stopLoading()
    web.navigationDelegate = nil
    coordinator.open = nil
    coordinator.links = [:]
    coordinator.html = ""
    coordinator.fallback = ""
  }
  final class Coordinator: NSObject, WKNavigationDelegate {
    var paperRGB: UInt32?
    var identity: UUID?, scale: Double = 1, dark = false, ready = false, failed = false
    var links: [String: String] = [:], html = "", fallback = "", open: ((String) -> Void)?
    func load(_ web: WKWebView) {
      guard !html.isEmpty, ready || failed else { return }
      web.loadHTMLString(ready ? html : fallback, baseURL: nil)
    }
    func webView(
      _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard let url = action.request.url else {
        decisionHandler(.cancel)
        return
      }
      if action.navigationType == .linkActivated, url.scheme == "cosmic-link", let id = url.host,
        let target = links[id]
      {
        decisionHandler(.cancel)
        open?(target)
        return
      }
      if action.navigationType == .other && url.absoluteString == "about:blank" {
        decisionHandler(.allow)
        return
      }
      decisionHandler(.cancel)
    }
    func webView(
      _ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
      decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
      decisionHandler(response.isForMainFrame ? .allow : .cancel)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      // No reload loop for a damaged or unexpectedly expensive message.
      webView.stopLoading()
      AppModel.shared.error = L(
        "The reading view stopped. Select the message again to reopen it.", "阅读视图已停止，请重新选择邮件。")
    }
  }
}
