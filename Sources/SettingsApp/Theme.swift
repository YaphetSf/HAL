import SwiftUI

// Design language for the HAL control center (2026-08-27): a graphite canvas with slowly
// drifting light blobs behind floating glass panes, and accents made of metal-edged glass
// rather than flat fills. Every accent still derives from the user's candidate-window scheme
// (D21), so picking "Ember" in Appearance re-tints the whole app live — the default is now
// "Mono", which turns the same machinery into brushed silver. Motion is intentionally
// generous here — this app never sits in the typing path, and every endless animation is
// gated on Reduce Motion.

extension RGB {
    /// Mixes toward white. The specular band in `accentGradient` is built from this, which
    /// is what separates metal from a flat two-stop ramp.
    func lightened(_ amount: Double) -> Color {
        Color(red: red + (1 - red) * amount,
              green: green + (1 - green) * amount,
              blue: blue + (1 - blue) * amount)
    }
}

extension CandidateColorScheme {
    /// The gradient used for icon tiles, pills, and hero accents. Four stops, not two: the
    /// bright band a third of the way across is the whole difference between "grey" and
    /// "silver" once the Mono preset is selected.
    var accentGradient: LinearGradient {
        LinearGradient(stops: [
            .init(color: accentStart.color, location: 0.0),
            .init(color: accentEnd.lightened(0.62), location: 0.34),
            .init(color: accentStart.lightened(0.08), location: 0.63),
            .init(color: accentEnd.color, location: 1.0)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Rim light for glass edges. Bright where the light lands, gone on the far side — a
    /// uniform hairline reads as plastic.
    var rim: LinearGradient {
        LinearGradient(colors: [.white.opacity(0.90), .white.opacity(0.30), .white.opacity(0.06)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    /// An accent tile: a scheme-tinted metal plate with Liquid Glass over it and a rim on
    /// top. Replaces a plain `fill(accentGradient)`, which had no depth to it.
    func accentGlass(_ scheme: CandidateColorScheme,
                     corner: CGFloat,
                     glowing: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return background(shape.fill(scheme.accentGradient.opacity(glowing ? 0.62 : 0.46)))
            .glassEffect(.regular.tint(scheme.accentEnd.color.opacity(glowing ? 0.30 : 0.20)),
                         in: shape)
            .overlay(shape.strokeBorder(scheme.rim, lineWidth: 1))
    }
}

// MARK: - Ambient background

/// The dark canvas with drifting blobs behind the glass panes. Blob colors follow the
/// scheme so the ambient light always matches the candidate window.
struct AmbientBackground: View {
    let scheme: CandidateColorScheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.105, green: 0.114, blue: 0.140),
                                    Color(red: 0.042, green: 0.047, blue: 0.065)],
                           startPoint: .top, endPoint: .bottom)
            Blob(color: scheme.accentStart.color, size: 620,
                 relativeCenter: CGPoint(x: 0.04, y: 0.04),
                 drift: CGSize(width: 48, height: 26), duration: 27)
            Blob(color: scheme.accentEnd.color, size: 520,
                 relativeCenter: CGPoint(x: 0.86, y: 0.1),
                 drift: CGSize(width: -54, height: 34), duration: 33)
            Blob(color: scheme.glow.color, size: 640,
                 relativeCenter: CGPoint(x: 0.46, y: 0.96),
                 drift: CGSize(width: 58, height: -40), duration: 39)
            Blob(color: Color(red: 0.82, green: 0.88, blue: 1.0), size: 560,
                 relativeCenter: CGPoint(x: 0.70, y: 0.42),
                 drift: CGSize(width: -34, height: 44), duration: 45)
        }
        .ignoresSafeArea()
    }
}

/// One blurred color blob slowly ping-ponging around its anchor.
private struct Blob: View {
    let color: Color
    let size: CGFloat
    let relativeCenter: CGPoint
    let drift: CGSize
    let duration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifted = false

    var body: some View {
        GeometryReader { proxy in
            Circle()
                .fill(color.opacity(0.26))
                .blur(radius: 90)
                .frame(width: size, height: size)
                .position(x: proxy.size.width * relativeCenter.x + (drifted ? drift.width : 0),
                          y: proxy.size.height * relativeCenter.y + (drifted ? drift.height : 0))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                drifted = true
            }
        }
    }
}

// MARK: - Glass surfaces

/// A frosted card floating over the ambient background.
struct GlassCardModifier: ViewModifier {
    var corner: CGFloat = 16

    /// Hue lock: raw `ultraThinMaterial` adopts whatever color the desktop wallpaper has
    /// behind the window (a green scene made the whole app look green), so a navy veil
    /// keeps the glass on-palette while it still blurs the ambient blobs.
    private static let veil = Color(red: 0.075, green: 0.082, blue: 0.105).opacity(0.18)

    /// A sheen down the face of the pane. Without it a frosted rectangle reads as a slab;
    /// with it the pane catches the same light as the rim.
    private static let sheen = LinearGradient(
        colors: [.white.opacity(0.10), .white.opacity(0.02), .clear],
        startPoint: .top, endPoint: .bottom)

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return content
            .background(
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Self.veil))
                    .overlay(shape.fill(Self.sheen))
            )
            .overlay(shape.strokeBorder(
                LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.18),
                                        .white.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}

extension View {
    func glassCard(corner: CGFloat = 16) -> some View {
        modifier(GlassCardModifier(corner: corner))
    }
}

/// Hover lift + accent glow for clickable cards.
struct HoverLiftModifier: ViewModifier {
    var glow: Color

    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering ? 1.015 : 1)
            .shadow(color: glow.opacity(hovering ? 0.45 : 0), radius: hovering ? 20 : 0, y: 5)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift(glow: Color) -> some View {
        modifier(HoverLiftModifier(glow: glow))
    }
}

/// Capsule-shaped glass button used for secondary actions (Refresh, Reset).
struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(configuration.isPressed ? 0.05 : 0.12)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.26, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Shared atoms

/// A small capsule for a single fact — a version string, a licence name.
struct InfoChip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white.opacity(0.62))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.white.opacity(0.06)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}

/// A physical-key style cap for shortcut rows.
struct Keycap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [.white.opacity(0.17), .white.opacity(0.06)],
                                         startPoint: .top, endPoint: .bottom))
            )
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
    }
}

/// A text-field caret that blinks while the preview is idle.
struct BlinkingCaret: View {
    var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(tint)
            .frame(width: 2, height: 18)
            .opacity(visible ? 1 : 0)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}

/// A mock host-app text field holding a partial word, used above candidate previews.
struct MockInputField: View {
    let text: String
    var tint: Color

    var body: some View {
        HStack(spacing: 1) {
            Text(text)
                .font(.system(size: 17, design: .rounded))
                .foregroundStyle(.white.opacity(0.88))
            BlinkingCaret(tint: tint)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 340)
        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.38)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08), lineWidth: 1))
    }
}

/// HAL's brand mark, drawn everywhere in-app: the sidebar, About, the install hero. The
/// artwork is the one bundled logo SVG through BrandMark, and the App Icon is rendered from
/// the same file by scripts/generate-app-icon.swift.
struct HALMark: View {
    var body: some View {
        if let mark = BrandMark.image {
            Image(nsImage: mark)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .accessibilityHidden(true)
        }
    }
}
