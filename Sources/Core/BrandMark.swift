import AppKit

/// The one brand mark: the bundled `logo.svg`. Every logo surface draws it — the sidebar,
/// About, the install hero, the menu bar item, the switch-animation stamp, and (via
/// scripts/generate-app-icon.swift) the App Icon and the input-method menu icon. Swapping
/// the logo is replacing that single file and rerunning the script.
enum BrandMark {
    /// The mark in full colour, for HAL's own surfaces.
    static var image: NSImage? {
        load()
    }

    /// The mark for the menu bar, rasterised at 3× — the SVG-backed image carries no bitmap
    /// layer, and the status item's drawing path renders nothing without one. Deliberately
    /// not a template: templates keep only the alpha channel, and the artwork is uniformly
    /// opaque, so a template collapses to a flat silhouette — the face lives in the colours.
    static var menuBarImage: NSImage? {
        guard let source = load() else { return nil }
        let side: CGFloat = 16
        let pixels = 48
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: NSSize(width: side, height: side)))
        let image = NSImage()
        image.addRepresentation(rep)
        return image
    }

    private static func load() -> NSImage? {
        Bundle.main.url(forResource: "logo", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
    }
}
