#!/usr/bin/env swift
// Renders the app icon (white mark-github on a dark rounded square) into AppIcon.appiconset.
// Usage: swift scripts/make-app-icon.swift
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let svg = root.appendingPathComponent("GitHubBar/Resources/Assets.xcassets/Octicons/mark-github.imageset/mark-github-16.svg")
let output = root.appendingPathComponent("GitHubBar/Resources/Assets.xcassets/AppIcon.appiconset")

guard let mark = NSImage(contentsOf: svg) else { fatalError("Can't load \(svg.path)") }

func render(size: Int) -> Data {
    let pixels = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: 824/1024 body with ~185/1024 corner radius.
    let inset = pixels * 100 / 1024
    let body = NSRect(x: inset, y: inset, width: pixels - inset * 2, height: pixels - inset * 2)
    let radius = body.width * 0.225
    let path = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = pixels * 10 / 1024
    shadow.shadowOffset = NSSize(width: 0, height: -pixels * 6 / 1024)
    shadow.set()
    NSColor(srgbRed: 0x0D / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // Subtle top-to-bottom gradient (Primer canvas.subtle -> canvas.default, dark).
    NSGradient(starting: NSColor(srgbRed: 0x2D / 255, green: 0x33 / 255, blue: 0x3B / 255, alpha: 1),
               ending: NSColor(srgbRed: 0x0D / 255, green: 0x11 / 255, blue: 0x17 / 255, alpha: 1))!
        .draw(in: path, angle: -90)

    let markSize = body.width * 0.6
    let markRect = NSRect(x: body.midX - markSize / 2, y: body.midY - markSize / 2, width: markSize, height: markSize)
    let tinted = NSImage(size: markRect.size, flipped: false) { rect in
        mark.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
    tinted.draw(in: markRect)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try? FileManager.default.removeItem(at: output)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(size: points * scale).write(to: output.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(points)x\(points)"])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: output.appendingPathComponent("Contents.json"))
print("App icon -> \(output.path)")
