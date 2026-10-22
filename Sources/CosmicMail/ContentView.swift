import AppKit
import MailCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @ObservedObject var model = AppModel.shared
  @ObservedObject var prefs = Preferences.shared
  @State private var dropping = false
  var body: some View {
    NavigationSplitView {
      VStack(spacing: 0) {
        List(
          selection: Binding(get: { model.selectedCollection }, set: { model.selectCollection($0) })
        ) {
          if model.capture != nil {
            Section(L("Email links", "邮件链接")) {
              Label(L("Captured link", "已接住的链接"), systemImage: "link").foregroundStyle(.tint)
            }
          }
          Section(L("Open files", "已打开的文件")) {
            ForEach(model.collections) { file in
              HStack(spacing: 10) {
                Image(systemName: file.entries.count > 1 ? "archivebox" : "envelope")
                  .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                  Text(file.url.deletingPathExtension().lastPathComponent).lineLimit(1)
                  Text("\(file.kind) · \(file.entries.count)").font(.system(size: 13))
                    .foregroundStyle(
                      .secondary)
                }
              }.padding(.vertical, 4).tag(file.id)
                .help(file.url.path)
                .contextMenu {
                  Button(L("Close file", "关闭文件")) { model.closeCollection(file.id) }
                }
            }
          }
        }.listStyle(.sidebar)
        VStack(alignment: .leading, spacing: 12) {
          Button {
            model.chooseFiles()
          } label: {
            Label(L("Open files…", "打开文件…"), systemImage: "plus")
          }.buttonStyle(.plain)
          HStack {
            SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain).help(
              L("Settings (⌘,)", "设置 (⌘,)"))
            Spacer()
            Text("Cosmic Mail").font(.system(size: 13)).foregroundStyle(.tertiary)
          }
        }.padding(18)
      }.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
    } detail: {
      Group {
        if let capture = model.capture {
          CaptureView(capture: capture)
        } else if let active = model.active {
          if active.entries.count > 1
            || ["MBOX", "MBX", "MBO", "Maildir"].contains(active.kind)
          {
            MailReadingPanes()
          } else {
            MessageView()
          }
        } else {
          WelcomeView()
        }
      }.background(Color(nsColor: .textBackgroundColor))
    }
    .toolbar {
      ToolbarItem(placement: .navigation) {
        if model.busy {
          HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(
              model.progress > 0
                ? L("\(model.progress) messages", "\(model.progress) 封邮件") : L("Opening…", "正在打开…")
            ).font(.system(size: 14))
            Button(L("Cancel", "取消")) { model.cancel() }
          }
        }
      }
      ToolbarItemGroup(placement: .primaryAction) {
        if model.active != nil {
          Button {
            guard model.currentMessageReady else { return }
            model.showDetails.toggle()
          } label: {
            Image(systemName: "info.circle")
          }.help(L("Message details", "邮件详情"))
            .disabled(
              model.entry == nil || model.readerFailed || (!model.reading && model.message == nil))
          Button {
            model.exportOriginal()
          } label: {
            Image(systemName: "square.and.arrow.up")
          }.help(L("Export original", "导出原始邮件")).disabled(!model.canExportOriginal)
        }
        Button {
          model.chooseFiles()
        } label: {
          Image(systemName: "folder")
        }.help(L("Open (⌘O)", "打开 (⌘O)"))
      }
    }
    .overlay {
      if dropping {
        RoundedRectangle(cornerRadius: 12).stroke(.tint, lineWidth: 3).padding(5).allowsHitTesting(
          false)
      }
    }
    .onDrop(of: [UTType.fileURL], isTargeted: $dropping) { providers in
      let batch = DropBatch()
      let group = DispatchGroup()
      for provider in providers.prefix(20) {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
          if let url { batch.add(url) }
          group.leave()
        }
      }
      group.notify(queue: .main) { model.open(batch.urls) }
      return !providers.isEmpty
    }
    .alert(
      L("Could not complete this action", "未能完成操作"),
      isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })
    ) {
      Button(L("OK", "好")) { model.error = nil }
    } message: {
      Text(model.error ?? "")
    }
  }
}
struct WelcomeView: View {
  @ObservedObject var model = AppModel.shared
  @ObservedObject var prefs = Preferences.shared
  var body: some View {
    VStack(spacing: 22) {
      ZStack {
        RoundedRectangle(cornerRadius: 25).fill(Color.accentColor.opacity(0.09)).frame(
          width: 108, height: 108)
        Image(systemName: "envelope.open").font(.system(size: 48, weight: .light)).foregroundStyle(
          .tint)
      }
      VStack(spacing: 10) {
        Text("Cosmic Mail").font(.system(size: 30, weight: .semibold))
        Text(L("A calm place for your mail.", "安心阅读，轻松接住邮件链接。 ")).font(.title3).foregroundStyle(
          .secondary)
      }
      Button {
        model.chooseFiles()
      } label: {
        Label(L("Open email or archive", "打开邮件或存档"), systemImage: "folder")
      }.controlSize(.large).buttonStyle(.borderedProminent).keyboardShortcut("o")
      Text(L("Drop files here to read them on your Mac.", "将文件拖到这里，在 Mac 上直接阅读。")).font(
        .system(size: 14)
      )
      .foregroundStyle(.secondary)
      Text("EML / EMLX / MSG / OFT / MBOX / Maildir").font(.system(size: 13)).foregroundStyle(
        .tertiary)
      Divider().frame(width: 64).padding(.vertical, 6)
      SettingsLink { Text(L("Set up email link capture…", "设置邮件链接接管…")) }.buttonStyle(.link)
      Text("© 2026 Songming.org").font(.system(size: 13)).foregroundStyle(.tertiary).padding(
        .top, 12)
    }.padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
struct MessageList: View {
  @ObservedObject var model = AppModel.shared
  @ObservedObject var prefs = Preferences.shared
  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Text(L("Messages", "邮件")).font(.headline)
        Spacer()
        Menu {
          Toggle(L("Newest first", "最新优先"), isOn: $model.newestFirst)
        } label: {
          Image(systemName: "arrow.up.arrow.down")
        }.menuStyle(.borderlessButton).fixedSize()
          .help(L("Message order", "邮件顺序"))
        if model.searching { ProgressView().controlSize(.small).help(L("Searching…", "正在搜索…")) }
        Text("\(model.entries.count)").font(.callout.monospacedDigit()).foregroundStyle(.secondary)
      }.padding(16)
      TextField(L("Search messages", "搜索邮件"), text: $model.query).textFieldStyle(
        .roundedBorder
      ).padding(.horizontal, 12).padding(.bottom, 12)
      if model.searchUnreadable > 0 {
        Text(
          L(
            "\(model.searchUnreadable) messages could not be searched.",
            "\(model.searchUnreadable) 封邮件未能搜索。")
        )
        .font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(
          .bottom, 8)
      }
      Divider()
      List(selection: Binding(get: { model.selectedEntry }, set: { model.select($0) })) {
        ForEach(model.entries) { entry in
          VStack(alignment: .leading, spacing: 6) {
            HStack {
              Text(entry.from.isEmpty ? L("Unknown sender", "未知发件人") : entry.from).font(
                .system(size: 14, weight: .semibold)
              ).lineLimit(1)
              Spacer()
            }
            Text(entry.subject.isEmpty ? L("No subject", "无主题") : entry.subject).font(
              .system(size: 13)
            ).lineLimit(2)
            if !entry.date.isEmpty {
              Text(readableDate(entry.date)).font(.system(size: 13)).foregroundStyle(.secondary)
                .lineLimit(1)
            }
          }.padding(.vertical, 7).tag(entry.id)
        }
      }.listStyle(.inset)
      if model.active?.indexLimitReached == true {
        indexNotice(
          L(
            "Partial list: the in-memory index limit was reached. Close other archives and reopen to free space.",
            "列表尚不完整：已达到内存索引上限。可关闭其他存档后重新打开以释放空间。"))
      } else if model.active?.indexInterrupted == true {
        indexNotice(
          L(
            "Indexing stopped. Reopen the archive to read the remaining messages.",
            "索引已停止，重新打开存档可继续读取其余邮件。"))
      }
    }.background(Color(nsColor: .controlBackgroundColor))
  }
  private func indexNotice(_ text: String) -> some View {
    Text(text).font(.system(size: 13)).foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading).padding(12)
  }
}
func readableDate(_ value: String) -> String {
  MailDate.display(value)
}

private final class DropBatch: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [URL] = []
  func add(_ url: URL) {
    lock.lock()
    values.append(url)
    lock.unlock()
  }
  var urls: [URL] {
    lock.lock()
    defer { lock.unlock() }
    return values
  }
}
