import XCTest

private func press(_ keyCode: UInt16, _ modifiers: KeyEvent.Modifiers) -> KeyEvent {
    KeyEvent(keyCode: keyCode, characters: nil, modifiers: modifiers)
}

final class HALShortcutTests: XCTestCase {
    private let space: UInt16 = 0x31
    private let tab: UInt16 = 0x30

    func testOptionSpaceSwitchesLanguage() {
        XCTAssertEqual(HALShortcut(press(space, [.option])), .switchLanguage)
    }

    func testShiftOptionSpaceSwitchesEnglishProfile() {
        XCTAssertEqual(HALShortcut(press(space, [.option, .shift])), .switchEnglishProfile)
    }

    func testOptionTabOpensAIEdit() {
        XCTAssertEqual(HALShortcut(press(tab, [.option])), .aiEdit)
    }

    func testCapsLockStateDoesNotChangeTheChord() {
        XCTAssertEqual(HALShortcut(press(space, [.option, .capsLock])), .switchLanguage)
        XCTAssertEqual(HALShortcut(press(tab, [.option, .capsLock])), .aiEdit)
    }

    func testOtherChordsAreNotOurs() {
        XCTAssertNil(HALShortcut(press(space, [])))
        XCTAssertNil(HALShortcut(press(space, [.shift])))
        XCTAssertNil(HALShortcut(press(space, [.control])))
        XCTAssertNil(HALShortcut(press(space, [.command, .option])))
        XCTAssertNil(HALShortcut(press(space, [.control, .option])))
        XCTAssertNil(HALShortcut(press(tab, [])))
        XCTAssertNil(HALShortcut(press(tab, [.shift])))
        XCTAssertNil(HALShortcut(press(tab, [.control])))
        XCTAssertNil(HALShortcut(press(tab, [.option, .shift])))
        XCTAssertNil(HALShortcut(press(tab, [.command, .option])))
        XCTAssertNil(HALShortcut(press(0x39, [.option])))
    }
}
