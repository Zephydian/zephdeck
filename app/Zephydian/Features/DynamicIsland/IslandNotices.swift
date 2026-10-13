// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// The closed island's short notices follow Vorssaint's indicators (UI/Notch/NotchNoticeView.swift and
// the feedback settings, commit 1d32501): something happens, the closed island shows it beside the
// notch for a moment, then goes back to what it showed. Zephydian changes: Zephydian's own events
// (a screenshot or recording from Capture, a new song, the microphone shortcut, Clipboard history);
// no volume or brightness (macOS keeps its own pop-ups, B-24); drawn like Zephydian's live
// activities (a wing each side of the notch); English text.

import AppKit
import SwiftUI

/// The notice showing now, if any. One at a time: a new one replaces the last.
@Observable
final class IslandNotices {
    static let shared = IslandNotices()

    struct Notice: Equatable {
        enum Kind: Equatable { case capture, song, mic, clipboard }
        let id = UUID()
        let kind: Kind
        let icon: String
        var image: NSImage?
        let text: String
        var tint: Color = .white
    }

    private(set) var current: Notice?
    @ObservationIgnored private var hide: Task<Void, Never>?
    @ObservationIgnored private var running = false
    private var settings: IslandSettings { IslandSettings.shared }

    func show(_ notice: Notice, for seconds: Double = 3) {
        guard running else { return }
        withAnimation(.smooth) { current = notice }
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, self.current?.id == notice.id else { return }
            withAnimation(.smooth) { self.current = nil }
        }
    }

    /// Listens to Zephydian's events while the island is on.
    func start() {
        running = true
        ScreenCapture.onShot = { [weak self] image, copied in
            guard let self, self.settings.noticeCaptures else { return }
            self.show(Notice(kind: .capture, icon: "camera.viewfinder",
                             image: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)),
                             text: copied ? "Copied" : "Screenshot"))
        }
        ScreenRecorder.onSaved = { [weak self] in
            guard let self, self.settings.noticeCaptures else { return }
            self.show(Notice(kind: .capture, icon: "record.circle", text: "Recording saved", tint: .red))
        }
        Microphone.onChange = { [weak self] muted in
            guard let self, self.settings.noticeMic else { return false }
            self.show(Notice(kind: .mic, icon: muted ? "mic.slash.fill" : "mic.fill", text: muted ? "Muted" : "Mic on",
                             tint: muted ? .red : .white))
            return true
        }
        ClipboardHistory.onCaptured = { [weak self] kind in
            // A screenshot copies itself too; its own notice says so already.
            guard let self, self.settings.noticeClipboard, self.current?.kind != .capture else { return }
            let (icon, text) = switch kind {
            case "image": ("photo", "Image copied")
            case "file": ("doc", "File copied")
            default: ("doc.on.clipboard", "Copied")
            }
            self.show(Notice(kind: .clipboard, icon: icon, text: text))
        }
        IslandMusic.shared.onNewTrack = { [weak self] in
            guard let self, self.settings.noticeSong else { return }
            let music = IslandMusic.shared
            self.show(Notice(kind: .song, icon: "music.note", image: music.artwork, text: music.title), for: 4)
        }
    }

    func stop() {
        running = false
        hide?.cancel()
        current = nil
        ScreenCapture.onShot = { _, _ in }
        ScreenRecorder.onSaved = {}
        Microphone.onChange = { _ in false }
        ClipboardHistory.onCaptured = { _ in }
        IslandMusic.shared.onNewTrack = {}
    }
}

/// A notice beside the notch: its icon or picture on the left, its text on the right.
struct IslandNoticeView: View {
    let model: IslandModel
    let notice: IslandNotices.Notice
    @State private var rightWidth: CGFloat = 0

    private var height: CGFloat { model.effectiveClosedHeight }
    private var side: CGFloat { max(height + 6, rightWidth + IslandTimerLiveActivity.margin) }

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let image = notice.image {
                    Image(nsImage: image).resizable().scaledToFill()
                        .frame(width: height - 10, height: height - 10)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                } else {
                    Image(systemName: notice.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(notice.tint)
                }
            }
            .frame(width: side, alignment: .trailing)
            .padding(.trailing, 0)

            Rectangle().fill(.black).frame(width: model.closedSize.width + 8)

            Text(notice.text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(notice.tint == .red ? .white : notice.tint)
                .lineLimit(1)
                .frame(maxWidth: 150, alignment: .leading)
                .fixedSize()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rightWidth = $0 }
                .frame(width: side, alignment: .leading)
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(notice.text)
    }
}

/// At rest with Battery (Vorssaint's resting choice): the battery icon and its percentage beside the notch.
struct IslandBatteryRest: View {
    let model: IslandModel
    private var battery: IslandBattery { IslandBattery.shared }
    static let wing: CGFloat = 44

    var body: some View {
        HStack(spacing: 0) {
            IslandBatteryIcon(width: 22)
                .frame(width: Self.wing, alignment: .center)
            Rectangle().fill(.black).frame(width: model.closedSize.width + 8)
            Text("\(Int(battery.level))%")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: Self.wing, alignment: .center)
        }
        .frame(height: model.effectiveClosedHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(Int(battery.level)) percent")
    }
}
