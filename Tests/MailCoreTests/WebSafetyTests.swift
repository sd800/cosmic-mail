import WebKit
import XCTest

@testable import MailCore

final class WebSafetyTests: XCTestCase {
  @MainActor func testWebKitCompilesResourceBarrier() async throws {
    let store = WKContentRuleListStore.default()!
    let list: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
      store.compileContentRuleList(
        forIdentifier: "CosmicMail.SecurityTest", encodedContentRuleList: MailSecurity.contentRules
      ) { list, error in
        if let list {
          continuation.resume(returning: list)
        } else {
          continuation.resume(throwing: error ?? MailError.malformed)
        }
      }
    }
    XCTAssertEqual(list.identifier, "CosmicMail.SecurityTest")
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      store.removeContentRuleList(forIdentifier: list.identifier) { error in
        if let error { continuation.resume(throwing: error) } else { continuation.resume() }
      }
    }
  }
}
