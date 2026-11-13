import AppKit
import SwiftUI

public enum VoicePanelState: Equatable, Sendable { case paused, standby, recognizing, starting, recoveryNeeded }

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
    let menu: () -> MenuItems

    private typealias ViewState<T> = SwiftUI.State<T>
    @Environment(\.singleGlassSurface) private var singleGlassSurface
    @Environment(\.insideVoiceRail) private var insideVoiceRail
    @Environment(\.compactVoiceSlot) private var compactSlot
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
                captureDisabled: Bool = false, @ViewBuilder menu: @escaping () -> MenuItems) {
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
        self.menu = menu
    }

    public var body: some View {
        GeometryReader { frame in
            content(VoicePanelMetrics(width: frame.size.width, inRail: insideVoiceRail),
                    compact: insideVoiceRail ? compactSlot : VoicePanelFootprint.isCompact(outerWidth: frame.size.width))
        }
    }

    private func content(_ metrics: VoicePanelMetrics, compact: Bool) -> some View {
        let scale = metrics.scale
        return VStack(spacing: 0) {
            CompactTranscriptView(document: document, access: access, onPage: onPage, focusPosition: focusPosition,
                editing: editing, latestRequest: latestRequest, onFollowChange: onFollowChange,
                onSelectionChange: onSelectionChange, fillContextMenu: fillContextMenu, applyEdits: applyEdits, onEdit: onEdit,
                showsLiveCaret: capture.state == .recognizing, typeScale: metrics.typeScale, compact: compact)
                .opacity(compact ? 0 : 1).accessibilityHidden(compact).allowsHitTesting(!compact)
                .padding(.leading, ReferencePanelStyle.textInset * scale - 2)
                .padding(.trailing, 8 * scale).frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: compact ? 0 : nil).clipped()

            HStack(spacing: 0) {
                if !compact && metrics.showsCopy {
                    copyButton(metrics)
                }
                if !compact { Spacer(minLength: 0) }
                captureButton(metrics, compact: compact)
            }
            .padding(.leading, compact ? 0 : metrics.footerLeading)
            .padding(.trailing, compact ? 0 : ReferencePanelStyle.footerTrailing * scale)
            .padding(.top, compact ? 0 : metrics.footerTop).padding(.bottom, compact ? 0 : metrics.footerBottom)
        }
        .padding(.top, compact ? 0 : metrics.topPadding)
        .background {
            if !singleGlassSurface && !compact { ReferencePanelSurface(radius: metrics.radius) }
        }
        .clipShape(RoundedRectangle(cornerRadius: compact ? 0 : metrics.radius, style: .continuous))
        .background {
            if !insideVoiceRail && !compact { VoicePanelShadow(radius: metrics.radius) }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func captureButton(_ metrics: VoicePanelMetrics, compact: Bool) -> some View {
        let scale = metrics.scale
        return Button(action: onToggle) {
            VoiceCaptureGlyph(presentation: capture, scale: scale)
                .foregroundStyle(ReferencePanelStyle.glyph)
                .frame(width: metrics.voiceWidth, height: metrics.controlHeight)
                .background { ReferenceControlSurface(scale: scale) }
                .background { if compact { Capsule().fill(.regularMaterial) } }
                .contentShape(Rectangle())
        }
        .buttonStyle(CaptureButtonStyle()).disabled(captureDisabled)
        .overlay(Capsule().stroke(Color.gray.opacity(captureFocused ? 0.65 : captureHovered ? 0.24 : 0), lineWidth: captureFocused ? 2 : 1).allowsHitTesting(false))
        .onHover { captureHovered = $0 }.focused($captureFocused)
        .help(capture.actionLabel).accessibilityLabel(capture.actionLabel)
        .accessibilityValue(capture.accessibilityValue).accessibilityIdentifier("panel.capture")
    }

    private struct CaptureButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.62 : 1)
        }
    }
}
