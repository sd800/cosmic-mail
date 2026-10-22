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
    XCTAssertTrue(
      result.page(dark: true, backgroundRGB: 0x1E1E1E).contains("style=\"--paper:#1E1E1E;"))
    XCTAssertTrue(
      result.page(dark: false, backgroundRGB: 0xFFFFFF).contains("style=\"--paper:#FFFFFF;"))
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
    XCTAssertEqual(
      SafeHTML.entities("A &amp; &#x4e2d;&#25991; &unknown; &lt;"), "A & 中文 &unknown; <")
    let mail = try MIME.parse(
      Data(
        "Subject: Broken boundary\nContent-Type: multipart/mixed; boundary=x\n\n--x\nContent-Type: text/plain\n\nKept without closing boundary"
          .utf8))
    XCTAssertEqual(mail.plain, "Kept without closing boundary")
    for count in 0..<128 {
      let bytes = Data((0..<count).map { UInt8(truncatingIfNeeded: $0 * 73 + count) })
      _ = try? Outlook.parse(bytes)
      _ = try? MIME.parse(bytes)
    }
    var hostile = MailMessage()
    hostile.html =
      String(repeating: "&amp;", count: 10000)
      + "<script><input><p>untrusted</script><p>Visible</p>"
    let result = SafeHTML.render(hostile)
    XCTAssertFalse(result.body.contains("<script"))
  }
  func testRasterBudgetRejectsDamagedAndAnimatedInputs() {
    XCTAssertFalse(SafeHTML.safeRaster(Data([137, 80, 78, 71, 13, 10, 26, 10])))
    let png = Data(
      base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+XbS8AAAAASUVORK5CYII="
    )!
    XCTAssertTrue(SafeHTML.safeRaster(png))
  }
}

// Small synthetic inputs only: budget exhaustion is simulated with lowered index limits.
extension MailCoreTests {
  func testMboxIncrementalIndexAndSmallBudgets() throws {
    let folder = try temp()
    let url = folder.appendingPathComponent("small.mbox")
    let raw =
      "From a@example.edu Mon Oct 19 12:00:00 2026\r\nSubject: First\r\nFrom: a@example.edu\r\n\r\nBody\r\nFrom b@example.edu Tue Oct 20 12:00:00 2026\r\nSubject: Second\r\n\r\nEnd"
    try Data(raw.utf8).write(to: url)
    var delivered: [MessageEntry] = []
    let all = try MailReader.collection(url, batch: { delivered += $0 })
    XCTAssertEqual(delivered.map(\.id), [0, 1])
    XCTAssertEqual(all.entries.map(\.subject), ["First", "Second"])
    XCTAssertEqual(try MailReader.message(all.entries[1]).plain, "End")
    let limited = try MailReader.collection(url, limits: IndexLimits(messages: 1))
    XCTAssertTrue(limited.indexLimitReached)
    XCTAssertEqual(limited.entries.count, 1)
    let memoryLimited = try MailReader.collection(
      url, limits: IndexLimits(bytes: all.entries[0].metadataBytes))
    XCTAssertEqual(memoryLimited.entries.count, 1)
    XCTAssertTrue(memoryLimited.indexLimitReached)
  }

  func testMboxContentLengthAndProseSeparators() throws {
    let folder = try temp()
    let url = folder.appendingPathComponent("variants.mbox")
    let body =
      "From prose@example.edu Tue Oct 20 12:00:00 2026\nSubject: Not a real message\n\nBody\n"
    let raw =
      "From a@example.edu Mon Oct 19 12:00:00 2026\nSubject: First\nContent-Length: \(body.utf8.count)\n\n"
      + body
      + "From b@example.edu Tue Oct 20 12:00:00 2026\nSubject: Second\n\nFrom prose@example.edu Tue Oct 20 12:00:00 2026\nNot a header\nTail"
    try Data(raw.utf8).write(to: url)
    let box = try MailReader.collection(url)
    XCTAssertEqual(box.entries.map(\.subject), ["First", "Second"])
    XCTAssertTrue(try MailReader.message(box.entries[0]).plain.contains("Not a real message"))
    XCTAssertTrue(try MailReader.message(box.entries[1]).plain.contains("Tail"))
  }

  func testMboxLongLineAcrossChunksAndCancellation() throws {
    let folder = try temp()
    let url = folder.appendingPathComponent("line.mbox")
    // 129 KiB crosses a scanner chunk; this is not a large-archive or performance test.
    let raw =
      "From a@example.edu Mon Oct 19 12:00:00 2026\nSubject: Line\n\n"
      + String(repeating: "x", count: 129 * 1024)
      + "\nFrom b@example.edu Tue Oct 20 12:00:00 2026\nSubject: Next\n\nDone"
    try Data(raw.utf8).write(to: url)
    XCTAssertEqual(try MailReader.collection(url).entries.map(\.subject), ["Line", "Next"])
    var stop = false
    XCTAssertThrowsError(
      try MailReader.collection(url, cancelled: { stop }, batch: { _ in stop = true })
    ) {
      XCTAssertEqual($0 as? MailError, .cancelled)
    }
  }

  func testOversizedEntryDoesNotAbortMemoryIndex() throws {
    let url = URL(fileURLWithPath: "/not-read.mbox")
    let index = MemoryIndex(url: url, limits: IndexLimits(), progress: { _ in }, batch: { _ in })
    let large = MessageEntry(
      id: 0, subject: "Large", from: "", date: "", offset: 0,
      length: Limits.message + 1, file: url)
    XCTAssertTrue(index.append(large))
    XCTAssertTrue(
      index.append(
        MessageEntry(
          id: 1, subject: "Small", from: "", date: "", offset: 0,
          length: 20, file: url)))
    XCTAssertEqual(index.finish(kind: "MBOX").entries.count, 2)
    XCTAssertThrowsError(try MailReader.message(large)) {
      XCTAssertEqual($0 as? MailError, .tooLarge)
    }
  }

  func testChangedSourceRejectedAndBackgroundSearch() throws {
    let folder = try temp()
    let url = folder.appendingPathComponent("source.mbox")
    let raw = Data(
      "From a@example.edu Mon Oct 19 12:00:00 2026\nSubject: First\nFrom: Sender\n\nBody".utf8)
    try raw.write(to: url)
    let box = try MailReader.collection(url)
    XCTAssertTrue(MailReader.isCurrent(box))
    XCTAssertEqual(try MailSearch.matching(box.entries, query: "FIRST").map(\.id), [0])
    XCTAssertEqual(try MailSearch.matching(box.entries, query: "sender").map(\.id), [0])
    XCTAssertThrowsError(try MailSearch.matching(box.entries, query: "first", cancelled: { true }))
    try raw.write(to: url, options: .atomic)
    XCTAssertFalse(MailReader.isCurrent(box))
    XCTAssertThrowsError(try MailReader.message(box.entries[0])) {
      XCTAssertEqual($0 as? MailError, .sourceChanged)
    }
    XCTAssertThrowsError(try MIME.parse(raw, cancelled: { true }))
  }
}

extension MailCoreTests {
  func testChineseCharsetRecoveryAndSplitHeaderWords() throws {
    // GBK's 鎔 is outside GB2312. An illegal byte must not corrupt valid neighbors.
    XCTAssertEqual(
      MIME.decode(Data([0xc4, 0xe3, 0xe6, 0x67, 0xff, 0xba, 0xc3]), charset: "gb2312"), "你鎔�好")
    XCTAssertEqual(MIME.decode(Data([0xe4, 0xbd, 0xa0, 0xff, 0xe5, 0xa5, 0xbd])), "你�好")
    XCTAssertEqual(MIME.headerText("=?UTF-8?B?5L0=?=\r\n =?utf-8?B?oOWlvQ==?="), "你好")
    XCTAssertEqual(MIME.headerText("=?gb2312?Q?=C4?= =?GB2312?Q?=E3=BA=C3?="), "你好")
    XCTAssertEqual(
      MIME.headerText("=?utf-8?Q?Hello?= plain =?utf-8?Q?world?="), "Hello plain world")
    let html =
      Data("<meta charset=gb2312><p>".utf8) + Data([0xc4, 0xe3, 0xba, 0xc3]) + Data("</p>".utf8)
    XCTAssertTrue(MIME.decodeHTML(html).contains("你好"))
  }
  func testSegmentedFilenamesAndMultipleInlineBodies() throws {
    XCTAssertEqual(
      MIME.filename([
        Header(
          name: "Content-Disposition",
          value: "attachment; filename*0*=GBK''%C4%; filename*1*=E3%BA%C3.doc")
      ]), "你好.doc")
    XCTAssertEqual(
      MIME.filename([
        Header(
          name: "Content-Disposition", value: "attachment; filename*0=hello; filename*1=world.txt")
      ]), "helloworld.txt")
    let raw = """
      Subject: Segments
      Content-Type: multipart/mixed; boundary=x

      --x
      Content-Type: text/html

      <p>Before</p>
      --x
      Content-Type: message/rfc822
      Content-Disposition: attachment

      Subject: Forwarded

      Inside
      --x
      Content-Type: text/html

      <p>After</p>
      --x
      Content-Type: multipart/alternative; boundary=y

      --y
      Content-Type: text/plain

      Same content
      --y
      Content-Type: text/html

      <b>Same content</b>
      --y--
      --x--
      """
    let mail = try MIME.parse(Data(raw.utf8))
    XCTAssertTrue(mail.html.contains("Before"))
    XCTAssertTrue(mail.html.contains("After"))
    XCTAssertEqual(mail.html.components(separatedBy: "Same content").count, 2)
    XCTAssertEqual(mail.attachments.first?.name, "Attached message.eml")
    XCTAssertTrue(mail.attachments.first?.canPreview == true)
    XCTAssertEqual(try MIME.parse(mail.attachments[0].bytes).subject, "Forwarded")
    let long = safeFilename(String(repeating: "邮件", count: 150) + ".eml")
    XCTAssertLessThanOrEqual(long.utf8.count, 220)
    XCTAssertTrue(long.hasSuffix(".eml"))
  }
  func testPassiveFormattingAndUnclosedInertWrappers() {
    var mail = MailMessage()
    mail.html = """
      <head><style>.news {color:#003366;width:600px} @media (max-width: 500px) {.news {width:100%}}
      @font-face {font-family:x;src:url(https://bad.test/font)}
      .bad{position:fixed;z-index:999;background:url(https://bad.test/pixel);margin-x}body{color:red}
      </style></head><form><button>Kept<button><video>Fallback
      <div hidden>Preheader</div><table class="news" width="600" cellpadding="0" cellspacing="0" border="0"><tr>
      <td width="50%" style="color:red;border-top:1px solid #aaaaaa;font-family:'FangSong',serif;font-size:16px;padding:12px">Don&rsquo;t &hellip; &eacute;&zwnj;</td></tr></table>
      <p style="position:fixed;background-image:url(file:///private);color:expression(alert(1));padding-x}body{color:red">End</p>
      """
    let result = SafeHTML.render(mail)
    XCTAssertTrue(result.body.contains("Kept"))
    XCTAssertTrue(result.body.contains("Fallback"))
    XCTAssertTrue(result.body.contains("Don’t … é\u{200c}"))
    XCTAssertTrue(result.body.contains("width:50%"))
    XCTAssertTrue(result.body.contains("display:none!important"))
    XCTAssertTrue(result.body.contains("font-family:"))
    XCTAssertTrue(result.body.contains("border-top:1px solid"))
    XCTAssertTrue(result.stylesheet.contains(".mail-content .m-news"))
    XCTAssertTrue(result.stylesheet.contains("@media (max-width: 500px)"))
    for bad in [
      "url(", "file:", "https:", "@font-face", "expression(", "position:", "z-index", "}body{",
      "<button", "<form", "<video",
    ] {
      XCTAssertFalse((result.body + result.stylesheet).contains(bad), bad)
    }
    XCTAssertFalse(result.page(dark: false).contains("td,th{padding:7px"))
  }
  func testBodySearchDateOrderAndStreamingExport() throws {
    let dir = try temp()
    let file = dir.appendingPathComponent("search.mbox")
    let raw = """
      From a@example.edu Mon Oct 19 12:00:00 2026
      Subject: Older
      To: Recipient <reader@example.edu>
      Date: 19 Oct 2026 12:00:00 +0000
      Content-Type: text/html

      <p>Needle &eacute; in body</p>
      From b@example.edu Tue Oct 20 12:00:00 2026
      Subject: Newer
      Date: 20 Oct 2026 12:00:00 +0000

      Other content
      """
    try Data(raw.utf8).write(to: file)
    let entries = try MailReader.collection(file).entries
    XCTAssertEqual(MailSearch.ordered(entries).map(\.subject), ["Newer", "Older"])
    XCTAssertEqual(try MailSearch.scan(entries, query: "needle é").entries.map(\.id), [0])
    XCTAssertEqual(try MailSearch.scan(entries, query: "reader@example.edu").entries.map(\.id), [0])
    XCTAssertThrowsError(try MailSearch.scan(entries, query: "notfound", cancelled: { true }))
    let output = dir.appendingPathComponent("copy.eml")
    try MailReader.exportOriginal(entries[0], to: output, chunkSize: 7)
    XCTAssertEqual(try Data(contentsOf: output), try MailReader.original(entries[0]))
    XCTAssertThrowsError(try MailReader.exportOriginal(entries[0], to: file))
    XCTAssertEqual(try Data(contentsOf: file), Data(raw.utf8))
    try Data("Keep existing destination".utf8).write(to: output)
    XCTAssertThrowsError(try MailReader.exportOriginal(entries[0], to: output, cancelled: { true }))
    XCTAssertEqual(try String(contentsOf: output), "Keep existing destination")
    XCTAssertThrowsError(try MailReader.validateDestination(file, protecting: [file]))
    let alias = dir.appendingPathComponent("alias.mbox")
    try FileManager.default.linkItem(at: file, to: alias)
    XCTAssertThrowsError(try MailReader.validateDestination(alias, protecting: [file]))
    XCTAssertNoThrow(try MailReader.validateDestination(output, protecting: [file]))
    XCTAssertFalse(
      try FileManager.default.contentsOfDirectory(atPath: dir.path).contains {
        $0.hasPrefix(".CosmicMail-")
      })
  }
}

extension MailCoreTests {
  /// A tiny regular-sector CFB fixture; no external mail, OLE activation, or large archives.
  private func msgFixture(_ streams: [String: Data]) -> Data {
    let storage = Set(
      streams.keys.flatMap { path -> [String] in
        let components = path.split(separator: "/").map(String.init)
        return (1..<components.count).map { components.prefix($0).joined(separator: "/") }
      })
    let paths = [""] + (Array(storage) + Array(streams.keys)).sorted()
    let directoryCount = (paths.count + 3) / 4
    var data = Data(repeating: 0, count: (2 + directoryCount + streams.count * 8) * 512)
    func u16(_ p: Int, _ v: UInt16) {
      data[p] = UInt8(v & 255)
      data[p + 1] = UInt8(v >> 8)
    }
    func u32(_ p: Int, _ v: UInt32) {
      for b in 0..<4 { data[p + b] = UInt8(truncatingIfNeeded: v >> (b * 8)) }
    }
    data.replaceSubrange(0..<8, with: [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])
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
    for id in 1...directoryCount {
      u32(512 + id * 4, id == directoryCount ? 0xffff_fffe : UInt32(id + 1))
    }
    var next = 1 + directoryCount
    for (index, path) in paths.enumerated() {
      let directory = index == 0 || storage.contains(path)
      let p = 1024 + index * 128
      let name = index == 0 ? "Root Entry" : String(path.split(separator: "/").last!)
      let encoded = Data((name + "\0").utf16.flatMap { [UInt8($0 & 255), UInt8($0 >> 8)] })
      data.replaceSubrange(p..<p + encoded.count, with: encoded)
      u16(p + 64, UInt16(encoded.count))
      data[p + 66] = index == 0 ? 5 : directory ? 1 : 2
      u32(p + 68, 0xffff_ffff)
      u32(p + 72, 0xffff_ffff)
      u32(p + 76, 0xffff_ffff)
      u32(p + 116, 0xffff_fffe)
      let parent = path.split(separator: "/").dropLast().joined(separator: "/")
      let siblings = paths.indices.filter {
        $0 > 0 && paths[$0].split(separator: "/").dropLast().joined(separator: "/") == parent
      }
      if let position = siblings.firstIndex(of: index), position + 1 < siblings.count {
        u32(p + 72, UInt32(siblings[position + 1]))
      }
      if directory {
        let children = paths.indices.filter {
          $0 > 0 && paths[$0].split(separator: "/").dropLast().joined(separator: "/") == path
        }
        if let child = children.first { u32(p + 76, UInt32(child)) }
      } else {
        let bytes = streams[path]!
        precondition(bytes.count <= 4096)
        let start = next
        next += 8
        u32(p + 116, UInt32(start))
        u32(p + 120, 4096)
        for id in start..<next { u32(512 + id * 4, id + 1 == next ? 0xffff_fffe : UInt32(id + 1)) }
        data.replaceSubrange((start + 1) * 512..<(start + 1) * 512 + bytes.count, with: bytes)
      }
    }
    return data
  }
  private func msgProperties(header: Int = 32, _ values: [(UInt32, UInt64)]) -> Data {
    var data = Data(repeating: 0, count: header)
    for (tag, value) in values {
      data.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: tag >> ($0 * 8)) })
      data.append(contentsOf: [0, 0, 0, 0])
      data.append(contentsOf: (0..<8).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    return data
  }
  func testMSGCodepagesDatesAndVisibleEmbeddedAttachments() throws {
    let nested = "__attach_version1.0_#00000000/"
    let ole = "__attach_version1.0_#00000001/"
    let missing = "__attach_version1.0_#00000002/"
    let ticks = UInt64((1_772_323_200 + 11_644_473_600) * 10_000_000)
    let streams: [String: Data] = [
      "__properties_version1.0": msgProperties([
        (0x3ffd_0003, 936), (0x3fde_0003, 936), (0x0039_0040, ticks),
      ]),
      "__substg1.0_0037001e": Data([0xc4, 0xe3, 0xba, 0xc3]),
      "__substg1.0_0c1a001e": Data([0xc4, 0xe3]),
      "__recip_version1.0_#00000000/__properties_version1.0": msgProperties(
        header: 8, [(0x0c15_0003, 1)]),
      "__recip_version1.0_#00000000/__substg1.0_3003001e": Data("reader@example.edu".utf8),
      "__substg1.0_10130102": Data("<p>".utf8) + Data([0xc4, 0xe3, 0xba, 0xc3]) + Data("</p>".utf8),
      nested + "__properties_version1.0": msgProperties(header: 8, [(0x3705_0003, 5)]),
      nested + "__substg1.0_3701000d/__properties_version1.0": msgProperties(
        header: 24, [(0x0e06_0040, ticks)]),
      nested + "__substg1.0_3701000d/__substg1.0_0037001e": Data([0xc4, 0xe3]),
      ole + "__properties_version1.0": msgProperties(header: 8, [(0x3705_0003, 6)]),
      missing + "__properties_version1.0": msgProperties(header: 8, [(0x3705_0003, 1)]),
    ]
    let mail = try Outlook.parse(msgFixture(streams))
    XCTAssertEqual(mail.subject, "你好")
    XCTAssertEqual(mail.from, "你")
    XCTAssertEqual(mail.to, "reader@example.edu")
    XCTAssertTrue(mail.html.contains("你好"))
    XCTAssertFalse(mail.date.isEmpty)
    XCTAssertEqual(MailDate.timestamp(mail.date), 1_772_323_200)
    XCTAssertEqual(mail.attachments.count, 3)
    XCTAssertEqual(mail.attachments[0].embedded.first?.subject, "你")
    XCTAssertEqual(
      MailDate.timestamp(mail.attachments[0].embedded.first?.date ?? ""), 1_772_323_200)
    XCTAssertTrue(mail.attachments[0].canPreview)
    XCTAssertTrue(mail.attachments[1].isOLE)
    XCTAssertFalse(mail.attachments[1].available)
    XCTAssertFalse(mail.attachments[2].available)
  }
}
