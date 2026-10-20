import XCTest

@testable import MailCore

final class MailDateTests: XCTestCase {
  let english = Locale(identifier: "en_GB")
  func testNumericOffsetWinsOverAmbiguousComment() {
    let value = MailDate.display("Fri, 15 Mar 2019 00:00:00 +0800 (CST)", locale: english)
    XCTAssertTrue(value.contains("15 Mar 2019"), value)
    XCTAssertTrue(value.contains("00:00:00"), value)
    XCTAssertTrue(value.hasSuffix("UTC+8"), value)
    XCTAssertFalse(value.contains("CST"))
    XCTAssertTrue(
      MailDate.display("Thu, 14 Mar 2019 10:00:00 -0600 (CST)", locale: english).hasSuffix("UTC-6"))
  }
  func testFractionalUTCAndMinutePrecision() {
    XCTAssertTrue(
      MailDate.display("15 Mar 2019 00:00 +0530", locale: english).hasSuffix("UTC+5:30"))
    XCTAssertTrue(
      MailDate.display("15 Mar 2019 00:00:01 -03:30", locale: english).hasSuffix("UTC-3:30"))
    XCTAssertTrue(MailDate.display("15 Mar 2019 00:00:00 GMT", locale: english).hasSuffix("UTC+0"))
    let chinese = MailDate.display(
      "15 Mar 2019 00:00:00 +0800 (CST)", locale: Locale(identifier: "zh_CN"))
    XCTAssertTrue(chinese.hasSuffix("UTC+8"), chinese)
  }
  func testMalformedDatesDoNotInventOffsets() {
    for raw in [
      "Unknown date", "15 Mar 2019 00:00 CST", "15 Mar 2019 00:00 +9999",
      "15 Mar 2019 00:00 +0800 (CST",
    ] {
      XCTAssertEqual(MailDate.display(raw, locale: english), raw)
    }
    XCTAssertTrue(
      MailDate.display("Fri, 15 Mar 2019 00:00:00 +0800 (China (Standard) Time)", locale: english)
        .hasSuffix("UTC+8"))
  }
}
