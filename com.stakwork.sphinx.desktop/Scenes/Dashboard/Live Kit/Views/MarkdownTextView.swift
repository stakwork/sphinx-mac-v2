import AppKit
import SwiftUI

// MARK: - AutosizingTextView

/// NSTextView subclass that computes its intrinsic height from its
/// laid-out content so SwiftUI can size it correctly without a scroll view.
final class AutosizingTextView: NSTextView {

    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else {
            return super.intrinsicContentSize
        }
        // Width must already be set (widthTracksTextView = true keeps it in sync).
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(used.height))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

    // When the view is resized (width changes) recalculate height.
    override func layout() {
        super.layout()
        invalidateIntrinsicContentSize()
    }
}

// MARK: - MarkdownTextView

struct MarkdownTextView: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AutosizingTextView {
        let tv = AutosizingTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainerInset = .zero
        // Width tracks the view so word-wrap works correctly.
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.lineFragmentPadding = 0
        tv.isAutomaticLinkDetectionEnabled = false
        tv.autoresizingMask = [.width]
        tv.delegate = context.coordinator
        return tv
    }

    func updateNSView(_ tv: AutosizingTextView, context: Context) {
        guard tv.attributedString() != attributedString else { return }
        tv.textStorage?.setAttributedString(attributedString)
        tv.invalidateIntrinsicContentSize()
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        func textView(_ textView: NSTextView,
                      clickedOnLink link: Any,
                      at charIndex: Int) -> Bool {
            if let url = link as? URL {
                NSWorkspace.shared.open(url)
            }
            return true
        }
    }
}
