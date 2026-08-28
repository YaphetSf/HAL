import AppKit
import SwiftUI

/// Which skin plays on a mode switch (D26). The stamp is the default and the one that
/// carries the user's artwork; the serve is the original tennis animation, kept behind a
/// toggle for the people who liked it.
enum ModeFeedbackStyle: Equatable, Sendable {
    case stamp
    case serve

    init(_ choice: ModeFeedbackChoice) {
        self = choice == .serve ? .serve : .stamp
    }
}

/// The single seam the panel talks to. Canvas size and caret anchoring belong to whichever
/// skin is playing, so both stay inside their own file (D24).
struct ModeFeedbackScene: View {
    let presentation: ModeFeedbackPresentation
    let artwork: NSImage?
    let placement: ModeFeedbackPlacement
    let style: ModeFeedbackStyle

    var body: some View {
        switch style {
        case .stamp:
            ModeFeedbackEffect(presentation: presentation, artwork: artwork)
        case .serve:
            ModeFeedbackServeEffect(presentation: presentation,
                                    horizontalDirection: placement.horizontalDirection,
                                    verticalDirection: placement.verticalDirection)
        }
    }

    static func canvasSize(for style: ModeFeedbackStyle) -> CGSize {
        switch style {
        case .stamp: return ModeFeedbackEffect.canvasSize
        case .serve: return ModeFeedbackServeEffect.canvasSize
        }
    }

    static func placement(for caret: CGRect, in visibleFrame: CGRect,
                          style: ModeFeedbackStyle) -> ModeFeedbackPlacement {
        switch style {
        case .stamp:
            return ModeFeedbackPlacement(origin: ModeFeedbackEffect.origin(for: caret,
                                                                          in: visibleFrame),
                                         horizontalDirection: .right,
                                         verticalDirection: .below)
        case .serve:
            return ModeFeedbackServeEffect.placement(for: caret, in: visibleFrame)
        }
    }
}
