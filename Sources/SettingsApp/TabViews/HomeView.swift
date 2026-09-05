import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Landing page: the shortcut cheat sheet, plus the enable guide when HAL is installed but
/// switched off. Navigation is the sidebar's job — Home does not repeat it as a row of cards.
struct HomeView: View {
    let scheme: CandidateColorScheme

    @State private var halEnabled = true

    private var schemeName: String {
        scheme.preset?.displayName ?? "Custom"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !halEnabled {
                    enableCard
                }
                quickControls
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .scrollIndicators(.never)
        .onAppear { halEnabled = HALInputSourceStatus.isEnabled }
        .onReceive(DistributedNotificationCenter.default().publisher(
            for: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String))) { _ in
            withAnimation(.easeInOut(duration: 0.35)) {
                halEnabled = HALInputSourceStatus.isEnabled
            }
        }
    }

    // MARK: Enable guide

    private var enableCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .accentGlass(scheme, corner: 8)
                Text("HAL is installed but not enabled")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 8) {
                step("1", "Open System Settings → Keyboard → Text Input → Edit")
                step("2", "Click  +  and add “HAL”")
                step("3", "Select HAL and start typing")
            }
            HStack {
                Button {
                    if let url = URL(string: HALInputSourceStatus.keyboardSettingsURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open System Settings", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(GlassButtonStyle())
                Spacer()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(scheme.accentGradient, lineWidth: 1.2)
                .opacity(0.5)
        )
    }

    private func step(_ number: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(scheme.accentStart.color)
                .frame(width: 20, height: 20)
                .background(Circle().fill(scheme.accentStart.color.opacity(0.16)))
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Quick controls

    private var quickControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("QUICK CONTROLS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            shortcutRow(keys: ["Caps Lock"], description: "Switch between Chinese and English")
            shortcutRow(keys: ["⇧", "Caps Lock"], description: "Switch between EN and EN+")
            shortcutRow(keys: ["⌥", "Caps Lock"], description: "Edit selected text with AI")
            shortcutRow(keys: ["←", "→"], description: "Pick an EN+ suggestion")
            shortcutRow(keys: ["Tab"], description: "Accept the suggestion")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func shortcutRow(keys: [String], description: String) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    if index > 0 {
                        Text("+")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Keycap(text: key)
                }
            }
            .frame(width: 198, alignment: .leading)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
