import SwiftUI

/// Renders an `AttributedString` using SwiftUI `Text`.
/// Sizing is handled entirely by SwiftUI — no NSViewRepresentable needed.
struct MarkdownTextView: View {
    let attributedString: AttributedString

    var body: some View {
        Text(attributedString)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }
}
