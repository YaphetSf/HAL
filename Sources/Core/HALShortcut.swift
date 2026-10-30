/// The chords HAL claims before a key reaches librime or the host (D11, D22, D27). Caps Lock
/// is never one of them: it stays the system's own lock key, so its state is ignored here.
enum HALShortcut: Equatable {
    case switchLanguage
    case switchEnglishProfile
    case aiEdit

    private static let space: UInt16 = 0x31
    private static let tab: UInt16 = 0x30

    init?(_ key: KeyEvent) {
        let chord = key.modifiers.subtracting(.capsLock)
        if key.keyCode == Self.space, chord == .option {
            self = .switchLanguage
        } else if key.keyCode == Self.space, chord == [.option, .shift] {
            self = .switchEnglishProfile
        } else if key.keyCode == Self.tab, chord == .option {
            self = .aiEdit
        } else {
            return nil
        }
    }
}
