import AppKit
// Regenerates the macOS AppIcon sizes from the iOS 1024 artwork:
//   swift scripts/make-mac-icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon~ios-marketing.png App/Assets.xcassets/AppIcon.appiconset
// Apple's macOS icon grid: 824×824 rounded body (radius ≈ 185) centered in 1024, soft drop shadow.
let args = CommandLine.arguments
guard let src = NSImage(contentsOfFile: args[1]) else { fatalError("no source") }
let outDir = args[2]
func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = CGFloat(px) / 1024
    let body = NSRect(x: 100 * k, y: 100 * k + 10 * k, width: 824 * k, height: 824 * k)
    let path = NSBezierPath(roundedRect: body, xRadius: 185 * k, yRadius: 185 * k)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 20 * k
    shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.black.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    path.addClip()
    // The iOS artwork already has its own tile + dark margin; enlarge it so
    // that inner tile fills the Mac body and the margin falls outside the clip.
    let zoom: CGFloat = 1.135
    let art = body.insetBy(dx: -body.width * (zoom - 1) / 2, dy: -body.height * (zoom - 1) / 2)
    src.draw(in: art, from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for (pt, scale) in [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)] {
    let name = "AppIcon-mac-\(pt)\(scale == 2 ? "@2x" : "").png"
    try! render(pt * scale).write(to: URL(fileURLWithPath: outDir + "/" + name))
    print(name)
}
