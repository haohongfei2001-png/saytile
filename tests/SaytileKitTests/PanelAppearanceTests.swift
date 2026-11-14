import AppKit
import SwiftUI
import Testing
@testable import SaytileVoiceUI

@Suite @MainActor struct PanelAppearanceTests {
    private struct Row: VoiceTranscriptEntry {
        let id = UUID()
        let position: Int64 = 1
        var displayText: String
    }

    @Test func defaultsPreserveExistingAppearanceAndRoundTrip() throws {
        let current = VoicePanelAppearance()
        #expect(current.panelColor == .original && current.buttonColor == .violet)
        #expect(current.opacity == .original && current.textSize == .standard)
        #expect(EnvironmentValues().voicePanelAppearance == current)
        #expect(current.textSize.typeScale == 0.72)
        #expect(abs(ReferencePanelStyle.fontSize * current.textSize.typeScale - 14.04) < 0.001)
        #expect(current.opacity.material(fullscreen: false, reduceTransparency: false) ==
            VoicePanelMaterial(cardWash: 0.42, cardBlur: 0.10, railWash: 0.27, railBlur: 0.12))
        #expect(current.opacity.material(fullscreen: true, reduceTransparency: false) ==
            VoicePanelMaterial(cardWash: 0.64, cardBlur: 0.85, railWash: 0.50, railBlur: 0.80))
        #expect(current.opacity.material(fullscreen: false, reduceTransparency: true) ==
            VoicePanelMaterial(cardWash: 1, cardBlur: 1, railWash: 0.94, railBlur: 1))
        let choice = VoicePanelAppearance(panelColor: .blue, buttonColor: .graphite, opacity: .dense, textSize: .extraLarge)
        #expect(try JSONDecoder().decode(VoicePanelAppearance.self, from: JSONEncoder().encode(choice)) == choice)
    }

    @Test func presetsAreProgressivelyMoreOpaqueAndFullscreenNeverWeakensThem() {
        var prior: VoicePanelMaterial?
        for preset in PanelOpacityPreset.allCases {
            let ordinary = preset.material(fullscreen: false, reduceTransparency: false)
            if let prior {
                #expect(ordinary.cardWash > prior.cardWash && ordinary.railWash > prior.railWash)
                #expect(ordinary.cardBlur >= prior.cardBlur && ordinary.railBlur >= prior.railBlur)
            }
            prior = ordinary
            let fullscreen = preset.material(fullscreen: true, reduceTransparency: false)
            #expect(fullscreen.cardWash >= ordinary.cardWash && fullscreen.railWash >= ordinary.railWash)
            #expect(fullscreen.cardBlur >= ordinary.cardBlur && fullscreen.railBlur >= ordinary.railBlur)
            let accessible = preset.material(fullscreen: true, reduceTransparency: true)
            #expect(accessible.cardWash == 1 && accessible.cardBlur == 1 && accessible.railBlur == 1)
            #expect(accessible.railWash >= ordinary.railWash)
        }
        #expect(PanelOpacityPreset.opaque.material(fullscreen: true, reduceTransparency: true) ==
            VoicePanelMaterial(cardWash: 1, cardBlur: 1, railWash: 1, railBlur: 1))
        #expect(PanelTextSizePreset.allCases.map(\.pointSize) == [12, 14.04, 16, 18])
    }

    private func fixture() -> (NSPanel, CompactTranscriptScrollView<Row>, Row) {
        _ = NSApplication.shared
        let box = NSRect(x: 0, y: 0, width: 210, height: 145)
        let panel = NSPanel(contentRect: box, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        let scroll = CompactTranscriptScrollView<Row>(frame: box)
        panel.contentView = scroll
        panel.orderBack(nil)
        let row = Row(displayText: (1...80).map { "第\($0)段阅读文字：保留数字24、人工换行与选中文字。" }.joined(separator: "\n"))
        scroll.applyTypeScale(PanelTextSizePreset.standard.typeScale)
        scroll.updateDocument(.init(entries: [row]))
        scroll.layoutSubtreeIfNeeded()
        return (panel, scroll, row)
    }

    private func fontSize(_ scroll: CompactTranscriptScrollView<Row>) -> CGFloat? {
        scroll.transcriptView.textStorage?.attribute(.font, at: 0, effectiveRange: nil).flatMap { ($0 as? NSFont)?.pointSize }
    }

    @Test func fontChangesPreserveReadingCharacterSelectionAndText() throws {
        let (panel, scroll, row) = fixture()
        defer { panel.orderOut(nil); panel.close() }
        let view = scroll.transcriptView
        let storage = try #require(view.textStorage)
        let manager = try #require(view.layoutManager), container = try #require(view.textContainer)
        let selected = (row.displayText as NSString).range(of: "第40段")
        view.setSelectedRange(selected)
        let selectedGlyph = manager.glyphIndexForCharacter(at: selected.location)
        let oldRect = manager.boundingRect(forGlyphRange: NSRange(location: selectedGlyph, length: 1), in: container)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: oldRect.minY + view.textContainerInset.height + 3))
        scroll.reflectScrolledClipView(scroll.contentView)
        let point = NSPoint(x: 0, y: scroll.documentVisibleRect.minY - view.textContainerInset.height)
        let topGlyph = manager.glyphIndex(for: point, in: container)
        let character = manager.characterIndexForGlyph(at: topGlyph)
        let topRect = manager.boundingRect(forGlyphRange: NSRange(location: topGlyph, length: 1), in: container)
        let offset = scroll.documentVisibleRect.minY - topRect.minY - view.textContainerInset.height
        #expect(!scroll.isFollowingLatest)
        let previousHeight = view.frame.height

        scroll.applyTypeScale(PanelTextSizePreset.extraLarge.typeScale)
        scroll.layoutSubtreeIfNeeded()
        #expect(view.textStorage === storage && view.string == row.displayText)
        #expect(view.selectedRange() == selected && scroll.selectionSnapshot == "第40段")
        #expect(abs((fontSize(scroll) ?? 0) - 18) < 0.001)
        #expect(view.frame.height > previousHeight)
        let newGlyph = manager.glyphIndexForCharacter(at: character)
        let newRect = manager.boundingRect(forGlyphRange: NSRange(location: newGlyph, length: 1), in: container)
        #expect(abs(scroll.documentVisibleRect.minY - newRect.minY - view.textContainerInset.height - offset) < 1)
        #expect(!scroll.isFollowingLatest && !panel.isKeyWindow)
    }

    @Test func fontChangesKeepAnUnselectedLiveTailAtTheEnd() {
        let (panel, scroll, row) = fixture()
        defer { panel.orderOut(nil); panel.close() }
        scroll.jumpToLatest()
        for choice in [PanelTextSizePreset.extraLarge, .small, .standard] {
            scroll.applyTypeScale(choice.typeScale)
            scroll.layoutSubtreeIfNeeded()
            #expect(scroll.isFollowingLatest)
            #expect(abs(scroll.documentVisibleRect.maxY - scroll.transcriptView.bounds.maxY) < 1)
            #expect(abs((fontSize(scroll) ?? 0) - choice.pointSize) < 0.001)
            #expect(scroll.transcriptView.string == row.displayText)
        }
    }

    @Test func latestFontChoiceWaitsForCompositionAndAppliesAfterCommit() throws {
        let (panel, scroll, original) = fixture()
        defer { panel.orderOut(nil); panel.close() }
        var row = original
        var changes = 0
        scroll.applyEdits = { edits in
            #expect(edits.count == 1 && edits[0].id == row.id)
            row.displayText = edits[0].after
            changes += 1
            return .init(entries: [row])
        }
        let view = scroll.transcriptView
        view.isEditable = true
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: 0, length: 0))
        #expect(view.hasMarkedText())
        scroll.applyTypeScale(PanelTextSizePreset.large.typeScale)
        scroll.applyTypeScale(PanelTextSizePreset.extraLarge.typeScale)
        #expect(view.hasMarkedText() && view.string.hasPrefix("zhong"))
        #expect(abs((fontSize(scroll) ?? 0) - 14.04) < 0.001)
        #expect(changes == 0)
        view.insertText("中", replacementRange: view.markedRange())
        #expect(!view.hasMarkedText() && changes == 1)
        #expect(view.string == "中" + original.displayText)
        #expect(abs((fontSize(scroll) ?? 0) - 18) < 0.001)
        #expect(!panel.isKeyWindow)
    }
}
