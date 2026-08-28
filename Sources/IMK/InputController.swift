import AppKit
import Carbon.HIToolbox
import InputMethodKit
import OSLog

private let log = Logger(subsystem: "com.hal.inputmethod", category: "imk")

/// Translates key events into rendering commands. All input method logic lives in
/// Core/InputSession; this class only speaks IMK.
///
/// Deliberately not renamed with `@objc`: Info.plist declares the module-qualified name
/// `HAL_input.InputController`, which resolves through Swift's default runtime name (D15).
/// The module name follows the target's PRODUCT_NAME, so renaming the target means editing
/// that Info.plist string too -- a mismatch fails silently at controller instantiation.
///
/// Isolation note: IMK calls all of this on the main thread, but the overrides cannot say so
/// — an override may not add isolation its ObjC superclass lacks, and `@preconcurrency` only
/// moves the problem (the override then cannot pass `self`, `event` or `sender` to any
/// isolated method). So Core and Engine are plain nonisolated types, and the only
/// `MainActor.assumeIsolated` hops are the AppKit-bound panel calls, which capture nothing
/// but Sendable values.
final class InputController: IMKInputController {
    private var session: InputSession?
    private var englishProfile: EnglishProfile = .direct
    private let englishCompletion = EnglishCompletionSession()
    private var englishSuggestionVisible = false
    /// Static so the isolation hop in `menu()` captures no `self`; only one input method
    /// menu can be open at a time anyway.
    nonisolated(unsafe) private static var modeMenu: NSMenu?

    /// English/Chinese is one setting for the whole input method, not one per client: IMK
    /// hands each text field its own controller, and a per-client flag would silently fall
    /// back to Chinese every time a new one appeared.
    nonisolated(unsafe) private static var isAsciiMode = false

    /// IMK's "leave the document alone" marker for both range arguments.
    private static let noRange = NSRange(location: NSNotFound, length: 0)

    /// The menu behind the input method's own icon, showing the same flag the menu bar item
    /// shows. Reading it back out of librime instead would be a second answer to the same
    /// question, and the two would eventually disagree.
    ///
    /// The menu is built inside the isolation hop and kept in a property rather than
    /// returned out of it, because NSMenu is not Sendable and so cannot cross.
    override func menu() -> NSMenu! {
        let isAscii = Self.isAsciiMode
        let englishProfile = englishProfile
        MainActor.assumeIsolated {
            let menu = Self.modeMenu ?? NSMenu()
            menu.removeAllItems()
            let title = isAscii ? (englishProfile == .assist ? "English Assist (EN+)" : "English Direct (EN)") : "中文"
            let mode = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            mode.isEnabled = false
            menu.addItem(mode)
            Self.modeMenu = menu
        }
        return Self.modeMenu
    }

    /// Caps Lock reaches HAL as F18 (D11), an ordinary key-down like any other, so this is
    /// the whole event mask the controller needs.
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    override func activateServer(_ sender: Any!) {
        log.info("activateServer client=\(Self.clientID(sender), privacy: .public)")
        if session == nil { session = InputSession(engine: RimeEngine()) }
        session?.setAsciiMode(Self.isAsciiMode)
        resetEnglishCompletion()
        publishMode()
    }

    /// Leaving a client with marked text still on screen is the classic input method bug:
    /// the text stays in the app we just left and nothing can remove it.
    override func deactivateServer(_ sender: Any!) {
        log.info("deactivateServer client=\(Self.clientID(sender), privacy: .public)")
        resetEnglishCompletion()
        hideModeFeedback()
        if let state = endComposition() { Self.draw(state, client: sender) }
    }

    /// IMK calls this when the client wants the composition resolved right now, such as on a
    /// click elsewhere in the document.
    override func commitComposition(_ sender: Any!) {
        resetEnglishCompletion()
        if let state = endComposition() { Self.draw(state, client: sender) }
    }

    override func hidePalettes() {
        resetEnglishCompletion()
        hideModeFeedback()
    }

    override func inputControllerWillClose() {
        resetEnglishCompletion()
        hideModeFeedback()
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        switch event.type {
        case .keyDown:
            // `characters` is only readable on key events; other event types raise (D13).
            log.info("keyDown code=\(event.keyCode) chars=\(event.characters ?? "", privacy: .public) mods=\(event.modifierFlags.rawValue)")
            if event.keyCode == UInt16(kVK_F18) {
                return event.modifierFlags.contains(.shift)
                    ? switchEnglishProfile(client: sender)
                    : switchLanguage(client: sender)
            }
            if Self.isAsciiMode {
                return handleEnglish(event, client: sender)
            }
            guard let key = KeyEventMapper.map(Self.keyEvent(from: event)) else { return false }
            guard let state = consume(key, caret: Self.caretRect(client: sender)) else { return false }
            Self.draw(state, client: sender)
            return true

        default:
            return false
        }
    }

    /// Caps Lock, remapped to F18 before it reaches IMK (D11). Switching inside HAL rather
    /// than switching the system input source is what makes it instant: a real input-source
    /// switch takes 400 ms to 1.5 s to reach the client, and every key typed in that window
    /// lands in the source being left. Nothing here waits on anything.
    private func switchLanguage(client sender: Any!) -> Bool {
        let caret = Self.caretRect(client: sender)
        Self.isAsciiMode.toggle()
        let name = Self.isAsciiMode ? (englishProfile == .assist ? "EN+" : "EN") : "Chinese"
        log.info("mode=\(name, privacy: .public)")
        resetEnglishCompletion()
        if let state = commitWithReturn() { Self.draw(state, client: sender) }
        session?.setAsciiMode(Self.isAsciiMode)
        publishMode()
        showModeFeedback(caret: caret)
        return true
    }

    /// Shift+Caps is a second, explicit axis: it changes how English behaves without asking
    /// HAL to guess whether the focused field contains chat or code (D22). From Chinese it
    /// goes straight to EN+, which keeps the common "I want assisted English now" gesture
    /// to one chord; ordinary Caps returns to Chinese afterwards.
    private func switchEnglishProfile(client sender: Any!) -> Bool {
        let caret = Self.caretRect(client: sender)
        resetEnglishCompletion()
        if !Self.isAsciiMode {
            if let state = endComposition() { Self.draw(state, client: sender) }
            Self.isAsciiMode = true
            englishProfile = .assist
            session?.setAsciiMode(true)
        } else {
            englishProfile = englishProfile == .assist ? .direct : .assist
        }
        log.info("englishProfile=\(self.englishProfile == .assist ? "EN+" : "EN", privacy: .public)")
        publishMode()
        showModeFeedback(caret: caret)
        return true
    }

    // MARK: - English Assist

    /// EN passes through here untouched. EN+ also returns false for ordinary typing; it only
    /// consumes Left/Right, Tab, and Esc only while its own suggestion is visibly active.
    private func handleEnglish(_ event: NSEvent, client sender: Any!) -> Bool {
        guard englishProfile == .assist else { return false }

        let modifiers = Self.modifiers(from: event.modifierFlags)
        if !modifiers.intersection([.command, .control, .option]).isEmpty {
            resetEnglishCompletion()
            return false
        }

        switch Int(event.keyCode) {
        case kVK_Tab:
            guard englishSuggestionVisible,
                  let suffix = englishCompletion.acceptSuggestion(),
                  let client = sender as? IMKTextInput else {
                resetEnglishCompletion()
                return false
            }
            client.insertText(suffix, replacementRange: Self.noRange)
            englishSuggestionVisible = false
            MainActor.assumeIsolated { CandidatePanel.shared.hide() }
            log.info("EN+ accepted suffix=\(suffix, privacy: .public)")
            return true

        case kVK_Escape:
            guard englishSuggestionVisible else {
                resetEnglishCompletion()
                return false
            }
            resetEnglishCompletion()
            return true

        case kVK_LeftArrow, kVK_RightArrow:
            guard englishSuggestionVisible else {
                resetEnglishCompletion()
                return false
            }
            englishCompletion.moveHighlight(by: Int(event.keyCode) == kVK_LeftArrow ? -1 : 1)
            showEnglishSuggestions()
            return true

        case kVK_Delete:
            let selection = Self.selectionRange(client: sender)
            englishCompletion.deleteBackward(caretLocation: selection?.location,
                                             selectionLength: selection?.length ?? 0)
            scheduleEnglishRefreshIfNeeded()
            return false

        default:
            let selection = Self.selectionRange(client: sender)
            guard englishCompletion.append(event.characters ?? "",
                                           caretLocation: selection?.location) else {
                resetEnglishCompletion()
                return false
            }
            scheduleEnglishRefreshIfNeeded()
            return false
        }
    }

    private func scheduleEnglishRefreshIfNeeded() {
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(refreshEnglishSuggestion),
                                               object: nil)
        englishSuggestionVisible = false
        MainActor.assumeIsolated { CandidatePanel.shared.hide() }
        guard englishCompletion.canRequestSuggestion else { return }
        let delay = SettingsStore.load().englishCompletionDelay
        perform(#selector(refreshEnglishSuggestion), with: nil,
                afterDelay: delay)
    }

    @objc private func refreshEnglishSuggestion() {
        guard Self.isAsciiMode, englishProfile == .assist,
              englishCompletion.canRequestSuggestion else { return }
        let prefix = englishCompletion.prefix
        let candidates = NSSpellChecker.shared.completions(
            forPartialWordRange: NSRange(location: 0, length: prefix.utf16.count),
            in: prefix,
            language: "en_GB",
            inSpellDocumentWithTag: 0
        ) ?? []
        englishCompletion.updateSuggestions(candidates)
        guard !englishCompletion.suggestions.isEmpty else {
            englishSuggestionVisible = false
            MainActor.assumeIsolated { CandidatePanel.shared.hide() }
            return
        }
        englishSuggestionVisible = true
        showEnglishSuggestions()
    }

    private func showEnglishSuggestions() {
        guard englishSuggestionVisible, !englishCompletion.suggestions.isEmpty else { return }
        let prefix = englishCompletion.prefix
        let suggestions = englishCompletion.suggestions
        let highlightedIndex = englishCompletion.highlightedIndex
        let caret = Self.caretRect(client: client())
        MainActor.assumeIsolated {
            CandidatePanel.shared.showEnglish(prefix: prefix,
                                              suggestions: suggestions,
                                              highlightedIndex: highlightedIndex,
                                              caret: caret)
        }
    }

    private func resetEnglishCompletion() {
        NSObject.cancelPreviousPerformRequests(withTarget: self,
                                               selector: #selector(refreshEnglishSuggestion),
                                               object: nil)
        englishCompletion.reset()
        englishSuggestionVisible = false
        MainActor.assumeIsolated { CandidatePanel.shared.hide() }
    }

    private func publishMode() {
        let isAscii = Self.isAsciiMode
        let profile = englishProfile
        MainActor.assumeIsolated {
            ModeState.shared.isAscii = isAscii
            ModeState.shared.englishProfile = profile
        }
    }

    /// D24's boundary: the input controller publishes only semantic mode + caret. Window
    /// behavior and the replaceable experimental skin both live under Panel/.
    private func showModeFeedback(caret: NSRect) {
        let mode: ModeFeedbackMode
        if !Self.isAsciiMode {
            mode = .chinese
        } else {
            mode = englishProfile == .assist ? .englishAssist : .english
        }
        MainActor.assumeIsolated {
            ModeFeedbackPanel.shared.show(mode, caret: caret)
        }
    }

    private func hideModeFeedback() {
        MainActor.assumeIsolated {
            ModeFeedbackPanel.shared.hide()
        }
    }

    private func consume(_ key: RimeKey, caret: NSRect) -> EngineState? {
        guard let session, let state = session.handle(key) else { return nil }
        MainActor.assumeIsolated {
            if state.candidates.isEmpty {
                CandidatePanel.shared.hide()
            } else {
                CandidatePanel.shared.show(state, caret: caret)
            }
        }
        return state
    }

    private func commitWithReturn() -> EngineState? {
        MainActor.assumeIsolated { CandidatePanel.shared.hide() }
        return session?.commitWithReturn()
    }

    private func endComposition() -> EngineState? {
        MainActor.assumeIsolated { CandidatePanel.shared.hide() }
        return session?.reset()
    }

    // MARK: - Talking to the client

    private static func draw(_ state: EngineState, client sender: Any!) {
        guard let client = sender as? IMKTextInput else { return }
        if let commit = state.commitText {
            client.insertText(commit, replacementRange: noRange)
        }
        guard let marked = state.composition else {
            client.setMarkedText("", selectionRange: NSRange(location: 0, length: 0),
                                 replacementRange: noRange)
            return
        }
        let underlined: [NSAttributedString.Key: Any] = [.underlineStyle: NSUnderlineStyle.single.rawValue]
        client.setMarkedText(NSAttributedString(string: marked.text, attributes: underlined),
                             selectionRange: NSRange(location: marked.cursor, length: 0),
                             replacementRange: noRange)
    }

    /// Screen rectangle of the composition's first character, which is what the candidate
    /// window hangs off. Some clients lie about it; that is what the M5 test matrix is for.
    private static func caretRect(client sender: Any!) -> NSRect {
        guard let client = sender as? IMKTextInput else { return .zero }
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        return rect
    }

    private static func selectionRange(client sender: Any!) -> NSRange? {
        guard let client = sender as? IMKTextInput else { return nil }
        let range = client.selectedRange()
        return range.location == NSNotFound ? nil : range
    }

    // MARK: - Events

    private static func keyEvent(from event: NSEvent) -> KeyEvent {
        KeyEvent(keyCode: event.keyCode,
                 characters: event.characters,
                 modifiers: modifiers(from: event.modifierFlags))
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyEvent.Modifiers {
        var modifiers: KeyEvent.Modifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.capsLock) { modifiers.insert(.capsLock) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        return modifiers
    }

    private static func clientID(_ sender: Any!) -> String {
        (sender as? IMKTextInput)?.bundleIdentifier() ?? "unknown"
    }
}
