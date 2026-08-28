import Foundation
import OSLog
import RimeBridge

private let log = Logger(subsystem: "com.hal.inputmethod", category: "engine")

/// One librime session, owned by one input controller.
///
/// Every `RIME_STRUCT` librime fills in has to be freed through librime's matching free
/// function, so each read below is paired with one.
final class RimeEngine: InputEngine {
    private var sessionID: RimeSessionId = 0

    init() {
        createSession()
    }

    deinit {
        guard sessionID != 0, let api = RimeRuntime.api else { return }
        _ = api.destroy_session(sessionID)
    }

    func process(keysym: Int32, modifiers: Int32) -> EngineState? {
        guard let api = RimeRuntime.api else { return nil }
        guard ensureSession(api) else { return nil }
        guard api.process_key(sessionID, keysym, modifiers) != 0 else { return nil }
        return readState(api)
    }

    func selectCandidate(onPageIndex index: Int) -> EngineState? {
        guard let api = RimeRuntime.api else { return nil }
        guard ensureSession(api) else { return nil }
        guard api.select_candidate_on_current_page(sessionID, index) != 0 else { return nil }
        return readState(api)
    }

    func setAsciiMode(_ enabled: Bool) {
        guard let api = RimeRuntime.api, sessionID != 0 else { return }
        api.set_option(sessionID, "ascii_mode", enabled ? 1 : 0)
    }

    func clear() {
        guard let api = RimeRuntime.api, sessionID != 0 else { return }
        api.clear_composition(sessionID)
    }

    // MARK: - Session

    private func createSession() {
        guard let api = RimeRuntime.api else { return }
        sessionID = api.create_session()
        if sessionID == 0 {
            log.error("could not create a rime session")
        }
    }

    /// A session can go stale when librime redeploys. Rebuilding it costs one composition,
    /// which beats any of the alternatives (D13).
    private func ensureSession(_ api: RimeApi) -> Bool {
        if sessionID != 0, api.find_session(sessionID) != 0 { return true }
        log.info("rime session \(self.sessionID) is stale, recreating")
        createSession()
        return sessionID != 0
    }

    // MARK: - Reading state

    private func readState(_ api: RimeApi) -> EngineState {
        var state = EngineState.idle
        state.commitText = takeCommit(api)

        var context = RimeContext()
        rimeStructInit(&context)
        guard api.get_context(sessionID, &context) != 0 else { return state }
        defer { _ = api.free_context(&context) }

        if context.composition.length > 0, let preedit = context.composition.preedit {
            let text = String(cString: preedit)
            state.composition = Composition(text: text,
                                            cursor: Self.utf16Offset(ofUTF8Byte: Int(context.composition.cursor_pos),
                                                                     in: text))
        }
        state.candidates = candidates(in: context.menu)
        state.highlightedIndex = Int(context.menu.highlighted_candidate_index)
        state.page = EngineState.Page(index: Int(context.menu.page_no),
                                      hasPrev: context.menu.page_no > 0,
                                      hasNext: context.menu.is_last_page == 0)
        return state
    }

    private func takeCommit(_ api: RimeApi) -> String? {
        var commit = RimeCommit()
        rimeStructInit(&commit)
        guard api.get_commit(sessionID, &commit) != 0 else { return nil }
        defer { _ = api.free_commit(&commit) }
        return commit.text.map { String(cString: $0) }
    }

    /// librime reports the caret as a byte offset into the UTF-8 preedit, while everything
    /// above wants an offset it can hand to AppKit. They only agree while the preedit is
    /// pure ASCII, which stops being true as soon as part of a phrase is picked.
    private static func utf16Offset(ofUTF8Byte byte: Int, in text: String) -> Int {
        let bytes = Array(text.utf8)
        guard byte > 0 else { return 0 }
        guard byte < bytes.count else { return text.utf16.count }
        return String(decoding: bytes[0..<byte], as: UTF8.self).utf16.count
    }

    private func candidates(in menu: RimeMenu) -> [Candidate] {
        guard let list = menu.candidates, menu.num_candidates > 0 else { return [] }
        return (0..<Int(menu.num_candidates)).map { index in
            let item = list[index]
            return Candidate(text: item.text.map { String(cString: $0) } ?? "",
                             comment: item.comment.map { String(cString: $0) })
        }
    }
}
