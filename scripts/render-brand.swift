#!/usr/bin/env swift
// Vector-first artwork for Procaine's selected sleeping Bluetooth identity.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("Procaine/Assets.xcassets")
let images = root.appendingPathComponent("images")
let blue = NSColor(calibratedRed: 0.18, green: 0.33, blue: 0.79, alpha: 1)
let violet = NSColor(calibratedRed: 0.42, green: 0.32, blue: 0.76, alpha: 1)

// Bluetooth rune rotated 90 degrees counterclockwise in AppKit's y-up space.
func glyph(_ color: NSColor, center: NSPoint, extent: CGFloat, weight: CGFloat) {
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: center.x - y * extent, y: center.y + x * extent)
    }
    color.setStroke()
    let path = NSBezierPath()
    path.lineWidth = weight
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.move(to: point(0, -0.5))
    path.line(to: point(0, 0.5))
    path.line(to: point(0.34, 0.25))
    path.line(to: point(-0.34, -0.25))
    path.move(to: point(-0.34, 0.25))
    path.line(to: point(0.34, -0.25))
    path.line(to: point(0, -0.5))
    path.stroke()
}

// Centered sideways Bluetooth rune; no enclosing shape.
func menuBadge(_ color: NSColor, center: NSPoint, scale: CGFloat) {
    glyph(color, center: center, extent: 18 * scale, weight: 1.15 * scale)
}

final class Artwork: NSView {
    enum Kind { case icon, symbol, wordmark }
    let kind: Kind
    init(size: NSSize, kind: Kind) { self.kind = kind; super.init(frame: NSRect(origin: .zero, size: size)) }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        switch kind {
        case .icon:
            let scale = bounds.width / 1024
            let transform = AffineTransform(scale: scale)
            (transform as NSAffineTransform).concat()
            let background = NSBezierPath(roundedRect: NSRect(x: 48, y: 48, width: 928, height: 928), xRadius: 212, yRadius: 212)
            NSGradient(starting: blue, ending: violet)!.draw(in: background, angle: -45)
            glyph(.white, center: NSPoint(x: 512, y: 512), extent: 560, weight: 42)
        case .symbol:
            let scale = bounds.width / 20
            menuBadge(.black, center: NSPoint(x: bounds.midX, y: bounds.midY - 0.75 * scale), scale: scale)
        case .wordmark:
            blue.setFill()
            let mark = Artwork(size: NSSize(width: 100, height: 100), kind: .icon)
            mark.draw(mark.bounds)
            ("Procaine" as NSString).draw(at: NSPoint(x: 125, y: 31), withAttributes: [
                .font: NSFont.systemFont(ofSize: 48, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
            ])
        }
    }
}

func png(_ view: NSView, to destination: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = view.bounds.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: destination)
}

let iconDir = catalog.appendingPathComponent("AppIcon.appiconset")
var entries: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "procaine-\(size)@\(scale)x.png"
        try png(Artwork(size: NSSize(width: size * scale, height: size * scale), kind: .icon), to: iconDir.appendingPathComponent(filename))
        entries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
try JSONSerialization.data(withJSONObject: ["images": entries, "info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted, .sortedKeys]).write(to: iconDir.appendingPathComponent("Contents.json"))
let symbolDir = catalog.appendingPathComponent("procaine.imageset")
try FileManager.default.createDirectory(at: symbolDir, withIntermediateDirectories: true)
let symbol = Artwork(size: NSSize(width: 20, height: 20), kind: .symbol)
try symbol.dataWithPDF(inside: symbol.bounds).write(to: symbolDir.appendingPathComponent("procaine.pdf"))
try JSONSerialization.data(withJSONObject: ["images": [["idiom": "universal", "filename": "procaine.pdf"]], "info": ["version": 1, "author": "xcode"], "properties": ["preserves-vector-representation": true, "template-rendering-intent": "template"]], options: [.prettyPrinted, .sortedKeys]).write(to: symbolDir.appendingPathComponent("Contents.json"))
let icon = Artwork(size: NSSize(width: 1024, height: 1024), kind: .icon)
try png(icon, to: images.appendingPathComponent("procaine-icon-v02.png"))
try icon.dataWithPDF(inside: icon.bounds).write(to: images.appendingPathComponent("procaine-icon-v02.pdf"))
let wordmark = Artwork(size: NSSize(width: 390, height: 110), kind: .wordmark)
try png(wordmark, to: images.appendingPathComponent("procaine-wordmark-v02.png"))
try wordmark.dataWithPDF(inside: wordmark.bounds).write(to: images.appendingPathComponent("procaine-wordmark-v02.pdf"))
try png(symbol, to: images.appendingPathComponent("procaine-menubar-symbol-v06.png"))
try symbol.dataWithPDF(inside: symbol.bounds).write(to: images.appendingPathComponent("procaine-menubar-symbol-v06.pdf"))

final class SymbolPreview: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSRect(x: 320, y: 0, width: 320, height: 220).fill()
        for (offset, color) in [(CGFloat(0), NSColor.black), (CGFloat(320), NSColor.white)] {
            menuBadge(color, center: NSPoint(x: offset + 55, y: 129.25), scale: 1)
            menuBadge(color, center: NSPoint(x: offset + 120, y: 128.5), scale: 2)
            menuBadge(color, center: NSPoint(x: offset + 235, y: 124.75), scale: 7)
            ("1×        2×                     7×" as NSString).draw(at: NSPoint(x: offset + 43, y: 52), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color])
        }
    }
}
try png(SymbolPreview(frame: NSRect(x: 0, y: 0, width: 640, height: 220)), to: images.appendingPathComponent("procaine-menubar-preview-v06.png"))
print("Rendered sleeping Bluetooth v02 app icons, lighter template symbol and wordmark.")
