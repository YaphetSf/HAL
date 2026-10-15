import Foundation

enum EnglishProfile: Equatable {
    case direct
    case assist
}

/// The part of EN+ that can be tested without IMK or AppKit. It remembers only keys HAL
/// itself observed in this input session; it never reads surrounding client text (D22).
final class EnglishCompletionSession {
    enum SuggestionKeyAction: Equatable {
        case passThrough
        case dismiss
        case showSuggestions
        case replace(text: String, range: NSRange)
    }

    static let minimumPrefixLength = 3
    static let maximumSuggestionCount = 3

    private(set) var prefix = ""
    private(set) var suggestions: [String] = []
    private(set) var highlightedIndex = 0
    private var expectedCaretLocation: Int?

    var canRequestSuggestion: Bool {
        prefix.count >= Self.minimumPrefixLength
    }

    /// nil means ordinary typing; the adapter continues observing the host-handled key.
    func handleSuggestionKey(_ event: KeyEvent, selection: NSRange?,
                             visible: Bool) -> SuggestionKeyAction? {
        guard event.modifiers.intersection([.command, .control, .option]).isEmpty else {
            reset()
            return .passThrough
        }
        switch event.keyCode {
        case 0x30: // Tab
            guard visible, let selection, selection.length == 0,
                  selection.location != NSNotFound,
                  selection.location == expectedCaretLocation,
                  selection.location >= prefix.utf16.count,
                  let suggestion = highlightedSuggestion else {
                reset()
                return .passThrough
            }
            if event.modifiers.contains(.shift) {
                highlightedIndex = (highlightedIndex + 1) % suggestions.count
                return .showSuggestions
            }
            let range = NSRange(location: selection.location - prefix.utf16.count,
                                length: prefix.utf16.count)
            reset()
            return .replace(text: suggestion, range: range)
        case 0x35: // Escape
            reset()
            return visible ? .dismiss : .passThrough
        case 0x7B...0x7E: // All arrows belong to the host editor, including Shift selection.
            reset()
            return .passThrough
        default:
            return nil
        }
    }

    /// Records one ASCII letter (or an apostrophe inside a word) before the host inserts it.
    /// A caret jump means the user clicked or navigated elsewhere, so the old prefix is not
    /// allowed to follow them into the new position.
    @discardableResult
    func append(_ characters: String, caretLocation: Int?) -> Bool {
        guard Self.isWordCharacter(characters, after: prefix) else {
            reset()
            return false
        }
        resetIfCaretMoved(to: caretLocation)
        prefix.append(contentsOf: characters)
        clearSuggestions()
        expectedCaretLocation = caretLocation.map { $0 + characters.utf16.count }
        return true
    }

    /// Records a host-handled backward delete. Selection deletion and cursor movement both
    /// invalidate the buffer; a simple one-character delete at the expected caret can stay.
    func deleteBackward(caretLocation: Int?, selectionLength: Int) {
        guard selectionLength == 0 else { return reset() }
        if let expectedCaretLocation, let caretLocation,
           expectedCaretLocation != caretLocation {
            return reset()
        }
        guard !prefix.isEmpty else { return reset() }
        prefix.removeLast()
        clearSuggestions()
        expectedCaretLocation = caretLocation.map { max(0, $0 - 1) }
    }

    /// Takes up to three strictly longer completions that actually begin with the observed
    /// prefix. NSSpellChecker normally guarantees both, but the Core boundary verifies them.
    func updateSuggestions(_ candidates: [String]) {
        guard canRequestSuggestion else {
            clearSuggestions()
            return
        }
        let observedPrefix = prefix
        var accepted: [String] = []
        for rawCandidate in candidates {
            let candidate = Self.normalise(candidate: rawCandidate, for: observedPrefix)
            guard candidate.count > observedPrefix.count,
                  candidate.lowercased().hasPrefix(observedPrefix.lowercased()),
                  !candidate.contains(where: { $0.isWhitespace }),
                  !accepted.contains(where: {
                      $0.caseInsensitiveCompare(candidate) == .orderedSame
                  }) else { continue }
            accepted.append(candidate)
            if accepted.count == Self.maximumSuggestionCount { break }
        }
        suggestions = accepted
        highlightedIndex = 0
    }

    var highlightedSuggestion: String? {
        guard suggestions.indices.contains(highlightedIndex) else { return nil }
        return suggestions[highlightedIndex]
    }

    func reset() {
        prefix = ""
        clearSuggestions()
        expectedCaretLocation = nil
    }

    private func clearSuggestions() {
        suggestions = []
        highlightedIndex = 0
    }

    private func resetIfCaretMoved(to location: Int?) {
        guard let expectedCaretLocation, let location,
              expectedCaretLocation != location else { return }
        reset()
    }

    private static func isWordCharacter(_ characters: String, after prefix: String) -> Bool {
        guard characters.unicodeScalars.count == 1,
              let scalar = characters.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A:
            return true
        case 0x27:
            return !prefix.isEmpty && prefix.last != "'"
        default:
            return false
        }
    }

    private static func normalise(candidate: String, for prefix: String) -> String {
        let letters = prefix.filter(\.isLetter)
        if !letters.isEmpty, letters == letters.uppercased() {
            return candidate.uppercased()
        }
        if let first = letters.first, first.isUppercase,
           letters.dropFirst().allSatisfy({ $0.isLowercase }) {
            return candidate.prefix(1).uppercased() + String(candidate.dropFirst())
        }
        return candidate
    }
}
