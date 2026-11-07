import AppKit
import Foundation
@main struct Review {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let view = CompactTranscriptScrollView(frame: NSRect(x: 0, y: 0, width: 314, height: 150))
        view.layoutSubtreeIfNeeded()
        let text = (0..<70).map { "第\($0)行：独立合成文字，不涉及私人资料。" }.joined(separator: "\n")
        view.updateTranscript(text); view.layoutSubtreeIfNeeded(); view.jumpToLatest()
        let bottom = view.contentView.bounds.origin.y
        view.contentView.scroll(to: NSPoint(x: 0, y: bottom - 2)); view.reflectScrolledClipView(view.contentView)
        let held = view.contentView.bounds.origin.y, following = view.isFollowingLatest
        view.updateTranscript(text + "\n合成追加的一行。")
        let after = view.contentView.bounds.origin.y
        let pass = !following && abs(after - held) < 1
        print("NEAR_BOTTOM_REVIEW passed=\(pass) original_bottom=\(bottom) manual_scroll_origin=\(held) following_after_manual_scroll=\(following) after_append_origin=\(after) window_created=false app_active=\(NSApp.isActive)")
        exit(pass ? 0 : 1)
    }
}
