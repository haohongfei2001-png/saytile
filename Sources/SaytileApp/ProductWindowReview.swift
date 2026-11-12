import AppKit
import SwiftUI
import AVFAudio
import SaytileKit
import SaytileVoiceUI

/// Available only through the existing explicit empty --ui-review data directory.
/// A separate read-only helper captures only these two windows from WindowServer.
extension AppDelegate {
    @MainActor func addSilentReviewAudio(model: AppModel, recordingID: UUID, frames: AVAudioFrameCount) async throws {
        let path = recordingID.uuidString + "/sample.wav"
        let url = model.store.audioDirectory.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.int16ChannelData else { throw CocoaError(.fileWriteUnknown) }
        buffer.frameLength = frames
        samples[0].initialize(repeating: 0, count: Int(frames))
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatInt16, interleaved: true)
            try file.write(from: buffer)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
        try await model.store.registerAudioChunk(recordingID: recordingID, relativePath: path, frames: Int64(frames))
    }

    @MainActor func reviewProductWindows(model: AppModel, output: URL) async throws {
        struct Stop: LocalizedError { let message: String; var errorDescription: String? { message } }
        guard try await model.store.listRecordings(limit: 1).isEmpty, let screen = NSScreen.screens.first,
              let environment = NSImage(contentsOf: output.appendingPathComponent("environment.png")) else {
            throw Stop(message: "Expected an empty archive and the controlled reference backdrop")
        }
        let request = output.appendingPathComponent("request.json")
        let sharedComparison = ProcessInfo.processInfo.environment["SAYTILE_SHARED_VOICE_COMPARISON"] == "1"
        let docked = WindowPlacement.initialPanel(visibleFrame: screen.visibleFrame)
        func frame<V: View>(_ view: V, _ name: String, _ size: CGSize, panel: Bool = false, dark: Bool = false, bottom: Bool = false) async throws {
            if let subset = ProcessInfo.processInfo.environment["SAYTILE_PRODUCT_WINDOW_SUBSET"],
               !subset.split(separator:",").contains(Substring(name)) { return }
            print("PRODUCT_SCENE_BEGIN "+name); fflush(nil)
            guard size.width < screen.visibleFrame.width, size.height < screen.visibleFrame.height else { throw Stop(message: "Scene exceeds the physical display") }
            let rect = NSRect(origin: .zero, size: size)
            let mask: NSWindow.StyleMask = panel ? [.borderless,.nonactivatingPanel] : [.titled,.closable,.miniaturizable,.resizable,.nonactivatingPanel]
            let window = ReviewScenePanel(contentRect: rect, styleMask: mask, backing: .buffered, defer: false)
            let backdrop = ReviewScenePanel(contentRect: rect, styleMask: [.borderless,.nonactivatingPanel], backing: .buffered, defer: false)
            defer { window.orderOut(nil); backdrop.orderOut(nil); window.close(); backdrop.close() }
            for item in [window,backdrop] {
                item.level = .floating; item.isReleasedWhenClosed = false; item.hidesOnDeactivate = false
                item.ignoresMouseEvents = true; item.hasShadow = false
            }
            window.title = panel ? "Saytile · 此刻" : name.hasPrefix("archive") ? "Saytile · 语音档案" : "Saytile · 设置"
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            if panel { window.isOpaque = false; window.backgroundColor = .clear }
            let host = NSHostingView(rootView: view.environment(\.colorScheme, dark ? .dark : .light))
            host.sizingOptions = []; window.contentView = host; window.setContentSize(size)
            let area = screen.visibleFrame
            if sharedComparison && panel { window.setFrame(docked, display: false) }
            else { window.setFrameOrigin(CGPoint(x: floor(area.midX-window.frame.width/2), y: floor(area.midY-window.frame.height/2))) }
            backdrop.setFrame(window.frame, display: false); backdrop.title = "Saytile controlled visual environment"
            let background = NSImageView(); background.image = environment; background.imageScaling = .scaleAxesIndependently
            backdrop.contentView = background; backdrop.isOpaque = true; backdrop.backgroundColor = .white
            backdrop.orderFrontRegardless(); window.order(.above, relativeTo: backdrop.windowNumber)
            try await Task.sleep(for: .milliseconds(480)); host.layoutSubtreeIfNeeded()
            if bottom {
                print("PRODUCT_INSPECT_FORM "+name); fflush(nil)
                func scrollIn(_ v: NSView) -> NSScrollView? {
                    if let s = v as? NSScrollView, let doc = s.documentView, doc.frame.height > s.contentSize.height+10 { return s }
                    return v.subviews.lazy.compactMap(scrollIn).first
                }
                if let sc = scrollIn(host), let doc = sc.documentView {
                sc.contentView.scroll(to: NSPoint(x: 0, y: doc.isFlipped ? doc.frame.height-sc.contentSize.height : 0))
                sc.reflectScrolledClipView(sc.contentView); try await Task.sleep(for: .milliseconds(200))
                print("PRODUCT_NATIVE_SCROLL "+name+" offset="+String(describing: sc.contentView.bounds.origin))
                } else {
                    // SwiftUI may render the system Form through a non-NSScrollView host.
                    // Deliver a scroll to the owned content responder only; never post global wheel events.
                    let target = host.hitTest(NSPoint(x: host.bounds.maxX*0.75, y: host.bounds.midY)) ?? host
                    guard let wheel = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:-420,wheel2:0,wheel3:0),
                          let event = NSEvent(cgEvent:wheel) else { throw Stop(message:"Cannot create local wheel event") }
                    target.scrollWheel(with:event); try await Task.sleep(for:.milliseconds(250))
                    print("PRODUCT_LOCAL_WHEEL_DELIVERED "+name+"; offset not observable")
                }
            }
            guard !window.isKeyWindow, !window.isMainWindow, NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() else {
                throw Stop(message: "Fixture took foreground or keyboard focus")
            }
            print("PRODUCT_SCENE_LAID_OUT "+name); fflush(nil)
            var info: [String:Any] = ["scene":name,"pid":getpid(),"window":window.windowNumber,"backdrop":backdrop.windowNumber,
                "points":[window.frame.width,window.frame.height],"scale":screen.backingScaleFactor]
            if sharedComparison && panel {
                let glass = VoiceRailMetrics(width: window.frame.width).cardFrame(in: window.frame)
                info["glass"] = [glass.minX, glass.minY, glass.width, glass.height]
                info["visible"] = [area.minX, area.minY, area.width, area.height]
            }
            try JSONSerialization.data(withJSONObject: info,options:.sortedKeys).write(to: request,options:.atomic)
            let ack = output.appendingPathComponent(name+".done")
            for _ in 0..<180 {
                if FileManager.default.fileExists(atPath: ack.path) {
                    guard (try String(contentsOf: ack,encoding:.utf8)) == "captured" else { throw Stop(message: "WindowServer capture denied for "+name) }
                    print("PRODUCT_WINDOWSERVER "+name); fflush(nil); return
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw Stop(message: "No compositor acknowledgement for "+name)
        }
        model.selectSource("local") // explicit diagnostics carry an inert legacy configuration; use the actual fresh-install source.
        let sz = NSSize(width:780,height:610), panelSize = sharedComparison ? docked.size : WindowPlacement.panelDefaultSize
        try await frame(InputPanelWindowView(model:model),"first-use",panelSize,panel:true)
        let text = sharedComparison ? "把设计系统的更新内容整理成一份简要的汇报，重点包括组件优化和交互调整。" : "我想让 Saytile 成为一个始终待命\n的语音输入工作台，它应该让文字\n自然出现，而不是让按钮打断表达。\n说完这一句，它会安静地等我\n继续开口。"
        let capture = UIPanelCaptureFixture()
        // Same AppModel and native panel as normal; only microphone/permission states are injected.
        let suite = "app.saytile.test.design."+UUID().uuidString
        let prefs = UserDefaults(suiteName:suite)!
        defer { prefs.removePersistentDomain(forName:suite) }
        let root = output.appendingPathComponent("capture-fixture-"+UUID().uuidString)
        let reviewBoard = sharedComparison ? NSPasteboard(name: .init("app.saytile.voice-comparison." + String(getpid()))) : nil
        defer { reviewBoard?.releaseGlobally() }
        let meter = try AppModel(directory:root,preferences:prefs,captureDependencies:capture.dependencies, copyPasteboard:reviewBoard)
        do {
            await meter.initialLoad(); capture.state = .interrupted("麦克风未获授权"); capture.authorization = .denied
            meter.objectWillChange.send()
            try await frame(InputPanelWindowView(model:meter),"first-denied",panelSize,panel:true)
            capture.state = .listening; capture.authorization = .authorized; meter.objectWillChange.send()
            try await frame(InputPanelWindowView(model:meter),"first-authorized",panelSize,panel:true)
            let speech = try await meter.store.createRecording()
            let ticket = try await meter.store.beginRecognition(recordingID:speech.id)
            _ = try await meter.store.applyRecognition(ticket:ticket,text:text,isFinal:false); await meter.refresh()
            guard meter.completedFirstTranscript else { throw Stop(message:"First stored partial was not recognized") }
            for (name,state,value) in [("paused",CaptureState.paused,Float(0)),("standby",.listening,0),("speaking",.speaking,1)] {
                capture.state = state; capture.level = value; meter.objectWillChange.send()
                try await frame(InputPanelWindowView(model:meter),"panel-"+name,panelSize,panel:true)
            }
            await meter.prepareForExit()
            if sharedComparison { return }
        } catch { await meter.prepareForExit(); throw error }
        try await frame(SettingsView(model:model),"settings",sz)
        try await frame(SettingsView(model:model,initialPage:.models),"models",sz)
        model.selectLocal(.apple)
        try await frame(SettingsView(model:model,initialPage:.models),"models-manual",sz)
        let manifest = try LocalModelManifest.load(.sherpa)
        let baseURL = model.store.directory.appendingPathComponent("LocalModels").appendingPathComponent(manifest.id.rawValue)
        let damaged = baseURL.appendingPathComponent(manifest.revision)
        let partial = damaged.appendingPathExtension("partial")
        guard let firstFile = manifest.files.first else { throw Stop(message:"Empty pinned manifest") }
        for folder in [damaged,partial] {
            let file = folder.appendingPathComponent(firstFile.path)
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data(repeating:0,count:4096).write(to:file)
        }
        let invalid = await model.localModels.library.status(.sherpa)
        guard !invalid.installed, invalid.error != nil, invalid.bytes == 4096 else { throw Stop(message:"Corrupt fixture unexpectedly became usable") }
        try await frame(SettingsView(model:model,initialPage:.models),"models-recovery",sz)
        try await model.localModels.delete(.sherpa)
        let clean = await model.localModels.library.status(.sherpa)
        guard clean.diskBytes == 0, !clean.installed else { throw Stop(message:"Temporary model deletion failed") }
        model.selectLocal(nil)
        try await frame(SettingsView(model:model,initialPage:.input),"input-compact-dark",.init(width:540,height:500),dark:true)
        try await frame(SettingsView(model:model,initialPage:.storage),"storage",sz)
        try await frame(SettingsView(model:model,initialPage:.about),"about",sz)
        print("PRODUCT_SELECT_HOSTED"); fflush(nil)
        model.selectSource("hosted"); print("PRODUCT_HOSTED_SELECTED"); fflush(nil)
        try await frame(SettingsView(model:model),"cloud",sz,bottom:true)
        model.selectSource("byok")
        try await frame(SettingsView(model:model),"byok",sz,bottom:true)
        model.selectSource("local")
        try await frame(ArchiveView(model:model),"archive-empty",.init(width:840,height:560))
        let base = Date()
        for (i,words) in ["周五的讨论，先把决定留下来。","合同金额是不超过三千元，不是三万元。","上午十点复核版本，然后继续。","今天的想法分成两件事。\n先把讨论中确定的时间记下来。\n还要核对上一版里的两处数字。\n把这几行留在一起，下午可以直接接着看。"].enumerated() {
            let row = try await model.store.createRecording(createdAt:base.addingTimeInterval(Double(i-3)*36_000))
            let t = try await model.store.beginRecognition(recordingID:row.id)
            _ = try await model.store.applyRecognition(ticket:t,text:words,isFinal:true)
            try await model.store.finishRecognition(ticket:t)
            // Silent synthetic PCM in the disposable archive only, never an external recording.
            if i == 3 {
                try await addSilentReviewAudio(model: model, recordingID: row.id, frames: 16_000)
            }
            try await model.store.finishRecording(id:row.id)
            if i == 3 { _ = try await model.store.saveEdit(recordingID:row.id,text:words+"\n记得带笔。") }
        }
        await model.refresh()
        try await frame(ArchiveView(model:model),"archive",.init(width:980,height:620))
        guard let row = model.records.first else { throw Stop(message:"No synthetic archive row") }
        await model.selectForEditing(row)
        try await frame(ArchiveView(model:model),"archive-detail",.init(width:1050,height:640))
        try await frame(ArchiveView(model:model),"archive-detail-compact-dark",.init(width:570,height:510),dark:true)
        print("PRODUCT_WINDOW_REVIEW_PASS single display, isolated source selected; no system authorization changes")
    }
}
@MainActor private final class ReviewScenePanel: NSPanel {
    override var canBecomeMain: Bool { false }
    override var canBecomeKey: Bool { false }
}
