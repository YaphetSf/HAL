import XCTest

/// The AI Editing phase machine against a scripted engine — the interaction that used to
/// be split between the input controller and the panel singleton, now testable in one place.
@MainActor
final class AIEditControllerTests: XCTestCase {
    private var engine = StubAIEditEngine()
    private var settings = AIEditSettings()
    private var states: [AIEditController.State] = []

    private func makeController() -> AIEditController {
        engine = StubAIEditEngine()
        states = []
        let controller = AIEditController(settingsProvider: { [self] in settings },
                                          engineProvider: { [self] _ in engine })
        controller.onChange = { [weak self] state in self?.states.append(state) }
        return controller
    }

    func testBeginOpensTheChoiceStep() {
        let controller = makeController()

        controller.begin(snapshot: Self.snapshot, caret: Self.caret)

        XCTAssertEqual(controller.phase, .choosing)
        XCTAssertEqual(controller.state.original, "Hello wrold")
        XCTAssertEqual(controller.state.caret, Self.caret)
    }

    func testSelectRunsTheEngineAndDeliversAResult() async {
        let controller = makeController()
        controller.begin(snapshot: Self.snapshot, caret: Self.caret)
        engine.reply = .success("Hello world")

        controller.select(.correct)
        XCTAssertEqual(controller.phase, .generating)
        await controller.settle()

        XCTAssertEqual(controller.phase, .result)
        XCTAssertEqual(engine.lastInstructions,
                       AIEditAction.correct.instructions(using: AIEditSettings()))
        XCTAssertEqual(engine.lastText, "Hello wrold")
        let replacement = controller.replacement()
        XCTAssertEqual(replacement?.text, "Hello world")
        XCTAssertEqual(replacement?.action, .correct)
        XCTAssertEqual(replacement?.snapshot, Self.snapshot)
        XCTAssertTrue(states.contains { $0.phase == .generating })
    }

    func testRephraseUsesTheUserOwnedPrompt() async {
        let controller = makeController()
        settings.rephrasePrompt = "CUSTOM PROMPT"
        controller.begin(snapshot: Self.snapshot, caret: Self.caret)

        controller.select(.rephrase)
        await controller.settle()

        XCTAssertEqual(engine.lastInstructions, "CUSTOM PROMPT")
    }

    func testCorrectKeepsItsBuiltInInstructions() async {
        let controller = makeController()
        settings.rephrasePrompt = "CUSTOM PROMPT"
        controller.begin(snapshot: Self.snapshot, caret: Self.caret)

        controller.select(.correct)
        await controller.settle()

        XCTAssertEqual(engine.lastInstructions,
                       AIEditAction.correct.instructions(using: settings))
        XCTAssertNotEqual(engine.lastInstructions, "CUSTOM PROMPT")
    }

    func testEngineFailureBecomesAFailureState() async {
        let controller = makeController()
        controller.begin(snapshot: Self.snapshot, caret: Self.caret)
        engine.reply = .failure(AIEditError.emptyResponse)

        controller.select(.correct)
        await controller.settle()

        XCTAssertEqual(controller.phase, .failure)
        XCTAssertEqual(controller.state.failureMessage,
                       "AI Editing failed: \(AIEditError.emptyResponse.localizedDescription)")
        XCTAssertNil(controller.replacement())
    }

    func testDismissDuringGenerationCancelsAndNeverShowsAResult() async {
        let controller = makeController()
        controller.begin(snapshot: Self.snapshot, caret: Self.caret)
        engine.holdsUntilCancelled = true

        controller.select(.correct)
        XCTAssertEqual(controller.phase, .generating)

        controller.dismiss()
        XCTAssertEqual(controller.phase, .hidden)
        await controller.drain()
        XCTAssertEqual(controller.phase, .hidden, "a cancelled run must not surface anything")
        XCTAssertNil(controller.replacement())
    }

    func testANewSelectionCancelsTheRunInFlight() async {
        let controller = makeController()
        controller.begin(snapshot: Self.snapshot, caret: Self.caret)
        engine.holdsUntilCancelled = true
        controller.select(.correct)

        controller.begin(snapshot: Self.snapshot, caret: Self.caret)
        await controller.drain()

        XCTAssertEqual(controller.phase, .choosing, "the new selection must win the panel")
        XCTAssertTrue(engine.cancelled)
    }

    func testReplacementIsNilOutsideTheResultPhase() {
        let controller = makeController()

        XCTAssertNil(controller.replacement())
        controller.begin(snapshot: Self.snapshot, caret: Self.caret)
        XCTAssertNil(controller.replacement())
    }

    func testFailPreflightShowsFailureWithoutASnapshot() {
        let controller = makeController()

        controller.fail("Select 1–1500 editable characters first.", caret: Self.caret)

        XCTAssertEqual(controller.phase, .failure)
        XCTAssertNil(controller.replacement())
    }

    // MARK: - Fixtures

    private static let snapshot = AIEditSnapshot(text: "Hello wrold",
                                                 range: NSRange(location: 0, length: 11),
                                                 clientID: "com.example.editor")
    private static let caret = CGRect(x: 10, y: 20, width: 1, height: 17)
}

/// Scripted stand-in for the edit engines. No mocking framework, by D2. The mutable
/// scripting fields are `nonisolated(unsafe)` because the whole interaction — test,
/// controller, and generation task — runs on the main actor.
private final class StubAIEditEngine: AIEditEngine {
    nonisolated(unsafe) var reply: Result<String, Error> = .success("replacement")
    /// When set, `edit` parks until the task is cancelled — the dismiss-during-generation case.
    nonisolated(unsafe) var holdsUntilCancelled = false
    nonisolated(unsafe) private(set) var lastInstructions: String?
    nonisolated(unsafe) private(set) var lastText: String?
    nonisolated(unsafe) private(set) var cancelled = false

    func edit(instructions: String, text: String) async throws -> String {
        lastInstructions = instructions
        lastText = text
        if holdsUntilCancelled {
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                cancelled = true
                throw error
            }
        }
        return try reply.get()
    }
}

@MainActor
private extension AIEditController {
    /// Lets the generation task run to completion: the task is @MainActor too, so yielding
    /// from the test hands it the main actor until it finishes.
    func settle() async {
        for _ in 0..<100 {
            await Task.yield()
            if phase != .generating { return }
        }
        XCTFail("generation never settled")
    }

    /// Yields long enough for a cancelled generation task to observe the cancellation.
    func drain() async {
        for _ in 0..<10 { await Task.yield() }
    }
}
