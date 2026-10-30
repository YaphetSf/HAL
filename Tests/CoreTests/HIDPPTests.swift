import XCTest

/// Report bytes are the ones the G915 TKL receiver (0xC547) and G305 receiver (0xC53F)
/// sent on 2026-10-30.
final class HIDPPTests: XCTestCase {
    func testFeatureIndexRequestIsALongReportWithTheSoftwareID() {
        let request = HIDPP.featureIndexRequest(device: 1, feature: 0x1001)
        XCTAssertEqual(request.count, 20)
        XCTAssertEqual(Array(request.prefix(6)), [0x11, 0x01, 0x00, 0x0A, 0x10, 0x01])
        XCTAssertTrue(request.dropFirst(6).allSatisfy { $0 == 0 })
    }

    func testCodenameReplyNamesTheKeyboard() throws {
        let request = HIDPP.codenameRequest(device: 1)
        XCTAssertEqual(request, [0x10, 0xFF, 0x83, 0xB5, 0x40, 0x00, 0x00])
        let report: [UInt8] = [0x11, 0xFF, 0x83, 0xB5, 0x40, 0x08, 0x47, 0x39, 0x31, 0x35,
                               0x20, 0x54, 0x4B, 0x4C, 0, 0, 0, 0, 0, 0]
        guard case .payload(let payload)? = HIDPP.reply(to: request, in: report) else {
            return XCTFail("codename reply not matched")
        }
        XCTAssertEqual(HIDPP.codename(from: payload), "G915 TKL")
    }

    func testEmptyPairingSlotIsAnError() {
        let request = HIDPP.codenameRequest(device: 2)
        XCTAssertEqual(HIDPP.reply(to: request, in: [0x10, 0xFF, 0x8F, 0x83, 0xB5, 0x09, 0x00]), .error)
    }

    func testFeatureErrorAndDeviceEventAreNotReplies() {
        let request = HIDPP.featureRequest(device: 1, featureIndex: 5, function: 0)
        var error = [UInt8](repeating: 0, count: 20)
        error.replaceSubrange(0..<6, with: [0x11, 0x01, 0xFF, 0x05, 0x0A, 0x02])
        XCTAssertEqual(HIDPP.reply(to: request, in: error), .error)

        var event = [UInt8](repeating: 0, count: 20)
        event.replaceSubrange(0..<7, with: [0x11, 0x01, 0x05, 0x00, 0x0F, 0xDA, 0x00])
        XCTAssertNil(HIDPP.reply(to: request, in: event))
        XCTAssertEqual(HIDPP.event(from: 1, featureIndex: 5, in: event)?.prefix(3), [0x0F, 0xDA, 0x00])
        XCTAssertNil(HIDPP.event(from: 2, featureIndex: 5, in: event))
    }

    func testOfflineDeviceIsAnErrorFromTheReceiver() {
        let request = HIDPP.featureIndexRequest(device: 1, feature: 0x1004)
        XCTAssertEqual(HIDPP.reply(to: request, in: [0x10, 0x01, 0x8F, 0x00, 0x0A, 0x09, 0x00]), .error)
    }

    func testLinkNotification() {
        let linked = HIDPP.linkChange(in: [0x10, 0x01, 0x41, 0x11, 0x31, 0x8E, 0x40])
        XCTAssertEqual(linked?.device, 1)
        XCTAssertEqual(linked?.isLinked, true)
        XCTAssertEqual(HIDPP.linkChange(in: [0x10, 0x01, 0x41, 0x11, 0x71, 0x8E, 0x40])?.isLinked, false)
        XCTAssertNil(HIDPP.linkChange(in: [0x10, 0xFF, 0x80, 0x02, 0x00, 0x00, 0x00]))
    }

    func testVoltageFeatureInterpolatesTheDischargeCurve() {
        XCTAssertEqual(HIDPP.battery(.voltage, payload: [0x0F, 0xDA, 0x00, 0x00]),
                       HIDPP.Battery(percent: 89, isCharging: false))
        XCTAssertEqual(HIDPP.battery(.voltage, payload: [0x0F, 0xDA, 0x80, 0x00])?.isCharging, true)
        XCTAssertEqual(HIDPP.percent(millivolts: 4300), 100)
        XCTAssertEqual(HIDPP.percent(millivolts: 4186), 100)
        XCTAssertEqual(HIDPP.percent(millivolts: 3811), 50)
        XCTAssertEqual(HIDPP.percent(millivolts: 3694), 15)
        XCTAssertEqual(HIDPP.percent(millivolts: 3500), 0)
        XCTAssertEqual(HIDPP.percent(millivolts: 3200), 0)
    }

    func testStatusFeature() {
        XCTAssertEqual(HIDPP.battery(.status, payload: [90, 50, 0, 0]),
                       HIDPP.Battery(percent: 90, isCharging: false))
        XCTAssertEqual(HIDPP.battery(.status, payload: [90, 50, 3, 0])?.isCharging, true)
        XCTAssertNil(HIDPP.battery(.status, payload: [0, 50, 0, 0]))
    }

    func testUnifiedFeatureFallsBackToLevelFlags() {
        XCTAssertEqual(HIDPP.battery(.unified, payload: [64, 0x04, 1, 1]),
                       HIDPP.Battery(percent: 64, isCharging: true))
        XCTAssertEqual(HIDPP.battery(.unified, payload: [0, 0x02, 0, 0]),
                       HIDPP.Battery(percent: 20, isCharging: false))
    }
}
