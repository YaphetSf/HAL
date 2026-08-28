import SwiftUI

/// The menu bar mark: the brand artwork in full colour, active while HAL is the current
/// input source, with the mode spelled out beside it.
///
/// The mark is deliberately not a template — a template keeps only the alpha channel and
/// the artwork is uniformly opaque, which would leave a flat silhouette. Colour is how the
/// face reads at 14pt.
struct ModeStatusView: View {
    /// Fixed so the menu bar does not reflow every time the mode changes.
    static let width: CGFloat = 48

    private let state = ModeState.shared

    var body: some View {
        let isAscii = state.isAscii
        let isActive = state.isActive
        let label = isAscii ? (state.englishProfile == .assist ? "EN+" : "EN") : "中"

        HStack(spacing: 4) {
            if let mark = BrandMark.menuBarImage {
                Image(nsImage: mark)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .saturation(isActive ? 1 : 0.25)
            }
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .strikethrough(!isActive)
                .contentTransition(.opacity)
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .opacity(isActive ? 1 : 0.55)
        .animation(.snappy(duration: 0.22), value: isAscii)
        .animation(.snappy(duration: 0.22), value: state.englishProfile)
        .animation(.snappy(duration: 0.22), value: isActive)
        .accessibilityElement()
        .accessibilityLabel(isActive
            ? (isAscii
                ? (state.englishProfile == .assist ? "HAL, English Assist" : "HAL, English Direct")
                : "HAL, Chinese")
            : "HAL, not the current input source")
        .accessibilityAddTraits(.isButton)
    }
}
