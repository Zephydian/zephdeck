// The island's timers: Zephydian's own (`PackTimers`, the Timer utility's). The layout and timing are
// Zephydian's, after Vorssaint's island timer (UI/Notch/NotchTimerView.swift; GPL-3.0-or-later,
// Copyright (C) 2026 Vorssaint) and the closed live activities copied from boring.notch.

import AppKit
import SwiftUI

/// The timers as the island sees them, and starting one as the Timer utility.
@Observable
final class IslandTimers {
    static let shared = IslandTimers()

    /// "… is done", shown over everything for 3 s when a timer ends.
    private(set) var doneAlert: String?
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    static let packID = "timer"
    static let quickStarts: [(label: String, minutes: Int)] = [("1m", 1), ("5m", 5), ("10m", 10), ("15m", 15), ("25m", 25), ("60m", 60)]

    private var services: PackServices { PackServices.shared }

    /// Every timer, soonest first (paused ones after). Reading it follows changes.
    var all: [PackTimers.Timer] {
        _ = services.revision
        return services.timers.all()
    }

    var soonest: PackTimers.Timer? { all.first }
    var isLive: Bool { soonest != nil }

    /// Island timers are the Timer utility's (the owner's choice): it has to be installed.
    var isInstalled: Bool { PackLibrary.shared.packs.contains { $0.id == Self.packID } }

    func start(minutes: Int) {
        guard isInstalled else { return }
        // The Timer utility's chosen sound (its "prefs"), "Glass" when it has none; "None" is silent.
        let prefs = PackStorage.shared(packID: Self.packID).get("prefs")
            .flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        let chosen = prefs?["sound"] as? String ?? "Glass"
        services.timers.start(packID: Self.packID, packName: "Timer", label: "\(minutes) min",
                              seconds: Double(minutes * 60), sound: chosen == "None" ? nil : chosen,
                              notify: true, chain: [])
    }

    func togglePause(_ timer: PackTimers.Timer) {
        if timer.endsAt == nil {
            services.timers.resume(packID: timer.packID, id: timer.id)
        } else {
            services.timers.pause(packID: timer.packID, id: timer.id)
        }
    }

    func stop(_ timer: PackTimers.Timer) {
        services.timers.cancel(packID: timer.packID, id: timer.id)
    }

    /// Listens for timers ending (while the island is on).
    func start() {
        PackTimers.onFinished = { [weak self] timer in self?.finished(timer) }
    }

    func stop() {
        PackTimers.onFinished = { _ in }
        hideTask?.cancel()
        doneAlert = nil
    }

    private func finished(_ timer: PackTimers.Timer) {
        withAnimation(IslandMotion.open) {
            doneAlert = timer.label.isEmpty ? "Time's up" : "\(timer.label) is done"
        }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(IslandMotion.close) { self?.doneAlert = nil }
        }
    }

    /// 4:32, 1:05:00; seconds rounded up so it reads 0:01 until it really ends.
    static func clock(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.up)), h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Closed island

/// A timer running: an orange timer icon and its name on the left of the notch, the time left on the
/// right, both hugging the notch (the owner's request). The two sides are as wide as the wider of
/// them, so the island stays centred on the real notch, and no wider.
struct IslandTimerLiveActivity: View {
    let model: IslandModel
    let timer: PackTimers.Timer
    @State private var leftWidth: CGFloat = 0
    @State private var rightWidth: CGFloat = 0

    /// Room between the text and the island's outer edge.
    static let margin: CGFloat = 8
    /// An estimate for the hover strip under a short pill (the real width follows the text).
    static func width(closed: CGFloat) -> CGFloat { closed + 28 + 2 * 70 }

    private var side: CGFloat { max(leftWidth, rightWidth) + Self.margin }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: timer.endsAt == nil ? "pause.circle.fill" : "timer")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(timer.label.isEmpty ? "Timer" : timer.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { leftWidth = $0 }
            .frame(width: side, alignment: .trailing)

            // A little wider than the camera notch (like the battery alert), so no letter slips behind it.
            Rectangle()
                .fill(.black)
                .frame(width: model.closedSize.width + 8)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(IslandTimers.clock(timer.remaining))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(timer.endsAt == nil ? Color(white: 0.6) : .orange)
                    .fixedSize()
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rightWidth = $0 }
            .frame(width: side, alignment: .leading)
        }
        .frame(height: model.effectiveClosedHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(timer.label), \(IslandTimers.clock(timer.remaining)) left\(timer.endsAt == nil ? ", paused" : "")")
    }
}

/// "Tea is done": the island widens for 3 s.
struct IslandTimerDoneAlert: View {
    let model: IslandModel
    let text: String

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.black).frame(width: model.closedSize.width + 10)
            Image(systemName: "timer")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .frame(width: IslandBatteryAlert.width, height: model.effectiveClosedHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

// MARK: - The Timers tab and Home

/// A ring that empties as the timer runs out.
struct IslandTimerRing: View {
    let timer: PackTimers.Timer
    let size: CGFloat

    var body: some View {
        let progress = timer.seconds > 0 ? min(1, max(0, timer.remaining / timer.seconds)) : 0
        ZStack {
            Circle().stroke(Color.orange.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The Timers tab: the running timers as rows, and quick starts.
struct IslandTimersPage: View {
    private var timers: IslandTimers { IslandTimers.shared }

    var body: some View {
        if !timers.isInstalled {
            IslandTimerInstall()
        } else {
            let all = timers.all
            VStack(alignment: .leading, spacing: 8) {
                if all.isEmpty {
                    Text("Start a timer")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.65))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 6) {
                            ForEach(all, id: \.id) { IslandTimerRow(timer: $0) }
                        }
                    }
                    .scrollIndicators(.never)
                    .onHover { IslandGestureGuard.overScrollingContent = $0 }
                    .onDisappear { IslandGestureGuard.overScrollingContent = false }
                }
                IslandQuickStarts(starts: IslandTimers.quickStarts)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

struct IslandTimerRow: View {
    let timer: PackTimers.Timer
    private var timers: IslandTimers { IslandTimers.shared }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 10) {
                IslandTimerRing(timer: timer, size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(timer.label.isEmpty ? "Timer" : timer.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if timer.phases > 1 {
                        Text("\(timer.packName) · \(timer.phase) of \(timer.phases)")
                            .font(.system(size: 10)).foregroundStyle(Color(white: 0.55))
                    }
                }
                Spacer(minLength: 4)
                Text(IslandTimers.clock(timer.remaining))
                    .font(.system(size: 20, weight: .medium).monospacedDigit())
                    .foregroundStyle(timer.endsAt == nil ? Color(white: 0.6) : .white)
                IslandHoverButton(icon: timer.endsAt == nil ? "play.fill" : "pause.fill",
                                  label: timer.endsAt == nil ? "Resume" : "Pause") { timers.togglePause(timer) }
                IslandHoverButton(icon: "xmark", label: "Stop") { timers.stop(timer) }
            }
            .padding(.vertical, 2)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Buttons that start a timer of so many minutes.
struct IslandQuickStarts: View {
    let starts: [(label: String, minutes: Int)]
    var columns: Int? = nil
    private var timers: IslandTimers { IslandTimers.shared }

    var body: some View {
        let grid = columns.map { Array(repeating: GridItem(.flexible(), spacing: 6), count: $0) }
            ?? Array(repeating: GridItem(.flexible(), spacing: 6), count: starts.count)
        LazyVGrid(columns: grid, spacing: 6) {
            ForEach(starts, id: \.minutes) { start in
                Button { timers.start(minutes: start.minutes) } label: {
                    Text(start.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(IslandTileButtonStyle())
                .help("Start a \(start.minutes)-minute timer")
                .accessibilityLabel("Start a \(start.minutes)-minute timer")
            }
        }
    }
}

/// Home's quick timer: the soonest timer large with pause and stop, or quick starts.
struct IslandTimerHome: View {
    private var timers: IslandTimers { IslandTimers.shared }

    var body: some View {
        if !timers.isInstalled {
            IslandTimerInstall()
        } else if let timer = timers.soonest {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        IslandTimerRing(timer: timer, size: 16)
                        Text(timer.label.isEmpty ? "Timer" : timer.label)
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    }
                    Text(IslandTimers.clock(timer.remaining))
                        .font(.system(size: 30, weight: .light).monospacedDigit())
                        .foregroundStyle(timer.endsAt == nil ? Color(white: 0.6) : .white)
                    HStack(spacing: 4) {
                        IslandHoverButton(icon: timer.endsAt == nil ? "play.fill" : "pause.fill",
                                          label: timer.endsAt == nil ? "Resume" : "Pause") { timers.togglePause(timer) }
                        IslandHoverButton(icon: "xmark", label: "Stop") { timers.stop(timer) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 8) {
                Label("Quick timer", systemImage: "timer")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                IslandQuickStarts(starts: [("1m", 1), ("5m", 5), ("10m", 10), ("25m", 25)], columns: 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Without the Timer utility: a button that opens the Library on Utilities.
struct IslandTimerInstall: View {
    @Environment(\.islandModel) private var model

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "timer").font(.system(size: 22)).foregroundStyle(.orange)
            Text("Timers come from the Timer utility.")
                .font(.system(size: 12)).foregroundStyle(Color(white: 0.7))
                .multilineTextAlignment(.center)
            Button("Get the Timer Utility") {
                model?.close()
                IslandHooks.openUtilitiesLibrary()
            }
            .buttonStyle(IslandLinkButtonStyle())
            .font(.system(size: 12, weight: .medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Things the island asks of the rest of Zephydian (set by AppDelegate).
enum IslandHooks {
    static var openUtilitiesLibrary: () -> Void = {}
}
