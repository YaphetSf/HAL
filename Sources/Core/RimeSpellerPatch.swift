import Foundation

/// Writes the user's fuzzy rules (D21) into `rime_ice.custom.yaml` as a marked
/// `speller/algebra/+` patch block. Rules are stored in user direction (input → match)
/// and inverted here into rime's `derive/^match$/input/`. Everything outside the
/// markers is the user's to edit (D12) and is preserved verbatim.
enum RimeSpellerPatch {
    private static let beginMarker = "# HAL speller rules begin"
    private static let endMarker = "# HAL speller rules end"

    /// Blocks written before 2026-08-26, when the page was a single din-ding toggle.
    private static let legacyMarkers = [("# HAL fuzzy din-ding begin", "# HAL fuzzy din-ding end")]

    static let userDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("HAL/Rime")

    static func schemaPatchURL(in userDirectory: URL) -> URL {
        userDirectory.appendingPathComponent("rime_ice.custom.yaml")
    }

    static func write(rules: [SpellerRule], asciiPhrases: [String],
                      pageSize: Int = UserSettings.defaultCandidatePageSize,
                      in userDirectory: URL) {
        let url = schemaPatchURL(in: userDirectory)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var withoutBlocks = existing
        for (begin, end) in [(beginMarker, endMarker)] + legacyMarkers {
            let pattern = "(?s)\\n?\\Q\(begin)\\E.*?\\Q\(end)\\E\\n?"
            withoutBlocks = withoutBlocks.replacingOccurrences(of: pattern, with: "",
                                                               options: .regularExpression)
        }
        let active = rules.filter { $0.isEnabled && SpellerRule.isValid(input: $0.input,
                                                                        match: $0.match) }
        let entries: [String] = {
            var lines: [String] = []
            if !active.isEmpty {
                lines.append("  \"speller/algebra/+\":")
                lines += active.map { rule in "    - derive/\(rule.anchoredMatch)/\(rule.input)/" }
            }
            if let pattern = recognizerPattern(forAsciiPhrases: asciiPhrases) {
                // Yaml double-quoted scalars would eat a lone backslash; double them.
                let yamlPattern = pattern.replacingOccurrences(of: "\\", with: "\\\\")
                lines.append("  \"recognizer/patterns/hal_ascii_pass\": \"\(yamlPattern)\"")
            }
            // rime's default is 5; only write a page_size when the user chose otherwise,
            // so resetting to the default strips the block back out (D21).
            if pageSize != UserSettings.defaultCandidatePageSize {
                lines.append("  \"menu/page_size\": \(pageSize)")
            }
            return lines
        }()
        let content: String
        if entries.isEmpty {
            content = withoutBlocks
        } else {
            let patch = """
            \(beginMarker)
            patch:
            \(entries.joined(separator: "\n"))
            \(endMarker)
            """
            content = withoutBlocks.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n" + patch
        }
        if !entries.isEmpty || !withoutBlocks.isEmpty {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                      withIntermediateDirectories: true)
            try? content.write(to: url, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// A phrase passes through the punctuation layer only while the recognizer sees the
    /// input as a match, so the regex has to full-match every intermediate state of
    /// typing the phrase: "e.g." becomes `^e(\.)?(g(\.)?)?$` (D23).
    static func recognizerPattern(forAsciiPhrases phrases: [String]) -> String? {
        let automata = phrases.compactMap { automaton(for: $0) }
        guard !automata.isEmpty else { return nil }
        return "^(" + automata.joined(separator: "|") + ")$"
    }

    /// `abc` -> `a(b(c)?)?`. Every prefix of the phrase full-matches; unrelated input does not.
    private static func automaton(for phrase: String) -> String? {
        let scalars = Array(phrase.unicodeScalars)
        guard isValidAsciiPhrase(phrase), scalars.count > 1 else { return nil }
        var body = escape(scalars[0])
        for scalar in scalars[1...] {
            body += "(" + escape(scalar)
        }
        body += String(repeating: ")?", count: scalars.count - 1)
        return body
    }

    static func isValidAsciiPhrase(_ phrase: String) -> Bool {
        let scalars = Array(phrase.unicodeScalars)
        guard let first = scalars.first, first.properties.isAlphabetic,
              scalars.allSatisfy({ $0.isASCII && !$0.properties.isWhitespace && $0 != "/" })
        else { return false }
        return true
    }

    private static func escape(_ scalar: Unicode.Scalar) -> String {
        scalar.properties.isAlphabetic || ("0"..."9").contains(scalar) ? String(scalar) : "\\\(scalar)"
    }
}
