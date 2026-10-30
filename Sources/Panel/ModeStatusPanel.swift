import AppKit
import SwiftUI

/// The drop-down under HAL's menu bar item, drawn by HAL instead of an NSMenu (D31).
///
/// Non-activating, like the candidate panel: taking key focus would pull it away from the
/// app being typed into, and the system would see a focus change inside HAL's own process.
/// Without key focus it never sees the keyboard, so it closes on a click anywhere else or
/// on the menu bar item again.
@MainActor
final class ModeStatusPanel {
    static let shared = ModeStatusPanel()

    /// Gap between the menu bar item and the card.
    private static let gap: CGFloat = 4

    private let panel: NSPanel
    private let hosting: FirstClickHostingView<ModeStatusPanelView>
    private weak var button: NSStatusBarButton?
    private var outsideClickMonitor: Any?
    private var openCount = 0

    var isOpen: Bool { panel.isVisible }

    private init() {
        hosting = FirstClickHostingView(rootView: ModeStatusPanelView(id: 0, scheme: .aurora,
                                                                      openControlCenter: {}, resized: { _ in }))
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered,
                        defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The SwiftUI card draws its own tinted shadow.
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
    }

    func toggle(below button: NSStatusBarButton) {
        isOpen ? close() : open(below: button)
    }

    func close() {
        guard isOpen else { return }
        panel.orderOut(nil)
        button?.highlight(false)
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        outsideClickMonitor = nil
    }

    private func open(below button: NSStatusBarButton) {
        self.button = button
        openCount += 1
        hosting.rootView = ModeStatusPanelView(
            id: openCount,
            // Read on every open: the control center writes Settings.json directly.
            scheme: SettingsStore.load().candidateColorScheme,
            openControlCenter: { [weak self] in
                self?.close()
                Self.openControlCenter()
            },
            resized: { [weak self] size in self?.place(size: size) })
        hosting.layoutSubtreeIfNeeded()
        place(size: hosting.fittingSize)
        panel.orderFrontRegardless()
        button.highlight(true)
        // Clicks in HAL's own windows (this card, the menu bar item) are local events and
        // never reach a global monitor.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in
            MainActor.assumeIsolated { ModeStatusPanel.shared.close() }
        }
    }

    /// Hangs the card from the menu bar item, kept on the item's screen. The view pads the
    /// card for its shadow, so the window starts that far outside the card's edge.
    private func place(size: CGSize) {
        guard let button, let itemWindow = button.window else { return }
        let item = itemWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let inset = ModeStatusPanelView.shadowPadding
        var x = item.minX - inset
        if let visible = (itemWindow.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX - inset + 6), visible.maxX + inset - 6 - size.width)
        }
        let top = item.minY - Self.gap + inset
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height),
                       display: true)
    }

    /// The control center (D21) is a separate app; looked up by bundle id rather than a
    /// hardcoded path, since where the user keeps it isn't HAL's business.
    private static func openControlCenter() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.hal.inputmethod.HALSettings")
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// A non-key panel would otherwise spend the first click making itself key.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
