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
        let allowedBundles = ["Saytile 设计体验.app": "app.saytile.mac.design-experience",
                              "Saytile 语音板体验.app": "app.saytile.mac.shared-voice-preview"]
        guard let id = allowedBundles[url.lastPathComponent] else { throw Problem("Expected a named isolated candidate") }
        let expected = CommandLine.arguments.count == 3 ? Int32(CommandLine.arguments[2]) : nil
        if CommandLine.arguments.count == 3, expected == nil {throw Problem("Invalid expected PID")}
        let existing = NSRunningApplication.runningApplications(withBundleIdentifier:id)
        guard Bundle(url:url)?.bundleIdentifier == id,
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
                if let w=window(app), !w.1.isEmpty {
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
        func gesture(_ app:NSRunningApplication, frame:CGRect, from a:CGPoint, to b:CGPoint) async throws -> CGRect {
            let dx = b.x-a.x, dy = b.y-a.y
            guard desktopOwner(at:a)==app.processIdentifier, window(app)?.1==frame,
                  NSEvent.pressedMouseButtons == 0 else { throw Problem("Refused unowned or busy pointer") }
            let source=CGEventSource(stateID:.hidSystemState)
            func event(_ type:CGEventType,_ pos:CGPoint) throws {
                guard let e=CGEvent(mouseEventSource:source,mouseType:type,mouseCursorPosition:pos,mouseButton:.left) else { throw Problem("Mouse event unavailable") }
                e.setIntegerValueField(.mouseEventClickState,value:1); e.post(tap:.cghidEventTap)
            }
            try event(.mouseMoved,a); try await Task.sleep(for:.milliseconds(90))
            guard desktopOwner(at:a)==app.processIdentifier, window(app)?.1==frame else { throw Problem("Ownership changed before gesture") }
            try event(.leftMouseDown,a); var held=true; var last=a
            defer { if held { try? event(.leftMouseUp,last) } }
            let steps = max(12,Int(ceil(max(abs(dx),abs(dy))/8)))
            for i in 1...steps {
                let t=CGFloat(i)/CGFloat(steps); last=CGPoint(x:a.x+dx*t,y:a.y+dy*t)
                guard window(app) != nil, !app.isTerminated else { throw Problem("Design panel disappeared during gesture") }
                try event(.leftMouseDragged,last); try await Task.sleep(for:.milliseconds(20))
            }
            try event(.leftMouseUp,b); held=false; try await Task.sleep(for:.milliseconds(240))
            return try await visible(app).1
        }
        enum Handle { case footer, top, left, bottom, bottomRight }
        func manipulate(_ app:NSRunningApplication, _ frame:CGRect, _ handle:Handle,
                        dx:CGFloat, dy:CGFloat) async throws -> CGRect {
            _ = try pausedStatus(app)
            let from:CGPoint, expected:CGRect
            switch handle {
            case .footer:
                // Blank space between the two existing controls.
                let railScale = min(1.5, frame.width/325)
                let side = 15 * railScale, bottom = min(8 * railScale, frame.height/8)
                let card = frame.width - 2 * side
                let scale = min(1, max(0.4, card/295))
                let expansion = min(1, max(0, (card-295)/49))
                let copyRight=frame.minX+side+(60+2.5*expansion)*scale
                let voiceLeft=frame.maxX-side-(100+6.5*expansion)*scale
                guard voiceLeft>copyRight else {throw Problem("No gap between footer controls")}
                from=CGPoint(x:(copyRight+voiceLeft)/2,y:frame.maxY-bottom-(26+9*expansion)*scale)
                expected=frame.offsetBy(dx:dx,dy:dy)
            case .top:
                from=CGPoint(x:frame.midX,y:frame.minY+9)
                expected=frame.offsetBy(dx:dx,dy:dy)
            case .left:
                from=CGPoint(x:frame.minX+2,y:frame.midY)
                expected=CGRect(x:frame.minX+dx,y:frame.minY,width:frame.width-dx,height:frame.height)
            case .bottomRight:
                from=CGPoint(x:frame.maxX-6,y:frame.maxY-6)
                expected=CGRect(origin:frame.origin,size:CGSize(width:frame.width+dx,height:frame.height+dy))
            case .bottom:
                from=CGPoint(x:frame.midX,y:frame.maxY-2)
                expected=CGRect(x:frame.minX,y:frame.minY,width:frame.width,height:frame.height+dy)
            }
            let actual=try await gesture(app,frame:frame,from:from,to:CGPoint(x:from.x+dx,y:from.y+dy))
            guard same(actual,expected) else {
                throw Problem("Gesture on \(handle) produced \(actual) from \(frame); expected \(expected)")
            }
            print("NATIVE_GESTURE handle=\(handle) before=\(frame) after=\(actual)"); fflush(nil)
            return actual
        }
        func pausedStatus(_ app:NSRunningApplication) throws -> AXUIElement {
            let ax=AXUIElementCreateApplication(app.processIdentifier)
            guard let raw=value(ax,"AXExtrasMenuBar"), CFGetTypeID(raw)==AXUIElementGetTypeID() else {throw Problem("Owned menu bar unavailable")}
            let bar=unsafeDowncast(raw,to:AXUIElement.self)
            let items=value(bar,kAXChildrenAttribute) as? [AXUIElement] ?? []
            let own=items.filter { node in
                var owner:pid_t=0; guard AXUIElementGetPid(node,&owner) == .success,owner==app.processIdentifier else{return false}
                return [kAXDescriptionAttribute,kAXTitleAttribute].contains { (value(node,$0) as? String)?.hasPrefix("Saytile · 暂停") == true }
            }
            guard own.count==1 else {throw Problem("Candidate is not paused or its status is ambiguous")}
            return own[0]
        }
        func clickOwnStatus(_ app:NSRunningApplication) throws {
            guard AXUIElementPerformAction(try pausedStatus(app),kAXPressAction as CFString) == .success else {throw Problem("Could not press paused menu item")}
        }
        func stop(_ app:NSRunningApplication) async throws {
            _ = try pausedStatus(app)
            guard app.bundleIdentifier==id,app.bundleURL?.resolvingSymlinksInPath()==url.resolvingSymlinksInPath(),app.terminate() else {throw Problem("Could not quit the isolated candidate gracefully")}
            for _ in 0..<60 { if app.isTerminated {return}; try await Task.sleep(for:.milliseconds(100)) }
            throw Problem("Timed out waiting for clean quit")
        }
        let foreground=NSWorkspace.shared.frontmostApplication?.processIdentifier
        let first:NSRunningApplication
        if let current=existing.first { first=current } else { first=try await launch() }
        let initial=try await visible(first)
        _ = try pausedStatus(first)
        guard foreground != first.processIdentifier else {throw Problem("Candidate is in use")}
        let primary = CGDisplayBounds(CGMainDisplayID())
        // WindowServer mouse and window geometry both use the top-left desktop origin.
        let displays = NSScreen.screens.map { screen in
            CGRect(x:screen.visibleFrame.minX, y:primary.maxY-screen.visibleFrame.maxY,
                   width:screen.visibleFrame.width, height:screen.visibleFrame.height)
        }
        guard let screen = displays.first else { throw Problem("No primary display") }
        let glass = initial.1
        let glassWidth = glass.width
        // The complete WindowServer rectangle includes the rail and its inset card.
        guard abs(glassWidth - screen.width * 0.125) <= 1,
              abs(glass.height - min(screen.height * 0.225, screen.width * 0.125 * 173 / 325)) <= 1,
              abs(glass.minY - screen.minY) <= 1, abs(screen.maxX - glass.maxX) <= 1 else {
            throw Problem("Initial glass does not match the primary voice region: frame=\(initial.1) visible=\(screen)")
        }
        print("DEFAULT_TOP_RIGHT visible=\(screen) frame=\(initial.1) glass_width=\(glassWidth)"); fflush(nil)
        let moved=try await manipulate(first,initial.1,.footer,dx:-72,dy:48)
        let wider=try await manipulate(first,moved,.left,dx:-54,dy:0)
        let heightAdjusted=try await manipulate(first,wider,.bottom,dx:0,dy:40)
        let taller=try await manipulate(first,heightAdjusted,.bottomRight,dx:24,dy:18)
        try clickOwnStatus(first); try await Task.sleep(for:.milliseconds(220))
        guard window(first)==nil else {throw Problem("Menu failed to hide")}
        try clickOwnStatus(first); let shown=try await visible(first)
        guard same(shown.1,taller) else {throw Problem("Hide/show changed chosen size or position")}
        print("HIDE_SHOW_RESTORED \(shown.1)"); fflush(nil)
        try await stop(first); let middle=try await launch(), during=try await visible(middle)
        _ = try pausedStatus(middle)
        guard first.processIdentifier != middle.processIdentifier, same(taller,during.1) else {throw Problem("Relaunch changed chosen size or position")}
        print("RELAUNCH_RESTORED \(during.1)"); fflush(nil)
        let other=displays.first { $0 != screen && $0.width>taller.width+32 && $0.height>taller.height+32 }
        var current=middle
        if let other {
            let dx=(other.midX-taller.midX).rounded(), dy=(other.midY-taller.midY).rounded()
            let across=try await manipulate(middle,taller,.top,dx:dx,dy:dy)
            guard other.contains(across) else {throw Problem("Cross-display gesture missed destination")}
            try await stop(middle); current=try await launch()
            let resumed=try await visible(current)
            _ = try pausedStatus(current)
            guard middle.processIdentifier != current.processIdentifier, same(across,resumed.1) else {throw Problem("Cross-display relaunch changed chosen size or position")}
            _ = try await manipulate(current,resumed.1,.top,dx:-dx,dy:-dy)
            print("SECOND_DISPLAY_RELAUNCH_RESTORED \(resumed.1)")
        }
        let cornerRestored=try await manipulate(current,taller,.bottomRight,dx:-24,dy:-18)
        let shorter=try await manipulate(current,cornerRestored,.bottom,dx:0,dy:-40)
        let narrower=try await manipulate(current,shorter,.left,dx:54,dy:0)
        let final=try await manipulate(current,narrower,.footer,dx:72,dy:-48)
        guard same(initial.1,final), foreground==NSWorkspace.shared.frontmostApplication?.processIdentifier else {throw Problem("Default was not restored or foreground changed")}
        _ = try pausedStatus(current)
        print("PLACEMENT_PASS restored_top_right=\(final) screens=\(NSScreen.screens.count) foreground_preserved=true paused=true")
    }
}
