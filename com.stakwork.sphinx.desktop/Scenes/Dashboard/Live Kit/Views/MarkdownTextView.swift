import AppKit
import SwiftUI

// MARK: - AutosizingTextView

/// NSTextView subclass that sizes itself to fit its content.
/// Reports the natural text width as intrinsicContentSize.width so
/// SwiftUI bubbles hug short messages rather than stretching full-width.
private final class AutosizingTextView: NSTextView {

    override var intrinsicContentSize: NSSize {
        guard let lm = layoutManager, let tc = textContainer else {
            return super.intrinsicContentSize
        }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        // Return natural text width + height so the bubble wraps the content.
        return NSSize(width: ceil(used.width), height: ceil(used.height))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }

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
        // Allow the container to grow as wide as the text needs.
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.lineFragmentPadding = 0
        // Large but finite max width so very long messages still wrap.
        tv.textContainer?.containerSize = NSSize(
            width: 400,
            height: CGFloat.greatestFiniteMagnitude
        )
        tv.isAutomaticLinkDetectionEnabled = false
        tv.autoresizingMask = []
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
