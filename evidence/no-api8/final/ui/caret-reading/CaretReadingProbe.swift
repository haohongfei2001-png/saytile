import AppKit
import SwiftUI
import SaytileKit

private struct ProbeError: Error, CustomStringConvertible { let description: String }
@main struct CaretReadingProbe {
    @MainActor static func main() async {
        do { try await run() }
        catch { print("OFFSCREEN_REVIEW_INCOMPLETE \(error)"); exit(1) }
    }
    @MainActor static func run() async throws {
        _ = NSApplication.shared.setActivationPolicy(.prohibited)
        guard NSApp.windows.isEmpty else { throw ProbeError(description:"fixture already has a window") }
        let suite = "app.saytile.test.caret-reading." + UUID().uuidString
        let prefs = UserDefaults(suiteName:suite)!
        let data = URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("saytile-caret-reading-" + UUID().uuidString)
        defer { prefs.removePersistentDomain(forName:suite); try? FileManager.default.removeItem(at:data) }
        var cfg = RecognitionConfiguration(); cfg.automaticRecovery = false; try cfg.save(to:prefs)
        let cloud = AppConnectionDependencies(presence:{_ in .missing}, save:{_,_ in throw CancellationError()},
            delete:{_ in throw CancellationError()}, verify:{_,_ in throw CancellationError()}, applyConfiguration:{_,_ in}, revokeCloud:{_ in})
        let capture = AppCaptureDependencies(state:{_ in .speaking}, start:{_ in}, pause:{_ in}, level:{_ in 0.5})
        let model = try AppModel(directory:data,preferences:prefs,connectionDependencies:cloud,captureDependencies:capture)
        await model.initialLoad()
        let rec = try await model.store.createRecording()
        let text = (0..<25).map { "第\($0)行 测试用合成文字。末尾保留原音。" }.joined(separator:"\n")
        _ = try await model.store.saveEdit(recordingID:rec.id,text:text)
        try await model.store.finishRecording(id:rec.id)
        await model.refresh()
        let host = NSHostingView(rootView:InputPanelWindowView(model:model))
        host.frame = CGRect(x:0,y:0,width:408,height:298)
        func settle() async {
            for _ in 0..<8 {
                host.layoutSubtreeIfNeeded()
                try? await Task.sleep(for:.milliseconds(15))
            }
        }
        await settle()
        var todo: [NSView] = [host]; var found: [CompactTranscriptScrollView] = []
        while let item = todo.popLast() {
            if let scroll = item as? CompactTranscriptScrollView { found.append(scroll) }
            todo.append(contentsOf:item.subviews)
        }
        guard found.count==1 else { throw ProbeError(description:"detached serving host had \(found.count) transcript views") }
        let scroll=found[0],view=scroll.transcriptView
        func check(_ expected:Bool, _ note:String) throws {
            guard expected else { throw ProbeError(description:note) }
            print("PASS " + note)
        }
        try check(host.window==nil && NSApp.windows.isEmpty && !NSApp.isActive,"no_window_or_activation")
        try check(model.panelCapturePresentation.state == .recognizing && view.showsLiveCaret && scroll.isFollowingLatest && view.string==text,"speaking_follows_and_marker_enabled")
        let ymax = max(0, view.bounds.height - scroll.contentSize.height)
        try check(ymax>10,"document_scrolls")
        scroll.contentView.scroll(to:CGPoint(x:0,y:ymax-2));scroll.reflectScrolledClipView(scroll.contentView)
        await settle()
        try check(!scroll.isFollowingLatest && !view.showsLiveCaret && abs(scroll.contentView.bounds.origin.y-(ymax-2))<0.01,"two_point_reading_hides_marker")
        let range=(text as NSString).range(of:"测试用合成文字")
        view.setSelectedRange(range)
        let next=text + "\n新的合成文字。"
        _=try await model.store.saveEdit(recordingID:rec.id,text:next)
        await model.refresh();await settle()
        try check(view.string == text && view.selectedRange()==range && scroll.hasDeferredUpdate && !view.showsLiveCaret,"selected_text_and_reading_marker_protected")
        scroll.jumpToLatest()
        await settle()
        try check(scroll.isFollowingLatest && view.showsLiveCaret && view.selectedRange().length==0 && view.string==next,"explicit_latest_restores_marker_and_pending_text")
        try check(model.audio.state == .paused && NSApp.windows.isEmpty,"microphone_controller_paused_no_window")
        await model.prepareForExit()
        print("OFFSCREEN_CARET_PASS source=69b90939 synthetic_text_only")
    }
}
