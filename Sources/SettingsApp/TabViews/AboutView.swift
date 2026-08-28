import AppKit
import SwiftUI

/// Identity page: which build this is, who made it, and what it stands on. The licence rows
/// are not decoration — HAL ships rime-ice under GPL-3.0, so every copy has to point its
/// holder at the source (D20).
struct AboutView: View {
    let scheme: CandidateColorScheme

    @State private var isUninstalling = false
    @State private var showUninstallConfirmation = false
    @State private var showUninstallFailure = false
    @State private var uninstallFailureMessage = ""

    private let installationContext = HALInstallationContext.live()

    private static let shortVersion =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    private static let build =
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                identityCard
                creditsCard
                if installationContext.isRunningFromInstalledApp {
                    uninstallCard
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .scrollIndicators(.never)
        .confirmationDialog("Uninstall HAL?", isPresented: $showUninstallConfirmation) {
            Button("Uninstall", role: .destructive) { uninstall() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your settings and personal dictionary will be kept.")
        }
        .alert("Uninstall failed", isPresented: $showUninstallFailure) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(uninstallFailureMessage)
        }
    }

    private var identityCard: some View {
        HStack(spacing: 18) {
            HALMark()
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 8) {
                Text("HAL")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(scheme.accentGradient)
                InfoChip { Text("Version \(Self.shortVersion) (\(Self.build))") }
                Text("Ding Zhong")
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.white)
                externalLink("dingz.uk", url: "https://dingz.uk")
            }
            Spacer(minLength: 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var creditsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BUILT ON")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            creditRow("librime", licence: "BSD-3-Clause")
            creditRow("rime-ice", licence: "GPL-3.0")
            creditRow("HAL", licence: "MIT")
            externalLink("Source on GitHub", url: "https://github.com/YaphetSf/HAL")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var uninstallCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("DANGER ZONE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            HStack {
                if isUninstalling {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Uninstalling HAL")
                } else {
                    Button("Uninstall HAL", role: .destructive) {
                        showUninstallConfirmation = true
                    }
                    .buttonStyle(GlassButtonStyle())
                }
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @MainActor
    private func uninstall() {
        isUninstalling = true
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try HALSystemInstaller.uninstall(context: installationContext)
                }.value
                if let settingsURL = URL(string: HALInputSourceStatus.keyboardSettingsURL) {
                    NSWorkspace.shared.open(settingsURL)
                }
                NSApplication.shared.terminate(nil)
            } catch {
                uninstallFailureMessage = error.localizedDescription
                showUninstallFailure = true
                isUninstalling = false
            }
        }
    }

    private func creditRow(_ name: String, licence: String) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.88))
                .frame(width: 92, alignment: .leading)
            InfoChip { Text(licence) }
            Spacer(minLength: 0)
        }
    }

    private func externalLink(_ title: String, url: String) -> some View {
        Button {
            if let destination = URL(string: url) {
                NSWorkspace.shared.open(destination)
            }
        } label: {
            HStack(spacing: 5) {
                Text(title)
                    .underline()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .font(.system(.callout, design: .rounded))
            .foregroundStyle(scheme.accentGradient)
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
    }
}
