import Foundation
import XCTest

final class EnglishCompletionKeyTests: XCTestCase {
    private func readySession(start: Int = 10) -> EnglishCompletionSession {
        let session = EnglishCompletionSession()
        for (offset, letter) in "hel".enumerated() {
            _ = session.append(String(letter), caretLocation: start + offset)
        }
        session.updateSuggestions(["hello", "help", "held"])
        return session
    }

    private func press(_ code: UInt16,
                       modifiers: KeyEvent.Modifiers = []) -> KeyEvent {
        KeyEvent(keyCode: code, characters: nil, modifiers: modifiers)
    }

    func testTabReplacesTheTypedWordInsteadOfInsertingASeparateSuffix() {
        let session = readySession()
        let action = session.handleSuggestionKey(press(0x30),
                                                  selection: NSRange(location: 13, length: 0),
                                                  visible: true)

        XCTAssertEqual(action, .replace(text: "hello", range: NSRange(location: 10, length: 3)))
        XCTAssertTrue(session.prefix.isEmpty)
        XCTAssertTrue(session.suggestions.isEmpty)
        XCTAssertEqual(session.handleSuggestionKey(press(0x30),
                                                    selection: NSRange(location: 15, length: 0),
                                                    visible: false), .passThrough)
    }

    func testAllArrowKeysDismissSuggestionsAndPassThroughToTheEditor() {
        for code: UInt16 in [0x7B, 0x7C, 0x7D, 0x7E] {
            for modifiers: KeyEvent.Modifiers in [[], .shift, .option, .command] {
                let session = readySession()
                XCTAssertEqual(session.handleSuggestionKey(press(code, modifiers: modifiers),
                                                            selection: NSRange(location: 13, length: 0),
                                                            visible: true), .passThrough)
                XCTAssertTrue(session.prefix.isEmpty)
                XCTAssertTrue(session.suggestions.isEmpty)
            }
        }
    }

    func testShiftTabCyclesAndPlainTabAcceptsTheHighlightedWord() {
        let session = readySession()
        let caret = NSRange(location: 13, length: 0)
        XCTAssertEqual(session.handleSuggestionKey(press(0x30, modifiers: .shift),
                                                    selection: caret, visible: true), .showSuggestions)
        XCTAssertEqual(session.highlightedSuggestion, "help")
        XCTAssertEqual(session.handleSuggestionKey(press(0x30), selection: caret, visible: true),
                       .replace(text: "help", range: NSRange(location: 10, length: 3)))
    }

    func testTabCannotApplyAfterTheCaretMovesOrTextIsSelected() {
        for selection: NSRange? in [NSRange(location: 40, length: 0),
                                    NSRange(location: 13, length: 2),
                                    NSRange(location: NSNotFound, length: 0), nil] {
            let session = readySession()
            XCTAssertEqual(session.handleSuggestionKey(press(0x30), selection: selection,
                                                        visible: true), .passThrough)
            XCTAssertTrue(session.suggestions.isEmpty)
        }
    }

    func testCompletionKeepsExistingSpacesAndPunctuationAroundTheWord() {
        for trailing in ["", " world", ", world", "   world"] {
            let document = NSMutableString(string: "Say hel" + trailing)
            let session = readySession(start: 4)
            guard case let .replace(text, range) = session.handleSuggestionKey(
                press(0x30), selection: NSRange(location: 7, length: 0), visible: true
            ) else { return XCTFail("Tab must produce a word replacement") }

            document.replaceCharacters(in: range, with: text)

            XCTAssertEqual(document as String, "Say hello" + trailing)
        }
    }

    func testTabShortcutsAndHiddenSuggestionsPassThrough() {
        for modifiers: KeyEvent.Modifiers in [[], .shift, .command, .control, .option] {
            let session = readySession()
            XCTAssertEqual(session.handleSuggestionKey(press(0x30, modifiers: modifiers),
                                                        selection: NSRange(location: 13, length: 0),
                                                        visible: modifiers != [] && modifiers != .shift),
                           .passThrough)
        }
    }
}
