import SwiftUI
import AppKit

/// Measurements from the user's supplied 1536x1024 reference (SHA256
/// 58be88a019cf0241b1c540f799d0944ed294e650b8c119923a434a6e4889a7c5).
/// The main card is approximately 690x469 image pixels. At 2x these are
/// macOS points, not a new layout invented from an earlier engineering render.
enum ReferencePanelStyle {
    static let corner: CGFloat = 28
    static let horizontalInset: CGFloat = 20
    static let bottomInset: CGFloat = 18
    static let fontSize: CGFloat = 19.5
    static let lineHeight: CGFloat = 26
    static let violet = Color(red: 0.48, green: 0.23, blue: 0.99)
    static let copyInk = Color(red: 0.43, green: 0.44, blue: 0.52)
    static let copySize = CGSize(width: 42, height: 34)
    static let voiceSize = CGSize(width: 92, height: 34)
    static let sampleText = "我想让 Saytile 成为一个始终待命的语音输入工作台，它应该让文字自然出现，而不是让按钮打断表达。说完这一句，它会安静地等我继续开口。"
}

/// Native window-background blur; tint and edge highlights are separate layers.
/// Does not read/capture the desktop or add any interaction or focusable control.
private struct ReferenceGlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ReferencePanelSurface: View {
    private let shape = RoundedRectangle(cornerRadius: ReferencePanelStyle.corner, style: .continuous)
    var body: some View {
        ZStack {
            ReferenceGlassBackdrop()
            LinearGradient(stops: [
                .init(color: Color(red: 0.855, green: 0.825, blue: 1.0), location: 0),
                .init(color: Color(red: 0.793, green: 0.821, blue: 1.0), location: 0.53),
                .init(color: Color(red: 0.695, green: 0.766, blue: 0.997), location: 1)
            ], startPoint: .leading, endPoint: .trailing).opacity(0.97)
            LinearGradient(colors: [.white.opacity(0.10), .clear, .white.opacity(0.015)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.80), .white.opacity(0.24)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.65)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct ReferenceControlSurface: View {
    let radius: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [.white.opacity(0.36), .white.opacity(0.16)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.90), .white.opacity(0.17)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.65)
            }
            .shadow(color: Color(red: 0.39, green: 0.40, blue: 0.76).opacity(0.27), radius: 5, x: 0, y: 5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The reference uses overlapping rounded squares, not folded document sheets.
struct ReferenceCopyMark: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 17
        var path = Path()
        path.move(to: CGPoint(x: 5.5, y: 11.5))
        path.addLine(to: CGPoint(x: 2.5, y: 11.5))
        path.addQuadCurve(to: CGPoint(x: 1, y: 10), control: CGPoint(x: 1, y: 11.5))
        path.addLine(to: CGPoint(x: 1, y: 2.5))
        path.addQuadCurve(to: CGPoint(x: 2.5, y: 1), control: CGPoint(x: 1, y: 1))
        path.addLine(to: CGPoint(x: 10, y: 1))
        path.addQuadCurve(to: CGPoint(x: 11.5, y: 2.5), control: CGPoint(x: 11.5, y: 1))
        path.addLine(to: CGPoint(x: 11.5, y: 5.5))
        path.addRoundedRect(in: CGRect(x: 5.5, y: 5.5, width: 10.5, height: 10.5),
                            cornerSize: CGSize(width: 1.7, height: 1.7))
        return path.applying(CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}
