import Foundation
import OSLog

private let capsLog = Logger(subsystem: "com.hal.inputmethod", category: "input-source")

/// Caps Lock, remapped to F18 for as long as HAL runs.
///
/// macOS only commits a Caps Lock press that is held past a threshold. A shorter press flips
/// the HID lock bit while the key is down, drops it again on release, and never emits an
/// event at all, which silently swallowed 8 of 50 presses back when HAL watched for the key
/// itself. F18 is a key no Apple keyboard has, so it arrives as an ordinary key-down and the
/// input controller reads it like any other (D11).
enum CapsLockKey {
    /// The usage IDs hidutil speaks: keyboard Caps Lock and keyboard F18.
    private static let capsLockUsage = 0x7_0000_0039
    private static let f18Usage = 0x7_0000_006D

    static func remap() {
        apply(remapped: true)
    }

    /// Leaves the keyboard as it was found. A hard kill skips this, which is why remap() sets
    /// the mapping outright rather than assuming Caps Lock is still untouched.
    static func restore() {
        apply(remapped: false)
    }

    /// hidutil's mapping lives in the HID system for this login session only, so a reboot
    /// hands Caps Lock back even if HAL never gets to clean up.
    private static func apply(remapped: Bool) {
        let mapping = remapped
            ? "[{\"HIDKeyboardModifierMappingSrc\":\(capsLockUsage),"
              + "\"HIDKeyboardModifierMappingDst\":\(f18Usage)}]"
            : "[]"

        let hidutil = Process()
        hidutil.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        hidutil.arguments = ["property", "--set", "{\"UserKeyMapping\":\(mapping)}"]
        hidutil.standardOutput = FileHandle.nullDevice
        hidutil.standardError = FileHandle.nullDevice

        do {
            try hidutil.run()
            hidutil.waitUntilExit()
        } catch {
            capsLog.error("could not run hidutil: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard hidutil.terminationStatus == 0 else {
            capsLog.error("hidutil refused the key mapping (status \(hidutil.terminationStatus))")
            return
        }
        capsLog.info("Caps Lock \(remapped ? "remapped to F18" : "handed back", privacy: .public)")
    }
}
