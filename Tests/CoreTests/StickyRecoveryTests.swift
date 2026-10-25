import XCTest

private let controlCenter = "com.apple.controlcenter"
private let chrome = "com.google.Chrome"

final class StickyRecoveryTests: XCTestCase {
    func testLosingHALAfterUseRecoversAtOnce() {
        var policy = StickyRecovery()
        policy.halBecameCurrent(at: 0)
        XCTAssertEqual(policy.fellBack(at: 300, client: chrome, secureInput: false), .recover)
        XCTAssertFalse(policy.isAwaitingFocusChange)
    }

    /// 2026-10-25: Control Center threw back each selection within ~20 ms, all three in
    /// 0.26 s, and the breaker never re-armed.
    func testControlCenterBounceWaitsUntilFocusReturnsToTheApp() {
        var policy = StickyRecovery()
        policy.halBecameCurrent(at: 0)
        XCTAssertEqual(policy.fellBack(at: 100, client: controlCenter, secureInput: true), .recover)

        XCTAssertTrue(policy.consumeSelection(at: 102.828))
        policy.halBecameCurrent(at: 102.828)
        XCTAssertEqual(policy.fellBack(at: 102.850, client: controlCenter, secureInput: false),
                       .awaitFocusChange(rejectedBy: controlCenter))

        XCTAssertFalse(policy.focusMoved(to: controlCenter, at: 102.9))
        XCTAssertTrue(policy.focusMoved(to: chrome, at: 103.399))
        XCTAssertFalse(policy.isAwaitingFocusChange)
        XCTAssertTrue(policy.consumeSelection(at: 103.4))
    }

    func testBounceUnderSecureInputIsNotARefusal() {
        var policy = StickyRecovery()
        policy.halBecameCurrent(at: 0)
        XCTAssertEqual(policy.fellBack(at: 0.05, client: chrome, secureInput: true), .recover)
    }

    func testBreakerRetriesOnTheFirstFocusChangeAfterCooldown() {
        var policy = StickyRecovery()
        for t in [0, 0.1, 0.2] {
            XCTAssertTrue(policy.consumeSelection(at: t))
        }
        XCTAssertFalse(policy.consumeSelection(at: 0.3))
        XCTAssertTrue(policy.isAwaitingFocusChange)

        XCTAssertFalse(policy.focusMoved(to: chrome, at: 10))
        XCTAssertTrue(policy.isAwaitingFocusChange)
        XCTAssertTrue(policy.focusMoved(to: chrome, at: 30.3))
        XCTAssertTrue(policy.consumeSelection(at: 30.3))
    }

    func testLosingHALDuringCooldownWaitsForFocus() {
        var policy = StickyRecovery()
        policy.giveUp(at: 0, rejectedBy: nil)
        policy.halBecameCurrent(at: 5)
        XCTAssertEqual(policy.fellBack(at: 20, client: chrome, secureInput: false),
                       .awaitFocusChange(rejectedBy: nil))
        XCTAssertTrue(policy.focusMoved(to: chrome, at: 31))
    }

    func testGivingUpSkipsTheClientThatRefused() {
        var policy = StickyRecovery()
        policy.giveUp(at: 0, rejectedBy: controlCenter)
        XCTAssertFalse(policy.focusMoved(to: controlCenter, at: 40))
        XCTAssertTrue(policy.focusMoved(to: chrome, at: 40))
    }

    func testHALBecomingCurrentEndsTheWait() {
        var policy = StickyRecovery()
        policy.halBecameCurrent(at: 0)
        _ = policy.fellBack(at: 0.02, client: controlCenter, secureInput: false)
        policy.halBecameCurrent(at: 5)
        XCTAssertFalse(policy.isAwaitingFocusChange)
        XCTAssertFalse(policy.focusMoved(to: chrome, at: 6))
    }

    func testUnlockClearsTheBreaker() {
        var policy = StickyRecovery()
        policy.giveUp(at: 0, rejectedBy: chrome)
        policy.reset()
        XCTAssertFalse(policy.isAwaitingFocusChange)
        XCTAssertTrue(policy.consumeSelection(at: 1))
    }
}
