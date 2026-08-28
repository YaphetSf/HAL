/// The composing/idle state machine. Owns the engine and decides what the front end has to
/// render. Knows nothing about IMK or librime.
final class InputSession {
    private let engine: InputEngine
    private let settings: () -> UserSettings
    private(set) var isComposing = false
    /// Non-nil while the pipeline rearranged the page (M8, D25). It owns what the user sees:
    /// selection keys land on the displayed candidate rather than librime's own index, and
    /// so does the highlight — a literal slot has no librime index for the highlight to sit on.
    private var display: Display?

    /// X11 keysyms InputSession acts on itself. KeyEventMapper sends previous/next candidate
    /// for the physical Left/Right keys, the axis HAL's horizontal candidate row moves along.
    private enum Keysym {
        static let space: Int32 = 0x20
        static let one: Int32 = 0x31
        static let nine: Int32 = 0x39
        static let ret: Int32 = 0xFF0D
        static let previousCandidate: Int32 = 0xFF52
        static let nextCandidate: Int32 = 0xFF54
    }

    private struct Display {
        var slots: [CandidateSlot]
        var highlightedIndex: Int
        /// What was last handed to the renderer, replayed as the highlight moves.
        var state: EngineState
    }

    init(engine: InputEngine, settings: @escaping () -> UserSettings = { SettingsStore.load() }) {
        self.engine = engine
        self.settings = settings
    }

    /// Returns the state to render, or nil when the engine passed on the key and the host
    /// app should get it instead.
    func handle(_ key: RimeKey) -> EngineState? {
        if let state = handledByDisplay(key) { return state }
        guard let state = engine.process(keysym: key.keysym, modifiers: key.mask) else {
            return nil
        }
        return rearranged(state)
    }

    /// Flips English/Chinese. The caller ends any composition first: the mode change is not
    /// what should decide the fate of half-typed pinyin.
    func setAsciiMode(_ enabled: Bool) {
        engine.setAsciiMode(enabled)
    }

    /// Sends Return through the engine so its configured commit behavior is preserved.
    func commitWithReturn() -> EngineState? {
        guard isComposing else { return nil }
        guard let state = engine.process(keysym: Keysym.ret, modifiers: 0) else {
            isComposing = false
            display = nil
            return .idle
        }
        isComposing = state.composition != nil
        display = nil
        return state
    }

    /// Drops a composition in progress without committing it. Called when the client goes
    /// away, so switching apps mid-composition cannot leave orphan marked text behind.
    func reset() -> EngineState? {
        guard isComposing else { return nil }
        engine.clear()
        isComposing = false
        display = nil
        return .idle
    }

    // MARK: - Candidate pipeline (M8)

    /// Space, 1–9 and the highlight keys act on the rearranged page, not on librime's
    /// idea of it. Returning nil leaves the key to the engine.
    private func handledByDisplay(_ key: RimeKey) -> EngineState? {
        guard var display, isComposing, key.mask == 0 else { return nil }
        switch key.keysym {
        case Keysym.previousCandidate, Keysym.nextCandidate:
            let moved = display.highlightedIndex + (key.keysym == Keysym.nextCandidate ? 1 : -1)
            // Stop at both ends: paging would recompute the page under a highlight librime
            // never knew about.
            if display.slots.indices.contains(moved) {
                display.highlightedIndex = moved
                display.state.highlightedIndex = moved
                self.display = display
            }
            return display.state
        case Keysym.space:
            return commit(display.slots[display.highlightedIndex])
        case Keysym.one...Keysym.nine:
            let index = Int(key.keysym - Keysym.one)
            guard display.slots.indices.contains(index) else { return nil }
            return commit(display.slots[index])
        default:
            return nil
        }
    }

    private func commit(_ slot: CandidateSlot) -> EngineState? {
        switch slot {
        case .engine(let index):
            guard let state = engine.selectCandidate(onPageIndex: index) else { return nil }
            isComposing = state.composition != nil
            display = nil
            return state
        case .literal(let candidate):
            // librime has no index for this one, so the composition is dropped and the
            // rule's own text goes to the client (D25).
            engine.clear()
            isComposing = false
            display = nil
            var state = EngineState.idle
            state.commitText = candidate.text
            return state
        }
    }

    private func rearranged(_ original: EngineState) -> EngineState {
        var state = original
        isComposing = state.composition != nil
        display = nil
        guard let input = state.composition?.text, !state.candidates.isEmpty else { return state }

        let pipeline = CandidatePipeline(
            processors: [WeightTableProcessor(rules: settings().weightedCandidates)]
        )
        guard let slots = pipeline.arrange(candidates: state.candidates, input: input,
                                           page: state.page),
              slots != original.candidates.indices.map(CandidateSlot.engine)
        else { return state }

        state.candidates = slots.map { slot in
            switch slot {
            case .engine(let index): return original.candidates[index]
            case .literal(let candidate): return candidate
            }
        }
        state.highlightedIndex = 0
        display = Display(slots: slots, highlightedIndex: 0, state: state)
        return state
    }
}
