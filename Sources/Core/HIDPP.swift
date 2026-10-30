import Foundation

/// Logitech HID++ framing and battery decoding (D30). Bytes in, values out; the IOKit side
/// lives in Peripheral/.
///
/// Both protocol generations reply the same way: the receiver or device echoes request bytes
/// 1...3 (device index, sub ID or feature index, register or function|software ID). An error
/// carries those three bytes one place later, behind 0x8F (HID++ 1.0) or 0xFF (HID++ 2.0).
enum HIDPP {
    static let shortReport: UInt8 = 0x10
    static let longReport: UInt8 = 0x11
    static let longLength = 20
    static let receiverIndex: UInt8 = 0xFF
    /// Any nonzero nibble works; zero marks reports the device sends on its own.
    static let softwareID: UInt8 = 0x0A
    static let deviceNameFeature: UInt16 = 0x0005

    struct Battery: Equatable {
        var percent: Int
        /// On external power, including full and still plugged in.
        var isCharging: Bool
    }

    enum BatteryFeature: UInt16, CaseIterable {
        case unified = 0x1004
        case status = 0x1000
        case voltage = 0x1001

        /// Reads the current level. Battery events reuse this function's payload layout.
        var readFunction: UInt8 { self == .unified ? 1 : 0 }
    }

    enum Reply: Equatable {
        case payload([UInt8])
        case error
    }

    // MARK: Requests

    static func featureRequest(device: UInt8, featureIndex: UInt8, function: UInt8,
                               params: [UInt8] = []) -> [UInt8] {
        var report = [UInt8](repeating: 0, count: longLength)
        report[0] = longReport
        report[1] = device
        report[2] = featureIndex
        report[3] = function << 4 | softwareID
        report.replaceSubrange(4..<4 + params.count, with: params)
        return report
    }

    /// Root feature (index 0), function 0: where `feature` sits on the device, 0 if absent.
    static func featureIndexRequest(device: UInt8, feature: UInt16) -> [UInt8] {
        featureRequest(device: device, featureIndex: 0, function: 0,
                       params: [UInt8(feature >> 8), UInt8(feature & 0xFF)])
    }

    /// Receiver register 0x02: report every paired device's link state as if it had just
    /// connected. Answered by one 0x41 notification per paired device.
    static let reportPairedDevices: [UInt8] = [shortReport, receiverIndex, 0x80, 0x02, 0x02, 0, 0]

    /// Receiver register 0xB5: the short name of the device paired at `device` (1-based).
    static func codenameRequest(device: UInt8) -> [UInt8] {
        [shortReport, receiverIndex, 0x83, 0xB5, 0x40 + device - 1, 0, 0]
    }

    // MARK: Reports

    static func reply(to request: [UInt8], in report: [UInt8]) -> Reply? {
        guard report.count >= 7, request.count >= 4,
              report[0] == shortReport || report[0] == longReport,
              report[1] == request[1]
        else { return nil }
        if report[2] == request[2] && report[3] == request[3] {
            return .payload(Array(report[4...]))
        }
        if report[2] == 0x8F || report[2] == 0xFF, report[3] == request[2], report[4] == request[3] {
            return .error
        }
        return nil
    }

    /// The receiver's 0x41 notification: a paired device connected, or dropped its link.
    static func linkChange(in report: [UInt8]) -> (device: UInt8, isLinked: Bool)? {
        guard report.count >= 7, report[0] == shortReport, report[2] == 0x41,
              (1...6).contains(report[1])
        else { return nil }
        return (report[1], report[4] & 0x40 == 0)
    }

    /// The payload of a report `device` sent on its own on `featureIndex`.
    static func event(from device: UInt8, featureIndex: UInt8, in report: [UInt8]) -> [UInt8]? {
        guard report.count >= 7, report[0] == longReport, report[1] == device,
              report[2] == featureIndex, report[3] & 0x0F == 0
        else { return nil }
        return Array(report[4...])
    }

    /// Codename reply payload: [sub ID, length, ASCII…].
    static func codename(from payload: [UInt8]) -> String? {
        guard payload.count >= 2 else { return nil }
        let length = Int(payload[1])
        guard length > 0, payload.count >= 2 + length else { return nil }
        return String(decoding: payload[2..<2 + length], as: UTF8.self)
    }

    /// Status bytes 1–4 (recharging, almost full, full, slow recharge) all mean external
    /// power; 0x1000 and 0x1004 share the encoding.
    static func battery(_ feature: BatteryFeature, payload: [UInt8]) -> Battery? {
        guard payload.count >= 4 else { return nil }
        switch feature {
        case .unified:
            // [state of charge %, level flags, status, external power]. A device without a
            // percentage reports 0 and only the coarse level flags.
            let percent = payload[0] > 0 ? Int(payload[0]) : approximatePercent(levelFlags: payload[1])
            return Battery(percent: percent, isCharging: (1...4).contains(payload[2]))
        case .status:
            // [level %, next level %, status]; level 0 means unknown.
            guard payload[0] > 0 else { return nil }
            return Battery(percent: Int(payload[0]), isCharging: (1...4).contains(payload[2]))
        case .voltage:
            // [millivolts, big-endian; flags]; flag bit 7 is external power.
            let millivolts = Int(payload[0]) << 8 | Int(payload[1])
            return Battery(percent: percent(millivolts: millivolts), isCharging: payload[2] & 0x80 != 0)
        }
    }

    /// Solaar's `BatteryLevelApproximation` for the 0x1004 level flags.
    private static func approximatePercent(levelFlags: UInt8) -> Int {
        if levelFlags & 0x08 != 0 { return 90 }
        if levelFlags & 0x04 != 0 { return 50 }
        if levelFlags & 0x02 != 0 { return 20 }
        if levelFlags & 0x01 != 0 { return 5 }
        return 0
    }

    /// Solaar's measured discharge points (`estimate_battery_level_percentage`), interpolated
    /// linearly. Data, not code (D20).
    private static let dischargeCurve: [(millivolts: Int, percent: Int)] = [
        (4186, 100), (4067, 90), (3989, 80), (3922, 70), (3859, 60), (3811, 50), (3778, 40),
        (3751, 30), (3717, 20), (3671, 10), (3646, 5), (3579, 2), (3500, 0),
    ]

    static func percent(millivolts: Int) -> Int {
        guard let top = dischargeCurve.first, let bottom = dischargeCurve.last else { return 0 }
        if millivolts >= top.millivolts { return top.percent }
        if millivolts <= bottom.millivolts { return bottom.percent }
        for (high, low) in zip(dischargeCurve, dischargeCurve.dropFirst()) where millivolts >= low.millivolts {
            let fraction = Double(millivolts - low.millivolts) / Double(high.millivolts - low.millivolts)
            return Int((Double(low.percent) + fraction * Double(high.percent - low.percent)).rounded())
        }
        return 0
    }
}
