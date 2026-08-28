import AppKit

let source = CommandLine.arguments[1]
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
let size = NSSize(width: 660, height: 400)
let image = NSImage(contentsOfFile: source)!
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: 660,
    pixelsHigh: 400,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
bitmap.size = size
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
image.draw(in: NSRect(origin: .zero, size: size))
try bitmap.representation(using: .png, properties: [:])!.write(to: destination)
