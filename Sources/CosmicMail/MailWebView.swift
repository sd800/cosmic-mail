import MailCore
import SwiftUI
import WebKit

/// One local shell per reading view. Message changes do not navigate/recreate WebKit.
struct MailWebView: NSViewRepresentable {
  let rendered: RenderedMail
  let plain: String
  let identity: UUID
  let dark: Bool
  let scale: Double
  let interactive: Bool
  let open: (String, UUID, NSView, NSRect) -> Void

  /// App-owned code in an isolated world. Mail is passed as data, never interpolated as code.
  static let updateScript = """
    if (replace) {
      const fragment = document.createElement('template');
      fragment.innerHTML = body;
      window.getSelection()?.removeAllRanges();
      const wrapper = document.createElement('div');
      wrapper.className = 'mail-content';
      wrapper.append(fragment.content);
      document.body.replaceChildren(wrapper);
      document.getElementById('mail-styles').textContent = stylesheet;
      window.scrollTo(0, 0);
    }
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    document.documentElement.style.setProperty('--paper', paper);
    document.body.style.fontSize = fontSize + 'px';
    document.documentElement.style.setProperty('--mail-scale', fontSize / 16);
    return true;
    """

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
    web.underPageBackgroundColor = Self.paperColor(dark: dark).0
    coordinator.web = web
    WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: "CosmicMail.LocalOnly.v2", encodedContentRuleList: MailSecurity.contentRules
    ) { [weak web, weak coordinator] list, _ in
      guard let web, let coordinator, !coordinator.retired else { return }
      if let list {
        web.configuration.userContentController.add(list)
        coordinator.ready = true
      } else {
        // Fail closed: the shell receives escaped text only if the resource barrier fails.
        coordinator.failed = true
      }
      coordinator.loadShell()
    }
    return web
  }
  func updateNSView(_ web: WKWebView, context: Context) {
    let coordinator = context.coordinator
    let (paperColor, rgb) = Self.paperColor(dark: dark)
    web.underPageBackgroundColor = paperColor
    coordinator.open = open
    coordinator.interactive = interactive
    let request = Content(
      identity: identity, rendered: rendered, plain: plain, dark: dark,
      scale: min(2, max(0.5, scale.isFinite ? scale : 1)), paperRGB: rgb)
    coordinator.desired = request
    if coordinator.terminatedAt != nil, coordinator.terminatedAt != identity {
      coordinator.terminatedAt = nil
      coordinator.loadShell()
    }
    coordinator.apply()
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
    coordinator.retired = true
    web.stopLoading()
    web.navigationDelegate = nil
    coordinator.open = nil
    coordinator.links = [:]
    coordinator.desired = nil
    coordinator.applied = nil
    coordinator.web = nil
  }
  struct Content {
    var identity: UUID
    var rendered: RenderedMail
    var plain: String
    var dark: Bool
    var scale: Double
    var paperRGB: UInt32
    func matches(_ other: Content?) -> Bool {
      other?.identity == identity && other?.dark == dark && other?.scale == scale
        && other?.paperRGB == paperRGB
    }
  }
  final class Coordinator: NSObject, WKNavigationDelegate {
    weak var web: WKWebView?
    var ready = false, failed = false, retired = false, interactive = false
    private var shellNavigation: WKNavigation?
    private var documentReady = false
    private var applying = false
    var desired: Content?, applied: Content?
    var terminatedAt: UUID?
    private var failedAt: UUID?
    var links: [String: String] = [:], open: ((String, UUID, NSView, NSRect) -> Void)?

    func loadShell() {
      guard !retired, let web, ready || failed, shellNavigation == nil else { return }
      // Empty trusted shell only; message content never enters a navigation/loadHTMLString call.
      let html = RenderedMail(body: "", links: [:]).page(
        dark: desired?.dark ?? false, scale: desired?.scale ?? 1,
        backgroundRGB: desired?.paperRGB)
      documentReady = false
      shellNavigation = web.loadHTMLString(html, baseURL: nil)
    }
    func apply() {
      guard !retired, documentReady, !applying, terminatedAt == nil, let web,
        let request = desired, failedAt != request.identity, !request.matches(applied)
      else { return }
      applying = true
      let replace = applied?.identity != request.identity
      let body =
        ready
        ? request.rendered.body
        : "<div class=\"plain\">" + SafeHTML.escape(request.plain) + "</div>"
      web.callAsyncJavaScript(
        MailWebView.updateScript,
        arguments: [
          "body": replace ? body : "", "stylesheet": ready ? request.rendered.stylesheet : "",
          "replace": replace, "dark": request.dark,
          "paper": String(format: "#%06X", request.paperRGB), "fontSize": 16 * request.scale,
        ], in: nil, in: .defaultClient
      ) { [weak self] result in
        guard let self, !self.retired, self.terminatedAt == nil else { return }
        self.applying = false
        switch result {
        case .success:
          self.applied = request
          self.links = self.ready ? request.rendered.links : [:]
          self.apply()  // At most one in-flight update; coalesce rapid changes to the latest request.
        case .failure:
          self.failedAt = request.identity
          self.links = [:]
          if self.desired?.identity != request.identity {
            self.apply()
            return
          }
          AppModel.shared.readingViewFailed(
            request.identity,
            explanation: L(
              "The reading view could not update. Try opening the message again.",
              "阅读视图未能更新，请尝试重新打开这封邮件。"))
        }
      }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
      guard !retired, navigation === shellNavigation else { return }
      documentReady = true
      apply()
    }
    func webView(
      _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard !retired, let url = action.request.url else {
        decisionHandler(.cancel)
        return
      }
      if action.navigationType == .linkActivated, url.scheme == "cosmic-link", let id = url.host,
        interactive, !applying, desired?.identity == applied?.identity, let target = links[id]
      {
        decisionHandler(.cancel)
        guard let identity = applied?.identity else { return }
        // Query only the already-sanitized anchor; source mail cannot supply executable code.
        webView.callAsyncJavaScript(
          "const a=[...document.links].find(a=>a.getAttribute('href')===href); if(!a)return null; const r=a.getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height};",
          arguments: ["href": url.absoluteString], in: nil, in: .defaultClient
        ) { [weak self, weak webView] result in
          guard let self, let webView, !self.retired, self.interactive, !self.applying,
            self.applied?.identity == identity, self.desired?.identity == identity
          else { return }
          var rectangle = NSRect(
            x: webView.bounds.midX, y: webView.bounds.midY, width: 1, height: 1)
          if case .success(let value) = result, let box = value as? [String: Double],
            let x = box["x"], let y = box["y"], let width = box["width"],
            let height = box["height"],
            [x, y, width, height].allSatisfy({ $0.isFinite }), width > 0, height > 0
          {
            rectangle = NSRect(
              x: x, y: webView.isFlipped ? y : webView.bounds.height - y - height, width: width,
              height: height)
            if !rectangle.intersects(webView.bounds) { return }
          }
          self.open?(target, identity, webView, rectangle)
        }
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
      decisionHandler(!retired && response.isForMainFrame ? .allow : .cancel)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      navigationFailed(error)
    }
    func webView(
      _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
      withError error: Error
    ) {
      navigationFailed(error)
    }
    private func navigationFailed(_ error: Error) {
      guard !retired, (error as NSError).code != NSURLErrorCancelled else { return }
      documentReady = false
      shellNavigation = nil
      terminatedAt = desired?.identity ?? UUID()
      links = [:]
      AppModel.shared.readingViewFailed(
        desired?.identity,
        explanation: L(
          "The reading view could not open. Try opening the message again.",
          "阅读视图未能打开，请尝试重新打开这封邮件。"))
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
      guard !retired else { return }
      webView.stopLoading()
      terminatedAt = desired?.identity
      documentReady = false
      shellNavigation = nil
      applying = false
      applied = nil
      links = [:]
      // Explicit reselection can recreate the shell, but unrelated updates never start a reload loop.
      AppModel.shared.readingViewFailed(
        desired?.identity,
        explanation: L(
          "The reading view stopped. Try opening the message again.", "阅读视图已停止，请尝试重新打开这封邮件。"))
    }
  }
}
