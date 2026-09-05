import XCTest

/// Runs against the real librime and the vendored rime-ice snapshot. The first run deploys
/// the full dictionary set into a temporary directory, which takes a while (PLAN.md §6.1).
final class RimeEngineTests: XCTestCase {
    private static let userDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("HALEngineTests-\(UUID().uuidString)")

    /// Points SettingsStore at the throwaway directory so `prepareUserDirectory` derives the
    /// fuzzy patch from test state, never from the developer's real Settings.json.
    override class func setUp() {
        super.setUp()
        SettingsStore.directoryOverride = userDirectory
        // .../Tests/EngineTests/RimeEngineTests.swift -> repository root
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        RimeRuntime.start(sharedDataDir: root.appendingPathComponent("Rime/rime-ice"),
                          userDataDir: userDirectory)
    }

    override class func tearDown() {
        SettingsStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: userDirectory)
        super.tearDown()
    }

    func testRuntimeIsUp() {
        XCTAssertNotNil(RimeRuntime.api, "librime failed to initialize")
    }

    func testNihaoOffersNiHao() throws {
        let engine = RimeEngine()
        var state: EngineState?
        for character in "nihao" {
            state = engine.process(keysym: Int32(character.unicodeScalars.first!.value), modifiers: 0)
        }
        let candidates = try XCTUnwrap(state?.candidates.map(\.text))
        XCTAssertTrue(candidates.contains("你好"), "expected 你好 among \(candidates)")
        XCTAssertEqual(state?.composition?.text.replacingOccurrences(of: " ", with: ""), "nihao")
    }

    func testSpaceCommitsTheFirstCandidate() throws {
        let engine = RimeEngine()
        for character in "nihao" {
            _ = engine.process(keysym: Int32(character.unicodeScalars.first!.value), modifiers: 0)
        }
        let state = try XCTUnwrap(engine.process(keysym: 0x20, modifiers: 0))
        XCTAssertEqual(state.commitText, "你好")
        XCTAssertNil(state.composition, "composition should be gone after committing")
    }

    func testClearDropsTheComposition() throws {
        let engine = RimeEngine()
        _ = engine.process(keysym: Int32(UInt8(ascii: "n")), modifiers: 0)
        engine.clear()
        let state = try XCTUnwrap(engine.process(keysym: Int32(UInt8(ascii: "i")), modifiers: 0))
        XCTAssertEqual(state.composition?.text, "i")
    }

    /// The full D21 flow: without rules, "din" only reaches di+n abbreviations (低能 …);
    /// after the HAL app Apply & Restart the rule must be deployed and offer ding candidates.
    func testDinToDingAfterApplyAndRestart() throws {
        func dinCandidates() throws -> [String] {
            let engine = RimeEngine()
            var state: EngineState?
            for character in "din" {
                state = engine.process(keysym: Int32(character.unicodeScalars.first!.value), modifiers: 0)
            }
            return try XCTUnwrap(state).candidates.map(\.text)
        }

        let baseline = try dinCandidates()
        XCTAssertFalse(baseline.contains("定"), "baseline should not offer ding candidates: \(baseline)")

        var rules = SettingsStore.load().spellerRules
        if let index = rules.firstIndex(where: { $0.match == SpellerRule.dinToDing.match }) {
            rules[index].isEnabled = true
        } else {
            rules.append(SpellerRule(input: SpellerRule.dinToDing.input,
                                     match: SpellerRule.dinToDing.match))
        }
        SettingsStore.saveSpellerRules(rules)
        RimeSpellerPatch.write(rules: rules, asciiPhrases: UserSettings.defaultAsciiPhrases, in: Self.userDirectory)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        RimeRuntime.stop()
        RimeRuntime.start(sharedDataDir: root.appendingPathComponent("Rime/rime-ice"),
                          userDataDir: Self.userDirectory)

        let withFuzzy = try dinCandidates()
        XCTAssertTrue(withFuzzy.contains("定"), "expected ding candidates among \(withFuzzy)")
    }

    /// D23: with the default pass phrases deployed, "e.g." survives the Chinese punctuator
    /// verbatim and space commits it as-is.
    func testEgPassesThroughInChineseMode() throws {
        let engine = RimeEngine()
        var state: EngineState?
        for character in "e.g." {
            state = engine.process(keysym: Int32(character.unicodeScalars.first!.value), modifiers: 0)
            XCTAssertNil(state?.commitText, "no partial commit while typing e.g.")
        }
        XCTAssertEqual(state?.composition?.text, "e.g.")
        let committed = try XCTUnwrap(engine.process(keysym: 0x20, modifiers: 0))
        XCTAssertEqual(committed.commitText, "e.g.")
        XCTAssertNil(committed.composition)
    }

    /// Punctuation outside any pass phrase still commits the Chinese form (D23 regression guard).
    func testPeriodStillCommitsChinesePunctuation() throws {
        let engine = RimeEngine()
        _ = engine.process(keysym: Int32(UInt8(ascii: "h")), modifiers: 0)
        let state = try XCTUnwrap(engine.process(keysym: Int32(UInt8(ascii: ".")), modifiers: 0))
        XCTAssertEqual(state.commitText?.hasSuffix("。"), true)
    }

    /// M8: select_candidate_on_current_page commits the chosen engine candidate (D23's
    /// sibling used by the weight boost).
    func testSelectCandidateOnPageCommitsThatCandidate() throws {
        let engine = RimeEngine()
        var state: EngineState?
        for character in "nihao" {
            state = engine.process(keysym: Int32(character.unicodeScalars.first!.value), modifiers: 0)
        }
        let second = try XCTUnwrap(state?.candidates.dropFirst().first)
        let committed = try XCTUnwrap(engine.selectCandidate(onPageIndex: 1))
        XCTAssertEqual(committed.commitText, second.text)
        XCTAssertNil(committed.composition)
    }

    /// D25: a weight rule for a word no dictionary librime reads contains — typed here as
    /// the abbreviation "sch" — puts HAL's own candidate in front of librime's page and
    /// commits it verbatim, without a user dictionary or a redeploy.
    func testWeightRuleSuppliesAWordLibrimeCannotProduce() throws {
        let session = InputSession(engine: RimeEngine(), settings: {
            UserSettings(spellerRules: [], asciiPhrases: [],
                         weightedCandidates: [WeightRule(input: "sch", candidate: "schematics")])
        })
        var state: EngineState?
        for character in "sch" {
            state = session.handle(RimeKey(keysym: Int32(character.unicodeScalars.first!.value),
                                           mask: 0))
        }
        let candidates = try XCTUnwrap(state?.candidates.map(\.text))
        XCTAssertEqual(candidates.first, "schematics")
        XCTAssertGreaterThan(candidates.count, 1, "librime's own page stays behind it")

        let committed = try XCTUnwrap(session.handle(RimeKey(keysym: 0x20, mask: 0)))
        XCTAssertEqual(committed.commitText, "schematics")
        XCTAssertNil(committed.composition)
    }

    /// D21: writing `menu/page_size` into the patch and redeploying changes how many
    /// candidates librime puts on one page — the real end-to-end path for the
    /// Appearance card's Apply & Restart. Settings are written first, matching what the
    /// Apply button does before the relaunch (`prepareUserDirectory` re-derives the patch
    /// from Settings.json on startup). The deterministic artifact is the rebuilt schema in
    /// the deploy directory, which is exactly what a new rime session reads its page size from.
    func testPageSizePatchChangesMenuSize() throws {
        SettingsStore.saveCandidatePageSize(3)
        RimeSpellerPatch.write(rules: [], asciiPhrases: [],
                               pageSize: SettingsStore.load().candidatePageSize,
                               in: Self.userDirectory)
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        RimeRuntime.stop()
        // Earlier tests in this class have already deployed this directory, and librime is
        // free to decide the deploy it holds is still current — which leaves the schema
        // built before the page size existed, carrying rime-ice's own page_size. Dropping
        // the build directory is what makes this test measure the patch and not that call.
        try? FileManager.default.removeItem(
            at: Self.userDirectory.appendingPathComponent("build"))
        RimeRuntime.start(sharedDataDir: root.appendingPathComponent("Rime/rime-ice"),
                          userDataDir: Self.userDirectory)

        let builtSchema = Self.userDirectory
            .appendingPathComponent("build/rime_ice.schema.yaml")
        let built = try String(contentsOf: builtSchema, encoding: .utf8)
        let pageLine = try XCTUnwrap(
            built.split(separator: "\n").first { $0.contains("page_size") })
        XCTAssertTrue(pageLine.contains("page_size: 3"),
                      "deployed schema should carry page_size 3, got '\(pageLine)'")

        let engine = RimeEngine()
        var state: EngineState?
        for character in "nihao" {
            state = engine.process(keysym: Int32(character.unicodeScalars.first!.value), modifiers: 0)
        }
        let candidates = try XCTUnwrap(state?.candidates)
        XCTAssertEqual(candidates.count, 3, "page_size 3 should yield 3 candidates, got \(candidates.map(\.text))")
        XCTAssertEqual(state?.page.hasNext, true)

        // Put the page size back so the deploy this test leaves behind doesn't decide
        // what a later test in the class starts from.
        SettingsStore.saveCandidatePageSize(UserSettings.defaultCandidatePageSize)
    }
}
