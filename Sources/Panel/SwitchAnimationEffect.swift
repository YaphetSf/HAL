import AppKit
import SwiftUI

/// The semantic result of a mode switch. Deliberately knows nothing about the skin below
/// it (D24), so a future visual direction does not leak back into InputController.
enum SwitchAnimationMode: Equatable, Sendable {
    case chinese
    case english
    case englishAssist
}

/// The small, stable payload that crosses from panel infrastructure into the skin. `id`
/// makes repeated switches to the same mode replay the one-shot animation.
struct SwitchAnimationPresentation: Equatable, Sendable {
    let id: UInt
    let mode: SwitchAnimationMode
    let scheme: CandidateColorScheme
}

/// The whole D24/D26 visual: appearance, animation, duration, canvas, and caret anchoring
/// live in this one file, so replacing HAL's visual language means replacing this file and
/// nothing else. The stamp shows the user's artwork in the middle — the tennis ball is only
/// the default one — with the mode badge pinned to its top-right corner (D26).
struct SwitchAnimationEffect: View {
    /// Infrastructure reads these two values, but owns neither.
    /// Room for the plate, the badge hanging off its corner, and both their shadows.
    static let canvasSize = CGSize(width: 148, height: 120)
    static let visibilityDuration: TimeInterval = 0.92

    let presentation: SwitchAnimationPresentation
    /// nil is the built-in ball: the user has no artwork, or theirs stopped loading (D26).
    let artwork: NSImage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        StampEffect(presentation: presentation, artwork: artwork, reduceMotion: reduceMotion)
            .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
            .accessibilityHidden(true)
    }

    /// Centers the stamp on the caret and drops it just below the input line, mirroring
    /// above when the bottom edge is in the way. Clamped so it never leaves the screen.
    static func origin(for caret: CGRect, in visibleFrame: CGRect) -> CGPoint {
        let below = caret.minY - Metrics.caretGap - canvasSize.height
        let y = below >= visibleFrame.minY ? below : caret.maxY + Metrics.caretGap
        let proposed = CGPoint(x: caret.minX - canvasSize.width / 2, y: y)
        return CGPoint(
            x: min(max(proposed.x, visibleFrame.minX),
                   max(visibleFrame.minX, visibleFrame.maxX - canvasSize.width)),
            y: min(max(proposed.y, visibleFrame.minY),
                   max(visibleFrame.minY, visibleFrame.maxY - canvasSize.height))
        )
    }
}

private enum Metrics {
    static let plate: CGFloat = 84
    static let artwork: CGFloat = 58
    /// The built-in ball stays the small mark it has always been, rather than being blown
    /// up to fill the plate like a piece of artwork.
    static let ball: CGFloat = 34
    static let corner: CGFloat = 22
    static let caretGap: CGFloat = 8
    static let badgeOffset = CGSize(width: 11, height: -9)
}

// MARK: - Stamp

private struct StampEffect: View {
    let presentation: SwitchAnimationPresentation
    let artwork: NSImage?
    let reduceMotion: Bool

    @State private var trigger: UInt = 0

    var body: some View {
        Color.clear
            .frame(width: SwitchAnimationEffect.canvasSize.width,
                   height: SwitchAnimationEffect.canvasSize.height)
            .keyframeAnimator(initialValue: StampMotion.start, trigger: trigger) { content, motion in
                content.overlay {
                    StampFrame(presentation: presentation,
                               artwork: artwork,
                               motion: reduceMotion ? motion.withoutMotion : motion)
                }
            } keyframes: { _ in
                KeyframeTrack(\.plateScale) {
                    SpringKeyframe(1.06, duration: 0.20)
                    SpringKeyframe(1, duration: 0.14)
                    LinearKeyframe(1, duration: 0.40)
                    CubicKeyframe(0.96, duration: 0.18)
                }
                KeyframeTrack(\.plateOpacity) {
                    LinearKeyframe(1, duration: 0.10)
                    LinearKeyframe(1, duration: 0.60)
                    CubicKeyframe(0, duration: 0.22)
                }
                KeyframeTrack(\.plateRotation) {
                    SpringKeyframe(1.5, duration: 0.20)
                    SpringKeyframe(0, duration: 0.16)
                    LinearKeyframe(0, duration: 0.56)
                }
                KeyframeTrack(\.badgeScale) {
                    LinearKeyframe(0.7, duration: 0.12)
                    SpringKeyframe(1.12, duration: 0.14)
                    SpringKeyframe(1, duration: 0.12)
                    LinearKeyframe(1, duration: 0.36)
                    CubicKeyframe(0.96, duration: 0.18)
                }
                KeyframeTrack(\.badgeOpacity) {
                    LinearKeyframe(0, duration: 0.12)
                    CubicKeyframe(1, duration: 0.10)
                    LinearKeyframe(1, duration: 0.48)
                    CubicKeyframe(0, duration: 0.22)
                }
                KeyframeTrack(\.glowScale) {
                    LinearKeyframe(0.72, duration: 0.04)
                    CubicKeyframe(1.2, duration: 0.30)
                    LinearKeyframe(1.2, duration: 0.58)
                }
                KeyframeTrack(\.glowOpacity) {
                    LinearKeyframe(0.85, duration: 0.06)
                    CubicKeyframe(0.34, duration: 0.24)
                    LinearKeyframe(0.34, duration: 0.40)
                    CubicKeyframe(0, duration: 0.22)
                }
            }
            .onChange(of: presentation.id, initial: true) { _, id in
                trigger = id
            }
    }
}

private struct StampMotion {
    var plateScale: CGFloat
    var plateOpacity: CGFloat
    var plateRotation: CGFloat
    var badgeScale: CGFloat
    var badgeOpacity: CGFloat
    var glowScale: CGFloat
    var glowOpacity: CGFloat

    static let start = StampMotion(plateScale: 0.62, plateOpacity: 0, plateRotation: -7,
                                   badgeScale: 0.7, badgeOpacity: 0,
                                   glowScale: 0.72, glowOpacity: 0)

    /// Reduce Motion keeps the fade and drops everything that moves (D24).
    var withoutMotion: StampMotion {
        StampMotion(plateScale: 1, plateOpacity: plateOpacity, plateRotation: 0,
                    badgeScale: 1, badgeOpacity: badgeOpacity,
                    glowScale: 1, glowOpacity: glowOpacity * 0.6)
    }
}

private struct StampFrame: View {
    let presentation: SwitchAnimationPresentation
    let artwork: NSImage?
    let motion: StampMotion

    private var accentStart: Color { presentation.scheme.accentStart.feedbackColor }
    private var accentEnd: Color { presentation.scheme.accentEnd.feedbackColor }
    private var glow: Color { presentation.scheme.glow.feedbackColor }
    private var accent: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            RadialGradient(colors: [glow.opacity(0.85), glow.opacity(0)],
                           center: .center, startRadius: 2, endRadius: Metrics.plate * 0.78)
                .frame(width: Metrics.plate * 1.5, height: Metrics.plate * 1.5)
                .scaleEffect(motion.glowScale)
                .opacity(motion.glowOpacity)
            plate
                .overlay(alignment: .topTrailing) {
                    ModeBadge(mode: presentation.mode, accent: accent, glow: glow)
                        .scaleEffect(motion.badgeScale)
                        .opacity(motion.badgeOpacity)
                        .offset(x: Metrics.badgeOffset.width, y: Metrics.badgeOffset.height)
                }
                .scaleEffect(motion.plateScale)
                .rotationEffect(.degrees(Double(motion.plateRotation)))
                .opacity(motion.plateOpacity)
        }
        .frame(width: SwitchAnimationEffect.canvasSize.width,
               height: SwitchAnimationEffect.canvasSize.height)
    }

    /// The artwork always lands on the same glass plate: a transparent PNG over a busy
    /// window is unreadable without one, and it keeps HAL's own surfaces recognizable.
    private var plate: some View {
        ArtworkMark(mode: presentation.mode,
                    artwork: artwork,
                    accent: accent,
                    glow: glow,
                    size: artwork == nil ? Metrics.ball : Metrics.artwork)
            .frame(width: Metrics.plate, height: Metrics.plate)
            .background {
                RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                            .fill(.black.opacity(0.3))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                            .strokeBorder(accent.opacity(0.7), lineWidth: 1)
                    }
            }
            .compositingGroup()
            .shadow(color: glow.opacity(0.6), radius: 10)
    }
}

// MARK: - Skin pieces

private struct ArtworkMark: View {
    let mode: SwitchAnimationMode
    let artwork: NSImage?
    let accent: LinearGradient
    let glow: Color
    let size: CGFloat

    var body: some View {
        Group {
            if let artwork {
                // The user's own colors, untouched — the accent still owns everything
                // around it (D26).
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: mode.ballSymbol)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(accent)
                    .shadow(color: glow.opacity(0.9), radius: 5)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct ModeBadge: View {
    let mode: SwitchAnimationMode
    let accent: LinearGradient
    let glow: Color

    var body: some View {
        Text(mode.label)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 23)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay { Capsule().fill(.black.opacity(0.34)) }
                    .overlay { Capsule().strokeBorder(accent.opacity(0.85), lineWidth: 1) }
            }
            .compositingGroup()
            .shadow(color: glow.opacity(0.75), radius: 8)
    }
}

private extension SwitchAnimationMode {
    var label: String {
        switch self {
        case .chinese: return "中"
        case .english: return "EN"
        case .englishAssist: return "EN+"
        }
    }

    var ballSymbol: String {
        switch self {
        case .chinese: return "tennisball.fill"
        case .english, .englishAssist: return "tennisball"
        }
    }
}

private extension RGB {
    var feedbackColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}
