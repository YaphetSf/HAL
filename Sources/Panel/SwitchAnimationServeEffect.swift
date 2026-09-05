import SwiftUI

/// The original D24 tennis serve, kept as the skin behind the Tennis Serve toggle (D26).
/// Appearance, animation, duration, canvas and caret anchoring all live in this one file.
struct SwitchAnimationServeEffect: View {
    /// Infrastructure reads these three values, but owns none of them.
    static let canvasSize = CGSize(width: 150, height: 62)
    static let visibilityDuration: TimeInterval = 0.86

    let presentation: SwitchAnimationPresentation
    let horizontalDirection: SwitchAnimationHorizontalDirection
    let verticalDirection: SwitchAnimationVerticalDirection

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                ReducedSwitchAnimationEffect(presentation: presentation,
                                          horizontalDirection: horizontalDirection,
                                          verticalDirection: verticalDirection)
            } else {
                CaretServeEffect(presentation: presentation,
                                 horizontalDirection: horizontalDirection,
                                 verticalDirection: verticalDirection)
            }
        }
        .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        .accessibilityHidden(true)
    }

    /// Keeps the launch flare aligned with the caret and flips the serve toward whichever
    /// side of the screen has room. The effect normally sits just below the input line and
    /// mirrors above it when the bottom edge is in the way.
    static func placement(for caret: CGRect, in visibleFrame: CGRect) -> SwitchAnimationPlacement {
        let rightRoom = visibleFrame.maxX - caret.minX
        let leftRoom = caret.minX - visibleFrame.minX
        let horizontal: SwitchAnimationHorizontalDirection = rightRoom >= canvasSize.width * 0.82
            || rightRoom >= leftRoom ? .right : .left
        let launchX = horizontal == .right ? Metrics.launchInset
            : canvasSize.width - Metrics.launchInset

        let belowTrailScreenY = caret.minY - Metrics.caretGap
        let belowOriginY = belowTrailScreenY - canvasSize.height + Metrics.trailY
        let vertical: SwitchAnimationVerticalDirection = belowOriginY >= visibleFrame.minY
            ? .below : .above
        let trailY = vertical == .below ? Metrics.trailY
            : canvasSize.height - Metrics.trailY
        let trailScreenY = vertical == .below
            ? belowTrailScreenY
            : caret.maxY + Metrics.caretGap

        let proposed = CGPoint(x: caret.minX - launchX,
                               y: trailScreenY - canvasSize.height + trailY)
        let x = min(max(proposed.x, visibleFrame.minX),
                    max(visibleFrame.minX, visibleFrame.maxX - canvasSize.width))
        let y = min(max(proposed.y, visibleFrame.minY),
                    max(visibleFrame.minY, visibleFrame.maxY - canvasSize.height))
        return SwitchAnimationPlacement(origin: CGPoint(x: x, y: y),
                                     horizontalDirection: horizontal,
                                     verticalDirection: vertical)
    }
}

enum SwitchAnimationHorizontalDirection: Sendable {
    case left
    case right

    var sign: CGFloat { self == .right ? 1 : -1 }
}

enum SwitchAnimationVerticalDirection: Sendable {
    case above
    case below

    /// SwiftUI's positive y-axis points down within the panel.
    var contentSign: CGFloat { self == .below ? 1 : -1 }
}

struct SwitchAnimationPlacement: Sendable {
    let origin: CGPoint
    let horizontalDirection: SwitchAnimationHorizontalDirection
    let verticalDirection: SwitchAnimationVerticalDirection
}

private enum Metrics {
    static let launchInset: CGFloat = 24
    static let trailY: CGFloat = 18
    static let caretGap: CGFloat = 4
    static let travel: CGFloat = 44
    static let trailLength: CGFloat = 72
}

// MARK: - Full-motion experimental skin

private struct CaretServeEffect: View {
    let presentation: SwitchAnimationPresentation
    let horizontalDirection: SwitchAnimationHorizontalDirection
    let verticalDirection: SwitchAnimationVerticalDirection

    @State private var trigger: UInt = 0

    var body: some View {
        Color.clear
            .frame(width: SwitchAnimationServeEffect.canvasSize.width,
                   height: SwitchAnimationServeEffect.canvasSize.height)
            .keyframeAnimator(initialValue: ServeMotion(), trigger: trigger) { content, motion in
                content.overlay {
                    CaretServeFrame(presentation: presentation,
                                    horizontalDirection: horizontalDirection,
                                    verticalDirection: verticalDirection,
                                    motion: motion)
                }
            } keyframes: { _ in
                KeyframeTrack(\.ringScale) {
                    SpringKeyframe(1.25, duration: 0.13)
                    CubicKeyframe(1.85, duration: 0.17)
                    CubicKeyframe(2.05, duration: 0.48)
                }
                KeyframeTrack(\.ringOpacity) {
                    LinearKeyframe(0.95, duration: 0.05)
                    CubicKeyframe(0, duration: 0.25)
                    LinearKeyframe(0, duration: 0.48)
                }
                KeyframeTrack(\.trailScale) {
                    SpringKeyframe(1, duration: 0.18)
                    LinearKeyframe(1, duration: 0.34)
                    CubicKeyframe(0.62, duration: 0.12)
                    CubicKeyframe(0, duration: 0.14)
                }
                KeyframeTrack(\.trailOpacity) {
                    LinearKeyframe(1, duration: 0.07)
                    LinearKeyframe(1, duration: 0.43)
                    CubicKeyframe(0, duration: 0.28)
                }
                KeyframeTrack(\.ballTravel) {
                    SpringKeyframe(48, duration: 0.24)
                    SpringKeyframe(Metrics.travel, duration: 0.12)
                    LinearKeyframe(Metrics.travel, duration: 0.24)
                    CubicKeyframe(52, duration: 0.18)
                }
                KeyframeTrack(\.ballLift) {
                    CubicKeyframe(-9, duration: 0.11)
                    SpringKeyframe(2, duration: 0.13)
                    SpringKeyframe(0, duration: 0.12)
                    LinearKeyframe(0, duration: 0.42)
                }
                KeyframeTrack(\.ballScale) {
                    SpringKeyframe(1.12, duration: 0.14)
                    SpringKeyframe(1, duration: 0.16)
                    LinearKeyframe(1, duration: 0.10)
                    CubicKeyframe(0.72, duration: 0.12)
                    LinearKeyframe(0.72, duration: 0.26)
                }
                KeyframeTrack(\.ballOpacity) {
                    LinearKeyframe(1, duration: 0.04)
                    LinearKeyframe(1, duration: 0.34)
                    CubicKeyframe(0, duration: 0.10)
                    LinearKeyframe(0, duration: 0.30)
                }
                KeyframeTrack(\.badgeScale) {
                    LinearKeyframe(0.78, duration: 0.22)
                    SpringKeyframe(1.08, duration: 0.13)
                    SpringKeyframe(1, duration: 0.13)
                    LinearKeyframe(1, duration: 0.18)
                    CubicKeyframe(0.94, duration: 0.12)
                }
                KeyframeTrack(\.badgeOpacity) {
                    LinearKeyframe(0, duration: 0.20)
                    CubicKeyframe(1, duration: 0.11)
                    LinearKeyframe(1, duration: 0.29)
                    CubicKeyframe(0, duration: 0.18)
                }
                KeyframeTrack(\.sparkScale) {
                    LinearKeyframe(0.2, duration: 0.22)
                    SpringKeyframe(1.15, duration: 0.12)
                    CubicKeyframe(1.55, duration: 0.18)
                    LinearKeyframe(1.55, duration: 0.26)
                }
                KeyframeTrack(\.sparkOpacity) {
                    LinearKeyframe(0, duration: 0.22)
                    LinearKeyframe(1, duration: 0.08)
                    CubicKeyframe(0, duration: 0.24)
                    LinearKeyframe(0, duration: 0.24)
                }
                KeyframeTrack(\.sparkRotation) {
                    LinearKeyframe(0, duration: 0.20)
                    CubicKeyframe(38, duration: 0.34)
                    LinearKeyframe(38, duration: 0.24)
                }
            }
            .onChange(of: presentation.id, initial: true) { _, id in
                trigger = id
            }
    }
}

private struct ServeMotion {
    var ringScale: CGFloat = 0.22
    var ringOpacity: CGFloat = 0
    var trailScale: CGFloat = 0.02
    var trailOpacity: CGFloat = 0
    var ballTravel: CGFloat = 0
    var ballLift: CGFloat = 0
    var ballScale: CGFloat = 0.3
    var ballOpacity: CGFloat = 0
    var badgeScale: CGFloat = 0.78
    var badgeOpacity: CGFloat = 0
    var sparkScale: CGFloat = 0.2
    var sparkOpacity: CGFloat = 0
    var sparkRotation: CGFloat = 0
}

private struct CaretServeFrame: View {
    let presentation: SwitchAnimationPresentation
    let horizontalDirection: SwitchAnimationHorizontalDirection
    let verticalDirection: SwitchAnimationVerticalDirection
    let motion: ServeMotion

    private var horizontalSign: CGFloat { horizontalDirection.sign }
    private var verticalSign: CGFloat { verticalDirection.contentSign }
    private var launchX: CGFloat {
        horizontalDirection == .right ? Metrics.launchInset
            : SwitchAnimationServeEffect.canvasSize.width - Metrics.launchInset
    }
    private var trailY: CGFloat {
        verticalDirection == .below ? Metrics.trailY
            : SwitchAnimationServeEffect.canvasSize.height - Metrics.trailY
    }
    private var landingX: CGFloat { launchX + horizontalSign * Metrics.travel }
    private var badgeY: CGFloat { trailY + verticalSign * 20 }
    private var accentStart: Color { presentation.scheme.accentStart.feedbackColor }
    private var accentEnd: Color { presentation.scheme.accentEnd.feedbackColor }
    private var glow: Color { presentation.scheme.glow.feedbackColor }
    private var accent: LinearGradient {
        LinearGradient(colors: [accentStart, accentEnd],
                       startPoint: horizontalDirection == .right ? .leading : .trailing,
                       endPoint: horizontalDirection == .right ? .trailing : .leading)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            trailGlow
            launchPulse
            flyingBall
            ModeBadge(mode: presentation.mode,
                      accent: accent,
                      glow: glow)
                .scaleEffect(motion.badgeScale)
                .opacity(motion.badgeOpacity)
                .position(x: landingX + horizontalSign * 10, y: badgeY)
            sparkBurst
        }
        .frame(width: SwitchAnimationServeEffect.canvasSize.width,
               height: SwitchAnimationServeEffect.canvasSize.height)
    }

    private var trailGlow: some View {
        ZStack {
            Capsule()
                .fill(glow.opacity(0.68))
                .frame(width: Metrics.trailLength, height: 8)
                .blur(radius: 5)
            Capsule()
                .fill(accent)
                .frame(width: Metrics.trailLength, height: 2.4)
            Capsule()
                .fill(.white.opacity(0.9))
                .frame(width: Metrics.trailLength * 0.34, height: 0.8)
                .offset(x: -horizontalSign * Metrics.trailLength * 0.22)
        }
        .scaleEffect(x: motion.trailScale,
                     y: 1,
                     anchor: horizontalDirection == .right ? .leading : .trailing)
        .opacity(motion.trailOpacity)
        .position(x: launchX + horizontalSign * Metrics.trailLength / 2,
                  y: trailY)
    }

    private var launchPulse: some View {
        ZStack {
            Circle()
                .stroke(accent, lineWidth: 1.4)
                .frame(width: 20, height: 20)
                .scaleEffect(motion.ringScale)
                .opacity(motion.ringOpacity)
            Capsule()
                .fill(accent)
                .frame(width: 2.2, height: 18)
                .shadow(color: glow.opacity(0.9), radius: 5)
                .opacity(max(motion.trailOpacity, motion.ringOpacity))
        }
        .position(x: launchX, y: trailY)
    }

    private var flyingBall: some View {
        BallMark(mode: presentation.mode,
                 accent: accent,
                 glow: glow,
                 size: 18)
            .scaleEffect(motion.ballScale)
            .rotationEffect(.degrees(Double(horizontalSign * motion.ballTravel * 7)))
            .opacity(motion.ballOpacity)
            .position(x: launchX + horizontalSign * motion.ballTravel,
                      y: trailY + verticalSign * motion.ballLift)
    }

    private var sparkBurst: some View {
        ZStack {
            ForEach(Spark.all) { spark in
                Circle()
                    .fill(spark.usesEndColor ? accentEnd : accentStart)
                    .frame(width: spark.size, height: spark.size)
                    .offset(x: spark.offset.width, y: spark.offset.height * verticalSign)
            }
        }
        .scaleEffect(motion.sparkScale)
        .rotationEffect(.degrees(Double(horizontalSign * motion.sparkRotation)))
        .opacity(motion.sparkOpacity)
        .position(x: landingX, y: badgeY)
        .shadow(color: glow.opacity(0.8), radius: 4)
    }
}

private struct Spark: Identifiable {
    let id: Int
    let offset: CGSize
    let size: CGFloat
    let usesEndColor: Bool

    static let all = [
        Spark(id: 0, offset: CGSize(width: -14, height: -8), size: 3, usesEndColor: false),
        Spark(id: 1, offset: CGSize(width: 3, height: -14), size: 2, usesEndColor: true),
        Spark(id: 2, offset: CGSize(width: 15, height: -5), size: 2.5, usesEndColor: false),
        Spark(id: 3, offset: CGSize(width: 13, height: 10), size: 2, usesEndColor: true),
    ]
}

// MARK: - Reduced Motion

private struct ReducedSwitchAnimationEffect: View {
    let presentation: SwitchAnimationPresentation
    let horizontalDirection: SwitchAnimationHorizontalDirection
    let verticalDirection: SwitchAnimationVerticalDirection

    @State private var trigger: UInt = 0

    var body: some View {
        let mode = presentation.mode
        let accent = LinearGradient(colors: [presentation.scheme.accentStart.feedbackColor,
                                              presentation.scheme.accentEnd.feedbackColor],
                                    startPoint: .leading,
                                    endPoint: .trailing)
        let glow = presentation.scheme.glow.feedbackColor
        let badgeX: CGFloat = horizontalDirection == .right ? 68 : 82
        let badgeY: CGFloat = verticalDirection == .below ? 38 : 24

        Color.clear
            .frame(width: SwitchAnimationServeEffect.canvasSize.width,
                   height: SwitchAnimationServeEffect.canvasSize.height)
            .keyframeAnimator(initialValue: CGFloat.zero, trigger: trigger) { content, opacity in
                content.overlay {
                    ModeBadge(mode: mode,
                              accent: accent,
                              glow: glow)
                        .opacity(opacity)
                        .position(x: badgeX, y: badgeY)
                }
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(1, duration: 0.12)
                    LinearKeyframe(1, duration: 0.38)
                    CubicKeyframe(0, duration: 0.20)
                }
            }
            .onChange(of: presentation.id, initial: true) { _, id in
                trigger = id
            }
    }
}

// MARK: - Skin pieces

private struct ModeBadge: View {
    let mode: SwitchAnimationMode
    let accent: LinearGradient
    let glow: Color

    var body: some View {
        HStack(spacing: 5) {
            BallMark(mode: mode,
                     accent: accent,
                     glow: glow,
                     size: 13)
            Text(mode.label)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 8)
        .frame(height: 27)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule().fill(.black.opacity(0.28))
                }
                .overlay {
                    Capsule().strokeBorder(accent.opacity(0.78), lineWidth: 1)
                }
        }
        .compositingGroup()
        .shadow(color: glow.opacity(0.72), radius: 9)
    }
}

private struct BallMark: View {
    let mode: SwitchAnimationMode
    let accent: LinearGradient
    let glow: Color
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: mode.ballSymbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(accent)
                .shadow(color: glow.opacity(0.9), radius: 4)
            if mode == .englishAssist {
                Text("+")
                    .font(.system(size: max(6, size * 0.46), weight: .black,
                                  design: .rounded))
                    .foregroundStyle(.white)
                    .offset(x: size * 0.24, y: -size * 0.24)
            }
        }
        .frame(width: size, height: size)
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

#Preview("Caret serve") {
    ZStack {
        Color.black
        SwitchAnimationServeEffect(
            presentation: SwitchAnimationPresentation(id: 1,
                                                   mode: .englishAssist,
                                                   scheme: .aurora),
            horizontalDirection: .right,
            verticalDirection: .below
        )
    }
    .frame(width: SwitchAnimationServeEffect.canvasSize.width,
           height: SwitchAnimationServeEffect.canvasSize.height)
}
