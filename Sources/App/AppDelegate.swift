import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        CapsLockKey.remap()
        ModeStatusItem.shared.install()
        ActiveInputSource.start()
    }

    /// librime writes the user dictionary on the way out, so finalize rather than just exit.
    func applicationWillTerminate(_ notification: Notification) {
        CapsLockKey.restore()
        RimeRuntime.stop()
    }
}
