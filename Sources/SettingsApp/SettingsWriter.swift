import Foundation
import OSLog

/// Everything that writes Settings.json. The settings app is the single writer — the
/// input method process only ever reads — and this file compiling into the settings
/// app target, and not into the input method, is what enforces that.
extension SettingsStore {
    static func saveCandidateColorScheme(_ scheme: CandidateColorScheme) {
        var settings = load()
        settings.candidateColorScheme = scheme
        save(settings)
    }

    static func saveCustomColorSchemes(_ schemes: [CustomColorScheme]) {
        var settings = load()
        settings.customColorSchemes = schemes
        save(settings)
    }

    static func saveEnglishCompletionDelay(_ delay: TimeInterval) {
        var settings = load()
        settings.englishCompletionDelay = UserSettings(englishCompletionDelay: delay)
            .englishCompletionDelay
        save(settings)
    }

    static func saveCandidatePageSize(_ size: Int) {
        var settings = load()
        settings.candidatePageSize = UserSettings(candidatePageSize: size).candidatePageSize
        save(settings)
    }

    static func saveCandidateWindowMaxWidth(_ width: Double) {
        var settings = load()
        settings.candidateWindowMaxWidth = UserSettings(candidateWindowMaxWidth: width)
            .candidateWindowMaxWidth
        save(settings)
    }

    static func saveSpellerRules(_ rules: [SpellerRule]) {
        var settings = load()
        settings.spellerRules = rules
        save(settings)
    }

    static func saveAsciiPhrases(_ phrases: [String]) {
        var settings = load()
        settings.asciiPhrases = phrases
        save(settings)
    }

    static func saveWeightedCandidates(_ rules: [WeightRule]) {
        var settings = load()
        settings.weightedCandidates = rules
        save(settings)
    }

    static func saveSwitchAnimation(_ choice: SwitchAnimationChoice) {
        var settings = load()
        settings.switchAnimation = choice
        save(settings)
    }

    static func saveAIEdit(_ aiEdit: AIEditSettings) {
        var settings = load()
        settings.aiEdit = aiEdit
        save(settings)
    }

    private static func save(_ settings: UserSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            invalidateCache()
        } catch {
            log.error("could not save Settings.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
