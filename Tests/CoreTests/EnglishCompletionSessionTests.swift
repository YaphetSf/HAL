import Foundation
import XCTest

final class EnglishCompletionSessionTests: XCTestCase {
    func testThreeContinuousLettersBecomeEligibleForCompletion() {
        let session = EnglishCompletionSession()

        XCTAssertTrue(session.append("h", caretLocation: 10))
        XCTAssertTrue(session.append("e", caretLocation: 11))
        XCTAssertFalse(session.canRequestSuggestion)
        XCTAssertTrue(session.append("l", caretLocation: 12))

        XCTAssertEqual(session.prefix, "hel")
        XCTAssertTrue(session.canRequestSuggestion)
    }

    func testCaretJumpStartsANewWordInsteadOfLeakingTheOldPrefix() {
        let session = EnglishCompletionSession()
        _ = session.append("h", caretLocation: 10)
        _ = session.append("e", caretLocation: 11)

        _ = session.append("n", caretLocation: 40)

        XCTAssertEqual(session.prefix, "n")
        XCTAssertFalse(session.canRequestSuggestion)
    }

    func testBackspaceKeepsAContinuousPrefixButSelectionDeletionResets() {
        let session = EnglishCompletionSession()
        _ = session.append("h", caretLocation: 0)
        _ = session.append("e", caretLocation: 1)
        _ = session.append("l", caretLocation: 2)

        session.deleteBackward(caretLocation: 3, selectionLength: 0)
        XCTAssertEqual(session.prefix, "he")

        session.deleteBackward(caretLocation: 2, selectionLength: 2)
        XCTAssertEqual(session.prefix, "")
    }

    func testAcceptReturnsOnlyTheMissingSuffixAndClearsState() {
        let session = EnglishCompletionSession()
        _ = session.append("h", caretLocation: 0)
        _ = session.append("e", caretLocation: 1)
        _ = session.append("l", caretLocation: 2)
        session.updateSuggestions(["hel", "hello", "help", "held", "helmet"])

        XCTAssertEqual(session.suggestions, ["hello", "help", "held"])
        XCTAssertEqual(session.acceptSuggestion(), "lo")
        XCTAssertEqual(session.prefix, "")
        XCTAssertTrue(session.suggestions.isEmpty)
    }

    func testCompletionPreservesTypedCapitalisation() {
        let title = EnglishCompletionSession()
        _ = title.append("H", caretLocation: 0)
        _ = title.append("e", caretLocation: 1)
        _ = title.append("l", caretLocation: 2)
        title.updateSuggestions(["hello"])

        let upper = EnglishCompletionSession()
        _ = upper.append("H", caretLocation: 0)
        _ = upper.append("E", caretLocation: 1)
        _ = upper.append("L", caretLocation: 2)
        upper.updateSuggestions(["hello"])

        XCTAssertEqual(title.suggestions, ["Hello"])
        XCTAssertEqual(upper.suggestions, ["HELLO"])
    }

    func testArrowNavigationSelectsOneOfThreeSuggestions() {
        let session = EnglishCompletionSession()
        _ = session.append("h", caretLocation: 0)
        _ = session.append("e", caretLocation: 1)
        _ = session.append("l", caretLocation: 2)
        session.updateSuggestions(["hello", "help", "held", "helmet"])

        session.moveHighlight(by: 1)
        XCTAssertEqual(session.highlightedSuggestion, "help")
        XCTAssertEqual(session.acceptSuggestion(), "p")
    }

    func testArrowNavigationStopsAtCandidateEdges() {
        let session = EnglishCompletionSession()
        _ = session.append("h", caretLocation: 0)
        _ = session.append("e", caretLocation: 1)
        _ = session.append("l", caretLocation: 2)
        session.updateSuggestions(["hello", "help"])

        session.moveHighlight(by: -1)
        XCTAssertEqual(session.highlightedIndex, 0)
        session.moveHighlight(by: 20)
        XCTAssertEqual(session.highlightedIndex, 1)
    }

    func testPunctuationResetsTheWord() {
        let session = EnglishCompletionSession()
        _ = session.append("h", caretLocation: 0)
        _ = session.append("e", caretLocation: 1)

        XCTAssertFalse(session.append("_", caretLocation: 2))
        XCTAssertEqual(session.prefix, "")
    }
}

final class UserSettingsTests: XCTestCase {
    func testOldSettingsWithoutEnglishDelayUseTheFasterDefault() throws {
        let settings = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))

        XCTAssertEqual(settings.englishCompletionDelay,
                       UserSettings.defaultEnglishCompletionDelay)
    }

    func testEnglishDelayIsClampedToTheExposedRange() {
        XCTAssertEqual(UserSettings(englishCompletionDelay: -1).englishCompletionDelay, 0)
        XCTAssertEqual(UserSettings(englishCompletionDelay: 1).englishCompletionDelay, 0.3)
    }

    func testCandidatePageSizeDefaultsAndClamps() {
        XCTAssertEqual(UserSettings().candidatePageSize,
                       UserSettings.defaultCandidatePageSize)
        XCTAssertEqual(UserSettings(candidatePageSize: 2).candidatePageSize, 3)
        XCTAssertEqual(UserSettings(candidatePageSize: 12).candidatePageSize, 9)
        XCTAssertEqual(UserSettings(candidatePageSize: 7).candidatePageSize, 7)
    }

    func testCandidatePageSizeRoundTrips() throws {
        let settings = UserSettings(candidatePageSize: 8)
        let decoded = try JSONDecoder().decode(UserSettings.self,
                                               from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.candidatePageSize, 8)
    }

    func testLegacySettingsWithoutPageSizeDecodeToTheDefault() throws {
        let legacy = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.candidatePageSize, UserSettings.defaultCandidatePageSize)
    }

    func testLegacyFuzzyFlagMigratesToSeededSpellerRule() throws {
        let enabled = try JSONDecoder().decode(UserSettings.self,
                                               from: Data(#"{"fuzzyDinToDing":true}"#.utf8))
        let disabled = try JSONDecoder().decode(UserSettings.self,
                                                from: Data(#"{"fuzzyDinToDing":false}"#.utf8))
        let untouched = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))

        var expected = SpellerRule.dinToDing
        expected.isEnabled = true
        XCTAssertEqual(enabled.spellerRules, [expected])
        XCTAssertEqual(disabled.spellerRules, [SpellerRule.dinToDing])
        XCTAssertEqual(untouched.spellerRules, [SpellerRule.dinToDing])
    }

    func testSpellerRulesRoundTrip() throws {
        var rule = SpellerRule(input: "ing", match: "in$")
        rule.isEnabled = false
        let settings = UserSettings(spellerRules: [rule])

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: data)

        XCTAssertEqual(decoded.spellerRules, [rule])
    }

    func testSpellerRuleValidation() {
        XCTAssertTrue(SpellerRule.isValid(input: "din", match: "ding"))
        XCTAssertFalse(SpellerRule.isValid(input: "", match: "ding"))
        XCTAssertFalse(SpellerRule.isValid(input: "d/in", match: "ding"))
        XCTAssertFalse(SpellerRule.isValid(input: "d in", match: "d\ning"))
    }

    func testAsciiPhrasesAndWeightsDefaultAndRoundTrip() throws {
        let fresh = try JSONDecoder().decode(UserSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(fresh.asciiPhrases, UserSettings.defaultAsciiPhrases)
        XCTAssertTrue(fresh.weightedCandidates.isEmpty)

        var settings = UserSettings()
        settings.asciiPhrases = ["e.g."]
        settings.weightedCandidates = [WeightRule(input: "cizu", candidate: "词组")]
        let decoded = try JSONDecoder().decode(UserSettings.self,
                                               from: try JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.asciiPhrases, ["e.g."])
        XCTAssertEqual(decoded.weightedCandidates, settings.weightedCandidates)
    }
}

final class RimeSpellerPatchTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RimeSpellerPatchTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writtenContent() throws -> String {
        try String(contentsOf: RimeSpellerPatch.schemaPatchURL(in: directory), encoding: .utf8)
    }

    func testWritesOnlyEnabledValidRulesAndPreservesForeignContent() throws {
        try """
        # my own patch, do not touch
        patch:
          "menu/page_size": 6
        """.write(to: RimeSpellerPatch.schemaPatchURL(in: directory), atomically: true, encoding: .utf8)

        RimeSpellerPatch.write(rules: [
            SpellerRule(input: "din", match: "ding"),
            SpellerRule(input: "an", match: "ang$", isEnabled: false),
            SpellerRule(input: "ang", match: "an"),
            SpellerRule(input: "c", match: "a/b")
        ], asciiPhrases: [], in: directory)

        let content = try writtenContent()
        XCTAssertTrue(content.contains("derive/^ding$/din/"))
        XCTAssertTrue(content.contains("derive/^an$/ang/"))
        XCTAssertFalse(content.contains("derive/ang$/an/"))
        XCTAssertFalse(content.contains("a/b"))
        XCTAssertTrue(content.contains("# my own patch, do not touch"))
    }

    func testStripsLegacyDinDingBlockAndRemovesFileWhenEmpty() throws {
        try """
        # HAL fuzzy din-ding begin
        patch:
          "speller/algebra/+":
            - derive/^din$/ding/
        # HAL fuzzy din-ding end
        """.write(to: RimeSpellerPatch.schemaPatchURL(in: directory), atomically: true, encoding: .utf8)

        RimeSpellerPatch.write(rules: [SpellerRule.dinToDing], asciiPhrases: [], in: directory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: RimeSpellerPatch.schemaPatchURL(in: directory).path))

        RimeSpellerPatch.write(rules: [SpellerRule(input: "ing", match: "in")],
                               asciiPhrases: [], in: directory)
        let content = try writtenContent()
        XCTAssertFalse(content.contains("din-ding"))
        XCTAssertTrue(content.contains("derive/^in$/ing/"))
    }

    func testAsciiPhrasesProduceRecognizerPatternInPatch() throws {
        RimeSpellerPatch.write(rules: [], asciiPhrases: ["e.g.", "etc."], in: directory)
        let content = try writtenContent()
        let pattern = try XCTUnwrap(RimeSpellerPatch.recognizerPattern(forAsciiPhrases: ["e.g.", "etc."]))
        XCTAssertTrue(content.contains("recognizer/patterns/hal_ascii_pass"))
        XCTAssertTrue(content.contains(pattern.replacingOccurrences(of: "\\", with: "\\\\")))
        XCTAssertFalse(content.contains("speller/algebra"))
    }

    func testRecognizerPatternMatchesEveryTypingPrefixOfAPhrase() throws {
        let pattern = try XCTUnwrap(RimeSpellerPatch.recognizerPattern(forAsciiPhrases: ["e.g."]))
        let regex = try NSRegularExpression(pattern: pattern)
        for prefix in ["e", "e.", "e.g", "e.g."] {
            let range = NSRange(prefix.startIndex..., in: prefix)
            XCTAssertNotNil(regex.firstMatch(in: prefix, range: range),
                            "prefix \(prefix) must full-match")
        }
        for other in ["x", "ex", "a.", "e.g.x", "E.G."] {
            let range = NSRange(other.startIndex..., in: other)
            XCTAssertNil(regex.firstMatch(in: other, range: range), "\(other) must not match")
        }
    }

    func testInvalidAsciiPhrasesAreRejected() {
        XCTAssertFalse(RimeSpellerPatch.isValidAsciiPhrase(".e.g"))
        XCTAssertFalse(RimeSpellerPatch.isValidAsciiPhrase("e g"))
        XCTAssertFalse(RimeSpellerPatch.isValidAsciiPhrase("e/g"))
        XCTAssertFalse(RimeSpellerPatch.isValidAsciiPhrase("e。g"))
        XCTAssertNil(RimeSpellerPatch.recognizerPattern(forAsciiPhrases: ["", "e g", ".x"]))
    }

    func testCustomPageSizeIsWrittenIntoThePatchBlock() throws {
        RimeSpellerPatch.write(rules: [], asciiPhrases: [],
                               pageSize: 9, in: directory)
        XCTAssertTrue(try writtenContent().contains("\"menu/page_size\": 9"))
    }

    func testDefaultPageSizeIsNotWrittenSoResetStripsTheBlock() throws {
        RimeSpellerPatch.write(rules: [], asciiPhrases: [],
                               pageSize: UserSettings.defaultCandidatePageSize, in: directory)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: RimeSpellerPatch.schemaPatchURL(in: directory).path))
    }

    func testPageSizeSurvivesRewriteAlongsideRules() throws {
        RimeSpellerPatch.write(rules: [SpellerRule(input: "din", match: "ding")],
                               asciiPhrases: ["e.g."], pageSize: 7, in: directory)
        RimeSpellerPatch.write(rules: [SpellerRule(input: "din", match: "ding")],
                               asciiPhrases: ["e.g."], pageSize: 8, in: directory)
        let content = try writtenContent()
        XCTAssertTrue(content.contains("\"menu/page_size\": 8"))
        XCTAssertFalse(content.contains("\"menu/page_size\": 7"))
    }
}
