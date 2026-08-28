import Foundation

/// The candidate window's color scheme (D21). Plain RGB, no SwiftUI import, so both HAL
/// and the control center app can depend on this from Core without that app pulling in
/// AppKit/IMK.
struct RGB: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
}

/// A named starting point. Selecting one just seeds `CandidateColorScheme.custom` with
/// its values — the user can still open the color pickers and drift away from it.
enum CandidateColorPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case aurora
    case ember
    case forest
    case mono

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aurora: return "Aurora"
        case .ember: return "Ember"
        case .forest: return "Forest"
        case .mono: return "Mono"
        }
    }

    var accentStart: RGB {
        switch self {
        case .aurora: return RGB(red: 0.58, green: 0.32, blue: 1.0)
        case .ember: return RGB(red: 1.0, green: 0.42, blue: 0.24)
        case .forest: return RGB(red: 0.16, green: 0.74, blue: 0.48)
        case .mono: return RGB(red: 0.45, green: 0.45, blue: 0.48)
        }
    }

    var accentEnd: RGB {
        switch self {
        case .aurora: return RGB(red: 0.13, green: 0.78, blue: 1.0)
        case .ember: return RGB(red: 1.0, green: 0.22, blue: 0.55)
        case .forest: return RGB(red: 0.42, green: 0.85, blue: 0.35)
        case .mono: return RGB(red: 0.72, green: 0.72, blue: 0.75)
        }
    }

    var glow: RGB {
        switch self {
        case .aurora: return RGB(red: 0.42, green: 0.55, blue: 1.0)
        case .ember: return RGB(red: 1.0, green: 0.40, blue: 0.30)
        case .forest: return RGB(red: 0.30, green: 0.80, blue: 0.50)
        case .mono: return RGB(red: 0.50, green: 0.50, blue: 0.50)
        }
    }
}

/// What `CandidateView` actually renders with. `preset` is nil once the user is on a
/// custom scheme; `customID` names which of the stored `CustomColorScheme`s is live then,
/// so two entries with identical colors still checkmark distinctly. `custom` always holds
/// the live values either way — switching back to a preset doesn't lose anything, it just
/// seeds whichever custom entry is edited next.
struct CandidateColorScheme: Codable, Equatable, Sendable {
    struct CustomColors: Codable, Equatable, Sendable {
        var accentStart: RGB
        var accentEnd: RGB
        var glow: RGB
    }

    var preset: CandidateColorPreset?
    var customID: UUID?
    var custom: CustomColors

    var accentStart: RGB { preset?.accentStart ?? custom.accentStart }
    var accentEnd: RGB { preset?.accentEnd ?? custom.accentEnd }
    var glow: RGB { preset?.glow ?? custom.glow }

    static func preset(_ preset: CandidateColorPreset) -> CandidateColorScheme {
        CandidateColorScheme(preset: preset, customID: nil,
                              custom: CustomColors(accentStart: preset.accentStart,
                                                    accentEnd: preset.accentEnd,
                                                    glow: preset.glow))
    }

    static func custom(_ entry: CustomColorScheme) -> CandidateColorScheme {
        CandidateColorScheme(preset: nil, customID: entry.id, custom: entry.colors)
    }

    /// What a fresh install starts on. Silver reads as the most finished of the four and
    /// stays out of the way of whatever is being typed; the rest are one click away.
    static let mono = preset(.mono)

    static let aurora = preset(.aurora)

    // customID decodes leniently: Settings.json is hand-editable and schemes written
    // before custom entries existed have no such key.
    init(preset: CandidateColorPreset?, customID: UUID?, custom: CustomColors) {
        self.preset = preset
        self.customID = customID
        self.custom = custom
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        preset = try values.decodeIfPresent(CandidateColorPreset.self, forKey: .preset)
        customID = try values.decodeIfPresent(UUID.self, forKey: .customID)
        custom = try values.decode(CustomColors.self, forKey: .custom)
    }

    enum CodingKeys: String, CodingKey {
        case preset, customID, custom
    }
}

/// One user-built scheme (D2x): an identity plus the three colors, kept in a list beside
/// the presets and selectable like one. The name is the row position — "Custom 1", ….
struct CustomColorScheme: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var colors: CandidateColorScheme.CustomColors
}
