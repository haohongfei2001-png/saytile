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
    let onEdit: (@MainActor () -> Void)?
    let target: String?
    let notice: String?
    let placeholder: String?
    let placeholderDetail: String?
    let captureDisabled: Bool
    let menu: () -> MenuItems

    private typealias ViewState<T> = SwiftUI.State<T>
    @Environment(\.insideVoiceRail) private var insideVoiceRail
    @ViewState private var captureHovered = false
    @FocusState private var captureFocused: Bool
    private let muted = Color(red: 0.43, green: 0.41, blue: 0.51)
    private let amber = Color(red: 0.58, green: 0.42, blue: 0.22)
    private let ink = Color(red: 0.17, green: 0.16, blue: 0.23)

    public init(document: PanelTimelineDocument<Entry>, access: PanelTranscriptAccess<Entry>, capture: VoicePanelCapture,
                canCopy: Bool, selectedText: String, onCopy: @escaping () -> Void, onToggle: @escaping () -> Void,
                onPage: @escaping (Bool) -> Void = { _ in }, onSelectionChange: @escaping (String) -> Void = { _ in },
                onFollowChange: @escaping (Bool) -> Void = { _ in }, focusPosition: Int64? = nil, editing: Bool = false,
                latestRequest: Int = 0, fillContextMenu: (@MainActor (NSMenu) -> Void)? = nil, onEdit: (@MainActor () -> Void)? = nil,
                target: String? = nil, notice: String? = nil, placeholder: String? = nil, placeholderDetail: String? = nil,
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
        self.onEdit = onEdit
        self.target = target
        self.notice = notice
        self.placeholder = placeholder
        self.placeholderDetail = placeholderDetail
        self.captureDisabled = captureDisabled
        self.menu = menu
    }

    public var body: some View {
        GeometryReader { frame in
            content(VoicePanelMetrics(width: frame.size.width, inRail: insideVoiceRail))
        }
    }

    private func content(_ metrics: VoicePanelMetrics) -> some View {
        let scale = metrics.scale
        return VStack(spacing: 0) {
            if let target {
                Label(target, systemImage: "arrow.up.forward.app")
                    .font(.system(size: 10)).foregroundStyle(muted)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14 * scale).padding(.bottom, 5)
                    .help(target).accessibilityIdentifier("panel.target")
            }
            if let notice {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text(notice).lineLimit(2).fixedSize(horizontal: false, vertical: true).help(notice)
                    Spacer(minLength: 0)
                }.font(.system(size: 11)).foregroundStyle(amber)
                    .padding(.horizontal, 14 * scale).padding(.vertical, 5).accessibilityIdentifier("panel.notice")
            }
            CompactTranscriptView(document: document, access: access, onPage: onPage, focusPosition: focusPosition,
                editing: editing, latestRequest: latestRequest, onFollowChange: onFollowChange,
                onSelectionChange: onSelectionChange, fillContextMenu: fillContextMenu, onEdit: onEdit,
                showsLiveCaret: capture.state == .recognizing, typeScale: metrics.typeScale)
                .overlay(alignment: .topLeading) {
                    if let placeholder {
                        VStack(alignment: .leading, spacing: 8 * scale) {
                            Text(placeholder).font(.system(size: ReferencePanelStyle.fontSize * metrics.typeScale))
                            if let placeholderDetail {
                                Text(placeholderDetail).font(.system(size: max(10, 12 * metrics.typeScale)))
                                    .lineSpacing(3).foregroundStyle(muted)
                            }
                        }.foregroundStyle(ink.opacity(0.8)).padding(.top, 6).padding(.horizontal, 2)
                            .accessibilityElement(children: .combine).allowsHitTesting(false)
                    }
                }
                .padding(.leading, ReferencePanelStyle.textInset * scale - 2)
                .padding(.trailing, 8 * scale).frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 0) {
                Button(action: onCopy) {
                    ReferenceCopyMark().stroke(ReferencePanelStyle.copyInk.opacity(canCopy ? 1 : 0.5),
                                               style: StrokeStyle(lineWidth: 1.65 * scale, lineCap: .round, lineJoin: .round))
                        .frame(width: metrics.copyMarkSize, height: metrics.copyMarkSize)
                        .frame(width: metrics.copyWidth, height: metrics.controlHeight)
                        .background { ReferenceControlSurface(copy: true, scale: scale) }
                        .contentShape(RoundedRectangle(cornerRadius: 13 * scale))
                }
                .buttonStyle(.plain).contextMenu(menuItems: menu)
                .help(canCopy ? "复制文字；右键打开更多操作" : "右键打开更多操作")
                .accessibilityLabel(selectedText.isEmpty ? "复制当前文字" : "复制所选文字")
                .accessibilityHint("右键或打开上下文菜单可查看更多操作")
                .accessibilityIdentifier("panel.copy")
                Spacer(minLength: 8 * scale)
                Button(action: onToggle) {
                    VoiceCaptureGlyph(presentation: capture, scale: scale)
                        .foregroundStyle(capture.state == .recoveryNeeded ? AnyShapeStyle(amber) : AnyShapeStyle(ReferencePanelStyle.glyph))
                        .frame(width: metrics.voiceWidth, height: metrics.controlHeight)
                        .background { ReferenceControlSurface(scale: scale) }
                        .contentShape(Capsule())
                }
                .buttonStyle(CaptureButtonStyle()).disabled(captureDisabled)
                .overlay(Capsule().stroke(Color.gray.opacity(captureFocused ? 0.65 : captureHovered ? 0.24 : 0), lineWidth: captureFocused ? 2 : 1))
                .onHover { captureHovered = $0 }.focused($captureFocused)
                .help(capture.actionLabel).accessibilityLabel(capture.actionLabel)
                .accessibilityValue(capture.accessibilityValue).accessibilityIdentifier("panel.capture")
            }
            .padding(.leading, metrics.footerLeading)
            .padding(.trailing, ReferencePanelStyle.footerTrailing * scale)
            .padding(.top, metrics.footerTop).padding(.bottom, metrics.footerBottom)
        }
        .padding(.top, metrics.topPadding)
        .background { ReferencePanelSurface(radius: metrics.radius) }
        .clipShape(RoundedRectangle(cornerRadius: metrics.radius, style: .continuous))
        .background {
            if !insideVoiceRail { VoicePanelShadow(radius: metrics.radius) }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct CaptureButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.opacity(configuration.isPressed ? 0.62 : 1)
        }
    }
}
