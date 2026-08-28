/// Everything Core knows about an input engine. The only implementation is RimeEngine;
/// the protocol exists so Core never sees librime (PLAN.md §7.1).
protocol InputEngine {
    /// Feeds one key press to the engine.
    /// - Parameters:
    ///   - keysym: X11 keysym, which for printable ASCII is the character's own code point.
    ///   - modifiers: librime modifier mask.
    /// - Returns: nil when the engine did not consume the key, so the host app should get it.
    func process(keysym: Int32, modifiers: Int32) -> EngineState?

    /// Commits the candidate at the given index of the current page. Used when a
    /// `CandidateProcessor` reordered the page and a selection key must land on the
    /// candidate the user saw, not the engine's own order (M8).
    func selectCandidate(onPageIndex index: Int) -> EngineState?

    /// Drops any composition in progress without committing it.
    func clear()

    /// Switches between Chinese and English. English is the engine passing every printable
    /// key straight back to the host app. Write-only on purpose: the front end owns the mode
    /// and tells the engine, so there is one answer to which mode HAL is in (D11).
    func setAsciiMode(_ enabled: Bool)
}
