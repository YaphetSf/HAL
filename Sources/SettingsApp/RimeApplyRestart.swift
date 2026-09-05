import AppKit
import Foundation

/// The one "write the patch, then bounce the input method" path (D21). Both the Fuzzy page
/// and the Appearance candidate-window card persist Settings.json + the yaml patch, then end
/// the running input method: it re-reads Settings.json, rewrites the schema patch and lets
/// librime redeploy on its next launch, which is what makes a new page size reach the
/// candidate window. macOS starts input methods on demand, so the next keystroke brings it
/// back — `NSWorkspace.open` on an input method bundle launches nothing at all.
@MainActor
enum RimeApplyRestart {
    /// The input method, not this control center: both ship a binary called `HAL…` and the
    /// bundle id is the only name that tells them apart. `killall HAL` used to end up here,
    /// in the control center, leaving librime on the build it deployed at its own startup.
    private static let inputMethodBundleID = "com.hal.inputmethod.HAL"

    /// `persist` runs before the restart, on the main thread, so the patch file is settled
    /// before the input method goes away. `completion` receives whether the input method is
    /// gone — including when it was not running, since it reads the new patch either way.
    static func apply(persist: () -> Void,
                      completion: @escaping (Bool) -> Void) {
        persist()
        let running = NSRunningApplication
            .runningApplications(withBundleIdentifier: inputMethodBundleID)
        guard !running.isEmpty else { return completion(true) }
        running.forEach { $0.terminate() }
        waitForExit(running, attemptsLeft: 12, then: completion)
    }

    /// Polled rather than observed: an input method that ignores the quit event has to be
    /// forced out, and the wait is over in a few hundred milliseconds either way.
    private static func waitForExit(_ apps: [NSRunningApplication], attemptsLeft: Int,
                                    then completion: @escaping (Bool) -> Void) {
        let alive = apps.filter { !$0.isTerminated }
        guard !alive.isEmpty else { return completion(true) }
        guard attemptsLeft > 0 else {
            alive.forEach { $0.forceTerminate() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                completion(alive.allSatisfy(\.isTerminated))
            }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            waitForExit(alive, attemptsLeft: attemptsLeft - 1, then: completion)
        }
    }
}
