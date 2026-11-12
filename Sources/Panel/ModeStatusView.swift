import SwiftUI

/// The menu bar mark: the brand artwork in full colour, active while HAL is the current
/// input source, with the mode spelled out beside it. While secure input keeps HAL out, the
/// icon of the app holding it stands in for the artwork (D31).
///
/// The mark is deliberately not a template — a template keeps only the alpha channel and
/// the artwork is uniformly opaque, which would leave a flat silhouette. Colour is how the
/// face reads at 14pt.
struct ModeStatusView: View {
    /// Fixed so the menu bar does not reflow every time the mode changes.
    static let width: CGFloat = 48

    private let state = ModeState.shared
    private let peripherals = PeripheralBatteryMonitor.shared

    var body: some View {
        let isAscii = state.isAscii
        let isActive = state.isActive
        let lowBattery = peripherals.hasLowBattery
        let label = isAscii ? (state.englishProfile == .assist ? "EN+" : "EN") : "中"
        let holder = isActive ? nil : state.secureInputHolder
        let holderIcon = holder?.icon
        // App icons carry their own margin, so they need 2pt more to match the mark.
        let markSide: CGFloat = holderIcon == nil ? 14 : 16
        let markIsLive = isActive || holderIcon != nil

        HStack(spacing: 4) {
            if let mark = holderIcon ?? BrandMark.menuBarImage {
                Image(nsImage: mark)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: markSide, height: markSide)
                    .saturation(markIsLive ? 1 : 0.25)
                    .overlay(alignment: .topTrailing) {
                        if lowBattery {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 5, height: 5)
                                .offset(x: 2, y: -2)
                        }
                    }
                    .opacity(markIsLive ? 1 : 0.55)
            }
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .strikethrough(!isActive)
                .contentTransition(.opacity)
                .opacity(isActive ? 1 : 0.55)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .animation(.snappy(duration: 0.22), value: isAscii)
        .animation(.snappy(duration: 0.22), value: state.englishProfile)
        .animation(.snappy(duration: 0.22), value: isActive)
        .animation(.snappy(duration: 0.22), value: holder?.pid)
        .accessibilityElement()
        .accessibilityLabel((isActive
            ? (isAscii
                ? (state.englishProfile == .assist ? "HAL, English Assist" : "HAL, English Direct")
                : "HAL, Chinese")
            : (holder.map { "HAL, secure input held by \($0.name)" } ?? "HAL, not the current input source"))
            + (lowBattery ? ", low battery" : ""))
        .accessibilityAddTraits(.isButton)
    }
}
