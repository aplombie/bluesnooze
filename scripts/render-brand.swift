#!/usr/bin/env swift
// Approved Bonded Signal identity: raster app master, vector menu-bar states.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("Procaine/Assets.xcassets")
let images = root.appendingPathComponent("images")
let masterURL = images.appendingPathComponent("brand/procaine-app-icon-source-v03.png")
let master: NSImage = {
    guard let image = NSImage(contentsOf: masterURL) else {
        fatalError("Missing approved app-icon source: images/brand/procaine-app-icon-source-v03.png")
    }
    // Package the generated tile in macOS's square canvas with a deterministic
    // boundary. This excludes transparent-edge residue outside the source tile.
    image.size = NSSize(width: 1254, height: 1254)
    return NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let tile = NSRect(x: 48, y: 48, width: 928, height: 928)
        NSBezierPath(roundedRect: tile, xRadius: 200, yRadius: 200).addClip()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: tile, from: NSRect(x: 94, y: 140, width: 1045, height: 997),
                   operation: .sourceOver, fraction: 1)
        return true
    }
}()

// Coordinates follow the approved mark in y-down space. Both states share a
// canvas and optical placement so toggling actions never shifts the status item.
func menuBadge(_ color: NSColor, in rect: NSRect, enabled: Bool) {
    let extent = min(rect.width, rect.height * 1.2)
    let origin = NSPoint(x: rect.midX - extent / 2, y: rect.midY + extent * 0.485)
    func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: origin.x + x * extent, y: origin.y - y * extent)
    }
    color.setStroke()
    let path = NSBezierPath()
    path.lineWidth = 0.055 * extent
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    func line(_ coordinates: [(CGFloat, CGFloat)], closed: Bool = false) {
        guard let first = coordinates.first else { return }
        path.move(to: point(first.0, first.1))
        for (x, y) in coordinates.dropFirst() { path.line(to: point(x, y)) }
        if closed { path.close() }
    }
    line([(0.18, 0.08), (0.31, 0.155), (0.31, 0.305),
          (0.18, 0.38), (0.05, 0.305), (0.05, 0.155)], closed: true)
    line([(0.31, 0.305), (0.53, 0.51)])
    line([(0.53, 0.51), (0.53, 0.18), (0.77, 0.345), (0.26, 0.73)])
    line([(0.53, 0.51), (0.53, 0.89), (0.77, 0.70), (0.53, 0.51)])
    if enabled {
        line([(0.19, 0.15), (0.25, 0.185)])
        line([(0.11, 0.275), (0.17, 0.31)])
        // Continue the central diagonal into the circle's upper-left edge.
        line([(0.77, 0.70), (0.867, 0.777)])
    }
    path.stroke()
    if enabled {
        let circle = NSBezierPath(ovalIn: NSRect(
            x: point(0.855, 0.81).x, y: point(0.91, 0.865).y,
            width: 0.11 * extent, height: 0.11 * extent))
        circle.lineWidth = path.lineWidth
        circle.stroke()
    }
}

final class Artwork: NSView {
    enum Kind { case icon, symbol(Bool), wordmark }
    let kind: Kind
    init(size: NSSize, kind: Kind) {
        self.kind = kind
        super.init(frame: NSRect(origin: .zero, size: size))
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func draw(_ dirtyRect: NSRect) {
        switch kind {
        case .icon:
            NSGraphicsContext.current?.imageInterpolation = .high
            master.draw(in: bounds)
        case .symbol(let enabled):
            menuBadge(.black, in: bounds.insetBy(dx: 1, dy: 0.5), enabled: enabled)
        case .wordmark:
            master.draw(in: NSRect(x: 0, y: 5, width: 100, height: 100))
            ("Procaine" as NSString).draw(at: NSPoint(x: 125, y: 31), withAttributes: [
                .font: NSFont.systemFont(ofSize: 48, weight: .semibold),
                .foregroundColor: NSColor(calibratedWhite: 0.12, alpha: 1)
            ])
        }
    }
}

func png(_ view: NSView, to destination: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = view.bounds.size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    view.draw(view.bounds)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: destination)
}

func json(_ object: [String: Any], to destination: URL) throws {
    try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: destination)
}

let iconDir = catalog.appendingPathComponent("AppIcon.appiconset")
try png(Artwork(size: NSSize(width: 1024, height: 1024), kind: .icon),
        to: images.appendingPathComponent("procaine-icon-v03.png"))
var entries: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "procaine-\(size)@\(scale)x.png"
        try png(Artwork(size: NSSize(width: size * scale, height: size * scale), kind: .icon),
                to: iconDir.appendingPathComponent(filename))
        entries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
    }
}
try json(["images": entries, "info": ["version": 1, "author": "xcode"]],
         to: iconDir.appendingPathComponent("Contents.json"))

for (name, enabled) in [("procaine", true), ("procaine-off", false)] {
    let directory = catalog.appendingPathComponent("\(name).imageset")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let symbol = Artwork(size: NSSize(width: 24, height: 20), kind: .symbol(enabled))
    let data = symbol.dataWithPDF(inside: symbol.bounds)
    try data.write(to: directory.appendingPathComponent("\(name).pdf"))
    try json(["images": [["idiom": "universal", "filename": "\(name).pdf"]],
              "info": ["version": 1, "author": "xcode"],
              "properties": ["preserves-vector-representation": true,
                             "template-rendering-intent": "template"]],
             to: directory.appendingPathComponent("Contents.json"))
    try data.write(to: images.appendingPathComponent("\(name)-menubar-v07.pdf"))
    try png(symbol, to: images.appendingPathComponent("\(name)-menubar-v07.png"))
}
let wordmark = Artwork(size: NSSize(width: 390, height: 110), kind: .wordmark)
try png(wordmark, to: images.appendingPathComponent("procaine-wordmark-v03.png"))

final class SymbolPreview: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSRect(x: 360, y: 0, width: 360, height: 260).fill()
        for (offset, color) in [(CGFloat(0), NSColor.black), (CGFloat(360), NSColor.white)] {
            for (enabled, y) in [(true, CGFloat(170)), (false, CGFloat(55))] {
                menuBadge(color, in: NSRect(x: offset + 35, y: y + 24, width: 22, height: 19), enabled: enabled)
                menuBadge(color, in: NSRect(x: offset + 95, y: y + 14, width: 44, height: 38), enabled: enabled)
                menuBadge(color, in: NSRect(x: offset + 205, y: y - 4, width: 88, height: 76), enabled: enabled)
                (enabled ? "Enabled" : "Off" as NSString).draw(at: NSPoint(x: offset + 30, y: y - 20),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: color])
            }
        }
    }
}
try png(SymbolPreview(frame: NSRect(x: 0, y: 0, width: 720, height: 260)),
        to: images.appendingPathComponent("procaine-menubar-preview-v07.png"))
print("Rendered Bonded Signal app icons and enabled/off vector menu-bar states.")
