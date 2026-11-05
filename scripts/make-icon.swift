import AppKit
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let p = CGFloat(pixels)
        NSColor(red: 0.94, green: 0.96, blue: 0.92, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x:p*0.05,y:p*0.05,width:p*0.9,height:p*0.9), xRadius:p*0.2, yRadius:p*0.2).fill()
        NSColor(red: 0.26, green: 0.39, blue: 0.30, alpha: 1).setFill()
        for (index,height) in [0.38,0.56,0.26].enumerated() {
            let h = p * height
            NSBezierPath(roundedRect: NSRect(x:p*(0.29+Double(index)*0.155),y:(p-h)/2,width:p*0.105,height:h),xRadius:p*0.0525,yRadius:p*0.0525).fill()
        }
        image.unlockFocus()
        let data = NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try data.write(to:URL(fileURLWithPath:destination).appendingPathComponent(name))
    }
}
