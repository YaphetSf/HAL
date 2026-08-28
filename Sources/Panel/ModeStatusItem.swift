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
/// Clicking opens a menu rather than toggling mode directly (that stayed Caps Lock-only,
/// D11) — the menu just shows which mode that is, plus the door to the HAL app (D21).
@MainActor
final class ModeStatusItem: NSObject, NSMenuDelegate {
    static let shared = ModeStatusItem()

    private var item: NSStatusItem?
    private let modeIndicator = NSMenuItem(title: "", action: nil, keyEquivalent: "")

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

        let menu = NSMenu()
        menu.delegate = self
        modeIndicator.isEnabled = false
        menu.addItem(modeIndicator)
        menu.addItem(.separator())
        let preferences = NSMenuItem(title: "Open HAL…", action: #selector(openPreferences), keyEquivalent: ",")
        preferences.target = self
        menu.addItem(preferences)
        item.menu = menu

        self.item = item
    }

    /// Refreshed right before the menu shows, since Caps Lock can change the mode at any
    /// time while it's closed.
    func menuWillOpen(_ menu: NSMenu) {
        let state = ModeState.shared
        guard state.isActive else {
            modeIndicator.title = "Not the current input source — ⌃Space to switch back"
            return
        }
        if !state.isAscii {
            let next = state.englishProfile == .assist ? "EN+" : "EN"
            modeIndicator.title = "中文 — Caps Lock switches to \(next)"
        } else if state.englishProfile == .assist {
            modeIndicator.title = "EN+ — ←/→ selects, Tab accepts; ⇧Caps Lock switches to EN"
        } else {
            modeIndicator.title = "EN — ⇧Caps Lock switches to EN+"
        }
    }

    /// The HAL control center (D21) is a separate app; looked up by bundle id rather than a hardcoded
    /// path, since where the user keeps it isn't HAL's business.
    @objc private func openPreferences() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.hal.inputmethod.HALSettings")
        else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}
