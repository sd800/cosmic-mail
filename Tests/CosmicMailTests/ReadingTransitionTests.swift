import AppKit
import WebKit
import XCTest

@testable import CosmicMail
@testable import MailCore

final class ReadingTransitionTests: XCTestCase {
  private func fixture() throws -> (URL, MailCollection) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("small.mbox")
    let raw =
      "From a@example.edu Mon Oct 19 12:00:00 2026\nFrom: a@example.edu\nSubject: First\n\nOne\nFrom b@example.edu Tue Oct 20 12:00:00 2026\nFrom: b@example.edu\nSubject: Second\n\nTwo"
    try Data(raw.utf8).write(to: file)
    return (file, try MailReader.collection(file))
  }
  @MainActor private func waitUntil(_ predicate: () -> Bool) async throws {
    for _ in 0..<200 {
      if predicate() { return }
      try await Task.sleep(for: .milliseconds(10))
    }
    XCTFail("Small-input operation did not finish")
  }
  @MainActor func testSwitchRetainsPresentationAndLatestSelectionWins() async throws {
    let (_, box) = try fixture()
    let model = AppModel()
    model.collections = [box]
    model.selectedCollection = box.id
    model.select(0)
    try await waitUntil { !model.reading }
    XCTAssertEqual(model.message?.subject, "First")
    let identity = model.selectionVersion
    let body = model.rendered?.body
    model.select(1)
    // No intermediate nil state, new identity, or wrong-message actions during the read.
    XCTAssertTrue(model.reading)
    XCTAssertEqual(model.message?.subject, "First")
    XCTAssertEqual(model.rendered?.body, body)
    XCTAssertEqual(model.selectionVersion, identity)
    XCTAssertFalse(model.currentMessageReady)
    try await waitUntil { !model.reading }
    XCTAssertEqual(model.message?.subject, "Second")
    XCTAssertTrue(model.currentMessageReady)
    let secondIdentity = model.selectionVersion
    model.external("mailto:stale@example.edu", from: identity)
    XCTAssertNil(model.capture)
    model.select(1)
    XCTAssertEqual(model.selectionVersion, secondIdentity)
    XCTAssertFalse(model.reading)
    model.readingViewFailed(identity, explanation: "Stale")
    XCTAssertFalse(model.readerFailed)
    model.readingViewFailed(secondIdentity, explanation: "Test failure")
    XCTAssertTrue(model.readerFailed)
    model.error = nil  // Dismissing the alert must not prevent explicit retry.
    model.select(1)
    XCTAssertTrue(model.reading)
    try await waitUntil { !model.reading }
    XCTAssertFalse(model.readerFailed)
    model.select(0)
    model.select(1)
    try await waitUntil { !model.reading }
    XCTAssertEqual(model.message?.subject, "Second")
    model.select(0)
    model.closeAll()
    try await Task.sleep(for: .milliseconds(20))
    XCTAssertNil(model.message)
    XCTAssertNil(model.rendered)
    XCTAssertFalse(model.currentMessageReady)
  }
  @MainActor func testFailedReadDoesNotLeavePreviousMailSelected() async throws {
    let (file, box) = try fixture()
    let model = AppModel()
    model.collections = [box]
    model.selectedCollection = box.id
    model.select(0)
    try await waitUntil { !model.reading }
    try Data("Changed".utf8).write(to: file, options: .atomic)
    model.select(1)
    try await waitUntil { !model.reading }
    XCTAssertNotNil(model.error)
    XCTAssertNil(model.message)
    XCTAssertNil(model.rendered)
    XCTAssertFalse(model.currentMessageReady)
    model.closeAll()
  }
  @MainActor func testLocalShellIsReusedAndAppearanceDoesNotResetText() async throws {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let web = WKWebView(
      frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
    let rules: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
      WKContentRuleListStore.default().compileContentRuleList(
        forIdentifier: "CosmicMail.ReadingTest", encodedContentRuleList: MailSecurity.contentRules
      ) { list, error in
        if let list {
          continuation.resume(returning: list)
        } else {
          continuation.resume(throwing: error ?? MailError.malformed)
        }
      }
    }
    web.configuration.userContentController.add(rules)
    let coordinator = MailWebView.Coordinator()
    coordinator.web = web
    coordinator.ready = true
    web.navigationDelegate = coordinator
    let first = UUID()
    var request = MailWebView.Content(
      identity: first, rendered: RenderedMail(body: "<p>First</p>", links: [:]), plain: "First",
      dark: true, scale: 1, paperRGB: 0x1E1E1E)
    coordinator.desired = request
    coordinator.loadShell()
    try await waitUntil { coordinator.applied?.identity == first }
    _ = try await script(
      web,
      "document.documentElement.dataset.shell='kept'; const r=document.createRange();r.selectNodeContents(document.querySelector('p'));window.getSelection().addRange(r); return true;"
    )
    request.dark = false
    request.paperRGB = 0xFFFFFF
    request.scale = 1.25
    coordinator.desired = request
    coordinator.apply()
    try await waitUntil { request.matches(coordinator.applied) }
    let retainedSelection =
      try await script(web, "return window.getSelection().toString();") as? String
    XCTAssertEqual(retainedSelection, "First")
    let second = UUID()
    request.identity = second
    let text = "Second 'quoted' \\ \" <literal>"
    request.rendered = RenderedMail(body: "<p>" + SafeHTML.escape(text) + "</p>", links: [:])
    coordinator.desired = request
    coordinator.apply()
    try await waitUntil { coordinator.applied?.identity == second }
    let state =
      try await script(
        web,
        #"""
        return {
          text: document.body.textContent,
          shell: document.documentElement.dataset.shell,
          selection: window.getSelection().toString(),
          font: document.body.style.fontSize,
          csp: document.querySelector('meta[http-equiv="Content-Security-Policy"]').content.includes("script-src 'none'")
        };
        """#) as? [String: Any]
    XCTAssertEqual(state?["text"] as? String, text)
    XCTAssertEqual(state?["shell"] as? String, "kept")
    XCTAssertEqual(state?["selection"] as? String, "")
    XCTAssertEqual(state?["font"] as? String, "20px")
    XCTAssertEqual(state?["csp"] as? Bool, true)
    MailWebView.dismantleNSView(web, coordinator: coordinator)
  }
  @MainActor func testOpeningFilesAppendsAndRestoresSelectedMessage() async throws {
    let (file, _) = try fixture()
    let secondFile = file.deletingLastPathComponent().appendingPathComponent("second.mbox")
    try FileManager.default.copyItem(at: file, to: secondFile)
    let model = AppModel()
    model.open([file])
    try await waitUntil { !model.busy && !model.reading }
    let firstID = try XCTUnwrap(model.selectedCollection)
    model.select(1)
    try await waitUntil { !model.reading }
    model.open([secondFile])
    try await waitUntil { !model.busy && !model.reading }
    XCTAssertEqual(model.collections.count, 2)
    let secondID = try XCTUnwrap(model.selectedCollection)
    XCTAssertNotEqual(firstID, secondID)
    model.selectCollection(firstID)
    try await waitUntil { !model.reading }
    XCTAssertEqual(model.selectedEntry, 1)
    model.open([file])
    try await waitUntil { !model.busy && !model.reading }
    XCTAssertEqual(model.collections.count, 2)
    XCTAssertEqual(model.selectedCollection, firstID)
    XCTAssertEqual(model.selectedEntry, 1)
    model.closeCollection(firstID)
    try await waitUntil { !model.reading }
    XCTAssertEqual(model.collections.map(\.id), [secondID])
    XCTAssertEqual(model.selectedCollection, secondID)
    model.closeAll()
  }
  @MainActor func testOnlyActualWindowCloseClearsSession() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let anchor = MainWindowLifecycle.Anchor()
    var closes = 0
    anchor.close = { closes += 1 }
    window.contentView = anchor
    window.contentView = NSView()  // A normal hierarchy replacement is not a file close.
    XCTAssertEqual(closes, 0)
    window.contentView = anchor
    window.close()
    XCTAssertEqual(closes, 1)
  }
  @MainActor private func script(_ web: WKWebView, _ source: String) async throws -> Any {
    try await withCheckedThrowingContinuation { continuation in
      web.callAsyncJavaScript(source, arguments: [:], in: nil, in: .defaultClient) {
        continuation.resume(with: $0)
      }
    }
  }
}
