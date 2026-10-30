import AppKit
import Observation
import SwiftUI

/// What the menu bar shows. The input controller owns the mode and pushes it here; this
/// exists because a SwiftUI view needs something observable to read.
@Observable
@MainActor
final class ModeState {
    static let shared = ModeState()

    var isAscii = false
    var englishProfile: EnglishProfile = .direct
    /// False when the system's current input source is something other than HAL — i.e. the
    /// system kicked HAL out and Caps Lock no longer reaches us (D11). Starts true because
    /// the menu bar item only matters while HAL is meant to be in front.
    var isActive = true

    private init() {}
}

/// HAL's own menu bar item. The system input menu can be switched off, and once it is, this
/// is the only thing on screen that says which mode HAL is in.
///
/// Clicking opens HAL's own drop-down (D31) rather than toggling mode directly (that stayed
/// Caps Lock-only, D11).
@MainActor
final class ModeStatusItem: NSObject {
    static let shared = ModeStatusItem()

    private var item: NSStatusItem?

    private override init() { super.init() }

    func install() {
        guard item == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: ModeStatusView.width)
        guard let button = item.button else { return }
        button.toolTip = "HAL"

        let hosting = NSHostingView(rootView: ModeStatusView())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ])

        button.target = self
        button.action = #selector(togglePanel)
        // On press, like the system's own menu bar items.
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])

        self.item = item
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        ModeStatusPanel.shared.toggle(below: sender)
    }
}
