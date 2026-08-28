import XCTest

private func press(_ keyCode: UInt16, _ characters: String? = nil,
                   _ modifiers: KeyEvent.Modifiers = []) -> KeyEvent {
    KeyEvent(keyCode: keyCode, characters: characters, modifiers: modifiers)
}

final class KeyEventMapperTests: XCTestCase {
    func testPrintableKeysAreTheirOwnKeysym() {
        XCTAssertEqual(KeyEventMapper.map(press(0x00, "a"))?.keysym, 0x61)
        XCTAssertEqual(KeyEventMapper.map(press(0x1D, "0"))?.keysym, 0x30)
        XCTAssertEqual(KeyEventMapper.map(press(0x31, " "))?.keysym, 0x20)
        for punctuation in [",", ".", ";", "'", "-", "="] {
            let scalar = Int32(punctuation.unicodeScalars.first!.value)
            XCTAssertEqual(KeyEventMapper.map(press(0x2B, punctuation))?.keysym, scalar,
                           "\(punctuation) should map to its own code point")
        }
    }

    func testEditingAndNavigationKeys() {
        let expected: [(UInt16, Int32)] = [
            (0x24, 0xFF0D),  // Return
            (0x33, 0xFF08),  // Backspace
            (0x35, 0xFF1B),  // Escape
            (0x7B, 0xFF52),  // Left: previous candidate (X11 "Up")
            (0x7C, 0xFF54),  // Right: next candidate (X11 "Down")
            (0x7D, 0xFF56),  // Down: page
            (0x7E, 0xFF55),  // Up: page
            (0x74, 0xFF55),  // Page Up
            (0x79, 0xFF56),  // Page Down
        ]
        for (keyCode, keysym) in expected {
            XCTAssertEqual(KeyEventMapper.map(press(keyCode))?.keysym, keysym,
                           "key code \(keyCode) should map to \(String(keysym, radix: 16))")
        }
    }

    func testCommandCombinationsAreNeverOurs() {
        // D10: the single rule that must have no exception.
        XCTAssertNil(KeyEventMapper.map(press(0x08, "c", [.command])))
        XCTAssertNil(KeyEventMapper.map(press(0x24, nil, [.command])))
        XCTAssertNil(KeyEventMapper.map(press(0x7B, nil, [.command, .shift])))
    }

    func testUnmappedKeysAreLeftAlone() {
        XCTAssertNil(KeyEventMapper.map(press(0x30, "\t")), "Tab is not in the M4 key set")
        XCTAssertNil(KeyEventMapper.map(press(0x73)), "Home is not in the M4 key set")
    }

    func testModifierMask() {
        XCTAssertEqual(KeyEventMapper.map(press(0x00, "a", [.shift]))?.mask, 1 << 0)
        XCTAssertEqual(KeyEventMapper.map(press(0x00, "a", [.capsLock]))?.mask, 1 << 1)
        XCTAssertEqual(KeyEventMapper.map(press(0x00, "a", [.control]))?.mask, 1 << 2)
        XCTAssertEqual(KeyEventMapper.map(press(0x00, "a", [.option]))?.mask, 1 << 3)
        XCTAssertEqual(KeyEventMapper.map(press(0x00, "a", [.shift, .control]))?.mask, 0b101)
    }

    func testModifierKeysThemselvesAreNotOurs() {
        // HAL only asks IMK for keyDown, so a bare modifier press never arrives; the mapper
        // has nothing to say about one. Caps Lock in particular belongs to the system's
        // input source switch (D11).
        XCTAssertNil(KeyEventMapper.map(press(0x39)))
        XCTAssertNil(KeyEventMapper.map(press(0x38)))
        // Their state still reaches librime in the mask of ordinary keys.
        XCTAssertEqual(KeyEventMapper.map(press(0x00, "A", [.capsLock]))?.mask, 1 << 1)
    }
}
