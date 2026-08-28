/// Translates key presses into librime's X11 vocabulary.
///
/// Only the keys listed in PLAN.md §M4 are mapped; anything else returns nil and goes to the
/// host app untouched. That is deliberate — a small table is one that can be read and
/// checked against the tests.
enum KeyEventMapper {
    /// X11 modifier mask bits, as librime reads them.
    private enum Mask {
        static let shift: Int32 = 1 << 0
        static let lock: Int32 = 1 << 1
        static let control: Int32 = 1 << 2
        static let alt: Int32 = 1 << 3
    }

    /// X11 keysyms for the non-printable keys HAL cares about.
    private enum Keysym {
        static let backSpace: Int32 = 0xFF08
        static let ret: Int32 = 0xFF0D
        static let escape: Int32 = 0xFF1B
        static let pageUp: Int32 = 0xFF55
        static let pageDown: Int32 = 0xFF56
        /// librime's Selector processor moves the candidate highlight on the raw
        /// Up/Down keysyms by default (no yaml binding needed — this is the same
        /// behavior M4 originally hung off the physical up/down keys). HAL's own
        /// candidate row is horizontal, so the physical Left/Right keys are wired
        /// to send these instead of literal Left/Right.
        static let previousCandidate: Int32 = 0xFF52  // X11 "Up"
        static let nextCandidate: Int32 = 0xFF54       // X11 "Down"
    }

    /// macOS virtual key codes. Named here rather than imported so Core stays free of Carbon.
    private enum VirtualKey {
        static let ret: UInt16 = 0x24
        static let delete: UInt16 = 0x33
        static let escape: UInt16 = 0x35
        static let pageUp: UInt16 = 0x74
        static let pageDown: UInt16 = 0x79
        static let left: UInt16 = 0x7B
        static let right: UInt16 = 0x7C
        static let down: UInt16 = 0x7D
        static let up: UInt16 = 0x7E
    }

    static func map(_ event: KeyEvent) -> RimeKey? {
        // D10: a Command combination is never ours, whatever else it looks like.
        guard !event.modifiers.contains(.command) else { return nil }
        guard let keysym = keysym(for: event) else { return nil }
        return RimeKey(keysym: keysym, mask: mask(for: event.modifiers))
    }

    private static func keysym(for event: KeyEvent) -> Int32? {
        switch event.keyCode {
        case VirtualKey.ret: return Keysym.ret
        case VirtualKey.delete: return Keysym.backSpace
        case VirtualKey.escape: return Keysym.escape
        // Up/Down page, same as -/=. Left/Right move the highlight between candidates
        // on the current page — the candidate row is horizontal, so that's the
        // natural axis for them, not paging and not the composition cursor.
        case VirtualKey.up: return Keysym.pageUp
        case VirtualKey.down: return Keysym.pageDown
        case VirtualKey.left: return Keysym.previousCandidate
        case VirtualKey.right: return Keysym.nextCandidate
        case VirtualKey.pageUp: return Keysym.pageUp
        case VirtualKey.pageDown: return Keysym.pageDown
        default: break
        }
        // Everything printable, where the keysym is the ASCII code point itself:
        // a-z, A-Z, 0-9, space, and the punctuation listed in §M4.
        guard let scalar = event.characters?.unicodeScalars.first,
              (0x20...0x7E).contains(scalar.value)
        else { return nil }
        return Int32(scalar.value)
    }

    private static func mask(for modifiers: KeyEvent.Modifiers) -> Int32 {
        var mask: Int32 = 0
        if modifiers.contains(.shift) { mask |= Mask.shift }
        if modifiers.contains(.capsLock) { mask |= Mask.lock }
        if modifiers.contains(.control) { mask |= Mask.control }
        if modifiers.contains(.option) { mask |= Mask.alt }
        return mask
    }
}
