import Foundation

/// When sticky HAL may spend a `TISSelectInputSource` call to win back the keyboard from the
/// fallback layout (D11). Pure bookkeeping: the caller owns TIS, timers and notifications
/// and passes in the clock.
///
/// Two ways to stall instead of selecting: a client that throws HAL straight back out, and
/// the circuit breaker. Both end at the next focus change, because a selection only has a
/// chance in a client that has not already refused one.
struct StickyRecovery {
    enum Response: Equatable {
        /// Select HAL now, or as soon as secure input ends.
        case recover
        /// Wait for focus to reach a client other than `rejectedBy`.
        case awaitFocusChange(rejectedBy: String?)
    }

    static let bounceWindow: TimeInterval = 1
    static let maxSelectionsPerBurst = 3
    static let burstWindow: TimeInterval = 5
    static let cooldown: TimeInterval = 30

    private(set) var isAwaitingFocusChange = false
    private(set) var rejectingClient: String?
    private(set) var suppressedUntil: TimeInterval = 0
    private var halCurrentSince: TimeInterval?
    private var recentSelections: [TimeInterval] = []

    mutating func halBecameCurrent(at now: TimeInterval) {
        halCurrentSince = now
        isAwaitingFocusChange = false
        rejectingClient = nil
    }

    /// HAL just lost to the fallback layout while `client` had focus. Losing it within
    /// `bounceWindow` of becoming current means that client refused HAL. Secure input is not
    /// a refusal: it ends when the password field loses focus, often inside the same app.
    mutating func fellBack(at now: TimeInterval, client: String?, secureInput: Bool) -> Response {
        let bounced = halCurrentSince.map { now - $0 < Self.bounceWindow } ?? false
        halCurrentSince = nil
        if isAwaitingFocusChange || now < suppressedUntil {
            isAwaitingFocusChange = true
            return .awaitFocusChange(rejectedBy: rejectingClient)
        }
        if bounced && !secureInput {
            awaitFocusChange(rejectedBy: client)
            return .awaitFocusChange(rejectedBy: client)
        }
        return .recover
    }

    /// Focus reached `client`. True when a stalled recovery should select HAL now.
    mutating func focusMoved(to client: String?, at now: TimeInterval) -> Bool {
        guard isAwaitingFocusChange, now >= suppressedUntil else { return false }
        if let rejectingClient, client == rejectingClient { return false }
        isAwaitingFocusChange = false
        rejectingClient = nil
        return true
    }

    /// Spends one selection. Running out of the burst budget opens the circuit breaker.
    mutating func consumeSelection(at now: TimeInterval) -> Bool {
        recentSelections.removeAll { now - $0 > Self.burstWindow }
        guard recentSelections.count < Self.maxSelectionsPerBurst else {
            giveUp(at: now, rejectedBy: nil)
            return false
        }
        recentSelections.append(now)
        return true
    }

    /// Cools down, then waits for focus to move to a client other than `client`.
    mutating func giveUp(at now: TimeInterval, rejectedBy client: String?) {
        suppressedUntil = now + Self.cooldown
        awaitFocusChange(rejectedBy: client)
    }

    /// The lock screen, not a client, pushed HAL out, so unlock starts from a clean slate.
    mutating func reset() {
        self = StickyRecovery()
    }

    private mutating func awaitFocusChange(rejectedBy client: String?) {
        isAwaitingFocusChange = true
        rejectingClient = client
    }
}
