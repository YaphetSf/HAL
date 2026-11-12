import SwiftUI

/// The menu bar drop-down's card (D31): the current mode, paired device batteries (D30), and
/// the door to the control center. Mode and batteries are observed live, so a Caps Lock press
/// or a battery event while the card is open shows up in place.
struct ModeStatusPanelView: View {
    static let shadowPadding: CGFloat = 14
    private static let width: CGFloat = 248
    private static let corner: CGFloat = 12

    /// Changes on every open, so the entrance animation replays instead of SwiftUI keeping
    /// the last open's state.
    let id: Int
    let scheme: CandidateColorScheme
    let openControlCenter: () -> Void
    let resized: (CGSize) -> Void

    var body: some View {
        Card(scheme: scheme, openControlCenter: openControlCenter)
            .id(id)
            .padding(Self.shadowPadding)
            .fixedSize()
            .onGeometryChange(for: CGSize.self, of: \.size, action: resized)
    }

    private struct Card: View {
        let scheme: CandidateColorScheme
        let openControlCenter: () -> Void

        private let mode = ModeState.shared
        private let peripherals = PeripheralBatteryMonitor.shared
        @Namespace private var modeHighlight
        @State private var appear: CGFloat = 0
        @State private var hoveringOpen = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: ModeStatusPanelView.corner, style: .continuous)
            VStack(spacing: 0) {
                modeSection
                    .padding(8)
                if !peripherals.devices.isEmpty {
                    divider
                    VStack(spacing: 9) {
                        ForEach(peripherals.devices, id: \.name, content: deviceRow)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
                divider
                openButton
                    .padding(6)
            }
            .frame(width: ModeStatusPanelView.width)
            .background(
                shape.fill(.regularMaterial)
                    .overlay(shape.strokeBorder(scheme.accentGradient.opacity(0.55), lineWidth: 1))
            )
            .clipShape(shape)
            .shadow(color: scheme.glow.color.opacity(0.3), radius: 12, y: 3)
            .scaleEffect(0.96 + 0.04 * appear, anchor: .top)
            .opacity(appear)
            .animation(.snappy(duration: 0.22), value: mode.isAscii)
            .animation(.snappy(duration: 0.22), value: mode.englishProfile)
            .animation(.snappy(duration: 0.22), value: mode.isActive)
            .animation(.snappy(duration: 0.22), value: mode.secureInputHolder?.pid)
            .animation(.snappy(duration: 0.22), value: peripherals.devices)
            .onAppear {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) { appear = 1 }
            }
        }

        // MARK: Mode

        /// Shows the mode; switching stays on Caps Lock (D11), so the tiles are not buttons.
        @ViewBuilder private var modeSection: some View {
            if mode.isActive {
                HStack(spacing: 6) {
                    modeTile("中", isCurrent: !mode.isAscii)
                    modeTile("EN", isCurrent: mode.isAscii && mode.englishProfile == .direct)
                    modeTile("EN+", isCurrent: mode.isAscii && mode.englishProfile == .assist)
                }
            } else if let holder = mode.secureInputHolder {
                HStack(spacing: 6) {
                    Text("Secure input")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let icon = holder.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 16, height: 16)
                    }
                    Text(holder.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, 6)
                .frame(height: 36)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Secure input held by \(holder.name)")
            } else {
                HStack(spacing: 8) {
                    Text("Not the current input source")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    keycap("⌃ Space")
                }
                .padding(.horizontal, 6)
                .frame(height: 36)
            }
        }

        private func modeTile(_ label: String, isCurrent: Bool) -> some View {
            Text(label)
                .font(.system(size: 14, weight: isCurrent ? .semibold : .medium))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.primary.opacity(0.05))
                    if isCurrent {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(scheme.accentGradient)
                            .shadow(color: scheme.glow.color.opacity(0.55), radius: 6)
                            .matchedGeometryEffect(id: "mode", in: modeHighlight)
                    }
                }
        }

        private func keycap(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.primary.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.primary.opacity(0.15), lineWidth: 1))
        }

        // MARK: Devices

        private func deviceRow(_ device: PeripheralBatteryMonitor.Device) -> some View {
            HStack(spacing: 8) {
                Image(systemName: Self.symbol(for: device.kind))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(device.name)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if device.battery.isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(scheme.accentGradient)
                }
                gauge(device)
                Text("\(device.battery.percent)%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(device.isLow ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .frame(width: 36, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(device.name), \(device.battery.percent) percent"
                                + (device.battery.isCharging ? ", charging" : ""))
        }

        private static func symbol(for kind: HIDPP.DeviceKind) -> String {
            switch kind {
            case .keyboard: "keyboard"
            case .mouse: "computermouse"
            case .other: "dot.radiowaves.left.and.right"
            }
        }

        private func gauge(_ device: PeripheralBatteryMonitor.Device) -> some View {
            let width: CGFloat = 34
            let height: CGFloat = 6
            let fill = max(height, width * CGFloat(min(device.battery.percent, 100)) / 100)
            return ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.1))
                Capsule()
                    .fill(device.isLow ? AnyShapeStyle(.red) : AnyShapeStyle(scheme.accentGradient))
                    .frame(width: fill)
            }
            .frame(width: width, height: height)
        }

        // MARK: Control center

        private var openButton: some View {
            Button(action: openControlCenter) {
                Text("Open HAL")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hoveringOpen ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background {
                        if hoveringOpen {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(scheme.accentGradient)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringOpen = $0 }
        }

        private var divider: some View {
            Rectangle()
                .fill(.primary.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, 10)
        }
    }
}
