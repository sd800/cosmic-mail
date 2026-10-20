import MailCore
import SwiftUI

struct CaptureView: View {
  let capture: MailtoCapture
  @ObservedObject var prefs = Preferences.shared
  @State private var copied = false
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 28) {
        HStack(spacing: 14) {
          Image(systemName: "link.circle.fill").font(.system(size: 38, weight: .light))
            .foregroundStyle(.tint)
          VStack(alignment: .leading, spacing: 5) {
            Text(L("Email link", "邮件链接")).font(.title2.weight(.semibold))
            Text(L("Nothing sent. Nothing launched.", "没有发送邮件，也没有打开其他邮件应用。")).foregroundStyle(
              .secondary)
          }
        }
        VStack(spacing: 0) {
          captureRow(L("To", "收件人"), capture.to)
          if !capture.cc.isEmpty {
            Divider()
            captureRow(L("Cc", "抄送"), capture.cc)
          }
          if !capture.bcc.isEmpty {
            Divider()
            captureRow(L("Bcc", "密送"), capture.bcc)
          }
          if !capture.subject.isEmpty {
            Divider()
            captureRow(L("Subject", "主题"), capture.subject)
          }
        }.background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14)).overlay {
          RoundedRectangle(cornerRadius: 14).stroke(
            Color(nsColor: .separatorColor).opacity(0.4), lineWidth: 0.5)
        }
        if !capture.body.isEmpty {
          VStack(alignment: .leading, spacing: 12) {
            Text(L("Message", "正文")).font(.headline)
            Text(capture.body).textSelection(.enabled).frame(
              maxWidth: .infinity, alignment: .leading)
          }.padding(20).background(
            .quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
        }
        HStack(spacing: 12) {
          Button {
            copyText(capture.text)
            copied = true
          } label: {
            Label(
              copied ? L("Copied", "已复制") : L("Copy details", "复制内容"),
              systemImage: copied ? "checkmark" : "doc.on.doc")
          }.buttonStyle(.borderedProminent)
          Button(L("Copy original link", "复制原始链接")) { copyText(capture.original) }.buttonStyle(
            .bordered)
        }.controlSize(.large)
        Text(
          L(
            "This link is only held in this window. You can copy what you need, or simply close it.",
            "链接仅保留在当前窗口中。可以复制需要的内容，也可以直接关闭。")
        ).font(.system(size: 14)).foregroundStyle(.secondary)
      }.padding(44).frame(maxWidth: 800, alignment: .leading).frame(maxWidth: .infinity)
    }.onChange(of: capture) { _, _ in copied = false }
  }
  @ViewBuilder func captureRow(_ title: String, _ value: String) -> some View {
    HStack(alignment: .top, spacing: 18) {
      Text(title).foregroundStyle(.secondary).frame(width: 68, alignment: .leading)
      Text(value.isEmpty ? "—" : value).textSelection(.enabled).frame(
        maxWidth: .infinity, alignment: .leading)
      if !value.isEmpty {
        Button {
          copyText(value)
        } label: {
          Image(systemName: "doc.on.doc")
        }.buttonStyle(.plain).foregroundStyle(.secondary).help(L("Copy", "复制"))
      }
    }.padding(18)
  }
}
