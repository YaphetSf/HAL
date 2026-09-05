import AppKit
import SwiftUI

/// Which skin plays on a mode switch (D26). The stamp is the default and the one that
/// carries the user's artwork; the serve is the original tennis animation, kept behind a
/// toggle for the people who liked it.
enum SwitchAnimationStyle: Equatable, Sendable {
    case stamp
    case serve

    init(_ choice: SwitchAnimationChoice) {
        self = choice == .serve ? .serve : .stamp
    }
}

/// The single seam the panel talks to. Canvas size and caret anchoring belong to whichever
/// skin is playing, so both stay inside their own file (D24).
struct SwitchAnimationScene: View {
    let presentation: SwitchAnimationPresentation
    let artwork: NSImage?
    let placement: SwitchAnimationPlacement
    let style: SwitchAnimationStyle

    var body: some View {
        switch style {
        case .stamp:
            SwitchAnimationEffect(presentation: presentation, artwork: artwork)
        case .serve:
            SwitchAnimationServeEffect(presentation: presentation,
                                    horizontalDirection: placement.horizontalDirection,
                                    verticalDirection: placement.verticalDirection)
        }
    }

    static func canvasSize(for style: SwitchAnimationStyle) -> CGSize {
        switch style {
        case .stamp: return SwitchAnimationEffect.canvasSize
        case .serve: return SwitchAnimationServeEffect.canvasSize
        }
    }

    static func placement(for caret: CGRect, in visibleFrame: CGRect,
                          style: SwitchAnimationStyle) -> SwitchAnimationPlacement {
        switch style {
        case .stamp:
            return SwitchAnimationPlacement(origin: SwitchAnimationEffect.origin(for: caret,
                                                                          in: visibleFrame),
                                         horizontalDirection: .right,
                                         verticalDirection: .below)
        case .serve:
            return SwitchAnimationServeEffect.placement(for: caret, in: visibleFrame)
        }
    }
}
