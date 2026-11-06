import AppKit
import SwiftUI
@MainActor final class StateModel: ObservableObject { @Published var text = "old" }
@MainActor struct Content: View {
    @ObservedObject var model: StateModel
    var body: some View { Form { TextField("Topic", text: $model.text, axis: .vertical).lineLimit(2...4).accessibilityIdentifier("topic") }.formStyle(.grouped) }
}
@main struct Probe {
    @MainActor static func main() {
        let app=NSApplication.shared; app.setActivationPolicy(.prohibited)
        let before=NSWorkspace.shared.frontmostApplication?.processIdentifier
        let model=StateModel();let host=NSHostingView(rootView:Content(model:model))
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:650,height:400),styleMask:[.titled,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.title="Saytile isolated text field probe";panel.alphaValue=0;panel.hidesOnDeactivate=false;panel.ignoresMouseEvents=true;panel.contentView=host;panel.orderBack(nil)
        Task { @MainActor in
            try? await Task.sleep(for:.milliseconds(400));host.layoutSubtreeIfNeeded()
            @MainActor func walk(_ v:NSView,_ depth:Int=0) {
                print(String(repeating:" ",count:depth)+String(describing:type(of:v))+" id="+(v.accessibilityIdentifier() ?? "-"))
                if let field=v as? NSTextField { print("FIELD value=\(field.stringValue) target=\(String(describing:field.target)) action=\(String(describing:field.action))") }
                if let text=v as? NSTextView { print("TEXTVIEW value=\(text.string) delegate=\(String(describing:text.delegate))") }
                for child in v.subviews { walk(child,depth+1) }
            }
            walk(host)
            @MainActor func fields(_ view:NSView)->[NSTextField] { (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { fields($0) } }
            let field=fields(host).first!
            print("PLACEHOLDER=\(field.placeholderString ?? "")")
            field.stringValue="changed using action"
            let sent=field.sendAction(field.action,to:field.target)
            try? await Task.sleep(for:.milliseconds(100))
            let made=panel.makeFirstResponder(field)
            print("FIRST made=\(made) responder=\(String(describing:panel.firstResponder)) editor=\(String(describing:field.currentEditor()))")
            if let editor=field.currentEditor() as? NSTextView {
                print("BEFORE_INSERT model=\(model.text) editor=\(editor.string)")
                editor.insertText("changed using action", replacementRange:NSRange(location:0,length:editor.string.utf16.count))
                _=panel.makeFirstResponder(host)
                try? await Task.sleep(for:.milliseconds(100))
            }
            print("ACTION sent=\(sent) model=\(model.text) field=\(field.stringValue)")
            print("MODEL=\(model.text);frontsame=\(before==NSWorkspace.shared.frontmostApplication?.processIdentifier)")
            panel.orderOut(nil); app.terminate(nil)
        }
        app.run()
    }
}
