import AppKit
import SwiftUI

/// Content changes never participate in divider sizing. Only a drag or container resize does.
struct MailReadingPanes: NSViewRepresentable {
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> NSSplitView {
    let split = NSSplitView()
    split.isVertical = true
    split.dividerStyle = .thin
    split.delegate = context.coordinator
    let list = NSHostingView(
      rootView: MessageList().frame(maxWidth: .infinity, maxHeight: .infinity))
    let reader = NSHostingView(
      rootView: MessageView().frame(maxWidth: .infinity, maxHeight: .infinity))
    // Disable hosted-content intrinsic sizing, including loading, errors, and long attachments.
    list.sizingOptions = []
    reader.sizingOptions = []
    split.addArrangedSubview(list)
    split.addArrangedSubview(reader)
    return split
  }
  func updateNSView(_ nsView: NSSplitView, context: Context) {}

  @MainActor final class Coordinator: NSObject, NSSplitViewDelegate {
    private var arranging = false
    func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
      guard splitView.subviews.count == 2, splitView.bounds.width > 0 else { return }
      arranging = true
      defer { arranging = false }
      let available = max(0, splitView.bounds.width - splitView.dividerThickness)
      let width = min(AppModel.shared.mailListWidth, max(0, available - 300))
      let list = max(min(260, available / 2), width)
      splitView.subviews[0].frame = NSRect(x: 0, y: 0, width: list, height: splitView.bounds.height)
      splitView.subviews[1].frame = NSRect(
        x: list + splitView.dividerThickness, y: 0,
        width: max(0, available - list), height: splitView.bounds.height)
    }
    func splitViewDidResizeSubviews(_ notification: Notification) {
      guard !arranging, let split = notification.object as? NSSplitView,
        let width = split.subviews.first?.frame.width, width >= 260
      else { return }
      AppModel.shared.mailListWidth = width
    }
    func splitView(
      _ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
      ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
      min(260, splitView.bounds.width / 2)
    }
    func splitView(
      _ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
      ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
      max(min(260, splitView.bounds.width / 2), min(460, splitView.bounds.width - 300))
    }
    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool { false }
  }
}
