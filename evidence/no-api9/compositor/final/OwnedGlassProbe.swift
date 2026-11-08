import AppKit
import SwiftUI
import ScreenCaptureKit
import CoreGraphics
import SaytileKit

private struct ProbeFailure: Error {
    let phase: String
    init(_ phase: String) { self.phase = phase }
}

@MainActor private final class PassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor private final class Backdrop: NSView {
    var warm = false { didSet { needsDisplay = true } }
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let raw = warm ? (0.77,0.22,0.16) : (0.12,0.68,0.34)
        NSColor(srgbRed: raw.0, green: raw.1, blue: raw.2, alpha: 1).setFill()
        bounds.fill()
        NSColor(srgbRed: raw.0+0.17, green: raw.1+0.17, blue: raw.2+0.17, alpha: 1).setFill()
        for x in stride(from: CGFloat(0), to: bounds.width, by: 12) {
            NSRect(x:x,y:0,width:6,height:bounds.height).fill()
        }
    }
}

@MainActor private final class Probe: NSObject, NSApplicationDelegate {
    var startingForeground: pid_t?
    var foregroundChanges = 0
    var token: NSObjectProtocol?
    var result: [String:Any] = [:]
    let out: URL
    init(out: URL) { self.out = out }

    func applicationDidFinishLaunching(_ note: Notification) {
        Task { @MainActor in
            do { try await run(); result["status"] = "MEASURED" }
            catch let err as ProbeFailure { result["status"] = "INCOMPLETE"; result["failure"] = err.phase }
            catch {
                let err=error as NSError
                result["status"]="INCOMPLETE";result["error_domain"]=err.domain;result["error_code"]=err.code
            }
            if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
            result["foreground_continuity"] = startingForeground == NSWorkspace.shared.frontmostApplication?.processIdentifier
            result["foreground_activation_notifications"] = foregroundChanges
            result["probe_became_active"] = NSApp.isActive
            let data=try! JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys])
            try! data.write(to:out,options:.atomic)
            // The owned windows have been removed and the receipt is durable.
            // No keyboard event is needed to wake NSApplication's event loop.
            exit(result["status"] as? String == "MEASURED" ? 0 : 2)
        }
    }

    func verifyFocus(_ windows: [PassivePanel]) throws {
        guard startingForeground == NSWorkspace.shared.frontmostApplication?.processIdentifier,
              !NSApp.isActive, windows.allSatisfy({ !$0.isKeyWindow && !$0.isMainWindow && !$0.canBecomeKey && !$0.canBecomeMain }) else {
            throw ProbeFailure("foreground_or_key_window_changed")
        }
    }
    func run() async throws {
        startingForeground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        result = ["mechanism":"SCShareableContent.currentProcess + display include-list of exactly two owned windows",
                  "microphone":false,"audio_capture":false,"cursor":false,"system_permissions_requested":false,
                  "whole_display_capture":false,"wallpaper_modified":false,"window_pixel_files_written":false,
                  "reduce_transparency":NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency]
        let permitted = CGPreflightScreenCaptureAccess()
        result["screen_capture_preflight"]=permitted
        guard permitted else {throw ProbeFailure("preflight_denied_no_request")}
        guard startingForeground != ProcessInfo.processInfo.processIdentifier else {throw ProbeFailure("probe_already_foreground")}
        token=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didActivateApplicationNotification,object:nil,queue:.main) { [weak self] _ in
            MainActor.assumeIsolated { self?.foregroundChanges += 1 }
        }
        let displayID=CGMainDisplayID()
        guard let screen=NSScreen.screens.first(where:{($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value==displayID}) else {throw ProbeFailure("main_display_unavailable")}
        let area=screen.visibleFrame
        // Only the enclosed inner region is ever sampled. Opaque padding surrounds every edge of the glass and shadows.
        let window=NSRect(x:area.midX-204,y:area.midY-149,width:408,height:298)
        let backing=window.insetBy(dx:-144,dy:-120)
        guard area.contains(backing) else {throw ProbeFailure("controlled_region_does_not_fit")}
        let lower=CGWindowLevelForKey(.desktopIconWindow)-3
        func panel(_ rect:NSRect,_ level:Int32)->PassivePanel {
            let p=PassivePanel(contentRect:rect,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            p.level = NSWindow.Level(rawValue:Int(level));p.ignoresMouseEvents=true;p.hasShadow=false
            p.hidesOnDeactivate=false;p.isReleasedWhenClosed=false
            p.collectionBehavior=[.stationary,.ignoresCycle,.fullScreenNone];p.setFrame(rect,display:false)
            return p
        }
        let background=panel(backing,lower), overlay=panel(window,lower+1)
        let windows=[background,overlay]
        defer {overlay.orderOut(nil);background.orderOut(nil);overlay.close();background.close()}
        let back=Backdrop(frame:NSRect(origin:.zero,size:backing.size))
        background.isOpaque=true;background.backgroundColor = .white;background.contentView=back
        overlay.isOpaque=false;overlay.backgroundColor = .clear
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("saytile-compositor-store-"+UUID().uuidString)
        let suite="saytile.test.compositor."+UUID().uuidString
        guard let prefs=UserDefaults(suiteName:suite) else {throw ProbeFailure("isolated_preferences_unavailable")}
        defer {prefs.removePersistentDomain(forName:suite);try? FileManager.default.removeItem(at:directory)}
        var cfg=RecognitionConfiguration();cfg.automaticRecovery=false;cfg.cloudEnabled=false;try cfg.save(to:prefs)
        let prohibited=AppConnectionDependencies(presence:{_ in .missing},save:{_,_ in throw ProbeFailure("unexpected_credential_save")},
            delete:{_ in throw ProbeFailure("unexpected_credential_delete")},verify:{_,_ in throw ProbeFailure("unexpected_cloud_verify")},
            applyConfiguration:{_,_ in},revokeCloud:{_ in})
        let capture=AppCaptureDependencies(state:{_ in .paused},start:{_ in},pause:{_ in},level:{_ in 0})
        let model=try AppModel(directory:directory,preferences:prefs,connectionDependencies:prohibited,captureDependencies:capture)
        await model.initialLoad()
        let row=try await model.store.createRecording()
        _=try await model.store.saveEdit(recordingID:row.id,text:"Saytile 合成文字")
        try await model.store.finishRecording(id:row.id);await model.refresh()
        let host=NSHostingView(rootView:InputPanelWindowView(model:model))
        host.frame=NSRect(origin:.zero,size:window.size);overlay.contentView=host
        background.orderBack(nil);overlay.order(.above,relativeTo:background.windowNumber)
        background.display();overlay.display();host.layoutSubtreeIfNeeded()
        try await Task.sleep(for:.milliseconds(550));try verifyFocus(windows)
        func transcript(in view:NSView)->NSTextView? {
            if let text=view as? NSTextView {return text}
            for child in view.subviews {if let text=transcript(in:child) {return text}}
            return nil
        }
        guard let textView=transcript(in:host),textView.string=="Saytile 合成文字",textView.isSelectable,!textView.isEditable else {throw ProbeFailure("production_text_fixture")}
        result["production_text"]=["synthetic_string_intact":true,"selectable":textView.isSelectable,
            "editable":textView.isEditable,"font_size_points":(textView.textStorage?.attribute(.font,at:0,effectiveRange:nil) as? NSFont)?.pointSize ?? -1]

        // Use the redacted, current-process API, not a system-window inventory.
        let owned=try await SCShareableContent.currentProcess
        guard let display=owned.displays.first(where:{$0.displayID==displayID}) else {throw ProbeFailure("owned_content_has_no_display")}
        let ids=Set([CGWindowID(background.windowNumber),CGWindowID(overlay.windowNumber)])
        let selected=owned.windows.filter{ids.contains($0.windowID) && $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier}
        guard selected.count==2, let front=selected.first(where:{$0.windowID==CGWindowID(overlay.windowNumber)}) else {throw ProbeFailure("two_owned_windows_not_resolved")}
        let filter=SCContentFilter(display:display,including:selected)
        filter.includeMenuBar=false
        guard Set(filter.includedWindows.map(\.windowID))==ids && filter.includedWindows.allSatisfy({$0.owningApplication?.processID==ProcessInfo.processInfo.processIdentifier}) else {throw ProbeFailure("filter_owner_mismatch")}
        let config=SCStreamConfiguration()
        let crop=front.frame.insetBy(dx:-16,dy:-16)
        guard let opaqueWindow=selected.first(where:{$0.windowID==CGWindowID(background.windowNumber)}),opaqueWindow.frame.insetBy(dx:100,dy:80).contains(crop) else {throw ProbeFailure("crop_not_inside_padded_opaque_owner")}
        config.sourceRect=crop.offsetBy(dx:-display.frame.minX,dy:-display.frame.minY)
        config.width=Int(crop.width);config.height=Int(crop.height)
        config.showsCursor=false;config.showMouseClicks=false;config.capturesAudio=false;config.captureMicrophone=false;config.includeChildWindows=false
        result["window_count"]=selected.count;result["capture_width"]=config.width;result["capture_height"]=config.height
        result["all_windows_confirmed_owned"]=true;result["only_aggregate_synthetic_roi"]=true
        func stats(_ im:CGImage) throws -> [String:Any] {
            let w=im.width,h=im.height;guard w==440 && h==330 else {throw ProbeFailure("unexpected_crop_geometry")}
            var raw=[UInt8](repeating:0,count:w*h*4)
            try raw.withUnsafeMutableBytes { data in
                guard let cs=CGColorSpace(name:CGColorSpace.sRGB),let context=CGContext(data:data.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:cs,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue) else {throw ProbeFailure("srgb_conversion")}
                context.draw(im,in:CGRect(x:0,y:0,width:w,height:h))
            }
            func sample(_ top:Int,_ bot:Int)->[String:Any] {
                var sums=[Double](repeating:0,count:3), edge=0.0,n=0
                for y in top..<bot {
                    for x in 120..<264 {
                        let i=(y*w+x)*4
                        for c in 0..<3 {sums[c]+=Double(raw[i+c])}
                        edge+=(0..<3).reduce(0.0){$0 + abs(Double(raw[i+$1])-Double(raw[i+6*4+$1]))}/3
                        n+=1
                    }
                }
                return ["mean_srgb8":sums.map{$0/Double(n)},"stripe_contrast":edge/Double(n)]
            }
            let glass=sample(162,170)
            func luma(_ rgb:[Double])->Double {
                let linear=rgb.map { code -> Double in let v=code/255;return v<=0.04045 ? v/12.92 : pow((v+0.055)/1.055,2.4) }
                return linear[0]*0.2126+linear[1]*0.7152+linear[2]*0.0722
            }
            var dark=[Double]()
            // This region contains the one synthetic text row and no exposed backing.
            // Restrict to dark neutral pixels to omit violet glyphs and gray control marks.
            for y in 52..<277 {
                for x in 68..<258 {
                    let offset=(y*w+x)*4
                    let rgb=(0..<3).map { Double(raw[offset+$0]) }
                    if rgb.max()!<72 && rgb.max()!-rgb.min()!<16 && raw[offset+3]==255 { dark.append(luma(rgb)) }
                }
            }
            dark.sort()
            var metrics:[String:Any]=["exposed_backdrop":sample(5,9),"glass_interior":glass,"dark_neutral_ink_pixels":dark.count]
            if !dark.isEmpty,let surface=glass["mean_srgb8"] as? [Double] {
                let median=dark[dark.count/2];metrics["median_dark_ink_luminance"]=median
                metrics["sampled_surface_to_ink_contrast"]=(luma(surface)+0.05)/(median+0.05)
            }
            return metrics
        }
        result["filter"]=["include_window_count":filter.includedWindows.count,"every_included_window_owner_matches_process":true,
                          "include_menu_bar":filter.includeMenuBar,"cursor":config.showsCursor,"audio":config.capturesAudio,
                          "microphone":config.captureMicrophone,"child_windows":config.includeChildWindows,"opaque_padding_points":[144,120],
                          "crop_within_opaque_backdrop":true] as [String:Any]
        var measurements:[[String:Any]]=[]
        for mode in ["production","clear","white_alpha_0.45","bare_popover_behind_window"] {
            switch mode {
            case "clear","white_alpha_0.45":
                let control=NSView(frame:NSRect(origin:.zero,size:window.size))
                control.wantsLayer=true
                control.layer?.backgroundColor=NSColor(srgbRed:1,green:1,blue:1,alpha:mode=="clear" ? 0:0.45).cgColor
                overlay.contentView=control
            case "bare_popover_behind_window":
                let effect=NSVisualEffectView(frame:NSRect(origin:.zero,size:window.size))
                effect.material = .popover;effect.state = .active;effect.blendingMode = .behindWindow
                effect.appearance=NSAppearance(named:.aqua)
                overlay.contentView=effect
            default:break
            }
            overlay.display()
            for warm in [false,true,false] {
                back.warm=warm;back.displayIfNeeded();background.display()
                try await Task.sleep(for:.milliseconds(400));try verifyFocus(windows)
                let img=try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
                try verifyFocus(windows)
                var sample=try stats(img);sample["mode"]=mode;sample["synthetic_backdrop"]=warm ? "warm":"cool";measurements.append(sample)
            }
        }
        result["measurements"]=measurements
        result["capture_state_stayed_paused"]=model.audio.state == .paused
        result["actual_foreground_surface"]="InputPanelWindowView > InputPanelView > ReferencePanelSurface"
        await model.prepareForExit()
    }
}

@main enum Entry {
    @MainActor static func main() {
        guard CommandLine.arguments.count==2 else {exit(64)}
        let app=NSApplication.shared
        let delegate=Probe(out:URL(fileURLWithPath:CommandLine.arguments[1]))
        app.setActivationPolicy(.accessory);app.delegate=delegate
        withExtendedLifetime(delegate){app.run()}
    }
}
