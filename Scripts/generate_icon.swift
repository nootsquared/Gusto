import AppKit

// A simple native vector brand mark; run from the repository root.
let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3,
    hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(red: 47 / 255, green: 74 / 255, blue: 58 / 255, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let leaf = NSBezierPath()
leaf.move(to: NSPoint(x: 270, y: 310))
leaf.curve(
    to: NSPoint(x: 765, y: 755), controlPoint1: NSPoint(x: 200, y: 680),
    controlPoint2: NSPoint(x: 500, y: 805))
leaf.curve(
    to: NSPoint(x: 270, y: 310), controlPoint1: NSPoint(x: 790, y: 390),
    controlPoint2: NSPoint(x: 510, y: 230))
NSColor(red: 239 / 255, green: 220 / 255, blue: 168 / 255, alpha: 1).setFill()
leaf.fill()
let stem = NSBezierPath()
stem.move(to: NSPoint(x: 270, y: 230))
stem.curve(
    to: NSPoint(x: 640, y: 625), controlPoint1: NSPoint(x: 320, y: 390),
    controlPoint2: NSPoint(x: 420, y: 510))
stem.lineWidth = 30
stem.lineCapStyle = .round
NSColor(red: 47 / 255, green: 74 / 255, blue: 58 / 255, alpha: 1).setStroke()
stem.stroke()
NSGraphicsContext.restoreGraphicsState()
let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Rescue/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(
    to: directory.appendingPathComponent("AppIcon.png"))
try Data(
    "{\"images\":[{\"filename\":\"AppIcon.png\",\"idiom\":\"universal\",\"platform\":\"ios\",\"size\":\"1024x1024\"}],\"info\":{\"author\":\"xcode\",\"version\":1}}"
        .utf8
).write(to: directory.appendingPathComponent("Contents.json"))
