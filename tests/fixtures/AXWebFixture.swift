import AppKit
import WebKit

@MainActor
final class WebFixtureController: NSObject, WKNavigationDelegate {
    let window: NSPanel
    let web: WKWebView
    var commandBytes = Data()
    let foregroundArmed: Bool
    private var activated = false
    init(foregroundArmed: Bool = false) {
        self.foregroundArmed = foregroundArmed
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: config)
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: foregroundArmed ? [.titled] : [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
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
        webView.evaluateJavaScript("focusComposer()") { _, error in
            FileHandle.standardOutput.write(Data((error == nil ? "WEB_FIXTURE_READY\n" : "WEB_FIXTURE_ERROR\n").utf8))
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
                NSApp.setActivationPolicy(.accessory)
                window.alphaValue = 1; window.ignoresMouseEvents = false
                window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
                window.makeFirstResponder(web)
                js = "focusComposer()"
            case "restore": js = "document.querySelectorAll('.extra').forEach(n=>n.remove());document.querySelector('#send').textContent='Send fixture only';history.replaceState({},'', '/chat/one');document.querySelector('h1').textContent='First synthetic chat';document.querySelector('textarea').value='PREFIX|SUFFIX';focusComposer();"
            case "replaceContext": js = "let h=document.querySelector('h1');h.outerHTML=h.outerHTML;"
            case "largeTree": js = "for(let i=0;i<140;i++){let d=document.createElement('div');d.className='extra';d.textContent='Synthetic node '+i;document.body.append(d);}"
            case "blankContext": js = "document.querySelector('h1').textContent='';document.querySelector('#send').textContent='';"
            case "silentContext": js = "document.querySelector('h1').textContent='Different synthetic chat with identical empty composer';"
            case "sameURL": js = "document.querySelector('h1').textContent='Second synthetic chat';document.querySelector('textarea').value='';focusComposer();"
            case "newURL": js = "history.pushState({},'', '/chat/two');document.querySelector('h1').textContent='Second synthetic chat';document.querySelector('textarea').value='';focusComposer();"
            case "replaceEditor": js = "document.querySelector('textarea').outerHTML='<textarea id=\"composer\" aria-label=\"Synthetic composer\"></textarea>';focusComposer();"
            case "select": js = "document.querySelector('textarea').setSelectionRange(0,6);"
            case "state": js = "JSON.stringify({text:document.querySelector('textarea').value,sends:window.sends,url:location.href})"
            default: continue
            }
            web.evaluateJavaScript(js) { value, error in
                let response: [String: Any] = ["command": command, "value": value.map { String(describing: $0) } ?? "", "error": error?.localizedDescription ?? ""]
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
