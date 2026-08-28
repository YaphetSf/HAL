import SwiftUI

/// EN+ suggestion timing, with a live preview of the suggestion bar.
struct EnglishSettingsView: View {
    let scheme: CandidateColorScheme

    @State private var delay = SettingsStore.load().englishCompletionDelay

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                previewStage
                delayCard
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
        .onChange(of: delay) { _, newDelay in
            SettingsStore.saveEnglishCompletionDelay(newDelay)
        }
    }

    private var previewStage: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("EN+ SUGGESTIONS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
            MockInputField(text: "hel", tint: scheme.accentEnd.color)
                .frame(maxWidth: .infinity)
            EnglishCompletionView(prefix: "hel", suggestions: ["hello", "help", "helpful"],
                                  highlightedIndex: 1, justAppeared: true, scheme: scheme)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var delayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestion delay")
                .font(.headline)
                .foregroundStyle(.white)
            Slider(value: $delay, in: UserSettings.englishCompletionDelayRange, step: 0.025) {
            } minimumValueLabel: {
                Text("0 ms").font(.caption).foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text("300 ms").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}
