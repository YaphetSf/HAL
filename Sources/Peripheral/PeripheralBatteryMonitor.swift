import Foundation
import IOKit.hid
import Observation
import OSLog

private let log = Logger(subsystem: "com.hal.inputmethod", category: "peripheral")

/// Battery levels of the Logitech devices paired to plugged-in receivers, for the menu bar
/// (D30). Read-only: HAL never writes a receiver or device setting.
///
/// Everything runs on the main run loop. IOHIDManager delivers its callbacks there, each
/// receiver has one request in flight at a time, and a reply that never comes (a sleeping
/// device) times out instead of blocking anything.
@Observable
@MainActor
final class PeripheralBatteryMonitor {
    struct Device: Equatable {
        let name: String
        let battery: HIDPP.Battery
    }

    static let shared = PeripheralBatteryMonitor()
    static let lowPercent = 15
    private static let refreshInterval: TimeInterval = 30 * 60

    private(set) var devices: [Device] = []

    var hasLowBattery: Bool {
        devices.contains { !$0.battery.isCharging && $0.battery.percent <= Self.lowPercent }
    }

    @ObservationIgnored private var manager: IOHIDManager?
    @ObservationIgnored private var receivers: [Receiver] = []

    private init() {}

    func start() {
        guard manager == nil else { return }
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // The HID++ long-report collection; Logitech's other vendor-page devices lack it.
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: 0x046D,
            kIOHIDDeviceUsagePageKey: 0xFF00,
            kIOHIDDeviceUsageKey: 0x0002,
        ] as CFDictionary)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { _, _, _, device in
            MainActor.assumeIsolated { PeripheralBatteryMonitor.shared.receiverAdded(device) }
        }, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { _, _, _, device in
            MainActor.assumeIsolated { PeripheralBatteryMonitor.shared.receiverRemoved(device) }
        }, nil)
        IOHIDManagerRegisterInputReportCallback(manager, { _, _, sender, _, _, report, length in
            guard let sender else { return }
            let key = UInt(bitPattern: sender)
            let bytes = Array(UnsafeBufferPointer(start: report, count: length))
            MainActor.assumeIsolated { PeripheralBatteryMonitor.shared.received(bytes, from: key) }
        }, nil)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if status != kIOReturnSuccess {
            log.error("IOHIDManagerOpen failed: \(status)")
        }
        self.manager = manager

        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { _ in
            MainActor.assumeIsolated { PeripheralBatteryMonitor.shared.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: Receivers

    private func receiverAdded(_ device: IOHIDDevice) {
        let receiver = Receiver(device: device)
        receivers.append(receiver)
        log.info("Receiver added pid=\(receiver.productID, format: .hex)")
        receiver.reportPairedDevices()
    }

    private func receiverRemoved(_ device: IOHIDDevice) {
        let key = Receiver.key(of: device)
        guard let index = receivers.firstIndex(where: { $0.key == key }) else { return }
        let receiver = receivers.remove(at: index)
        receiver.cancelAll()
        log.info("Receiver removed pid=\(receiver.productID, format: .hex)")
        publish()
    }

    private func refresh() {
        receivers.forEach { $0.reportPairedDevices() }
    }

    private func received(_ report: [UInt8], from key: UInt) {
        guard let receiver = receivers.first(where: { $0.key == key }) else { return }
        if receiver.consumeReply(report) { return }
        if let change = HIDPP.linkChange(in: report) {
            if change.isLinked {
                Task { @MainActor in await self.query(change.device, on: receiver) }
            }
            return
        }
        for (index, paired) in receiver.paired {
            guard let feature = paired.feature,
                  let payload = HIDPP.event(from: index, featureIndex: feature.index, in: report),
                  let battery = HIDPP.battery(feature.kind, payload: payload)
            else { continue }
            update(battery, of: index, on: receiver)
        }
    }

    // MARK: Devices

    /// Name, battery feature, then level. The first two are cached, so a refresh is one read.
    private func query(_ index: UInt8, on receiver: Receiver) async {
        guard !receiver.paired[index, default: Paired()].isQuerying else { return }
        receiver.paired[index, default: Paired()].isQuerying = true
        defer { receiver.paired[index]?.isQuerying = false }

        if receiver.paired[index]?.name == nil {
            receiver.paired[index]?.name = await name(of: index, on: receiver)
        }
        if receiver.paired[index]?.feature == nil {
            for kind in HIDPP.BatteryFeature.allCases {
                // No reply at all means asleep or gone: stop rather than time out three times.
                guard case .payload(let found)? = await receiver.send(
                    HIDPP.featureIndexRequest(device: index, feature: kind.rawValue))
                else { return }
                if found[0] != 0 {
                    receiver.paired[index]?.feature = (found[0], kind)
                    break
                }
            }
        }
        guard let feature = receiver.paired[index]?.feature,
              case .payload(let payload)? = await receiver.send(HIDPP.featureRequest(
                  device: index, featureIndex: feature.index, function: feature.kind.readFunction)),
              let battery = HIDPP.battery(feature.kind, payload: payload)
        else { return }
        update(battery, of: index, on: receiver)
    }

    /// The receiver's short codename; Bolt receivers keep names elsewhere, so fall back to the
    /// device's own full name.
    private func name(of index: UInt8, on receiver: Receiver) async -> String? {
        if case .payload(let payload)? = await receiver.send(HIDPP.codenameRequest(device: index)),
           let codename = HIDPP.codename(from: payload) {
            return codename
        }
        guard case .payload(let found)? = await receiver.send(
                  HIDPP.featureIndexRequest(device: index, feature: HIDPP.deviceNameFeature)),
              found[0] != 0,
              case .payload(let count)? = await receiver.send(
                  HIDPP.featureRequest(device: index, featureIndex: found[0], function: 0))
        else { return nil }
        let length = Int(count[0])
        var bytes: [UInt8] = []
        while bytes.count < length {
            guard case .payload(let chunk)? = await receiver.send(HIDPP.featureRequest(
                      device: index, featureIndex: found[0], function: 1, params: [UInt8(bytes.count)])),
                  !chunk.isEmpty
            else { return nil }
            bytes += chunk
        }
        return String(decoding: bytes.prefix(length), as: UTF8.self)
    }

    private func update(_ battery: HIDPP.Battery, of index: UInt8, on receiver: Receiver) {
        guard receiver.paired[index]?.battery != battery else { return }
        receiver.paired[index]?.battery = battery
        log.info("Battery device=\(index) \(battery.percent)% charging=\(battery.isCharging)")
        publish()
    }

    private func publish() {
        let current = receivers.flatMap { receiver in
            receiver.paired.compactMap { index, paired in
                paired.battery.map { Device(name: paired.name ?? "Device \(index)", battery: $0) }
            }
        }.sorted { $0.name < $1.name }
        if current != devices { devices = current }
    }
}

private struct Paired {
    var name: String?
    var feature: (index: UInt8, kind: HIDPP.BatteryFeature)?
    var battery: HIDPP.Battery?
    var isQuerying = false
}

/// One plugged-in receiver: a serial request queue over its HID++ interface, plus what is
/// known about each paired device.
@MainActor
private final class Receiver {
    private struct Pending {
        let request: [UInt8]
        let continuation: CheckedContinuation<HIDPP.Reply?, Never>
    }

    /// A sleeping G915 TKL misses 0.5 s but answers within 3 s (D30).
    private static let replyTimeout: Duration = .seconds(3)

    let device: IOHIDDevice
    let key: UInt
    let productID: UInt32
    var paired: [UInt8: Paired] = [:]
    private var queue: [Pending] = []
    private var inFlight: Pending?
    private var generation = 0

    static func key(of device: IOHIDDevice) -> UInt {
        UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
    }

    init(device: IOHIDDevice) {
        self.device = device
        key = Self.key(of: device)
        productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.uint32Value ?? 0
    }

    /// Answered through the 0x41 notifications the monitor already handles.
    func reportPairedDevices() {
        Task { @MainActor in _ = await self.send(HIDPP.reportPairedDevices) }
    }

    func send(_ request: [UInt8]) async -> HIDPP.Reply? {
        await withCheckedContinuation { continuation in
            queue.append(Pending(request: request, continuation: continuation))
            pump()
        }
    }

    /// True when `report` answered the request in flight.
    func consumeReply(_ report: [UInt8]) -> Bool {
        guard let pending = inFlight, let reply = HIDPP.reply(to: pending.request, in: report) else {
            return false
        }
        finish(reply)
        return true
    }

    func cancelAll() {
        let waiting = (inFlight.map { [$0] } ?? []) + queue
        inFlight = nil
        queue = []
        waiting.forEach { $0.continuation.resume(returning: nil) }
    }

    private func pump() {
        guard inFlight == nil, !queue.isEmpty else { return }
        let next = queue.removeFirst()
        inFlight = next
        generation += 1
        let token = generation
        let status = next.request.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, CFIndex(next.request[0]),
                                 $0.baseAddress!, $0.count)
        }
        guard status == kIOReturnSuccess else {
            log.error("HID++ write failed pid=\(self.productID, format: .hex): \(status)")
            finish(nil)
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.replyTimeout)
            guard let self, self.generation == token, self.inFlight != nil else { return }
            self.finish(nil)
        }
    }

    private func finish(_ reply: HIDPP.Reply?) {
        let pending = inFlight
        inFlight = nil
        pending?.continuation.resume(returning: reply)
        pump()
    }
}
