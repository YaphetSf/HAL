import SwiftUI

/// AI-edit provider selection (D28): Apple's system model or any
/// OpenAI-compatible model server the user runs locally or remotely.
struct AIEditSettingsView: View {
    private static let recommendedModelURL = URL(
        string: "https://huggingface.co/mlx-community/Qwen3.5-9B-MLX-4bit"
    )!

    let scheme: CandidateColorScheme

    @State private var settings = SettingsStore.load().aiEdit

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                providerCard
                rephrasePromptCard
                if settings.provider == .openAICompatible {
                    endpointCard
                    recommendedModelCard
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    private var providerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("PROVIDER")
            Picker("Provider", selection: $settings.provider) {
                ForEach(AIEditProvider.allCases) { provider in
                    Text(provider.label).tag(provider)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .onChange(of: settings.provider) { _, _ in persist() }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var rephrasePromptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionHeader("REPHRASE PROMPT")
                Spacer()
                Button("Reset") {
                    settings.rephrasePrompt = AIEditSettings.defaultRephrasePrompt
                }
                .buttonStyle(.plain)
                .foregroundStyle(settings.rephrasePrompt == AIEditSettings.defaultRephrasePrompt
                                 ? Color.secondary
                                 : scheme.accentStart.color)
                .disabled(settings.rephrasePrompt == AIEditSettings.defaultRephrasePrompt)
            }
            TextEditor(text: $settings.rephrasePrompt)
                .font(.system(.callout, design: .monospaced))
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                .padding(10)
                .frame(minHeight: 220)
                .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.38)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.09), lineWidth: 1)
                )
                .accessibilityLabel("Rephrase prompt")
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onChange(of: settings.rephrasePrompt) { _, _ in persist() }
    }

    private var endpointCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader("MODEL SERVER")
            field("Chat completions URL",
                  placeholder: "http://server-address:port/v1/chat/completions",
                  text: $settings.endpointURL)
            HStack {
                Text("Timeout")
                    .foregroundStyle(.secondary)
                Picker("Timeout", selection: $settings.timeout) {
                    ForEach(AIEditSettings.timeoutChoices, id: \.self) { seconds in
                        Text("\(Int(seconds)) s").tag(seconds)
                    }
                }
                .labelsHidden()
                .frame(width: 100)
            }
            if !settings.endpointURL.isEmpty && !settings.isEndpointConfigured {
                Label("The URL must be a valid http(s) address.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .onChange(of: settings.endpointURL) { _, _ in persist() }
        .onChange(of: settings.timeout) { _, _ in persist() }
    }

    private var recommendedModelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("RECOMMENDED MODEL")
            Link(destination: Self.recommendedModelURL) {
                HStack(spacing: 8) {
                    Text("Qwen3.5-9B-MLX-4bit")
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(scheme.accentStart.color)
            }
            .buttonStyle(.plain)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
    }

    private func persist() {
        SettingsStore.saveAIEdit(settings)
    }
}
