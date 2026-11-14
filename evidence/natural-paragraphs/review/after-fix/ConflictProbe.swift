import AppKit
struct StubEntry { var id: UUID; var position: Int64 }
struct StubEdit { var id: UUID; var after: String }
struct PanelTimelineDocument {
 var text = ""
 var displayed: [Int64:String] { [:] }
 var entries: [StubEntry] { [] }
 func edits(replacingDisplayedText value: String) -> [StubEdit]? { [] }
}
struct ArchiveDisplayParagraph { var document: PanelTimelineDocument; var emptyTextLabel = "" }
enum ProbeConflict: Error { case concurrentRevision }
@main struct ConflictProbe {
 @MainActor static func main() {
  _ = NSApplication.shared
  NSApplication.shared.setActivationPolicy(.prohibited)
  let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 320,height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
  let view = ArchiveParagraphTextView(frame: window.contentView!.bounds)
  view.isEditable = true; view.delegate = view
  window.contentView!.addSubview(view)
  view.display(.init(document: .init(text: "旧句")))
  let focused = window.makeFirstResponder(view)
  view.display(.init(document: .init(text: "识别迟到的新句")))
  let shownBeforeTyping = view.string
  view.save = { _,_ in throw ProbeConflict.concurrentRevision }
  view.insertText("我的", replacementRange: NSRange(location: 0,length: 0))
  let afterTyping = view.string
  view.endInteraction()
  view.display(.init(document: .init(text: "另一轮识别结果")))
  let lost = !afterTyping.contains("我的") || !view.string.contains("我的")
  print("CONFLICT_REPRO focused=\(focused) before=\(shownBeforeTyping) after=\(afterTyping) afterBlur=\(view.string) localEditLost=\(lost) visible=\(window.isVisible)")
 }
}
