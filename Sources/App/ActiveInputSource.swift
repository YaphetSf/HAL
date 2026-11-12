import AppKit
import Carbon
import Foundation
import IOKit
import OSLog

private let sourceLog = Logger(subsystem: "com.hal.inputmethod", category: "input-source")

/// Watches which input source the system is on and tries to keep HAL selected after macOS
/// silently hands the keyboard back to its ASCII fallback layout. TIS sometimes accepts a
/// selection globally without delivering it to the focused client, so recovery is deliberately
/// best-effort and bounded: a client that refuses HAL must not trigger an infinite
/// source-switch loop. When `StickyRecovery` stalls, the next focus change resumes it (D11).
enum ActiveInputSource {
    private static let inputSourceID = "com.hal.inputmethod.HAL"
    private static let maxAttemptsPerRecovery = 3
    private static let retryDelays: [TimeInterval] = [0, 0.15, 0.5]
    private static let secureInputPollInterval: TimeInterval = 0.25

    /// Whether HAL was the active source right before the screen locked — the only case
    /// worth trying to restore on unlock (§6.2). If the user had deliberately switched away
    /// before locking, unlocking should not yank them back onto HAL.
    nonisolated(unsafe) private static var wasActiveBeforeLock = false
    nonisolated(unsafe) private static var isScreenLocked = false

    /// Sticky becomes armed only after HAL has actually been selected. Starting HAL while
    /// the user is already on another source therefore does not claim the keyboard.
    nonisolated(unsafe) private static var shouldKeepHALActive = false
    nonisolated(unsafe) private static var lastSourceID: String?

    /// Captured whenever HAL is current. It cannot be read after the switch: selecting any
    /// ASCII-capable layout makes it the most recently used one, so the answer would always
    /// equal the new source and could not tell the system's fallback from a deliberate pick.
    nonisolated(unsafe) private static var fallbackSourceID: String?

    /// The client IMK last activated HAL in. Menu bar popups such as Control Center take key
    /// focus without becoming the frontmost app, so this is the only way to name them.
    nonisolated(unsafe) private static var lastClient: (id: String, at: TimeInterval)?

    /// Recovery state lives on the main run loop with the notification callbacks.
    nonisolated(unsafe) private static var policy = StickyRecovery()
    nonisolated(unsafe) private static var recoveryTimer: Timer?
    nonisolated(unsafe) private static var recoveryAttempt = 0
    nonisolated(unsafe) private static var recoveryTrigger: String?
    nonisolated(unsafe) private static var isWaitingForSecureInput = false

    /// Sets the initial state and subscribes to the notifications this needs: TIS for every
    /// source change, app activation to resume a stalled recovery, plus screen lock/unlock to
    /// enter the recovery path (§6.2 — the lock screen's password field runs outside any
    /// third-party input method, and macOS never restores the pre-lock source on its own).
    /// `start` is called from `applicationDidFinishLaunching` (main thread); the notification
    /// blocks run on `.main` too, so all may hop into the MainActor with `assumeIsolated`.
    static func start() {
        MainActor.assumeIsolated {
            let sourceID = selectedSourceID()
            lastSourceID = sourceID
            shouldKeepHALActive = sourceID == inputSourceID
            if shouldKeepHALActive {
                fallbackSourceID = currentFallbackSourceID()
                policy.halBecameCurrent(at: now())
            }
            apply(sourceID: sourceID)
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { sourceDidChange() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let appID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier
            MainActor.assumeIsolated { focusDidMove(to: appID, via: "app-activated") }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                isScreenLocked = true
                wasActiveBeforeLock = isHALCurrent()
                cancelRecovery()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                isScreenLocked = false
                recoverAfterUnlock()
            }
        }
    }

    static func isHALCurrent() -> Bool {
        selectedSourceID() == inputSourceID
    }

    /// Called from `activateServer`, which IMK runs on the main thread. While the system is
    /// on the fallback layout, IMK still briefly activates HAL in each newly focused client,
    /// which is the only focus signal when a menu bar popup hands focus back to the app
    /// underneath it.
    static func clientDidActivate(_ clientID: String) {
        MainActor.assumeIsolated {
            lastClient = (clientID, now())
            focusDidMove(to: clientID, via: "client-activated")
        }
    }

    @MainActor
    private static func sourceDidChange() {
        let sourceID = selectedSourceID()
        let previousSourceID = lastSourceID
        lastSourceID = sourceID
        apply(sourceID: sourceID)

        switch sourceID {
        case inputSourceID:
            if isWaitingForSecureInput {
                sourceLog.notice("sticky recovery not needed: system restored HAL after secure input app=\(frontmostAppID(), privacy: .public)")
            }
            shouldKeepHALActive = true
            fallbackSourceID = currentFallbackSourceID()
            policy.halBecameCurrent(at: now())
            cancelRecovery()

        case _ where isFallback(sourceID):
            guard shouldKeepHALActive, !isScreenLocked else { return }
            let client = focusedClientID()
            switch policy.fellBack(at: now(), client: client, secureInput: IsSecureEventInputEnabled()) {
            case .recover:
                let trigger = previousSourceID == inputSourceID ? "HAL-to-fallback" : "fallback-reverted"
                scheduleRecovery(trigger: trigger, after: retryDelays[0])
            case .awaitFocusChange(let rejectedBy):
                cancelRecovery()
                sourceLog.notice("sticky recovery waiting for focus to move rejectedBy=\(rejectedBy ?? "any", privacy: .public) client=\(client, privacy: .public) app=\(frontmostAppID(), privacy: .public)")
            }

        default:
            // Any other source is an intentional choice. Sticky HAL only owns the system's
            // fallback layout described by D11.
            shouldKeepHALActive = false
            cancelRecovery()
        }
    }

    @MainActor
    private static func focusDidMove(to clientID: String?, via trigger: String) {
        guard policy.isAwaitingFocusChange,
              shouldKeepHALActive,
              !isScreenLocked,
              isFallback(selectedSourceID()),
              policy.focusMoved(to: clientID, at: now())
        else { return }
        sourceLog.notice("sticky recovery resuming: focus moved via=\(trigger, privacy: .public) client=\(clientID ?? "unknown", privacy: .public)")
        scheduleRecovery(trigger: "focus-moved", after: retryDelays[0])
    }

    @MainActor
    private static func apply(sourceID: String?) {
        let active = sourceID == inputSourceID
        if active != ModeState.shared.isActive {
            sourceLog.info("HAL is now \(active ? "active" : "not the current input source", privacy: .public)")
        }
        ModeState.shared.isActive = active
    }

    /// D11 found `TISSelectInputSource` doesn't reach an already-focused client mid-composition
    /// (a fast per-keystroke toggle needs it to work every time, so that ruled it out there).
    /// Low-frequency recovery is different: the user usually has not started typing, and
    /// the same API already worked after unlock. Failed or reverted selections stay bounded
    /// by the shared circuit breaker; the menu bar still tells the user to use ⌃Space.
    @MainActor
    private static func recoverAfterUnlock() {
        let shouldRestore = wasActiveBeforeLock
        wasActiveBeforeLock = false

        let sourceID = selectedSourceID()
        lastSourceID = sourceID
        apply(sourceID: sourceID)
        guard shouldRestore, isFallback(sourceID) else { return }

        shouldKeepHALActive = true
        policy.reset()
        scheduleRecovery(trigger: "screen-unlock", after: retryDelays[0])
    }

    @MainActor
    private static func scheduleRecovery(trigger: String, after delay: TimeInterval) {
        guard recoveryTimer == nil else { return }

        if recoveryTrigger == nil {
            recoveryTrigger = trigger
            recoveryAttempt = 0
            sourceLog.notice("sticky recovery queued trigger=\(trigger, privacy: .public) fallback=\(fallbackSourceID ?? "unknown", privacy: .public) app=\(frontmostAppID(), privacy: .public)")
        }

        let timer = Timer(timeInterval: delay, repeats: false) { _ in
            MainActor.assumeIsolated {
                recoveryTimer = nil
                performRecoveryAttempt()
            }
        }
        recoveryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @MainActor
    private static func performRecoveryAttempt() {
        guard let trigger = recoveryTrigger,
              shouldKeepHALActive,
              !isScreenLocked,
              isFallback(selectedSourceID())
        else {
            cancelRecovery()
            return
        }

        // A focused password field turns on secure event input and macOS forces an
        // ASCII-capable layout until it loses focus; selecting HAL there is reverted within
        // milliseconds and HAL receives no keys anyway. Poll without spending budget.
        if IsSecureEventInputEnabled() {
            publishSecureInputHolder()
            if !isWaitingForSecureInput {
                isWaitingForSecureInput = true
                let holder = ModeState.shared.secureInputHolder.map { "\($0.name)(\($0.pid))" } ?? "unknown"
                sourceLog.notice("sticky recovery waiting for secure input to end holder=\(holder, privacy: .public) trigger=\(trigger, privacy: .public) app=\(frontmostAppID(), privacy: .public)")
            }
            scheduleRecovery(trigger: trigger, after: secureInputPollInterval)
            return
        }
        if isWaitingForSecureInput {
            isWaitingForSecureInput = false
            clearSecureInputHolder()
            sourceLog.notice("sticky recovery resuming after secure input ended trigger=\(trigger, privacy: .public) app=\(frontmostAppID(), privacy: .public)")
        }

        guard policy.consumeSelection(at: now()) else {
            sourceLog.error("sticky recovery circuit breaker opened after \(StickyRecovery.maxSelectionsPerBurst) selections in \(Int(StickyRecovery.burstWindow))s, retrying on the first focus change after \(Int(StickyRecovery.cooldown))s trigger=\(trigger, privacy: .public) app=\(frontmostAppID(), privacy: .public)")
            cancelRecovery()
            return
        }

        recoveryAttempt += 1
        let attempt = recoveryAttempt
        let appID = frontmostAppID()
        guard let source = halInputSource() else {
            sourceLog.error("sticky recovery failed: HAL input source unavailable trigger=\(trigger, privacy: .public) app=\(appID, privacy: .public)")
            policy.giveUp(at: now(), rejectedBy: nil)
            cancelRecovery()
            return
        }

        let status = TISSelectInputSource(source)
        let selectedID = selectedSourceID()
        lastSourceID = selectedID
        apply(sourceID: selectedID)

        if status == noErr, selectedID == inputSourceID {
            sourceLog.notice("sticky recovery selected HAL attempt=\(attempt) trigger=\(trigger, privacy: .public) app=\(appID, privacy: .public)")
            policy.halBecameCurrent(at: now())
            cancelRecovery()
            return
        }

        guard attempt < maxAttemptsPerRecovery else {
            sourceLog.error("sticky recovery failed after \(attempt) attempts status=\(status) selected=\(selectedID ?? "unknown", privacy: .public) trigger=\(trigger, privacy: .public) app=\(appID, privacy: .public)")
            policy.giveUp(at: now(), rejectedBy: focusedClientID())
            cancelRecovery()
            return
        }

        sourceLog.info("sticky recovery retrying attempt=\(attempt) status=\(status) selected=\(selectedID ?? "unknown", privacy: .public) trigger=\(trigger, privacy: .public) app=\(appID, privacy: .public)")
        scheduleRecovery(trigger: trigger, after: retryDelays[attempt])
    }

    @MainActor
    private static func cancelRecovery() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        recoveryAttempt = 0
        recoveryTrigger = nil
        isWaitingForSecureInput = false
        clearSecureInputHolder()
    }

    /// Runs on every poll: the holder can change while HAL waits.
    @MainActor
    private static func publishSecureInputHolder() {
        let pid = secureInputHolderPID()
        guard pid != ModeState.shared.secureInputHolder?.pid else { return }
        ModeState.shared.secureInputHolder = pid.map { pid in
            let app = NSRunningApplication(processIdentifier: pid)
            return SecureInputHolder(pid: pid, name: app?.localizedName ?? "PID \(pid)", icon: app?.icon)
        }
    }

    @MainActor
    private static func clearSecureInputHolder() {
        guard ModeState.shared.secureInputHolder != nil else { return }
        ModeState.shared.secureInputHolder = nil
    }

    /// WindowServer publishes the holder in this user's session entry on the IORegistry
    /// root; there is no public API for it.
    private static func secureInputHolderPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard let users = IORegistryEntryCreateCFProperty(root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]]
        else { return nil }
        let session = users.first { $0["kCGSSessionUserIDKey"] as? uid_t == getuid() }
        return (session?["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value
    }

    @MainActor
    private static func isFallback(_ sourceID: String?) -> Bool {
        sourceID != nil && sourceID == fallbackSourceID
    }

    /// The client HAL was just activated in, if that was moments ago; otherwise the
    /// frontmost app.
    @MainActor
    private static func focusedClientID() -> String {
        if let lastClient, now() - lastClient.at < StickyRecovery.bounceWindow {
            return lastClient.id
        }
        return frontmostAppID()
    }

    private static func now() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }

    private static func halInputSource() -> TISInputSource? {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]
        else { return nil }
        return list.first { sourceID(of: $0) == inputSourceID }
    }

    private static func selectedSourceID() -> String? {
        TISCopyCurrentKeyboardInputSource().flatMap { sourceID(of: $0.takeRetainedValue()) }
    }

    /// The most recently used ASCII-capable keyboard layout: TSM translates keys through it
    /// while HAL is selected, and macOS drops to it when it pushes HAL out (lock screen,
    /// secure input, a client refusing HAL). The non-layout variant answers with HAL itself,
    /// because HAL declares Latn.
    private static func currentFallbackSourceID() -> String? {
        TISCopyCurrentASCIICapableKeyboardLayoutInputSource().flatMap { sourceID(of: $0.takeRetainedValue()) }
    }

    private static func sourceID(of source: TISInputSource) -> String? {
        guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    @MainActor
    private static func frontmostAppID() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    }
}
