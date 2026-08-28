import AppKit
import Carbon
import Foundation
import OSLog

private let sourceLog = Logger(subsystem: "com.hal.inputmethod", category: "input-source")

/// Watches which input source the system is on and tries to keep HAL selected after macOS
/// silently hands the keyboard back to British. TIS sometimes accepts a selection globally
/// without delivering it to the focused client, so recovery is deliberately best-effort and
/// bounded: a client that refuses HAL must not trigger an infinite source-switch loop (D11).
enum ActiveInputSource {
    private static let inputSourceID = "com.hal.inputmethod.HAL"
    private static let britishSourceID = "com.apple.keylayout.British"
    private static let maxAttemptsPerRecovery = 3
    private static let maxSelectionsPerBurst = 3
    private static let burstWindow: TimeInterval = 5
    private static let cooldown: TimeInterval = 30
    private static let retryDelays: [TimeInterval] = [0, 0.15, 0.5]

    /// Whether HAL was the active source right before the screen locked — the only case
    /// worth trying to restore on unlock (§6.2). If the user had deliberately switched away
    /// before locking, unlocking should not yank them back onto HAL.
    nonisolated(unsafe) private static var wasActiveBeforeLock = false
    nonisolated(unsafe) private static var isScreenLocked = false

    /// Sticky becomes armed only after HAL has actually been selected. Starting HAL while
    /// the user is already on another source therefore does not claim the keyboard.
    nonisolated(unsafe) private static var shouldKeepHALActive = false
    nonisolated(unsafe) private static var lastSourceID: String?

    /// Recovery state lives on the main run loop with the notification callbacks. The recent
    /// selection timestamps span recovery cycles so a client that repeatedly reverts a
    /// successful-looking TIS selection still hits the circuit breaker.
    nonisolated(unsafe) private static var recoveryTimer: Timer?
    nonisolated(unsafe) private static var recoveryAttempt = 0
    nonisolated(unsafe) private static var recoveryTrigger: String?
    nonisolated(unsafe) private static var recentSelectionTimes: [TimeInterval] = []
    nonisolated(unsafe) private static var suppressedUntil: TimeInterval = 0

    /// Sets the initial state and subscribes to the distributed notifications this needs:
    /// TIS for every source change, plus screen lock/unlock to enter the recovery path (§6.2 —
    /// the lock screen's password field runs outside any third-party input method, and macOS
    /// never restores the pre-lock source on its own). `start` is called from
    /// `applicationDidFinishLaunching` (main thread); the notification blocks run on `.main`
    /// too, so all may hop into the MainActor with `assumeIsolated`.
    static func start() {
        MainActor.assumeIsolated {
            let sourceID = selectedSourceID()
            lastSourceID = sourceID
            shouldKeepHALActive = sourceID == inputSourceID
            apply(sourceID: sourceID)
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { sourceDidChange() }
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

    @MainActor
    private static func sourceDidChange() {
        let sourceID = selectedSourceID()
        let previousSourceID = lastSourceID
        lastSourceID = sourceID
        apply(sourceID: sourceID)

        switch sourceID {
        case inputSourceID:
            shouldKeepHALActive = true
            cancelRecovery()

        case britishSourceID:
            guard shouldKeepHALActive, !isScreenLocked else { return }
            let trigger = previousSourceID == inputSourceID ? "HAL-to-British" : "British-reverted"
            scheduleRecovery(trigger: trigger, after: retryDelays[0])

        default:
            // Another non-British input source is an intentional choice. Sticky HAL only
            // owns the British fallback described by D11.
            shouldKeepHALActive = false
            cancelRecovery()
        }
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
        guard shouldRestore, sourceID == britishSourceID else { return }

        shouldKeepHALActive = true
        recentSelectionTimes.removeAll()
        suppressedUntil = 0
        scheduleRecovery(trigger: "screen-unlock", after: retryDelays[0])
    }

    @MainActor
    private static func scheduleRecovery(trigger: String, after delay: TimeInterval) {
        guard recoveryTimer == nil else { return }

        let now = ProcessInfo.processInfo.systemUptime
        guard now >= suppressedUntil else {
            let remaining = Int((suppressedUntil - now).rounded(.up))
            sourceLog.error("sticky recovery suppressed for another \(remaining)s trigger=\(trigger, privacy: .public) app=\(frontmostAppID(), privacy: .public)")
            return
        }

        if recoveryTrigger == nil {
            recoveryTrigger = trigger
            recoveryAttempt = 0
            sourceLog.notice("sticky recovery queued trigger=\(trigger, privacy: .public) app=\(frontmostAppID(), privacy: .public)")
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
              selectedSourceID() == britishSourceID
        else {
            cancelRecovery()
            return
        }

        guard consumeSelectionBudget(trigger: trigger) else {
            cancelRecovery()
            return
        }

        recoveryAttempt += 1
        let attempt = recoveryAttempt
        let appID = frontmostAppID()
        guard let source = halInputSource() else {
            sourceLog.error("sticky recovery failed: HAL input source unavailable trigger=\(trigger, privacy: .public) app=\(appID, privacy: .public)")
            enterCooldown()
            cancelRecovery()
            return
        }

        let status = TISSelectInputSource(source)
        let selectedID = selectedSourceID()
        lastSourceID = selectedID
        apply(sourceID: selectedID)

        if status == noErr, selectedID == inputSourceID {
            sourceLog.notice("sticky recovery selected HAL attempt=\(attempt) trigger=\(trigger, privacy: .public) app=\(appID, privacy: .public)")
            cancelRecovery()
            return
        }

        guard attempt < maxAttemptsPerRecovery else {
            sourceLog.error("sticky recovery failed after \(attempt) attempts status=\(status) selected=\(selectedID ?? "unknown", privacy: .public) trigger=\(trigger, privacy: .public) app=\(appID, privacy: .public)")
            enterCooldown()
            cancelRecovery()
            return
        }

        sourceLog.info("sticky recovery retrying attempt=\(attempt) status=\(status) selected=\(selectedID ?? "unknown", privacy: .public) trigger=\(trigger, privacy: .public) app=\(appID, privacy: .public)")
        scheduleRecovery(trigger: trigger, after: retryDelays[attempt])
    }

    @MainActor
    private static func consumeSelectionBudget(trigger: String) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        recentSelectionTimes.removeAll { now - $0 > burstWindow }
        guard recentSelectionTimes.count < maxSelectionsPerBurst else {
            enterCooldown()
            sourceLog.error("sticky recovery circuit breaker opened after \(maxSelectionsPerBurst) selections in \(Int(burstWindow))s trigger=\(trigger, privacy: .public) app=\(frontmostAppID(), privacy: .public)")
            return false
        }
        recentSelectionTimes.append(now)
        return true
    }

    @MainActor
    private static func enterCooldown() {
        suppressedUntil = ProcessInfo.processInfo.systemUptime + cooldown
    }

    @MainActor
    private static func cancelRecovery() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
        recoveryAttempt = 0
        recoveryTrigger = nil
    }

    private static func halInputSource() -> TISInputSource? {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource]
        else { return nil }
        return list.first { source in
            guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
            return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String == inputSourceID
        }
    }

    private static func selectedSourceID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    @MainActor
    private static func frontmostAppID() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    }
}
