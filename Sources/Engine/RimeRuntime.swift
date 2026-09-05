import Foundation
import OSLog
import RimeBridge

private let log = Logger(subsystem: "com.hal.inputmethod", category: "engine")

/// librime's C API is versioned by a leading `data_size` field that the caller must set to
/// the size of everything after it. The C header does this with a macro; Swift has to do it
/// by hand, and forgetting it makes librime read a struct it thinks is empty.
func rimeStructInit<T>(_ value: inout T) {
    withUnsafeMutableBytes(of: &value) { bytes in
        bytes.storeBytes(of: Int32(MemoryLayout<T>.size - MemoryLayout<Int32>.size), as: Int32.self)
    }
}

private let notificationHandler: RimeNotificationHandler = { _, _, messageType, messageValue in
    let type = messageType.map { String(cString: $0) } ?? ""
    let value = messageValue.map { String(cString: $0) } ?? ""
    log.info("rime \(type, privacy: .public)=\(value, privacy: .public)")
}

/// The one librime instance in the process: setup, first-run deployment, teardown.
/// Sessions live in `RimeEngine`, one per input controller.
enum RimeRuntime {
    /// nil until `start` succeeds. A copy of librime's function-pointer table.
    ///
    /// `nonisolated(unsafe)` because the whole engine layer runs on IMK's main thread and
    /// nothing else ever touches it (D1); the compiler cannot see that contract.
    nonisolated(unsafe) private(set) static var api: RimeApi?

    /// Strings handed to librime must outlive the call; the runtime is process-wide, so
    /// these are simply never freed.
    nonisolated(unsafe) private static var ownedCStrings: [UnsafeMutablePointer<CChar>] = []

    /// Deploys synchronously on first run (D7): a few seconds once, in exchange for the
    /// simplest possible state model.
    static func start(sharedDataDir: URL, userDataDir: URL) {
        guard api == nil else { return }
        guard let table = rime_get_api()?.pointee else {
            log.fault("rime_get_api returned nil; librime is not loaded")
            return
        }

        do {
            try prepareUserDirectory(userDataDir)
        } catch {
            log.error("could not prepare \(userDataDir.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return
        }

        var traits = RimeTraits()
        rimeStructInit(&traits)
        traits.shared_data_dir = own(sharedDataDir.path)
        traits.user_data_dir = own(userDataDir.path)
        traits.distribution_name = own("HAL")
        traits.distribution_code_name = own("HAL")
        traits.distribution_version = own(Bundle.main.shortVersion)
        // The "rime." prefix is what makes librime clean up its own old log files.
        traits.app_name = own("rime.hal")
        traits.log_dir = own(NSTemporaryDirectory())
        #if DEBUG
        traits.min_log_level = 0
        #else
        traits.min_log_level = 2
        #endif

        table.setup(&traits)
        table.set_notification_handler(notificationHandler, nil)
        table.initialize(&traits)
        if table.start_maintenance(1) != 0 {
            log.info("deploying, this blocks until librime is done")
            table.join_maintenance_thread()
        }
        api = table
        log.info("librime ready shared=\(sharedDataDir.path, privacy: .public) user=\(userDataDir.path, privacy: .public)")
    }

    static func stop() {
        guard let table = api else { return }
        api = nil
        table.finalize()
        log.info("librime finalized")
    }

    /// Creates the user directory and seeds the one patch HAL depends on. Existing files are
    /// never overwritten: everything in here is the user's to edit (D12).
    private static func prepareUserDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let settings = SettingsStore.load()
        RimeSpellerPatch.write(rules: settings.spellerRules,
                               asciiPhrases: settings.asciiPhrases,
                               pageSize: settings.candidatePageSize,
                               in: url)
        let patch = url.appendingPathComponent("default.custom.yaml")
        guard !FileManager.default.fileExists(atPath: patch.path) else { return }
        try """
        # HAL narrows rime-ice's schema list to full pinyin only (PLAN.md §1.2).
        # This file is yours to edit; HAL only creates it when it is missing.
        patch:
          schema_list:
            - schema: rime_ice
        """.write(to: patch, atomically: true, encoding: .utf8)
    }

    private static func own(_ string: String) -> UnsafePointer<CChar> {
        let copy = strdup(string)!
        ownedCStrings.append(copy)
        return UnsafePointer(copy)
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
