import AppKit
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.hal.inputmethod", category: "panel")

/// The candidate window: one borderless, non-activating panel shared by every controller,
/// since only one client can be composing at a time.
///
/// Non-activating matters. A panel that takes key focus would pull it away from the app
/// being typed into, and the composition would die on the spot.
@MainActor
final class CandidatePanel {
    static let shared = CandidatePanel()

    private let panel: NSPanel
    private let hosting: NSHostingView<CandidatePanelRootView>
    /// Distance between the text caret and the panel.
    private static let gap: CGFloat = 4

    private init() {
        hosting = NSHostingView(rootView: CandidatePanelRootView(content: .chinese(.idle,
                                                                                   justAppeared: false,
                                                                                   scheme: .aurora)))
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered,
                        defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Clicking to pick a candidate is Backlog; until then the panel is inert.
        panel.ignoresMouseEvents = true
        // No `.stationary`: it pins the panel to the space it first appeared on, so apps
        // living on other spaces (one window per space) never saw any candidates. The
        // standard input-method behavior is canJoinAllSpaces + fullScreenAuxiliary.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
    }

    func show(_ state: EngineState, caret: NSRect) {
        guard !state.candidates.isEmpty else { return hide() }
        let justAppeared = !panel.isVisible
        // Read on every show rather than cached: the control center (D21) writes this file
        // directly, and a fresh read is cheap enough not to bother syncing otherwise.
        hosting.rootView = CandidatePanelRootView(content: .chinese(state,
                                                                     justAppeared: justAppeared,
                                                                     scheme: SettingsStore.load().candidateColorScheme))
        present(caret: caret)
    }

    func showEnglish(prefix: String, suggestions: [String], highlightedIndex: Int,
                     caret: NSRect) {
        guard !prefix.isEmpty, !suggestions.isEmpty else { return hide() }
        hosting.rootView = CandidatePanelRootView(content: .english(prefix: prefix,
                                                                     suggestions: suggestions,
                                                                     highlightedIndex: highlightedIndex,
                                                                     justAppeared: !panel.isVisible,
                                                                     scheme: SettingsStore.load().candidateColorScheme))
        present(caret: caret)
    }

    private func present(caret: NSRect) {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setContentSize(size)
        let origin = origin(for: size, caret: caret)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        log.debug("present caret=\(NSStringFromRect(caret), privacy: .public) size=\(NSStringFromSize(size), privacy: .public) origin=\(NSStringFromPoint(origin), privacy: .public) onScreen=\(NSScreen.screens.contains { $0.frame.contains(origin) }, privacy: .public)")
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Below the caret, flipped above when the bottom of the screen is in the way, and never
    /// hanging off the side.
    private func origin(for size: NSSize, caret: NSRect) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var y = caret.minY - Self.gap - size.height
        if y < visible.minY {
            y = caret.maxY + Self.gap
        }
        let x = min(max(caret.minX, visible.minX), max(visible.minX, visible.maxX - size.width))
        return NSPoint(x: x, y: y)
    }
}

private struct CandidatePanelRootView: View {
    enum Content {
        case chinese(EngineState, justAppeared: Bool, scheme: CandidateColorScheme)
        case english(prefix: String, suggestions: [String], highlightedIndex: Int,
                     justAppeared: Bool, scheme: CandidateColorScheme)
    }

    let content: Content

    @ViewBuilder var body: some View {
        switch content {
        case let .chinese(state, justAppeared, scheme):
            CandidateView(candidates: state.candidates,
                          highlightedIndex: state.highlightedIndex,
                          page: state.page,
                          justAppeared: justAppeared,
                          scheme: scheme)
        case let .english(prefix, suggestions, highlightedIndex, justAppeared, scheme):
            EnglishCompletionView(prefix: prefix,
                                  suggestions: suggestions,
                                  highlightedIndex: highlightedIndex,
                                  justAppeared: justAppeared,
                                  scheme: scheme)
        }
    }
}
