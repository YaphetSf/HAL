import SwiftUI

// HAL draws its own palette (2026-08-28). The system `ColorPicker` was pulled out because
// its well hands the click to AppKit: the picker opens in a window of its own, anchored to
// the NSView backing the well. Inside the scheme editor that anchor resolved to the screen
// origin, so the palette kept opening in the bottom-left corner of the display instead of
// beside the swatch. Drawing hue/saturation/brightness ourselves keeps every pixel of the
// palette inside the pane the user clicked in, and it matches the rest of the control
// center instead of dropping a stock grey panel on top of it.

/// Which of a scheme's three colors the palette is currently shaping.
private enum PaletteChannel: String, CaseIterable, Identifiable {
    case accentStart
    case accentEnd
    case glow

    var id: Self { self }

    var title: String {
        switch self {
        case .accentStart: return "Start"
        case .accentEnd: return "End"
        case .glow: return "Glow"
        }
    }

    var keyPath: WritableKeyPath<CandidateColorScheme.CustomColors, RGB> {
        switch self {
        case .accentStart: return \.accentStart
        case .accentEnd: return \.accentEnd
        case .glow: return \.glow
        }
    }
}

/// Hue / saturation / brightness, kept as the palette's own state so a color dragged down
/// to black or grey still remembers which hue it came from — RGB alone cannot say.
struct HSB: Equatable {
    var hue: Double
    var saturation: Double
    var brightness: Double

    init(hue: Double, saturation: Double, brightness: Double) {
        self.hue = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    init(_ rgb: RGB) {
        let high = max(rgb.red, rgb.green, rgb.blue)
        let low = min(rgb.red, rgb.green, rgb.blue)
        let span = high - low
        var hue = 0.0
        if span > 0 {
            if high == rgb.red {
                hue = (rgb.green - rgb.blue) / span
            } else if high == rgb.green {
                hue = 2 + (rgb.blue - rgb.red) / span
            } else {
                hue = 4 + (rgb.red - rgb.green) / span
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        self.init(hue: hue, saturation: high == 0 ? 0 : span / high, brightness: high)
    }

    var rgb: RGB {
        let scaled = hue * 6
        let sector = Int(scaled.rounded(.down)) % 6
        let offset = scaled - scaled.rounded(.down)
        let dim = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * offset)
        let rising = brightness * (1 - saturation * (1 - offset))
        switch sector {
        case 0: return RGB(red: brightness, green: rising, blue: dim)
        case 1: return RGB(red: falling, green: brightness, blue: dim)
        case 2: return RGB(red: dim, green: brightness, blue: rising)
        case 3: return RGB(red: dim, green: falling, blue: brightness)
        case 4: return RGB(red: rising, green: dim, blue: brightness)
        default: return RGB(red: brightness, green: dim, blue: falling)
        }
    }

    var color: Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

extension RGB {
    var hexString: String {
        func channel(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }
}

/// The palette itself: pick one of the scheme's three colors on the left, shape it on the
/// right. `onCommit` fires once per gesture, not once per pixel, so a drag re-tints the app
/// live but only touches Settings.json when the mouse comes up.
struct PaletteEditor: View {
    @Binding var colors: CandidateColorScheme.CustomColors
    let onCommit: () -> Void

    @State private var channel: PaletteChannel = .accentStart
    @State private var hsb: HSB

    init(colors: Binding<CandidateColorScheme.CustomColors>, onCommit: @escaping () -> Void) {
        _colors = colors
        self.onCommit = onCommit
        _hsb = State(initialValue: HSB(colors.wrappedValue.accentStart))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EDIT COLORS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    ForEach(PaletteChannel.allCases) { swatch($0) }
                    hex
                    Spacer(minLength: 0)
                }
                .frame(width: 124)
                VStack(spacing: 10) {
                    SaturationBrightnessField(hsb: hsb, update: apply)
                    HueSlider(hsb: hsb, update: apply)
                }
            }
        }
        // The control center re-tints itself over 0.9s whenever the scheme changes, which
        // is right for picking a preset and wrong for a drag: the knob has to sit under
        // the cursor, not ease toward it.
        .transaction { $0.animation = nil }
    }

    private var hex: some View {
        Text(colors[keyPath: channel.keyPath].hexString)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.66))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.05)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 1))
    }

    private func swatch(_ item: PaletteChannel) -> some View {
        let isSelected = channel == item
        return Button {
            channel = item
            hsb = HSB(colors[keyPath: item.keyPath])
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(colors[keyPath: item.keyPath].color)
                    .frame(width: 18, height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.white.opacity(0.28), lineWidth: 1))
                Text(item.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Color.white.opacity(0.55))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(isSelected ? 0.10 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white.opacity(isSelected ? 0.24 : 0.08), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One write path for both controls: local HSB first (so the knob tracks the cursor
    /// with no round trip), then the scheme, then the disk once the gesture ends.
    private func apply(_ next: HSB, isFinal: Bool) {
        hsb = next
        colors[keyPath: channel.keyPath] = next.rgb
        if isFinal { onCommit() }
    }
}

/// The square: saturation left to right, brightness top to bottom, over the live hue.
private struct SaturationBrightnessField: View {
    let hsb: HSB
    let update: (HSB, Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                Rectangle().fill(Color(hue: hsb.hue, saturation: 1, brightness: 1))
                LinearGradient(colors: [.white, .white.opacity(0)],
                               startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.black.opacity(0), .black],
                               startPoint: .top, endPoint: .bottom)
                Knob(color: hsb.color)
                    .position(x: hsb.saturation * size.width,
                              y: (1 - hsb.brightness) * size.height)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { move($0.location, in: size, isFinal: false) }
                .onEnded { move($0.location, in: size, isFinal: true) })
        }
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    private func move(_ point: CGPoint, in size: CGSize, isFinal: Bool) {
        var next = hsb
        next.saturation = clamped(point.x / max(size.width, 1))
        next.brightness = 1 - clamped(point.y / max(size.height, 1))
        update(next, isFinal)
    }
}

/// The spectrum rail. The knob is inset by its own radius so it never hangs off the ends.
private struct HueSlider: View {
    let hsb: HSB
    let update: (HSB, Bool) -> Void

    private static let radius: CGFloat = 9
    private static let spectrum = stride(from: 0.0, through: 1.0, by: 1.0 / 12)
        .map { Color(hue: $0, saturation: 1, brightness: 1) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let track = max(width - Self.radius * 2, 1)
            ZStack {
                Capsule()
                    .fill(LinearGradient(colors: Self.spectrum,
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
                Knob(color: Color(hue: hsb.hue, saturation: 1, brightness: 1))
                    .position(x: Self.radius + hsb.hue * track, y: proxy.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { move($0.location.x, track: track, isFinal: false) }
                .onEnded { move($0.location.x, track: track, isFinal: true) })
        }
        .frame(height: 18)
    }

    private func move(_ x: CGFloat, track: CGFloat, isFinal: Bool) {
        var next = hsb
        next.hue = clamped((x - Self.radius) / track)
        update(next, isFinal)
    }
}

/// The draggable marker shared by both controls: the picked color under a white ring.
private struct Knob: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 16, height: 16)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
    }
}

private func clamped(_ value: CGFloat) -> Double {
    Double(min(max(value, 0), 1))
}
