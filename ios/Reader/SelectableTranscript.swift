#if os(iOS)
import SwiftUI
import UIKit

// Native range selection and Copy; no editing or nested scrolling in the list.
struct SelectableTranscript: UIViewRepresentable {
    let text: String
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textColor = .label
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.accessibilityIdentifier = "archive.text"
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        // Sync refresh must never reset a reader's selection for identical text.
        if view.text != text { view.text = text }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        return CGSize(width: width, height: ceil(uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height))
    }
}
#endif
