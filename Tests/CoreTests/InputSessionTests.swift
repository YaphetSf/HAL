import XCTest

/// Scripted stand-in for RimeEngine. No mocking framework, by D2.
private final class StubEngine: InputEngine {
    var replies: [EngineState?] = []
    private(set) var clearCount = 0
    private(set) var received: [Int32] = []
    private(set) var asciiMode = false
    private(set) var selectedPageIndexes: [Int] = []

    func process(keysym: Int32, modifiers: Int32) -> EngineState? {
        received.append(keysym)
        return replies.isEmpty ? nil : replies.removeFirst()
    }

    func selectCandidate(onPageIndex index: Int) -> EngineState? {
        selectedPageIndexes.append(index)
        return replies.isEmpty ? nil : replies.removeFirst()
    }

    func clear() {
        clearCount += 1
    }

    func commitComposition() -> EngineState? {
        replies.isEmpty ? nil : replies.removeFirst()
    }

    func setAsciiMode(_ enabled: Bool) {
        asciiMode = enabled
    }
}

private func composing(_ text: String, cursor: Int? = nil) -> EngineState {
    var state = EngineState.idle
    state.composition = Composition(text: text, cursor: cursor ?? text.utf16.count)
    return state
}

private func key(_ keysym: Int32) -> RimeKey {
    RimeKey(keysym: keysym, mask: 0)
}

private func committing(_ text: String) -> EngineState {
    var state = EngineState.idle
    state.commitText = text
    return state
}

final class InputSessionTests: XCTestCase {
    func testKeyTheEngineIgnoresIsLeftToTheHostApp() {
        let engine = StubEngine()
        let session = InputSession(engine: engine)

        XCTAssertNil(session.handle(key(0x41)))
        XCTAssertFalse(session.isComposing)
    }

    func testCompositionIsReportedAndRemembered() {
        let engine = StubEngine()
        engine.replies = [composing("ni")]
        let session = InputSession(engine: engine)

        let state = session.handle(key(0x6E))
        XCTAssertEqual(state?.composition, Composition(text: "ni", cursor: 2))
        XCTAssertNil(state?.commitText)
        XCTAssertTrue(session.isComposing)
    }

    func testCommitEndsTheComposition() {
        let engine = StubEngine()
        engine.replies = [composing("nihao"), committing("你好")]
        let session = InputSession(engine: engine)

        _ = session.handle(key(0x6E))
        let state = session.handle(key(0x20))
        XCTAssertEqual(state?.commitText, "你好")
        XCTAssertNil(state?.composition, "marked text must be erased once it is committed")
        XCTAssertFalse(session.isComposing)
    }

    func testResetWhileComposingClearsTheEngine() {
        let engine = StubEngine()
        engine.replies = [composing("ni")]
        let session = InputSession(engine: engine)
        _ = session.handle(key(0x6E))

        let state = session.reset()
        XCTAssertEqual(engine.clearCount, 1)
        XCTAssertEqual(state, .idle, "the client still has to be told to erase")
        XCTAssertFalse(session.isComposing)
    }

    func testResetWhileIdleDoesNothing() {
        let engine = StubEngine()
        let session = InputSession(engine: engine)

        XCTAssertNil(session.reset())
        XCTAssertEqual(engine.clearCount, 0)
    }

    func testComposeCommitsWithReturnWhileComposing() {
        let engine = StubEngine()
        engine.replies = [composing("nihao"), committing("nihao")]
        let session = InputSession(engine: engine)
        _ = session.handle(key(0x6E))

        let state = session.commitWithReturn()
        XCTAssertEqual(state?.commitText, "nihao")
        XCTAssertNil(state?.composition, "marked text must be gone once committed")
        XCTAssertFalse(session.isComposing)
    }

    func testCommitWithReturnWhileIdleDoesNothing() {
        let engine = StubEngine()
        let session = InputSession(engine: engine)

        XCTAssertNil(session.commitWithReturn())
        XCTAssertFalse(session.isComposing)
    }

    func testCommitWithReturnUsesReturnKey() {
        let engine = StubEngine()
        engine.replies = [composing("nihao"), committing("nihao")]
        let session = InputSession(engine: engine)
        _ = session.handle(key(0x6E))

        let state = session.commitWithReturn()
        XCTAssertEqual(state?.commitText, "nihao")
        XCTAssertEqual(engine.received, [0x6E, 0xFF0D])
        XCTAssertFalse(session.isComposing)
    }

    // MARK: - Manual weights (M8, D25)

    private func weightedSettings(_ rules: [WeightRule]) -> UserSettings {
        UserSettings(spellerRules: [], asciiPhrases: [], weightedCandidates: rules)
    }

    private func paging(_ input: String, _ candidates: [String],
                        highlighted: Int = 0, page: Int = 0) -> EngineState {
        var state = composing(input)
        state.candidates = candidates.map { Candidate(text: $0, comment: nil) }
        state.highlightedIndex = highlighted
        state.page = EngineState.Page(index: page, hasPrev: page > 0, hasNext: true)
        return state
    }

    func testWeightedCandidateIsBoostedToTheFront() {
        let engine = StubEngine()
        engine.replies = [paging("cizu", ["次序", "词组", "词库"])]
        let session = InputSession(engine: engine, settings: {
            self.weightedSettings([WeightRule(input: "cizu", candidate: "词组")])
        })

        let state = session.handle(key(0x75))  // "u", the last key of "cizu"
        XCTAssertEqual(state?.candidates.map(\.text), ["词组", "次序", "词库"])
        XCTAssertEqual(state?.highlightedIndex, 0)
    }

    func testSpaceCommitsTheBoostedCandidateThroughTheEngineIndex() {
        let engine = StubEngine()
        engine.replies = [paging("cizu", ["次序", "词组", "词库"]), committing("词组")]
        let session = InputSession(engine: engine, settings: {
            self.weightedSettings([WeightRule(input: "cizu", candidate: "词组")])
        })
        _ = session.handle(key(0x75))

        let state = session.handle(key(0x20))
        XCTAssertEqual(engine.selectedPageIndexes, [1], "display front maps back to engine index 1")
        XCTAssertEqual(engine.received, [0x75], "space must not reach process_key")
        XCTAssertEqual(state?.commitText, "词组")
        XCTAssertFalse(session.isComposing)
    }

    func testDigitsSelectTheDisplayedCandidate() {
        let engine = StubEngine()
        engine.replies = [paging("cizu", ["次序", "词组", "词库"]), committing("次序")]
        let session = InputSession(engine: engine, settings: {
            self.weightedSettings([WeightRule(input: "cizu", candidate: "词组")])
        })
        _ = session.handle(key(0x75))

        _ = session.handle(key(0x32))  // "2" is 次序 after the boost
        XCTAssertEqual(engine.selectedPageIndexes, [0])
    }

    func testWithoutWeightsSelectionGoesThroughTheEngine() {
        let engine = StubEngine()
        engine.replies = [paging("cizu", ["次序", "词组"]), committing("次序")]
        let session = InputSession(engine: engine, settings: { self.weightedSettings([]) })
        _ = session.handle(key(0x75))

        _ = session.handle(key(0x20))
        XCTAssertTrue(engine.selectedPageIndexes.isEmpty)
        XCTAssertEqual(engine.received, [0x75, 0x20])
    }

    func testWeightedCandidateTheEngineCannotProduceIsInserted() {
        let engine = StubEngine()
        engine.replies = [paging("schematics", ["赛车马蹄才是", "赛车马蹄", "是"])]
        let session = InputSession(engine: engine, settings: {
            self.weightedSettings([WeightRule(input: "schematics", candidate: "schematics")])
        })

        let state = session.handle(key(0x73))
        XCTAssertEqual(state?.candidates.map(\.text),
                       ["schematics", "赛车马蹄才是", "赛车马蹄", "是"])
        XCTAssertEqual(state?.highlightedIndex, 0)
    }

    func testSpaceCommitsTheInsertedCandidateWithoutTheEngine() {
        let engine = StubEngine()
        engine.replies = [paging("schematics", ["赛车马蹄才是", "是"])]
        let session = InputSession(engine: engine, settings: {
            self.weightedSettings([WeightRule(input: "schematics", candidate: "schematics")])
        })
        _ = session.handle(key(0x73))

        let state = session.handle(key(0x20))
        XCTAssertEqual(state?.commitText, "schematics")
        XCTAssertNil(state?.composition, "marked text must be erased once it is committed")
        XCTAssertTrue(state?.candidates.isEmpty ?? false)
        XCTAssertEqual(engine.clearCount, 1, "the composition librime still holds has to go")
        XCTAssertTrue(engine.selectedPageIndexes.isEmpty)
        XCTAssertEqual(engine.received, [0x73], "space must not reach process_key")
        XCTAssertFalse(session.isComposing)
    }

    func testDigitPastTheInsertedCandidateStillReachesTheEngine() {
        let engine = StubEngine()
        engine.replies = [paging("schematics", ["赛车马蹄才是", "是"]), committing("是")]
        let session = InputSession(engine: engine, settings: {
            self.weightedSettings([WeightRule(input: "schematics", candidate: "schematics")])
        })
        _ = session.handle(key(0x73))

        _ = session.handle(key(0x33))  // "3" is the engine's second candidate after the insert
        XCTAssertEqual(engine.selectedPageIndexes, [1])
    }

    func testNothingIsInsertedPastTheFirstPage() {
        let engine = StubEngine()
        engine.replies = [paging("schematics", ["赛车马蹄才是", "是"], page: 1)]
        let session = InputSession(engine: engine, settings: {
            self.weightedSettings([WeightRule(input: "schematics", candidate: "schematics")])
        })

        let state = session.handle(key(0x73))
        XCTAssertEqual(state?.candidates.map(\.text), ["赛车马蹄才是", "是"])
    }

    func testHighlightMovesOverTheRearrangedPageAndSpaceFollowsIt() {
        let engine = StubEngine()
        engine.replies = [paging("schematics", ["赛车马蹄才是", "是"]), committing("赛车马蹄才是")]
        let session = InputSession(engine: engine, settings: {
            self.weightedSettings([WeightRule(input: "schematics", candidate: "schematics")])
        })
        _ = session.handle(key(0x73))

        let moved = session.handle(key(0xFF54))  // right, i.e. next candidate
        XCTAssertEqual(moved?.highlightedIndex, 1)
        XCTAssertEqual(moved?.candidates.map(\.text), ["schematics", "赛车马蹄才是", "是"])
        XCTAssertEqual(engine.received, [0x73], "the highlight is HAL's while the page is rearranged")

        let state = session.handle(key(0x20))
        XCTAssertEqual(engine.selectedPageIndexes, [0], "space commits what is highlighted")
        XCTAssertEqual(state?.commitText, "赛车马蹄才是")
    }

    func testHighlightStopsAtBothEndsOfTheRearrangedPage() {
        let engine = StubEngine()
        engine.replies = [paging("schematics", ["赛车马蹄才是"])]
        let session = InputSession(engine: engine, settings: {
            self.weightedSettings([WeightRule(input: "schematics", candidate: "schematics")])
        })
        _ = session.handle(key(0x73))

        XCTAssertEqual(session.handle(key(0xFF52))?.highlightedIndex, 0, "already at the front")
        XCTAssertEqual(session.handle(key(0xFF54))?.highlightedIndex, 1)
        XCTAssertEqual(session.handle(key(0xFF54))?.highlightedIndex, 1, "already at the end")
        XCTAssertEqual(engine.received, [0x73])
    }
}

final class WeightTableProcessorTests: XCTestCase {
    private let candidates = ["次序", "词组", "词库"].map { Candidate(text: $0, comment: nil) }

    private func arrange(_ rules: [WeightRule], _ input: String,
                         page: Int = 0) -> [CandidateSlot]? {
        WeightTableProcessor(rules: rules)
            .arrange(candidates: candidates, input: input,
                     page: EngineState.Page(index: page, hasPrev: page > 0, hasNext: true))
    }

    func testMatchingInputBoostsTheCandidate() {
        XCTAssertEqual(arrange([WeightRule(input: "cizu", candidate: "词组")], "cizu"),
                       [.engine(1), .engine(0), .engine(2)])
    }

    func testSeparatorsAndCaseAreIgnored() {
        XCTAssertEqual(arrange([WeightRule(input: "CiZu", candidate: "词组")], "ci zu"),
                       [.engine(1), .engine(0), .engine(2)])
    }

    func testNoMatchLeavesThePageAlone() {
        XCTAssertNil(arrange([WeightRule(input: "cizu", candidate: "词组")], "ciku"))
        XCTAssertNil(arrange([WeightRule(input: "cizu", candidate: "次序")], "cizu"),
                     "already first: nothing to reorder")
    }

    func testAnAbsentCandidateIsSuppliedByHAL() {
        XCTAssertEqual(arrange([WeightRule(input: "cizu", candidate: "不在")], "cizu"),
                       [.literal(Candidate(text: "不在", comment: nil)),
                        .engine(0), .engine(1), .engine(2)])
        XCTAssertNil(arrange([WeightRule(input: "cizu", candidate: "不在")], "cizu", page: 1),
                     "one rule stays one candidate: later pages are the engine's")
    }
}
