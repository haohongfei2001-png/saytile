import AppKit
import SwiftUI

public enum VoicePanelState: Equatable, Sendable { case paused, standby, recognizing, starting, recoveryNeeded }

private struct VoicePanelFullscreenKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// Hosts report the surrounding window context; the shared card alone owns
    /// its material response. Ordinary desktop rendering remains the default.
    var isOverFullscreen: Bool {
        get { self[VoicePanelFullscreenKey.self] }
        set { self[VoicePanelFullscreenKey.self] = newValue }
    }
}

public struct VoicePanelCapture: Equatable, Sendable {
    public let state: VoicePanelState
    public let level: Double?
    public let actionLabel: String
    public let accessibilityValue: String
    public init(state: VoicePanelState, level: Double?, actionLabel: String, accessibilityValue: String) {
        self.state = state
        self.level = state == .recognizing ? level.flatMap { $0.isFinite ? max(0, min(1, $0)) : nil } : nil
        self.actionLabel = actionLabel
        self.accessibilityValue = accessibilityValue
    }
}

/// Both hosts place this transcript card inside a shared FramedVoiceSlot.
/// Persistence, capture lifecycle and menu actions belong to the host.
public struct VoiceSurfacePanel<Entry: VoiceTranscriptEntry, MenuItems: View>: View {
    let document: PanelTimelineDocument<Entry>
    let access: PanelTranscriptAccess<Entry>
    let capture: VoicePanelCapture
    let canCopy: Bool
    let selectedText: String
    let onCopy: () -> Void
    let onToggle: () -> Void
    let onPage: (Bool) -> Void
    let onSelectionChange: (String) -> Void
    let onFollowChange: (Bool) -> Void
    let focusPosition: Int64?
    let editing: Bool
    let latestRequest: Int
    let fillContextMenu: (@MainActor (NSMenu) -> Void)?
    let applyEdits: (@MainActor ([VoicePanelEdit]) throws -> PanelTimelineDocument<Entry>)?
    let onEdit: (@MainActor () -> Void)?
    let captureDisabled: Bool
    let compactHelp: String?
    let menu: () -> MenuItems

    private typealias ViewState<T> = SwiftUI.State<T>
    @Environment(\.singleGlassSurface) private var singleGlassSurface
    @Environment(\.insideVoiceRail) private var insideVoiceRail
    @Environment(\.voiceSlotLayout) private var slotLayout
    @ViewState private var captureHovered = false
    @FocusState private var captureFocused: Bool
    private let ink = Color(red: 0.17, green: 0.16, blue: 0.23)

    /// Legacy host message parameters remain source-compatible. The document area contains only user text.
    public init(document: PanelTimelineDocument<Entry>, access: PanelTranscriptAccess<Entry>, capture: VoicePanelCapture,
                canCopy: Bool, selectedText: String, onCopy: @escaping () -> Void, onToggle: @escaping () -> Void,
                onPage: @escaping (Bool) -> Void = { _ in }, onSelectionChange: @escaping (String) -> Void = { _ in },
                onFollowChange: @escaping (Bool) -> Void = { _ in }, focusPosition: Int64? = nil, editing: Bool = false,
                latestRequest: Int = 0, fillContextMenu: (@MainActor (NSMenu) -> Void)? = nil, onEdit: (@MainActor () -> Void)? = nil,
                applyEdits: (@MainActor ([VoicePanelEdit]) throws -> PanelTimelineDocument<Entry>)? = nil,
                target _: String? = nil, notice _: String? = nil, placeholder _: String? = nil, placeholderDetail _: String? = nil,
                captureDisabled: Bool = false, compactHelp: String? = nil, @ViewBuilder menu: @escaping () -> MenuItems) {
        self.document = document
        self.access = access
        self.capture = capture
        self.canCopy = canCopy
        self.selectedText = selectedText
        self.onCopy = onCopy
        self.onToggle = onToggle
        self.onPage = onPage
        self.onSelectionChange = onSelectionChange
        self.onFollowChange = onFollowChange
        self.focusPosition = focusPosition
        self.editing = editing
        self.latestRequest = latestRequest
        self.fillContextMenu = fillContextMenu
        self.applyEdits = applyEdits
        self.onEdit = onEdit
        self.captureDisabled = captureDisabled
        self.compactHelp = compactHelp
        self.menu = menu
    }

    public var body: some View {
        GeometryReader { frame in
            let layout = slotLayout ?? VoicePanelLayout(size: frame.size, inRail: false)
            content(layout, metrics: VoicePanelMetrics(width: layout.cardFrame.width, inRail: insideVoiceRail))
        }
    }

    private func content(_ layout: VoicePanelLayout, metrics: VoicePanelMetrics) -> some View {
        let card = layout.cardFrame
        let text = layout.transcriptFrame
        let copy = layout.copyFrame
        let captureRect = layout.captureFrame
        return ZStack(alignment: .topLeading) {
            CompactTranscriptView(document: document, access: access, onPage: onPage, focusPosition: focusPosition,
                editing: editing, latestRequest: latestRequest, onFollowChange: onFollowChange,
                onSelectionChange: onSelectionChange, fillContextMenu: fillContextMenu, applyEdits: applyEdits, onEdit: onEdit,
                showsLiveCaret: capture.state == .recognizing, typeScale: metrics.typeScale, compact: !layout.canUseTranscript)
                .frame(width: text.width, height: text.height).clipped()
                .opacity(layout.transcriptOpacity)
                .accessibilityHidden(!layout.canUseTranscript).allowsHitTesting(layout.canUseTranscript)
                .position(x: text.midX - card.minX, y: card.maxY - text.midY)

            copyButton(metrics)
                .disabled(!layout.canUseCopy)
                .opacity(layout.copyOpacity)
                .accessibilityHidden(!layout.canUseCopy).allowsHitTesting(layout.canUseCopy)
                .position(x: copy.midX - card.minX, y: card.maxY - copy.midY)
            captureButton(metrics, rect: captureRect, chrome: layout.controlChromeOpacity)
                .position(x: captureRect.midX - card.minX, y: card.maxY - captureRect.midY)
        }
        .frame(width: card.width, height: card.height)
        .background {
            if !singleGlassSurface { ReferencePanelSurface(radius: layout.innerRadius) }
        }
        .clipShape(RoundedRectangle(cornerRadius: layout.innerRadius, style: .continuous))
        .background {
            if !insideVoiceRail { VoicePanelShadow(radius: layout.innerRadius) }
        }
        .foregroundStyle(ink)
    }

    private func copyButton(_ metrics: VoicePanelMetrics) -> some View {
        let scale = metrics.scale
        return Button(action: onCopy) {
            ReferenceCopyMark().stroke(ReferencePanelStyle.copyInk.opacity(canCopy ? 1 : 0.5),
                                       style: StrokeStyle(lineWidth: 1.65 * scale, lineCap: .round, lineJoin: .round))
                .frame(width: metrics.copyMarkSize, height: metrics.copyMarkSize)
                .frame(width: metrics.copyWidth, height: metrics.controlHeight)
                .background { ReferenceControlSurface(copy: true, scale: scale) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).contextMenu(menuItems: menu)
        .help(canCopy ? "复制文字；右键打开更多操作" : "右键打开更多操作")
        .accessibilityLabel(selectedText.isEmpty ? "复制当前文字" : "复制所选文字")
        .accessibilityHint("右键或打开上下文菜单可查看更多操作")
        .accessibilityIdentifier("panel.copy")
    }

    private func captureButton(_ metrics: VoicePanelMetrics, rect: CGRect, chrome: CGFloat) -> some View {
        let highlight = Color.gray.opacity(captureFocused ? 0.65 : captureHovered ? 0.24 : 0)
        return Button(action: onToggle) {
            VoiceCaptureGlyph(presentation: capture, scale: metrics.scale)
                .foregroundStyle(ReferencePanelStyle.glyph)
                .frame(width: rect.width, height: rect.height)
                .background { ReferenceControlSurface(scale: metrics.scale).opacity(chrome) }
                .overlay {
                    Capsule().strokeBorder(highlight.opacity(captureFocused ? 1 : chrome), lineWidth: captureFocused ? 2 : 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(CaptureButtonStyle()).disabled(captureDisabled)
        .onHover { captureHovered = $0 }.focused($captureFocused)
        .contextMenu(menuItems: menu)
        .help(chrome < 1 ? compactHelp ?? capture.actionLabel : capture.actionLabel)
        .accessibilityLabel(capture.actionLabel)
        .accessibilityValue(capture.accessibilityValue).accessibilityIdentifier("panel.capture")
    }

    private struct CaptureButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.62 : 1)
        }
    }
}
