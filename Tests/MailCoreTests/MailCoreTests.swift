import XCTest

@testable import MailCore

final class MailCoreTests: XCTestCase {
  func temp() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    addTeardownBlock { try? FileManager.default.removeItem(at: url) }
    return url
  }
  func testMailtoPreservesPlusAndDecodesFields() throws {
    let value = try MailtoCapture(
      "mailto:student+notes@example.edu?to=other%40example.edu&cc=one%40example.edu&cc=two%40example.edu&subject=Hello%0D%0ABcc%3A%20bad&body=Line%201%0ALine%202&"
    )
    XCTAssertEqual(value.to, "student+notes@example.edu, other@example.edu")
    XCTAssertEqual(value.cc, "one@example.edu, two@example.edu")
    XCTAssertEqual(value.subject, "Hello Bcc: bad")
    XCTAssertEqual(value.body, "Line 1\nLine 2")
    XCTAssertNoThrow(try MailtoCapture("mailto:?&&"))
    XCTAssertThrowsError(try MailtoCapture("https://example.edu"))
  }
  func testMIMEAlternativeEncodingAttachmentAndCID() throws {
    let raw = """
      From: =?UTF-8?Q?Test_Sender?= <sender@example.edu>
      Subject: =?UTF-8?B?5L2g5aW9?= =?UTF-8?Q?_Mail?=
      To: reader@example.edu
      MIME-Version: 1.0
      Content-Type: multipart/mixed; boundary="outer"

      --outer
      Content-Type: multipart/alternative; boundary=inner

      --inner
      Content-Type: text/plain; charset=UTF-8
      Content-Transfer-Encoding: quoted-printable

      Hello=20world=0ASecond line
      --inner
      Content-Type: text/html

      <p>Hello <b>world</b></p><img src="cid:local"><img src="https://example.edu/track">
      --inner--
      --outer
      Content-Type: image/png; name="sample.png"
      Content-ID: <local>
      Content-Transfer-Encoding: base64

      iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+XbS8AAAAASUVORK5CYII=
      --outer
      Content-Type: application/octet-stream
      Content-Disposition: attachment; filename*=UTF-8''hello%20world.txt
      Content-Transfer-Encoding: base64

      SGVsbG8=
      --outer--
      """
    let mail = try MIME.parse(Data(raw.utf8))
    XCTAssertEqual(mail.subject, "你好 Mail")
    XCTAssertEqual(mail.from, "Test Sender <sender@example.edu>")
    XCTAssertTrue(mail.plain.contains("Hello world\nSecond line"))
    XCTAssertEqual(mail.attachments.count, 2)
    XCTAssertEqual(mail.attachments.last?.name, "hello world.txt")
    XCTAssertEqual(mail.attachments.last?.bytes, Data("Hello".utf8))
    let rendered = SafeHTML.render(mail)
    XCTAssertTrue(rendered.body.contains("data:image/png;base64,"))
    XCTAssertFalse(rendered.body.contains("https://"))
  }
  func testSanitizerBlocksActiveAndRemoteContent() {
    var mail = MailMessage()
    mail.html = """
      <html><head><style>body{background:url(https://bad.test)}</style></head><body onload="bad()"><script>alert(1)</script><iframe src="https://bad.test"></iframe><svg><script>evil()</script></svg><form action="https://bad.test"><input value="secret"></form><p style="color:red;background:url(https://bad.test);text-align:center" onclick="bad()">Safe &amp; sound</p><a href="javascript:alert(1)">Bad</a><a href="https://example.edu/hello?a=1&amp;b=2">Good</a><a href="file:///etc/passwd">File</a><img src="https://bad.test/pixel" onerror="bad()"></body></html>
      """
    let result = SafeHTML.render(mail)
    let page = result.page(dark: true)
    XCTAssertEqual(result.links.count, 1)
    XCTAssertEqual(result.links.values.first, "https://example.edu/hello?a=1&b=2")
    XCTAssertTrue(result.body.contains("Safe &amp; sound"))
    for text in [
      "<script", "<iframe", "onload", "onclick", "onerror", "javascript:", "file:", "bad.test",
      "color:red",
    ] { XCTAssertFalse(result.body.contains(text), text) }
    XCTAssertTrue(page.contains("default-src 'none'"))
    XCTAssertTrue(page.contains("script-src 'none'"))
    XCTAssertNil(SafeHTML.safeLink("https://user:secret@example.edu"))
    XCTAssertNil(SafeHTML.safeLink("x-apple.systempreferences:privacy"))
  }
  func testEMLXExcludesMetadataAndExportsEML() throws {
    let folder = try temp()
    let url = folder.appendingPathComponent("sample.emlx")
    let message = Data("From: a@example.edu\nSubject: Example\n\nBody".utf8)
    var bytes = Data("\(message.count)\n".utf8)
    bytes.append(message)
    bytes.append(Data("\n<plist>private metadata</plist>".utf8))
    try bytes.write(to: url)
    let box = try MailReader.collection(url)
    XCTAssertEqual(try MailReader.message(box.entries[0]).plain, "Body")
    XCTAssertEqual(try MailReader.original(box.entries[0]), message)
    XCTAssertThrowsError(try MailReader.emlx(Data("999999\nHi".utf8), extension: "emlx"))
  }
  func testMboxLazyIndexAndCancellation() throws {
    let folder = try temp()
    let url = folder.appendingPathComponent("sample.mbox")
    let data =
      "From a@example.edu Mon Oct 19 12:00:00 2026\nFrom: a@example.edu\nSubject: First\n\nBody\n>From quoted line\n\nFrom b@example.edu Tue Oct 20 12:00:00 2026\nFrom: b@example.edu\nSubject: Second\n\nOther body\n"
    try Data(data.utf8).write(to: url)
    let box = try MailReader.collection(url)
    XCTAssertEqual(box.entries.map(\.subject), ["First", "Second"])
    XCTAssertTrue(try MailReader.message(box.entries[1]).plain.contains("Other body"))
    XCTAssertThrowsError(try MailReader.collection(url, cancelled: { true }))
    try Data("Not an email".utf8).write(to: url)
    XCTAssertThrowsError(try MailReader.collection(url))
  }
  func testMaildirSkipsSymlinks() throws {
    let folder = try temp()
    let cur = folder.appendingPathComponent("cur")
    try FileManager.default.createDirectory(at: cur, withIntermediateDirectories: true)
    let raw = Data("From: a@example.edu\nSubject: A\n\nSafe".utf8)
    try raw.write(to: cur.appendingPathComponent("message"))
    try FileManager.default.createSymbolicLink(
      at: cur.appendingPathComponent("link"),
      withDestinationURL: cur.appendingPathComponent("message"))
    XCTAssertEqual(try MailReader.collection(folder).entries.count, 1)
  }
  func testDamagedCompoundRejectedWithoutCrash() {
    XCTAssertThrowsError(try Outlook.parse(Data()))
    var bytes = Data(repeating: 0, count: 1024)
    bytes.replaceSubrange(0..<8, with: [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])
    bytes[28] = 0xfe
    bytes[29] = 0xff
    bytes[30] = 9
    bytes[32] = 6
    XCTAssertThrowsError(try Outlook.parse(bytes))
  }
  func testLimitsAndSafeNames() {
    XCTAssertEqual(safeFilename("../../secret"), ".._.._secret")
    XCTAssertEqual(safeFilename(".."), "Attachment")
    XCTAssertThrowsError(try MIME.parse(Data(repeating: 0, count: Limits.message + 1)))
  }
}

extension MailCoreTests {
  func testOutlookUnicodeStreamsAndFATCycle() throws {
    var data = Data(repeating: 0, count: 19 * 512)
    func u16(_ p: Int, _ v: UInt16) {
      data[p] = UInt8(v & 255)
      data[p + 1] = UInt8(v >> 8)
    }
    func u32(_ p: Int, _ v: UInt32) { for b in 0..<4 { data[p + b] = UInt8((v >> (b * 8)) & 255) } }
    data.replaceSubrange(0..<8, with: [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])
    u16(24, 0x3e)
    u16(26, 3)
    u16(28, 0xfffe)
    u16(30, 9)
    u16(32, 6)
    u32(44, 1)
    u32(48, 1)
    u32(56, 4096)
    u32(60, 0xffff_fffe)
    u32(68, 0xffff_fffe)
    for p in stride(from: 76, to: 512, by: 4) { u32(p, 0xffff_ffff) }
    u32(76, 0)
    for p in stride(from: 512, to: 1024, by: 4) { u32(p, 0xffff_ffff) }
    u32(512, 0xffff_fffd)
    u32(516, 0xffff_fffe)
    for id in 2...17 { u32(512 + id * 4, [9, 17].contains(id) ? 0xffff_fffe : UInt32(id + 1)) }
    func node(
      _ index: Int, _ name: String, _ kind: UInt8, _ start: UInt32, _ size: UInt32,
      _ child: UInt32 = 0xffff_ffff, _ right: UInt32 = 0xffff_ffff
    ) {
      let p = 1024 + index * 128
      let bytes = Data((name + "\0").utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
      data.replaceSubrange(p..<p + bytes.count, with: bytes)
      u16(p + 64, UInt16(bytes.count))
      data[p + 66] = kind
      u32(p + 68, 0xffff_ffff)
      u32(p + 72, right)
      u32(p + 76, child)
      u32(p + 116, start)
      u32(p + 120, size)
    }
    node(0, "Root Entry", 5, 0xffff_fffe, 0, 1)
    node(1, "__substg1.0_0037001F", 2, 2, 4096, 0xffff_ffff, 2)
    node(2, "__substg1.0_1000001F", 2, 10, 4096)
    let subject = Data("Unicode 邮件\0".utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
    let body = Data("Hello from Outlook\0".utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
    data.replaceSubrange(1536..<1536 + subject.count, with: subject)
    data.replaceSubrange(5632..<5632 + body.count, with: body)
    let mail = try Outlook.parse(data)
    XCTAssertEqual(mail.subject, "Unicode 邮件")
    XCTAssertEqual(mail.plain, "Hello from Outlook")
    u32(512 + 2 * 4, 2)
    XCTAssertThrowsError(try Outlook.parse(data))
  }
}

extension MailCoreTests {
    func testEntitiesAndMalformedBoundariesStayInert() throws {
        XCTAssertEqual(SafeHTML.entities("A &amp; &#x4e2d;&#25991; &unknown; &lt;"),"A & 中文 &unknown; <")
        let mail=try MIME.parse(Data("Subject: Broken boundary\nContent-Type: multipart/mixed; boundary=x\n\n--x\nContent-Type: text/plain\n\nKept without closing boundary".utf8))
        XCTAssertEqual(mail.plain,"Kept without closing boundary")
        for count in 0..<128 {
            let bytes=Data((0..<count).map{UInt8(truncatingIfNeeded:$0*73+count)})
            _ = try? Outlook.parse(bytes)
            _ = try? MIME.parse(bytes)
        }
        var hostile=MailMessage();hostile.html=String(repeating:"&amp;",count:10000)+"<script><input><p>untrusted</script><p>Visible</p>"
        let result=SafeHTML.render(hostile)
        XCTAssertFalse(result.body.contains("<script"))
    }
    func testRasterBudgetRejectsDamagedAndAnimatedInputs() {
        XCTAssertFalse(SafeHTML.safeRaster(Data([137,80,78,71,13,10,26,10])))
        let png=Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+XbS8AAAAASUVORK5CYII=")!
        XCTAssertTrue(SafeHTML.safeRaster(png))
    }
}
