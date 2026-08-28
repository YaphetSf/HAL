import AppKit
import OSLog
import SwiftUI

private let modeFeedbackLog = Logger(subsystem: "com.hal.inputmethod",
                                     category: "panel")

/// Window mechanics for caret mode feedback: non-activating, mouse-transparent, shared
/// across every IMK controller, and able to follow the active client across Spaces.
///
/// Visual decisions live in ModeFeedbackEffect.swift. This type deliberately delegates
/// canvas size, caret anchoring, and lifetime to that replaceable skin.
@MainActor
final class ModeFeedbackPanel: NSObject {
    static let shared = ModeFeedbackPanel()

    private let panel: NSPanel
    private let hosting: NSHostingView<ModeFeedbackScene>
    private var generation: UInt = 0

    private override init() {
        let initial = ModeFeedbackPresentation(id: 0,
                                               mode: .chinese,
                                               scheme: .aurora)
        hosting = NSHostingView(rootView: ModeFeedbackScene(
            presentation: initial,
            artwork: nil,
            placement: ModeFeedbackScene.placement(for: .zero, in: .zero, style: .stamp),
            style: .stamp
        ))
        panel = NSPanel(contentRect: NSRect(origin: .zero,
                                            size: ModeFeedbackScene.canvasSize(for: .stamp)),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered,
                        defer: false)
        super.init()
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
    }

    func show(_ mode: ModeFeedbackMode, caret: NSRect) {
        guard Self.isUsable(caret) else {
            modeFeedbackLog.debug("skip mode feedback: invalid caret=\(NSStringFromRect(caret), privacy: .public)")
            return
        }

        let screen = NSScreen.screens.first {
            $0.frame.insetBy(dx: -1, dy: -1).contains(caret.origin)
                || $0.frame.intersects(caret)
        } ?? NSScreen.main
        guard let screen else { return }

        generation &+= 1
        let settings = SettingsStore.load()
        let presentation = ModeFeedbackPresentation(
            id: generation,
            mode: mode,
            scheme: settings.candidateColorScheme
        )
        let style = ModeFeedbackStyle(settings.modeFeedback)
        let placement = ModeFeedbackScene.placement(for: caret, in: screen.visibleFrame,
                                                    style: style)

        hosting.rootView = ModeFeedbackScene(
            presentation: presentation,
            artwork: ModeFeedbackArtwork.image(for: settings.modeFeedback),
            placement: placement,
            style: style
        )
        panel.setContentSize(ModeFeedbackScene.canvasSize(for: style))
        panel.setFrameOrigin(placement.origin)
        panel.orderFrontRegardless()

        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(hideAfterDelay),
                                               object: nil)
        perform(#selector(hideAfterDelay),
                with: nil,
                afterDelay: ModeFeedbackEffect.visibilityDuration)

        modeFeedbackLog.debug("mode feedback caret=\(NSStringFromRect(caret), privacy: .public) origin=\(NSStringFromPoint(placement.origin), privacy: .public)")
    }

    func hide() {
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(hideAfterDelay),
                                               object: nil)
        panel.orderOut(nil)
    }

    @objc private func hideAfterDelay() {
        panel.orderOut(nil)
    }

    private static func isUsable(_ caret: NSRect) -> Bool {
        caret.origin.x.isFinite
            && caret.origin.y.isFinite
            && caret.size.width.isFinite
            && caret.size.height.isFinite
            && caret.size.height > 0
            && caret != .zero
    }
}
