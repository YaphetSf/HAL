import AppKit
import SwiftUI

struct HALInstallationView: View {
    private enum Phase: Equatable {
        case ready
        case working
        case failed(String)
    }

    let context: HALInstallationContext

    @State private var phase = Phase.ready
    private let scheme = SettingsStore.load().candidateColorScheme

    var body: some View {
        ZStack {
            AmbientBackground(scheme: scheme)
            VStack(spacing: 28) {
                HALMark()
                    .frame(width: 112, height: 112)

                Text("HAL")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(scheme.accentGradient)

                phaseContent
            }
            .padding(44)
            .frame(width: 440)
            .frame(minHeight: 340)
            .glassCard(corner: 24)
            .padding(36)
        }
        .tint(scheme.accentStart.color)
        .frame(minWidth: 520, minHeight: 420)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch phase {
        case .ready:
            installButton
        case .working:
            ProgressView()
                .controlSize(.large)
                .accessibilityLabel("Installing HAL")
        case let .failed(message):
            VStack(spacing: 18) {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                installButton
            }
        }
    }

    private var installButton: some View {
        Button(context.requirement.actionTitle) {
            beginPrimaryAction()
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.extraLarge)
        .keyboardShortcut(.defaultAction)
    }

    @MainActor
    private func beginPrimaryAction() {
        phase = .working
        Task { await performPrimaryAction() }
    }

    @MainActor
    private func performPrimaryAction() async {
        do {
            if context.requirement == .openInstalled {
                try await Task.detached(priority: .userInitiated) {
                    try HALSystemInstaller.launchInstalledApp(context: context, newInstance: false)
                }.value
            } else {
                await HALRunningApplicationCoordinator.stopOtherControlCenters()
                try await Task.detached(priority: .userInitiated) {
                    try HALSystemInstaller.install(context: context)
                    try HALSystemInstaller.launchInstalledApp(context: context, newInstance: true)
                }.value
                if !HALInputSourceStatus.isEnabled,
                   let settingsURL = URL(string: HALInputSourceStatus.keyboardSettingsURL) {
                    NSWorkspace.shared.open(settingsURL)
                }
            }
            NSApplication.shared.terminate(nil)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
