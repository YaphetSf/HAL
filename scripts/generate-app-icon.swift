#!/usr/bin/env swift

// Renders the one brand logo (Resources/Brand/logo.svg) into every bitmap surface that
// ships it: the App Icon set and the input-method menu icon. Rebranding is replacing
// logo.svg and rerunning this script; the in-app surfaces read the SVG directly.

import AppKit

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let brandURL = repoRoot.appendingPathComponent("Resources/Brand/logo.svg")
let appIconDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ??
    "Sources/SettingsApp/Resources/Assets.xcassets/AppIcon.appiconset",
                           relativeTo: repoRoot)
let menuIconURL = repoRoot.appendingPathComponent("Sources/App/Resources/HALMenuIcon.tiff")

guard let brand = NSImage(contentsOf: brandURL), brand.size.width > 0 else {
    fatalError("cannot read the brand logo at \(brandURL.path)")
}

func png(of image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let data = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

// The App Icon: macOS tiles every icon, so the mark sits on the same dark tile as before.
let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

try FileManager.default.createDirectory(at: appIconDirectory, withIntermediateDirectories: true)

for (filename, size) in outputs {
    let canvas = CGFloat(size)
    let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { rect in
        NSGraphicsContext.current?.imageInterpolation = .high

        let tile = NSBezierPath(roundedRect: rect.insetBy(dx: canvas * 0.055, dy: canvas * 0.055),
                                xRadius: canvas * 0.22, yRadius: canvas * 0.22)
        NSGradient(colors: [NSColor(red: 0.10, green: 0.14, blue: 0.20, alpha: 1),
                            NSColor(red: 0.015, green: 0.025, blue: 0.045, alpha: 1)])!
            .draw(in: tile, angle: -55)

        brand.draw(in: rect.insetBy(dx: canvas * 0.13, dy: canvas * 0.13))
        return true
    }
    try png(of: image, to: appIconDirectory.appendingPathComponent(filename))
}

// The input-method menu icon: a 16×16 template, so the system tints it from the alpha.
let menuIcon = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
    NSGraphicsContext.current?.imageInterpolation = .high
    brand.draw(in: rect.insetBy(dx: 0.5, dy: 0.5))
    return true
}
guard let tiff = menuIcon.tiffRepresentation else {
    throw CocoaError(.fileWriteUnknown)
}
try tiff.write(to: menuIconURL)

print("wrote \(outputs.count) app icons to \(appIconDirectory.path)")
print("wrote \(menuIconURL.path)")
