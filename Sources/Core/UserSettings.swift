import Foundation
import OSLog

/// One fuzzy rule in user direction (D21): typing `input` also matches candidates whose
/// syllable is `match` — e.g. `din → ding` means typing "din" offers 定/顶/丁. Rime's
/// `derive` runs the other way (dictionary → derived spelling), so the patch writer
/// inverts it: `derive/^ding$/din/`.
struct SpellerRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var input: String
    var match: String
    var isEnabled = true

    static let dinToDing = SpellerRule(input: "din", match: "ding", isEnabled: false)

    private static let regexMetacharacters = Set("^$()[]|*+?.\\")

    /// Plain matches anchor to whole syllables (`ding` becomes `^ding$`); anything
    /// containing regex metacharacters passes through untouched, which is how suffix
    /// rules like `ang$` (all -ang syllables) stay expressible.
    var anchoredMatch: String {
        match.contains(where: { Self.regexMetacharacters.contains($0) }) ? match : "^\(match)$"
    }

    /// `/` would break the derive expression and whitespace would break the yaml line.
    static func isValid(input: String, match: String) -> Bool {
        let characters = input + match
        guard !input.isEmpty, !match.isEmpty else { return false }
        return !characters.contains("/") && characters.allSatisfy { !$0.isWhitespace }
    }
}

/// One manual weight (M8): when the composed input matches `input`, `candidate` is
/// boosted to the top of the current page.
struct WeightRule: Codable, Equatable, Identifiable {
    var id = UUID()
    var input: String
    var candidate: String

    static func isValid(input: String, candidate: String) -> Bool {
        !input.isEmpty && !candidate.isEmpty
    }
}

/// The small settings payload shared by the input method and HAL control center (D21/D22). New fields decode
/// with defaults so an existing appearance-only Settings.json keeps working.
struct UserSettings: Codable, Equatable {
    static let defaultEnglishCompletionDelay: TimeInterval = 0.075
    static let englishCompletionDelayRange: ClosedRange<TimeInterval> = 0...0.3
    static let defaultAsciiPhrases = ["e.g.", "i.e.", "etc."]
    /// How many candidates librime puts on one page, wired into rime's `menu/page_size`
    /// by the patch writer (D21). Selection numbers 1-9 stay unambiguous, so the ceiling is 9.
    static let candidatePageSizeRange = 3...9
    static let defaultCandidatePageSize = 5
    /// How wide the candidate window may grow before a single long candidate gets
    /// ellipsized instead of pushing the row off screen (D21). Applied by the panel on
    /// every show, so a change reaches the next candidate window without a restart.
    static let candidateWindowMaxWidthRange = 200.0...900.0
    static let defaultCandidateWindowMaxWidth = 640.0

    var candidateColorScheme: CandidateColorScheme
    /// The user-built schemes (D2x), selectable beside the presets; the live one is named
    /// by `candidateColorScheme.customID`.
    var customColorSchemes: [CustomColorScheme]
    var englishCompletionDelay: TimeInterval
    /// Candidates per page in the candidate window (D21): rime's `menu/page_size`,
    /// 3-9, applied by the patch writer.
    var candidatePageSize: Int
    /// Hard cap on the candidate window's width (D21); a single candidate longer than
    /// the cap is ellipsized instead of stretching the row off screen. Read live by the
    /// panel on every show, so it applies to the next candidate window without a restart.
    var candidateWindowMaxWidth: Double
    var spellerRules: [SpellerRule]
    var asciiPhrases: [String]
    var weightedCandidates: [WeightRule]
    /// What a mode switch plays: an artwork stamp or the tennis serve (D26).
    var switchAnimation: SwitchAnimationChoice
    /// AI-edit provider and its endpoint configuration (D28).
    var aiEdit: AIEditSettings

    init(candidateColorScheme: CandidateColorScheme = .mono,
         customColorSchemes: [CustomColorScheme] = [],
         englishCompletionDelay: TimeInterval = Self.defaultEnglishCompletionDelay,
         candidatePageSize: Int = Self.defaultCandidatePageSize,
         candidateWindowMaxWidth: Double = Self.defaultCandidateWindowMaxWidth,
         spellerRules: [SpellerRule] = [SpellerRule.dinToDing],
         asciiPhrases: [String] = UserSettings.defaultAsciiPhrases,
         weightedCandidates: [WeightRule] = [],
         switchAnimation: SwitchAnimationChoice = .miku,
         aiEdit: AIEditSettings = AIEditSettings()) {
        self.candidateColorScheme = candidateColorScheme
        self.customColorSchemes = customColorSchemes
        self.englishCompletionDelay = Self.clamp(englishCompletionDelay)
        self.candidatePageSize = Self.clampPageSize(candidatePageSize)
        self.candidateWindowMaxWidth = Self.clampMaxWidth(candidateWindowMaxWidth)
        self.spellerRules = spellerRules
        self.asciiPhrases = asciiPhrases
        self.weightedCandidates = weightedCandidates
        self.switchAnimation = switchAnimation
        self.aiEdit = aiEdit
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        candidateColorScheme = try values.decodeIfPresent(CandidateColorScheme.self,
                                                           forKey: .candidateColorScheme) ?? .mono
        customColorSchemes = try values.decodeIfPresent([CustomColorScheme].self,
                                                          forKey: .customColorSchemes) ?? []
        let delay = try values.decodeIfPresent(TimeInterval.self,
                                                forKey: .englishCompletionDelay)
            ?? Self.defaultEnglishCompletionDelay
        englishCompletionDelay = Self.clamp(delay)
        candidatePageSize = Self.clampPageSize(
            try values.decodeIfPresent(Int.self, forKey: .candidatePageSize)
                ?? Self.defaultCandidatePageSize)
        candidateWindowMaxWidth = Self.clampMaxWidth(
            try values.decodeIfPresent(Double.self, forKey: .candidateWindowMaxWidth)
                ?? Self.defaultCandidateWindowMaxWidth)
        if let rules = try values.decodeIfPresent([SpellerRule].self, forKey: .spellerRules) {
            spellerRules = rules
        } else {
            // Settings.json written before 2026-08-26 only had the din-ding toggle.
            var migrated = SpellerRule.dinToDing
            migrated.isEnabled = try values.decodeIfPresent(Bool.self, forKey: .fuzzyDinToDing) ?? false
            spellerRules = [migrated]
        }
        asciiPhrases = try values.decodeIfPresent([String].self, forKey: .asciiPhrases)
            ?? Self.defaultAsciiPhrases
        weightedCandidates = try values.decodeIfPresent([WeightRule].self,
                                                        forKey: .weightedCandidates) ?? []
        switchAnimation = (try? values.decodeIfPresent(SwitchAnimationChoice.self,
                                                    forKey: .switchAnimation)) ?? .miku
        aiEdit = (try? values.decodeIfPresent(AIEditSettings.self,
                                                 forKey: .aiEdit)) ?? AIEditSettings()
    }

    /// `fuzzyDinToDing` exists only so pre-2026-08-26 Settings.json still decodes; it is
    /// never written back.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(candidateColorScheme, forKey: .candidateColorScheme)
        try container.encode(customColorSchemes, forKey: .customColorSchemes)
        try container.encode(englishCompletionDelay, forKey: .englishCompletionDelay)
        try container.encode(candidatePageSize, forKey: .candidatePageSize)
        try container.encode(candidateWindowMaxWidth, forKey: .candidateWindowMaxWidth)
        try container.encode(spellerRules, forKey: .spellerRules)
        try container.encode(asciiPhrases, forKey: .asciiPhrases)
        try container.encode(weightedCandidates, forKey: .weightedCandidates)
        try container.encode(switchAnimation, forKey: .switchAnimation)
        try container.encode(aiEdit, forKey: .aiEdit)
    }

    private enum CodingKeys: String, CodingKey {
        case candidateColorScheme
        case customColorSchemes
        case englishCompletionDelay
        case candidatePageSize
        case candidateWindowMaxWidth
        case spellerRules
        case asciiPhrases
        case weightedCandidates
        case switchAnimation
        case aiEdit
        case fuzzyDinToDing
    }

    private static func clamp(_ delay: TimeInterval) -> TimeInterval {
        min(max(delay, englishCompletionDelayRange.lowerBound),
            englishCompletionDelayRange.upperBound)
    }

    /// Settings.json is hand-editable; anything outside the selectable range clamps in.
    private static func clampPageSize(_ size: Int) -> Int {
        min(max(size, candidatePageSizeRange.lowerBound),
            candidatePageSizeRange.upperBound)
    }

    private static func clampMaxWidth(_ width: Double) -> Double {
        min(max(width, candidateWindowMaxWidthRange.lowerBound),
            candidateWindowMaxWidthRange.upperBound)
    }
}

/// `~/Library/Application Support/HAL/Settings.json` is the only shared store. No XPC or
/// App Group: the settings app writes atomically and HAL loads at the next relevant event.
/// Reading is the hot path — every keystroke goes through InputSession's settings closure —
/// so a load costs one stat unless the file changed. The writer lives in the settings app
/// target (`SettingsWriter.swift`), which is what makes this store single-writer.
enum SettingsStore {
    static let log = Logger(subsystem: "com.hal.inputmethod", category: "settings")

    /// Test isolation only: redirects reads and writes away from the user's real
    /// `~/Library/Application Support/HAL/Settings.json`. Never set in production.
    nonisolated(unsafe) static var directoryOverride: URL? {
        didSet { cache = nil }
    }

    /// The one directory both processes agree on. Settings.json and anything else HAL
    /// keeps for itself — D26's artwork — live side by side in it.
    static var directory: URL {
        directoryOverride
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("HAL")
    }

    static var url: URL {
        directory.appendingPathComponent("Settings.json")
    }

    /// What one stat of Settings.json identifies. Size rides along with mtime so two
    /// writes inside one timestamp tick still count as different files.
    private struct CacheEntry: Equatable {
        let modified: Date
        let size: Int
        let settings: UserSettings
    }

    /// Every settings access in a process happens on its main thread — IMK key handling,
    /// panels, and the settings app are all main-thread callers. That is the same
    /// contract `RimeRuntime.api` rests on; the compiler cannot see it.
    nonisolated(unsafe) private static var cache: CacheEntry?

    static func load() -> UserSettings {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? Int else {
            // No settings file yet: nothing worth remembering.
            cache = nil
            return UserSettings()
        }
        if let cache, cache.modified == modified, cache.size == size {
            return cache.settings
        }
        do {
            let settings = try JSONDecoder().decode(UserSettings.self, from: Data(contentsOf: url))
            cache = CacheEntry(modified: modified, size: size, settings: settings)
            return settings
        } catch {
            // A file hand-edited into invalidity must not silently look like a clean default.
            log.error("Settings.json is unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
            cache = CacheEntry(modified: modified, size: size, settings: UserSettings())
            return UserSettings()
        }
    }

    /// Drops the cached read. The writer calls this after saving, so the next load
    /// re-stats instead of trusting a stale entry.
    static func invalidateCache() {
        cache = nil
    }
}
