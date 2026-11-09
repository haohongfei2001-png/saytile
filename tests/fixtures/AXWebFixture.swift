import AppKit
import WebKit

#if SAYTILE_FOREGROUND_FIXTURE
typealias FixtureWindowBase = NSWindow
#else
typealias FixtureWindowBase = NSPanel
#endif

@MainActor
final class WebFixturePanel: FixtureWindowBase {
    var keyboardAllowed = false
    var keyboardEvents = 0
    override var canBecomeKey: Bool { keyboardAllowed }
    override var canBecomeMain: Bool { keyboardAllowed }
    override func sendEvent(_ event: NSEvent) {
        if !keyboardAllowed, [.keyDown, .keyUp, .flagsChanged].contains(event.type) {
            keyboardEvents += 1; return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class WebFixtureController: NSObject, WKNavigationDelegate {
    let window: WebFixturePanel
    let web: WKWebView
    var commandBytes = Data()
    let foregroundArmed: Bool
    private var activated = false
    init(foregroundArmed: Bool = false) {
        self.foregroundArmed = foregroundArmed
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: config)
        window = WebFixturePanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: foregroundArmed ? [.titled] : [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        window.title = "Saytile synthetic web fixture"
        window.alphaValue = 0; window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false; window.contentView = web
        window.makeFirstResponder(web); window.orderBack(nil)
        web.navigationDelegate = self
        web.loadHTMLString(Self.html, baseURL: URL(string: "https://saytile-fixture.invalid/chat/one"))
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let bytes = handle.availableData
            if bytes.isEmpty { handle.readabilityHandler = nil; return }
            Task { @MainActor [weak self] in self?.consume(bytes) }
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        _ = webView.accessibilityChildren()
        webView.evaluateJavaScript("focusComposer();document.querySelector('textarea').value==='PREFIX|SUFFIX'&&document.querySelector('textarea').selectionStart===7&&document.querySelector('textarea').selectionEnd===7") { [self] value, error in
            guard error == nil, value as? Bool == true, !window.isKeyWindow, !window.isMainWindow, window.keyboardEvents == 0 else {
                FileHandle.standardOutput.write(Data("WEB_FIXTURE_ISOLATION_FAILED\n".utf8)); return
            }
            FileHandle.standardOutput.write(Data("WEB_FIXTURE_ISOLATION initial_expected=true key=false main=false keyboard_events=0\nWEB_FIXTURE_READY\n".utf8))
        }
    }
    func consume(_ bytes: Data) {
        commandBytes.append(bytes)
        while let newline = commandBytes.firstIndex(of: 10) {
            let line = commandBytes.prefix(upTo: newline); commandBytes.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: String], let command = object["command"] else { continue }
            let js: String
            switch command {
            case "activate":
                guard foregroundArmed, !activated else { continue }
                activated = true
                window.keyboardAllowed = true
                NSApp.setActivationPolicy(.regular)
                window.alphaValue = 1; window.ignoresMouseEvents = false
                window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                window.makeFirstResponder(web)
                js = "focusComposer()"
            case "focusOwned":
                guard foregroundArmed, activated, NSApp.isActive else { FileHandle.standardOutput.write(Data("{\"command\":\"focusOwned\",\"error\":\"Owned app inactive\"}\n".utf8)); continue }
                window.makeKeyAndOrderFront(nil); window.makeFirstResponder(web)
                js = "focusComposer()"
            case "restore": js = "document.querySelectorAll('.extra').forEach(n=>n.remove());document.querySelector('#send').textContent='Send fixture only';history.replaceState({},'', '/chat/one');document.querySelector('h1').textContent='First synthetic chat';document.querySelector('textarea').value='PREFIX|SUFFIX';focusComposer();"
            case "replaceContext": js = "let h=document.querySelector('h1');h.outerHTML=h.outerHTML;"
            case "largeTree": js = "for(let i=0;i<140;i++){let d=document.createElement('div');d.className='extra';d.textContent='Synthetic node '+i;document.body.append(d);}"
            case "blankContext": js = "document.querySelector('h1').textContent='';document.querySelector('#send').textContent='';"
            case "silentContext": js = "document.querySelector('h1').textContent='Different synthetic chat with identical empty composer';"
            case "sameURL": js = "document.querySelector('h1').textContent='Second synthetic chat';document.querySelector('textarea').value='';focusComposer();"
            case "newURL": js = "history.pushState({},'', '/chat/two');document.querySelector('h1').textContent='Second synthetic chat';document.querySelector('textarea').value='';focusComposer();"
            case "replaceEditor": js = "document.querySelector('textarea').outerHTML='<textarea id=\"composer\" aria-label=\"Synthetic composer\"></textarea>';focusComposer();"
            case "manualEdit": js = "let t=document.querySelector('textarea');t.value='PREFIX|我的改字SUFFIX';t.setSelectionRange(11,11);"
            case "blur": js = "document.querySelector('#send').focus();"
            case "select": js = "document.querySelector('textarea').setSelectionRange(0,6);"
            case "state": js = "(()=>{let t=document.querySelector('textarea').value;let known=['','PREFIX|SUFFIX','PREFIX|你好😀SUFFIX','PREFIX|你好😀，接着说SUFFIX','PREFIX|网页😀SUFFIX','PREFIX|50😀SUFFIX','PREFIX|500👩🏽‍💻SUFFIX','PREFIX|我的改字SUFFIX'].includes(t);return JSON.stringify({text:known?t:'UNEXPECTED_TEXT_OMITTED',knownSyntheticText:known,utf16Length:t.length,sends:window.sends,url:location.href});})()"
            default: continue
            }
            web.evaluateJavaScript(js) { [self] value, error in
                let response: [String: Any] = ["command": command, "value": value.map { String(describing: $0) } ?? "", "error": error?.localizedDescription ?? "",
                    "keyWindow": window.isKeyWindow, "mainWindow": window.isMainWindow, "keyboardEvents": window.keyboardEvents]
                if let data = try? JSONSerialization.data(withJSONObject: response) { FileHandle.standardOutput.write(data + Data([10])) }
            }
        }
    }
    static let html = """
    <!doctype html><html><head><title>Saytile synthetic web fixture</title></head><body>
    <h1>First synthetic chat</h1><textarea id="composer" aria-label="Synthetic composer" style="width:500px;height:200px">PREFIX|SUFFIX</textarea>
    <button id="send">Send fixture only</button><script>
    window.sends=0;function focusComposer(){let c=document.querySelector('textarea');c.focus();c.setSelectionRange(Math.min(7,c.value.length),Math.min(7,c.value.length));}
    document.addEventListener('keydown',e=>{if(e.key==='Enter'){window.sends++;e.preventDefault();}});
    document.querySelector('#send').onclick=()=>window.sends++;
    </script></body></html>
    """
}
@main
struct AXWebFixture {
    @MainActor static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.prohibited)
        let controller = WebFixtureController(foregroundArmed: CommandLine.arguments.contains("--foreground-armed"))
        withExtendedLifetime(controller) { app.run() }
    }
}
