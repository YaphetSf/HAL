import AppKit
import Carbon
import InputMethodKit
import OSLog

private let log = Logger(subsystem: "com.hal.inputmethod", category: "imk")

// `HAL --register` registers the bundle with the Text Input Source system so that a fresh
// install appears in System Settings without logging out. Run by scripts/build-install.sh.
if CommandLine.arguments.contains("--register") {
    let status = TISRegisterInputSource(Bundle.main.bundleURL as CFURL)
    guard status == noErr else {
        log.error("TISRegisterInputSource failed: \(status)")
        exit(EXIT_FAILURE)
    }
    exit(EXIT_SUCCESS)
}

// The IMKServer must exist before the run loop starts and stay alive for the whole process.
// Its name must match InputMethodConnectionName in Info.plist exactly (D15).
guard let connectionName = Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
      let bundleID = Bundle.main.bundleIdentifier,
      let resources = Bundle.main.resourceURL
else {
    log.fault("Info.plist is missing InputMethodConnectionName or a bundle identifier")
    exit(EXIT_FAILURE)
}

let server = IMKServer(name: connectionName, bundleIdentifier: bundleID)
guard server != nil else {
    log.fault("IMKServer could not be created: \(connectionName, privacy: .public)")
    exit(EXIT_FAILURE)
}

let delegate = AppDelegate()
NSApplication.shared.delegate = delegate

// Deploys synchronously on first run (D7), so the first keystroke never races it.
RimeRuntime.start(sharedDataDir: resources.appendingPathComponent("RimeData"),
                  userDataDir: URL.rimeUserDirectory)

log.info("HAL started connection=\(connectionName, privacy: .public) bundle=\(bundleID, privacy: .public)")

NSApplication.shared.run()
