import AppKit

/// The one anchoring rule for every caret-hung panel (candidate window, AI Editing):
/// below the caret, flipped above when the bottom of the screen is in the way, and
/// never hanging off the side.
enum PanelAnchoring {
    private static let gap: CGFloat = 4

    static func origin(for size: NSSize, caret: NSRect) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var y = caret.minY - gap - size.height
        if y < visible.minY {
            y = caret.maxY + gap
        }
        let x = min(max(caret.minX, visible.minX), max(visible.minX, visible.maxX - size.width))
        return NSPoint(x: x, y: y)
    }
}
