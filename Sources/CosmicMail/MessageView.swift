import AppKit
import MailCore
import SwiftUI

struct MessageView: View {
  @ObservedObject var model = AppModel.shared
  @ObservedObject var prefs = Preferences.shared
  @Environment(\.colorScheme) var scheme
  @State private var showLoading = false
  var body: some View {
    VStack(spacing: 0) {
      if let mail = model.message {
        header(mail)
        if model.showDetails { details(mail) }
        Divider().padding(.horizontal, 28)
      }
      // This representable has one stable position for loading, content, and empty states.
      MailWebView(
        rendered: model.rendered ?? RenderedMail(body: "", links: [:]),
        plain: model.message?.plain ?? "", identity: model.selectionVersion,
        dark: scheme == .dark, scale: prefs.textSize / 16,
        interactive: model.currentMessageReady, open: model.external
      )
      .padding(.horizontal, 28)
      .overlay {
        if model.message == nil || model.readerFailed {
          placeholder.background(Color(nsColor: .textBackgroundColor))
        }
      }
      if let mail = model.message {
        if !mail.attachments.isEmpty {
          Divider()
          ScrollView(.horizontal) {
            HStack(spacing: 10) {
              ForEach(mail.attachments) { attachment in
                Button {
                  model.saveAttachment(attachment)
                } label: {
                  HStack(spacing: 10) {
                    Image(systemName: "paperclip").font(.system(size: 16)).foregroundStyle(
                      .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(attachment.name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        .truncationMode(.middle)
                      Text(
                        ByteCountFormatter.string(
                          fromByteCount: Int64(attachment.bytes.count), countStyle: .file)
                      )
                      .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Image(systemName: "square.and.arrow.down").font(.system(size: 15))
                      .foregroundStyle(.secondary)
                  }
                  .padding(.horizontal, 12).frame(
                    minWidth: 150, maxWidth: 240, minHeight: 50, maxHeight: 50
                  )
                  .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 7))
                  .overlay {
                    RoundedRectangle(cornerRadius: 7).stroke(
                      Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
                  }
                  .contentShape(RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain).help(L("Save attachment…", "保存附件…") + " " + attachment.name)
              }
            }.padding(.horizontal, 16).padding(.vertical, 12)
          }.fixedSize(horizontal: false, vertical: true)
        }
      }
    }
    .allowsHitTesting(!model.reading)
    .overlay(alignment: .top) {
      if showLoading && model.reading {
        ProgressView().progressViewStyle(.linear).frame(height: 2).allowsHitTesting(false)
      }
    }
    .task(id: model.readRequest) {
      showLoading = false
      guard model.reading else { return }
      do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
      if model.reading { showLoading = true }
    }
    .onChange(of: model.reading) { _, reading in
      if !reading { showLoading = false }
    }
  }
  @ViewBuilder private var placeholder: some View {
    if model.reading {
      Color(nsColor: .textBackgroundColor)
    } else if model.readerFailed {
      VStack(spacing: 14) {
        Text(L("The reading view stopped.", "阅读视图已停止。")).foregroundStyle(.secondary)
        Button(L("Try again", "重试")) { model.select(model.selectedEntry) }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    } else if let entry = model.entry, entry.length > Limits.message {
      ContentUnavailableView(
        L("Message too large to preview", "邮件过大，暂不预览"), systemImage: "envelope.badge",
        description: Text(
          L(
            "This message exceeds the 32 MiB preview limit. You can continue reading other messages in the archive.",
            "这封邮件超过 32 MiB 预览上限，仍可正常阅读存档中的其他邮件。")))
    } else {
      ContentUnavailableView(
        L("Select a message", "选择一封邮件"), systemImage: "envelope.open",
        description: Text(L("Choose a message to read it here.", "在列表中选择邮件即可阅读。")))
    }
  }
  private func header(_ mail: MailMessage) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(mail.subject.isEmpty ? L("No subject", "无主题") : mail.subject)
        .font(.system(size: 20, weight: .semibold)).lineLimit(2).textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack(alignment: .top, spacing: 10) {
        Text(String(mail.from.first ?? "M").uppercased()).font(.system(size: 15, weight: .medium))
          .foregroundStyle(.tint).frame(width: 32, height: 32)
          .background(Color.accentColor.opacity(0.08), in: Circle())
        VStack(alignment: .leading, spacing: 3) {
          Text(mail.from.isEmpty ? L("Unknown sender", "未知发件人") : mail.from)
            .font(.system(size: 14, weight: .semibold)).lineLimit(2).textSelection(.enabled)
          if !mail.to.isEmpty {
            Text(L("To: ", "收件人：") + mail.to).lineLimit(2).textSelection(.enabled)
          }
          if !mail.cc.isEmpty {
            Text(L("Cc: ", "抄送：") + mail.cc).lineLimit(2).textSelection(.enabled)
          }
          if !mail.date.isEmpty {
            Text(readableDate(mail.date)).lineLimit(1).textSelection(.enabled)
          }
        }.font(.system(size: 13)).foregroundStyle(.secondary)
      }
    }.padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 16).fixedSize(
      horizontal: false, vertical: true)
  }
  private func details(_ mail: MailMessage) -> some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(L("Message details", "邮件详情")).font(.system(size: 14, weight: .semibold))
          Spacer()
          Button(L("Copy headers", "复制邮件头")) {
            copyText(mail.headers.map { "\($0.name): \($0.value)" }.joined(separator: "\n"))
          }.buttonStyle(.link)
        }
        ForEach(Array(mail.headers.enumerated()), id: \.offset) { _, field in
          VStack(alignment: .leading, spacing: 3) {
            Text(field.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            Text(
              ["date", "resent-date", "delivery-date"].contains(field.name.lowercased())
                ? readableDate(field.value) : field.value
            ).font(.system(size: 14)).textSelection(.enabled)
          }
        }
      }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
    }.frame(maxHeight: 210).background(
      .quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8)
    )
    .padding(.horizontal, 28).padding(.bottom, 14)
  }
}
