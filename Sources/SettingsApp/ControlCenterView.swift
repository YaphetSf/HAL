import Carbon.HIToolbox
import SwiftUI

/// Root of HAL's control center: ambient canvas, a floating glass sidebar, and a floating
/// content pane. Page set: Home / Appearance / Fuzzy / Weights / English / About (D21, D23, M8).
struct ControlCenterView: View {
    enum Destination: String, CaseIterable, Identifiable {
        case home
        case appearance
        case fuzzy
        case weights
        case english
        case aiEdit
        case about

        var id: Self { self }

        var title: String {
            switch self {
            case .home: "Home"
            case .appearance: "Appearance"
            case .fuzzy: "Fuzzy Pinyin"
            case .weights: "Weights"
            case .english: "EN+"
            case .aiEdit: "AI Editing"
            case .about: "About"
            }
        }

        var systemImage: String {
            switch self {
            case .home: "house"
            case .appearance: "paintpalette"
            case .fuzzy: "character.magnify"
            case .weights: "arrow.up.arrow.down"
            case .english: "text.bubble"
            case .aiEdit: "arrow.2.squarepath"
            case .about: "info.circle"
            }
        }
    }

    @State private var selection: Destination = .home
    /// Single source of truth for the app-wide accent; Appearance writes it and everything
    /// re-tints live (user decision, 2026-08-26).
    @State private var scheme: CandidateColorScheme = SettingsStore.load().candidateColorScheme

    var body: some View {
        ZStack {
            AmbientBackground(scheme: scheme)
            HStack(spacing: 0) {
                Sidebar(selection: $selection, scheme: scheme)
                    .frame(width: 236)
                    .glassCard()
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .padding(.leading, 12)
                pane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .glassCard()
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .padding(.trailing, 12)
                    .padding(.leading, 12)
            }
        }
        .tint(scheme.accentStart.color)
        .animation(.spring(response: 0.42, dampingFraction: 0.85), value: selection)
        .animation(.easeInOut(duration: 0.9), value: scheme)
        .frame(minWidth: 860, minHeight: 560)
    }

    /// The active page. Re-keying on `selection` remounts the page so entrance animations
    /// replay and the slide transition fires.
    private var pane: some View {
        Group {
            switch selection {
            case .home: HomeView(scheme: scheme)
            case .appearance: AppearanceSettingsView(scheme: $scheme)
            case .fuzzy: FuzzySettingsView(scheme: scheme)
            case .weights: WeightsSettingsView(scheme: scheme)
            case .english: EnglishSettingsView(scheme: scheme)
            case .aiEdit: AIEditSettingsView(scheme: scheme)
            case .about: AboutView(scheme: scheme)
            }
        }
        .id(selection)
        // Pages travel vertically (user rule, 2026-08-26): the incoming page rises from
        // below while the outgoing one exits through the top.
        .transition(.asymmetric(
            insertion: .move(edge: .bottom)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.97)),
            removal: .move(edge: .top)
                .combined(with: .opacity)
                .combined(with: .scale(scale: 0.99))
        ))
    }
}

private struct Sidebar: View {
    @Binding var selection: ControlCenterView.Destination
    let scheme: CandidateColorScheme

    @Namespace private var selectionPill
    @State private var isActivated = false

    private static let liveGreen = Color(red: 0.20, green: 0.82, blue: 0.40)
    private static let offRed = Color(red: 1.0, green: 0.34, blue: 0.31)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 11) {
                HALMark()
                    .frame(width: 40, height: 40)
                Text("HAL")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
            .padding(.top, 48)   // keeps clear of the traffic lights
            .padding(.bottom, 18)

            ForEach(ControlCenterView.Destination.allCases) { destination in
                row(destination)
            }

            Spacer(minLength: 12)

            activation
        }
        .frame(maxHeight: .infinity)
        .onAppear { isActivated = HALInputSourceStatus.isEnabled }
        .onReceive(DistributedNotificationCenter.default().publisher(
            for: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String))) { _ in
            withAnimation(.easeInOut(duration: 0.3)) {
                isActivated = HALInputSourceStatus.isEnabled
            }
        }
    }

    /// Read-only light: is HAL switched on in the system's input source list right now.
    /// Only System Settings can flip it — macOS lets an app disable its own input source but
    /// silently refuses to enable one, so a switch here would be a button that half works.
    private var activation: some View {
        HStack(spacing: 9) {
            let light = isActivated ? Self.liveGreen : Self.offRed
            Circle()
                .fill(light)
                .frame(width: 9, height: 9)
                .shadow(color: light.opacity(isActivated ? 0.85 : 0.5), radius: 4)
            Text(isActivated ? "Activated" : "Deactivated")
                .font(.system(.caption, design: .rounded).weight(.medium))
                .foregroundStyle(.white.opacity(isActivated ? 0.75 : 0.45))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func row(_ destination: ControlCenterView.Destination) -> some View {
        let isSelected = destination == selection
        return Button {
            selection = destination
        } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 27, height: 27)
                    .accentGlass(scheme, corner: 7.5, glowing: isSelected)
                    .shadow(color: scheme.glow.color.opacity(isSelected ? 0.40 : 0.10),
                            radius: isSelected ? 7 : 2, y: 1)
                Text(destination.title)
                    .font(.system(.body, design: .rounded).weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : Color.white.opacity(0.52))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.white.opacity(0.1))
                        .matchedGeometryEffect(id: "selection-pill", in: selectionPill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}
