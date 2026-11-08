import AppKit
import ApplicationServices
import Foundation

private final class Owned: @unchecked Sendable { let node:AXUIElement;init(_ node:AXUIElement){self.node=node} }
@main struct Probe {
    static func value(_ e:AXUIElement,_ name:String)->CFTypeRef? {
        AXUIElementSetMessagingTimeout(e,0.12);var v:CFTypeRef?
        return AXUIElementCopyAttributeValue(e,name as CFString,&v) == .success ? v:nil
    }
    static func nodes(_ e:AXUIElement)->[AXUIElement] {
        var q=[e], seen=Set<CFHashCode>(), result=[AXUIElement]()
        while !q.isEmpty,seen.count<160 {
            let v=q.removeFirst();guard seen.insert(CFHash(v)).inserted else {continue}
            result.append(v);q += value(v,kAXChildrenAttribute) as? [AXUIElement] ?? []
        }
        return result
    }
    static func actions(_ e:AXUIElement)->[String] {
        var list:CFArray?;guard AXUIElementCopyActionNames(e,&list) == .success else{return []}
        return list as? [String] ?? []
    }
    @MainActor static func main() async {
        NSApplication.shared.setActivationPolicy(.prohibited)
        guard CommandLine.arguments.count==3,let pid=Int32(CommandLine.arguments[1]),
              AXIsProcessTrusted(),NSWorkspace.shared.frontmostApplication?.processIdentifier != pid else {
            print("UNAVAILABLE own fixture or existing AX trust"); exit(5)
        }
        let nonce=CommandLine.arguments[2],root=AXUIElementCreateApplication(pid)
        let initialFront=NSWorkspace.shared.frontmostApplication?.processIdentifier
        var target:AXUIElement?
        for _ in 0..<10 {
            let ownedWindows=(value(root,kAXWindowsAttribute) as? [AXUIElement] ?? []).filter {
                value($0,kAXTitleAttribute) as? String == "Saytile own context "+nonce
            }
            if ownedWindows.count==1 {
                target=nodes(ownedWindows[0]).first { value($0,kAXIdentifierAttribute) as? String=="fixture.transcript" && value($0,kAXRoleAttribute) as? String==kAXTextAreaRole }
            }
            if target != nil {break};try? await Task.sleep(for:.milliseconds(80))
        }
        guard let target else {print("UNAVAILABLE owned transcript window/PID match");exit(5)}
        var actualPID:pid_t=0;guard AXUIElementGetPid(target,&actualPID) == .success,actualPID==pid else {exit(6)}
        let advertised=actions(target);print("OWNED_TRANSCRIPT_ACTIONS",advertised);fflush(nil)
        guard advertised.contains(kAXShowMenuAction) else {print("AX_SHOW_MENU_NOT_ADVERTISED");exit(5)}
        let handle=Owned(target)
        let opening=Task.detached { AXUIElementSetMessagingTimeout(handle.node,4);return AXUIElementPerformAction(handle.node,kAXShowMenuAction as CFString).rawValue }
        var selected=false
        for _ in 0..<24 {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier==initialFront else {print("REFUSED foreground changed");exit(6)}
            var seen=nodes(root);seen += nodes(target)
            if let item=seen.first(where:{ value($0,kAXRoleAttribute) as? String==kAXMenuItemRole && value($0,kAXTitleAttribute) as? String=="编辑合成段落 "+nonce }) {
                var itemPID:pid_t=0;guard AXUIElementGetPid(item,&itemPID) == .success,itemPID==pid else {exit(6)}
                let code=AXUIElementPerformAction(item,kAXPressAction as CFString)
                print("OWNED_MENU_ITEM_AXPRESS",code.rawValue);selected=code == .success;break
            }
            try? await Task.sleep(for:.milliseconds(70))
        }
        if !selected {
            for node in nodes(root) where value(node,kAXRoleAttribute) as? String==kAXMenuRole { _=AXUIElementPerformAction(node,kAXCancelAction as CFString) }
        }
        let show=await opening.value;let stable=initialFront==NSWorkspace.shared.frontmostApplication?.processIdentifier
        print("AX_CONTEXT_MENU_RESULT show_code=\(show) item_selected=\(selected) foreground_unchanged=\(stable)")
        exit(show==0 && selected && stable ? 0:5)
    }
}
