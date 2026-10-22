import AppKit
import MailCore
import SwiftUI

/// Native, nonmodal capture. Link data is displayed as text, never rendered as HTML or executed.
@MainActor struct CapturedMailLink {
  struct Field: Identifiable {
    var id: Int
    var label: String
    var value: String
  }
  var title: String
  var symbol: String
  var fields: [Field]
  var copyLabel: String
  var copyValue: String
  init?(_ raw: String) {
    guard let safe = SafeHTML.safeLink(raw), let url = URL(string: safe) else { return nil }
    title = L("Link", "链接")
    symbol = "link"
    copyLabel = L("Copy link", "复制链接")
    copyValue = safe
    fields = [Field(id: 0, label: "URL", value: safe)]
    if url.scheme?.lowercased() == "mailto", let mail = try? MailtoCapture(safe) {
      title = L("Email link", "邮件链接")
      symbol = "envelope"
      fields = [
        (L("To", "收件人"), mail.to), (L("Cc", "抄送"), mail.cc),
        (L("Bcc", "密送"), mail.bcc), (L("Subject", "主题"), mail.subject),
        (L("Message", "正文"), mail.body),
      ].enumerated().compactMap { index, pair in
        pair.1.isEmpty ? nil : Field(id: index, label: pair.0, value: pair.1)
      }
      let simple = mail.cc.isEmpty && mail.bcc.isEmpty && mail.subject.isEmpty && mail.body.isEmpty
      copyValue = simple ? mail.to : mail.text
      copyLabel = simple ? L("Copy address", "复制地址") : L("Copy message", "复制邮件内容")
    } else if ["tel", "sms"].contains(url.scheme?.lowercased() ?? "") {
      let telephone = url.scheme?.lowercased() == "tel"
      let parts = String(safe.dropFirst(4)).split(
        separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
      let number = String(parts.first ?? "").removingPercentEncoding ?? String(parts.first ?? "")
      title = telephone ? L("Telephone", "电话号码") : L("Text message", "短信")
      symbol = telephone ? "phone" : "message"
      fields = [Field(id: 0, label: telephone ? L("Number", "号码") : L("To", "收件人"), value: number)]
      copyLabel = L("Copy number", "复制号码")
      copyValue = number
      if !telephone,
        let body = URLComponents(string: safe)?.queryItems?.first(where: {
          $0.name.lowercased() == "body"
        })?.value, !body.isEmpty
      {
        fields.append(Field(id: 1, label: L("Message", "内容"), value: body))
        copyLabel = L("Copy message", "复制短信内容")
        copyValue = "To: \(number)\n\n\(body)"
      }
    }
  }
}

@MainActor final class LinkPopoverPresenter {
  private var popover: NSPopover?
  func dismiss() {
    popover?.close()
    popover = nil
  }
  func show(_ capture: CapturedMailLink, in view: NSView, at rectangle: NSRect) {
    guard view.window != nil else { return }
    dismiss()
    let popover = NSPopover()
    popover.behavior = .transient
    popover.contentViewController = NSHostingController(
      rootView: LinkCaptureView(capture: capture) { [weak self] in self?.dismiss() })
    self.popover = popover
    popover.show(relativeTo: rectangle.intersection(view.bounds), of: view, preferredEdge: .maxY)
  }
}

private struct LinkCaptureView: View {
  let capture: CapturedMailLink
  let close: () -> Void
  @State private var copied = false
  private var detailsHeight: CGFloat {
    min(
      220,
      max(
        48, capture.fields.reduce(0) { $0 + 32 + CGFloat(min(8, ($1.value.count + 39) / 40)) * 20 })
    )
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label(capture.title, systemImage: capture.symbol).font(.system(size: 14, weight: .semibold))
        Spacer()
        Button(action: close) { Image(systemName: "xmark").frame(width: 24, height: 24) }
          .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Close", "关闭"))
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(capture.fields) { field in
            VStack(alignment: .leading, spacing: 3) {
              Text(field.label).font(.system(size: 13)).foregroundStyle(.secondary)
              Text(field.value).font(.system(size: 14)).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
      }.frame(height: detailsHeight)
      HStack {
        Spacer()
        Button {
          copyText(capture.copyValue)
          copied = true
        } label: {
          Label(
            copied ? L("Copied", "已复制") : capture.copyLabel,
            systemImage: copied ? "checkmark" : "doc.on.doc")
        }.buttonStyle(.borderedProminent).disabled(capture.copyValue.isEmpty)
      }
    }.padding(14).frame(width: 344)
  }
}
