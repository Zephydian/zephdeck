// Battery alerts and the header's battery. Copied into Zephdeck from boring.notch
// (github.com/TheBoredTeam/boring.notch, GPL-3.0, commit e2654ee):
// - BatteryActivityManager (managers/BatteryActivityManager.swift) and BatteryStatusViewModel
//   (models/BatteryStatusViewModel.swift): IOKit power-source notices, Low Power Mode, the status lines
// - BatteryView, BatteryMenuView and BoringBatteryView (components/Live activities/BoringBattery.swift)
// - the battery expanding view and its 3 s timing (ContentView.swift, BoringViewCoordinator.swift)
// Zephdeck changes: one @Observable model instead of the manager, view model and notification queue;
// alerts for low battery (20% and 10%) and full charge added, each alert a switch; SF Symbols instead
// of boring.notch's bolt and plug images; battery health and cycles from Zephdeck's SystemSensors;
// nothing runs on a Mac without a battery; English text.

import AppKit
import IOKit.ps
import SwiftUI

/// The Mac's battery, kept current from macOS's power-source notices (nothing polled) while the island is on.
@Observable
final class IslandBattery {
    static let shared = IslandBattery()

    /// A short alert in the closed island.
    struct Alert: Equatable {
        let text: String
        let id = UUID()
    }

    private(set) var hasBattery = false
    /// 0…100.
    private(set) var level: Float = 0
    private(set) var isPluggedIn = false
    private(set) var isCharging = false
    private(set) var isInLowPowerMode = false
    /// Minutes, 0 when unknown.
    private(set) var timeToFullCharge = 0
    private(set) var alert: Alert?

    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var lowPowerObserver: NSObjectProtocol?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var running = false
    /// The lowest low-battery step already announced on this discharge (20, then 10).
    @ObservationIgnored private var lowAnnounced: Float = 101
    private static let alertDuration: Duration = .seconds(3)

    func start() {
        guard !running else { return }
        running = true
        read(announce: false)
        guard hasBattery else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let battery = Unmanaged<IslandBattery>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { battery.read(announce: true) }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            self.source = source
        }
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.read(announce: true) }
        }
    }

    func stop() {
        running = false
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
        source = nil
        if let lowPowerObserver { NotificationCenter.default.removeObserver(lowPowerObserver) }
        lowPowerObserver = nil
        hideTask?.cancel()
        alert = nil
    }

    // MARK: Reading

    private func read(announce: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let description = sources.lazy.compactMap({
                  IOPSGetPowerSourceDescription(snapshot, $0)?.takeUnretainedValue() as? [String: Any]
              }).first(where: { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType }),
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else {
            hasBattery = false
            return
        }
        hasBattery = true
        let newLevel = Float(current) / Float(maximum) * 100
        let pluggedIn = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let charging = description[kIOPSIsChargingKey] as? Bool ?? false
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let settings = IslandSettings.shared

        if announce {
            if pluggedIn != isPluggedIn, settings.batteryPlugAlert {
                show(pluggedIn ? (charging ? "Charging" : "Plugged In") : "Unplugged")
            } else if lowPower != isInLowPowerMode, settings.batteryLowPowerAlert {
                show("Low Power \(lowPower ? "On" : "Off")")
            } else if pluggedIn, newLevel >= 100, level < 100, settings.batteryFullAlert {
                show("Fully Charged")
            } else if !pluggedIn, settings.batteryLowAlert,
                      let step = [Float(10), 20].first(where: { newLevel <= $0 && level > $0 }), step < lowAnnounced {
                lowAnnounced = step
                show("Low Battery")
            }
        }
        if pluggedIn { lowAnnounced = 101 }

        withAnimation(.smooth) {
            level = newLevel
            isPluggedIn = pluggedIn
            isCharging = charging
            isInLowPowerMode = lowPower
            timeToFullCharge = max(0, description[kIOPSTimeToFullChargeKey] as? Int ?? 0)
        }
    }

    private func show(_ text: String) {
        withAnimation(IslandMotion.open) { alert = Alert(text: text) }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.alertDuration)
            guard !Task.isCancelled else { return }
            withAnimation(IslandMotion.close) { self?.alert = nil }
        }
    }

    /// The battery's color: yellow in Low Power Mode, red when low, green while charging or full.
    var color: Color {
        if isInLowPowerMode { return .yellow }
        if level <= 20 && !isCharging && !isPluggedIn { return .red }
        if isCharging || isPluggedIn || level >= 100 { return .green }
        return .white
    }
}

// MARK: - Views

/// The battery outline filled to its level, with a bolt or plug over it.
struct IslandBatteryIcon: View {
    var width: CGFloat = 26
    private var battery: IslandBattery { IslandBattery.shared }

    private var statusSymbol: String? {
        if battery.isCharging { return "bolt.fill" }
        if battery.isPluggedIn { return "powerplug.fill" }
        return nil
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "battery.0")
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.5))
                .frame(width: width + 1)

            RoundedRectangle(cornerRadius: 2.5)
                .fill(battery.color)
                .frame(
                    width: CGFloat(battery.level / 100) * (width - 6),
                    height: (width - 2.75) - 18
                )
                .padding(.leading, 2)

            if let statusSymbol {
                Image(systemName: statusSymbol)
                    .font(.system(size: width * 0.36, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 1)
                    .frame(width: width, height: width)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(Int(battery.level)) percent\(battery.isCharging ? ", charging" : battery.isPluggedIn ? ", plugged in" : "")")
    }
}

/// The closed island's alert: the status on the left of the notch, the battery on the right.
struct IslandBatteryAlert: View {
    let model: IslandModel
    let text: String
    private var battery: IslandBattery { IslandBattery.shared }

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: model.closedSize.width + 10)

            HStack(spacing: 6) {
                Text("\(Int(battery.level))%")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                IslandBatteryIcon(width: 30)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(width: IslandBatteryAlert.width, height: model.effectiveClosedHeight, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text), battery \(Int(battery.level)) percent")
    }

    /// As wide as the open island (minus the closed island's side insets).
    static var width: CGFloat { IslandSizing.openSize.width - 2 * IslandSizing.cornerRadiusInsets.closed.bottom }
}

/// The header's battery: its percentage and icon; a click shows the details.
struct IslandBatteryButton: View {
    let model: IslandModel
    @State private var showsDetails = false
    private var battery: IslandBattery { IslandBattery.shared }

    var body: some View {
        Button {
            showsDetails.toggle()
        } label: {
            HStack(spacing: 4) {
                Text("\(Int(battery.level))%")
                    .font(.callout)
                    .foregroundStyle(.white)
                    .monospacedDigit()
                IslandBatteryIcon(width: 26)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandTileButtonStyle())
        .help("Battery")
        .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
            IslandBatteryDetails { showsDetails = false }
        }
        .onChange(of: showsDetails) { _, showing in
            // The island stays open while the details are up, and closes after if the pointer left.
            model.menuOpen = showing
            if !showing, model.state == .open, !model.pinned, !model.isPointerInside() {
                withAnimation(IslandMotion.close) { model.close() }
            }
        }
    }
}

/// boring.notch's battery menu, with health and cycles from Zephdeck's sensors.
struct IslandBatteryDetails: View {
    let dismiss: () -> Void
    @State private var healthPercent: Double?
    @State private var cycles: Int?
    private var battery: IslandBattery { IslandBattery.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Battery").font(.headline)
                Spacer()
                Text("\(Int(battery.level))%").font(.headline).monospacedDigit()
            }
            VStack(alignment: .leading, spacing: 8) {
                if let percent = healthPercent {
                    Label("Health: \(Int(percent.rounded()))%", systemImage: "heart")
                }
                if let cycles {
                    Label("Cycles: \(cycles)", systemImage: "arrow.triangle.2.circlepath")
                }
                if battery.isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle")
                }
                if battery.isCharging {
                    Label("Charging", systemImage: "bolt.fill")
                } else if battery.isPluggedIn {
                    Label("Plugged In", systemImage: "powerplug.fill")
                }
                if battery.timeToFullCharge > 0 {
                    Label("Full in \(battery.timeToFullCharge) min", systemImage: "clock")
                }
                if !battery.isCharging && battery.isPluggedIn && battery.level >= 80 && battery.level < 100 {
                    Label("Charging on hold", systemImage: "pause.circle")
                }
            }
            .font(.subheadline)
            Divider()
            Button {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
                    NSWorkspace.shared.open(url)
                }
                dismiss()
            } label: {
                Label("Battery Settings…", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 260)
        .task {
            let reading = await Task.detached(priority: .utility) { () -> (Double?, Int?) in
                let battery = SystemSensors.battery()
                return (battery["healthPercent"] as? Double, battery["cycles"] as? Int)
            }.value
            healthPercent = reading.0
            cycles = reading.1
        }
    }
}
