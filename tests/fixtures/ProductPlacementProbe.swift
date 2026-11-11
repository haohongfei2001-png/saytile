import AppKit
import ApplicationServices

// Exercises a native mouse drag on the explicitly installed, distinct, paused design candidate only.
// It cannot inspect text or click another process, and never grants permissions.
@main struct ProductPlacementProbe {
    struct Problem: Error, CustomStringConvertible { let description: String; init(_ s:String){description=s} }
    @MainActor static func main() async {
        do { try await run(); exit(0) } catch { print("PLACEMENT_BLOCKED_OR_FAILED \(error)"); exit(1) }
    }
    @MainActor static func run() async throws {
        guard (2...3).contains(CommandLine.arguments.count), AXIsProcessTrusted(), CGPreflightPostEventAccess() else { throw Problem("AX or posting permission unavailable") }
        let url = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true).standardizedFileURL
        let id = "app.saytile.mac.design-experience"
        let expected = CommandLine.arguments.count == 3 ? Int32(CommandLine.arguments[2]) : nil
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier:id)
        guard Bundle(url:url)?.bundleIdentifier == id, url.lastPathComponent == "Saytile 设计体验.app",
              expected == nil ? existing.isEmpty : (existing.count==1 && existing[0].processIdentifier==expected && existing[0].bundleURL?.resolvingSymlinksInPath()==url.resolvingSymlinksInPath()) else { throw Problem("Expected only the specified design candidate") }
        NSApplication.shared.setActivationPolicy(.prohibited)
        let originalPointer=CGEvent(source:nil)?.location
        defer { if let originalPointer { CGWarpMouseCursorPosition(originalPointer) } }
        func launch() async throws -> NSRunningApplication {
            let c=NSWorkspace.OpenConfiguration(); c.activates=false; c.addsToRecentItems=false
            let app=try await NSWorkspace.shared.openApplication(at:url,configuration:c)
            guard app.bundleURL?.resolvingSymlinksInPath()==url.resolvingSymlinksInPath(),app.bundleIdentifier==id else { throw Problem("Unexpected instance") }
            return app
        }
        func value(_ node:AXUIElement,_ key:String)->CFTypeRef? {
            var result:CFTypeRef?; guard AXUIElementCopyAttributeValue(node,key as CFString,&result) == .success else { return nil }; return result
        }
        func window(_ app:NSRunningApplication)->(Int,CGRect)? {
            // Inspect names/geometry only after filtering by our verified PID.
            let rows=CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
            for r in rows where (r[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier {
                if r[kCGWindowName as String] as? String == "Saytile · 此刻",let n=r[kCGWindowNumber as String] as? Int,
                   let b=r[kCGWindowBounds as String] as? NSDictionary, let rect=CGRect(dictionaryRepresentation:b) { return (n,rect) }
            }
            return nil
        }
        func visible(_ app:NSRunningApplication) async throws -> (Int,CGRect) {
            var previous:CGRect?
            for _ in 0..<50 {
                if let w=window(app), w.1.width>=384, w.1.height>=264 {
                    if previous==w.1 {return w}; previous=w.1
                } else {previous=nil}
                try await Task.sleep(for:.milliseconds(100))
            }
            throw Problem("No visible owned panel")
        }
        func same(_ a:CGRect,_ b:CGRect)->Bool { abs(a.minX-b.minX)<1 && abs(a.minY-b.minY)<1 && a.size==b.size }
        func desktopOwner(at pt:CGPoint)->pid_t? {
            var node:AXUIElement?, pid:pid_t=0
            guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(pt.x),Float(pt.y),&node) == .success,
                  let node, AXUIElementGetPid(node,&pid) == .success else { return nil }; return pid
        }
        func drag(_ app:NSRunningApplication,_ start:CGRect,_ dx:CGFloat,_ dy:CGFloat) async throws -> CGRect {
            let a=CGPoint(x:start.midX,y:start.minY+37), b=CGPoint(x:a.x+dx,y:a.y+dy)
            guard desktopOwner(at:a)==app.processIdentifier, window(app)?.1==start else { throw Problem("Refused pointer outside the verified design panel") }
            let source=CGEventSource(stateID:.hidSystemState)
            func event(_ type:CGEventType,_ pos:CGPoint) throws {
                guard let e=CGEvent(mouseEventSource:source,mouseType:type,mouseCursorPosition:pos,mouseButton:.left) else { throw Problem("Mouse event unavailable") }
                e.setIntegerValueField(.mouseEventClickState,value:1); e.post(tap:.cghidEventTap)
            }
            try event(.mouseMoved,a); try await Task.sleep(for:.milliseconds(90))
            guard desktopOwner(at:a)==app.processIdentifier else { throw Problem("Ownership changed before gesture") }
            try event(.leftMouseDown,a); var held=true; var last=a
            defer { if held { try? event(.leftMouseUp,last) } }
            let steps = max(12,Int(ceil(max(abs(dx),abs(dy))/6)))
            for i in 1...steps {
                let t=CGFloat(i)/CGFloat(steps); last=CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)
                guard window(app) != nil, !app.isTerminated else { throw Problem("Design panel disappeared during drag") }
                try event(.leftMouseDragged,last); try await Task.sleep(for:.milliseconds(22))
                if steps > 20 && (i%max(1,steps/4)==0 || i==steps) {
                    print("OWNED_DRAG_PROGRESS injected=\(last) pointer=\(String(describing:CGEvent(source:nil)?.location)) window=\(String(describing:window(app)?.1.origin))");fflush(nil)
                }
            }
            try event(.leftMouseUp,b); held=false; try await Task.sleep(for:.milliseconds(320))
            let final=try await visible(app)
            // AppKit consumes the first motion sample to cross its drag threshold.
            // Compare direction and useful travel; hide/show and restart below must restore the *exact measured* frame.
            let mx=final.1.minX-start.minX, my=final.1.minY-start.minY
            guard mx*dx>0, my*dy>0, abs(mx-dx)<=8, abs(my-dy)<=8, final.1.size==start.size else { throw Problem("Native drag did not follow its path: \(start) -> \(final.1)") };return final.1
        }
        func clickOwnStatus(_ app:NSRunningApplication) throws {
            let ax=AXUIElementCreateApplication(app.processIdentifier)
            guard let raw=value(ax,"AXExtrasMenuBar"), CFGetTypeID(raw)==AXUIElementGetTypeID() else {throw Problem("Owned menu bar unavailable")}
            let bar=unsafeDowncast(raw,to:AXUIElement.self)
            let items=value(bar,kAXChildrenAttribute) as? [AXUIElement] ?? []
            let own=items.filter { node in
                var owner:pid_t=0; guard AXUIElementGetPid(node,&owner) == .success,owner==app.processIdentifier else{return false}
                return [kAXDescriptionAttribute,kAXTitleAttribute].contains { (value(node,$0) as? String)?.hasPrefix("Saytile") == true }
            }
            guard own.count==1,AXUIElementPerformAction(own[0],kAXPressAction as CFString) == .success else {throw Problem("No unique status button")}
        }
        func stop(_ app:NSRunningApplication) async throws {
            guard app.bundleIdentifier==id,app.bundleURL?.resolvingSymlinksInPath()==url.resolvingSymlinksInPath(),app.terminate() else {throw Problem("Could not quit the isolated candidate gracefully")}
            for _ in 0..<60 { if app.isTerminated {return}; try await Task.sleep(for:.milliseconds(100)) }
            throw Problem("Timed out waiting for clean quit")
        }
        let foreground=NSWorkspace.shared.frontmostApplication?.processIdentifier
        let first:NSRunningApplication
        if let current=existing.first {first=current} else {first=try await launch()}
        let initial=try await visible(first)
        print("INITIAL_FRAME \(initial.1) foreground_own=\(foreground==first.processIdentifier)"); fflush(nil)
        guard initial.1.size==CGSize(width:408,height:298), foreground != first.processIdentifier else {throw Problem("Invalid default or foreground")}
        let dx:CGFloat = initial.1.midX > CGDisplayBounds(CGMainDisplayID()).midX ? -72 : 72
        let dy:CGFloat = initial.1.midY > CGDisplayBounds(CGMainDisplayID()).midY ? -48 : 48
        let chosen=try await drag(first,initial.1,dx,dy)
        print("NATIVE_DRAG default=\(initial.1) chosen=\(chosen)"); fflush(nil)
        try clickOwnStatus(first); try await Task.sleep(for:.milliseconds(220)); guard window(first)==nil else {throw Problem("Menu failed to hide")}
        try clickOwnStatus(first); let shown=try await visible(first); guard same(shown.1,chosen) else {throw Problem("Hide/show moved panel")}
        print("HIDE_SHOW_RESTORED \(shown.1)"); fflush(nil)
        try await stop(first); let middle=try await launch(), during=try await visible(middle)
        guard first.processIdentifier != middle.processIdentifier, same(chosen,during.1) else {throw Problem("Primary-display relaunch did not restore exact frame")}
        print("FIRST_RELAUNCH_RESTORED \(during.1)"); fflush(nil)
        let primary = CGDisplayBounds(CGMainDisplayID())
        let options = NSScreen.screens.map { s in CGRect(x:s.visibleFrame.minX,y:primary.maxY-s.visibleFrame.maxY,width:s.visibleFrame.width,height:s.visibleFrame.height) }
        let other = options.first { !$0.contains(CGPoint(x:chosen.midX,y:chosen.midY)) && $0.width>chosen.width && $0.height>chosen.height }
        var beforeRestart=chosen
        var moveAcross = CGPoint.zero
        if let other {
            moveAcross=CGPoint(x:round(other.midX-chosen.midX),y:round(other.midY-chosen.midY))
            beforeRestart=try await drag(middle,chosen,moveAcross.x,moveAcross.y)
            guard other.contains(beforeRestart) else {throw Problem("Native gesture did not reach second display")}
            print("SECOND_DISPLAY_CHOSEN \(beforeRestart)"); fflush(nil)
        }
        try await stop(middle); let second=try await launch(), restarted=try await visible(second)
        guard first.processIdentifier != second.processIdentifier,same(beforeRestart,restarted.1) else {throw Problem("Relaunch lost chosen position")}
        var back=restarted.1
        if other != nil {
            back=try await drag(second,restarted.1,-moveAcross.x,-moveAcross.y)
            guard abs(back.minX-chosen.minX)<=2 && abs(back.minY-chosen.minY)<=2 else {throw Problem("Return from second display changed the initial location")}
        }
        let final=try await drag(second,back,-dx,-dy)
        guard same(initial.1,final), NSWorkspace.shared.frontmostApplication?.processIdentifier != second.processIdentifier else {throw Problem("Default not restored or focus stolen")}
        print("PLACEMENT_PASS relaunched=\(restarted.1) restored_for_user=\(final) screens=\(NSScreen.screens.count) foreground_preserved=\(foreground==NSWorkspace.shared.frontmostApplication?.processIdentifier)")
        if ProcessInfo.processInfo.environment["SAYTILE_CENTER_NEW_TEST_PROFILE"] == "1", let screen=options.first {
            let center=CGPoint(x:round(screen.midX-final.midX),y:round(screen.midY-final.midY))
            if abs(center.x)>8 && abs(center.y)>8 {
                let saved=try await drag(second,final,center.x,center.y)
                guard abs(saved.midX-screen.midX)<2 && abs(saved.midY-screen.midY)<2 else {throw Problem("Could not return this new QA-only profile to its natural first position")}
                print("NEW_PROFILE_HANDOFF centered_by_mouse=\(saved) existing_personal_preferences_accessed=false")
            }
        }
    }
}
