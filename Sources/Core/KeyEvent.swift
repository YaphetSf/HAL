/// A key press as Core sees it: no AppKit, no librime. `KeyEventMapper` turns it into the
/// X11 keysym and modifier mask librime's C API expects.
struct KeyEvent: Equatable {
    struct Modifiers: OptionSet, Equatable {
        let rawValue: Int
        static let shift = Modifiers(rawValue: 1 << 0)
        static let capsLock = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let option = Modifiers(rawValue: 1 << 3)
        static let command = Modifiers(rawValue: 1 << 4)
    }

    /// Virtual key code, i.e. the physical key, independent of layout.
    var keyCode: UInt16
    /// What the key would type, used for everything printable.
    var characters: String?
    var modifiers: Modifiers
}

/// What librime needs to be told about one key press.
struct RimeKey: Equatable {
    var keysym: Int32
    var mask: Int32
}
