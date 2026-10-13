// The calendar, laid out like the iPhone's "Up Next" Calendar widget (the owner's choice, 2026-10-07):
// the day's weekday and date on the left, that day's events on the right (today: what's left of it),
// arrows on both sides to change the day; a click anywhere opens the Calendar app, or asks for access
// until it's given. Copied into Zephydian from boring.notch (github.com/TheBoredTeam/boring.notch,
// GPL-3.0, commit e2654ee): EmptyEventsView and ReminderToggle (components/Calendar/BoringCalendar.swift,
// created by Harsh Vardhan Goswami). Zephydian changes: the widget layout replaces boring.notch's day
// strip and list; an access button instead of asking on its own; the next-event live activity for the
// closed island is Zephydian's own; English text.

import SwiftUI

/// The calendar widget: the medium "Up Next" layout, or the small one in a narrow Home slot.
struct IslandCalendarView: View {
    @Environment(\.islandPreview) private var preview
    private var calendar: IslandCalendar { IslandCalendar.shared }

    /// A fixed height, like boring.notch's calendar (B-30): without it the list grew past the island
    /// and never needed to scroll. It follows the island's size (126 at Spacious).
    static var height: CGFloat { IslandSizing.openSize.height - 64 }
    static let wideLayoutWidth: CGFloat = 320

    var body: some View {
        GeometryReader { proxy in
            Group {
                // The wide layout needs room for the arrows, the date and a readable list (B-38: a
                // Home slot on a bigger island is just over 200 pt and squeezed it).
                if proxy.size.width < Self.wideLayoutWidth {
                    small
                } else {
                    medium()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            // Empty space opens Calendar (or asks for access); the list, the arrows and a reminder's
            // circle keep their own clicks (B-30).
            .background { Color.clear.contentShape(Rectangle()).onTapGesture { activate() } }
        }
        .frame(height: Self.height)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: calendar.hasAccess ? "Open Calendar" : "Allow Calendar Access") { activate() }
        .onAppear {
            guard !preview else { return }
            // Back to today each time it shows.
            Task { await calendar.show(dayOffset: 0) }
        }
    }

    private func activate() {
        guard !preview else { return }
        guard calendar.hasAccess else {
            Task { await calendar.askOrOpenSettings() }
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func arrow(_ direction: Int) -> some View {
        Button {
            guard !preview else { return }
            Task { await calendar.show(dayOffset: direction) }
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(white: 0.6))
                .frame(width: 22)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandTileButtonStyle())
        .disabled(!calendar.hasAccess)
        .opacity(calendar.hasAccess ? 1 : 0.3)
        .help(direction < 0 ? "Previous day" : "Next day")
        .accessibilityLabel(direction < 0 ? "Previous day" : "Next day")
    }

    // MARK: Layouts

    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(calendar.day.formatted(.dateTime.weekday(.wide)).uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.red)
            Text("\(Calendar.current.component(.day, from: calendar.day))")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func medium() -> some View {
        HStack(alignment: .top, spacing: 10) {
            arrow(-1)
            dateBlock.frame(width: 84, alignment: .leading).padding(.top, 4)
                .contentShape(Rectangle())
                .onTapGesture { activate() }
            Group {
                if !calendar.hasAccess {
                    IslandCalendarAccess()
                } else if calendar.showsToday {
                    upNext()
                } else {
                    dayList()
                }
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            arrow(1)
        }
    }

    /// Another day: all its events, in a list that scrolls.
    @ViewBuilder private func dayList() -> some View {
        let events = calendar.dayEvents
        if events.isEmpty {
            Text("No events").font(.subheadline).foregroundStyle(Color(white: 0.65))
        } else {
            IslandEventScroll(sections: [.init(id: "day", title: nil, events: events, tomorrow: true)])
        }
    }

    /// A third of Home (B-34): the arrows and a smaller date on top, the day's events in a list
    /// that scrolls below.
    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                arrow(-1)
                VStack(spacing: 0) {
                    Text(calendar.day.formatted(.dateTime.weekday(.wide)).uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.red)
                    Text("\(Calendar.current.component(.day, from: calendar.day))")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { activate() }
                .accessibilityElement(children: .combine)
                arrow(1)
            }
            .frame(height: 44)
            Group {
                if !calendar.hasAccess {
                    // A real button (B-32): plain text took the click and did nothing.
                    Button("Allow Calendar Access") { activate() }
                        .buttonStyle(IslandLinkButtonStyle())
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                } else {
                    let events = calendar.showsToday ? calendar.today : calendar.dayEvents
                    if events.isEmpty {
                        Text(calendar.showsToday ? "No more events today" : "No events")
                            .font(.caption).foregroundStyle(Color(white: 0.65))
                            .frame(maxWidth: .infinity)
                    } else {
                        IslandEventScroll(sections: [.init(id: "small", title: nil, events: events, tomorrow: !calendar.showsToday)])
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// What's left today, in a list that scrolls (tomorrow is the › arrow away, B-31).
    @ViewBuilder private func upNext() -> some View {
        let today = calendar.today
        if today.isEmpty {
            IslandEmptyEventsView()
        } else {
            IslandEventScroll(sections: [.init(id: "today", title: nil, events: today, tomorrow: false)])
        }
    }
}

/// The events in boring.notch's List (B-30: a ScrollView didn't scroll in the island window; the List
/// does in boring.notch's). It scrolls to the next event when it appears. While the pointer is over
/// it, the island's swipe gestures stand aside so scrolling doesn't close the island.
struct IslandEventScroll: View {
    struct Section: Identifiable {
        let id: String
        let title: String?
        let events: [IslandEvent]
        let tomorrow: Bool
    }

    var note: String?
    let sections: [Section]

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if let note {
                    Text(note).font(.caption).foregroundStyle(Color(white: 0.65)).modifier(IslandListRow())
                }
                ForEach(sections) { section in
                    if let title = section.title {
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(white: 0.55))
                            .padding(.top, 2)
                            .modifier(IslandListRow())
                    }
                    ForEach(section.events) { event in
                        IslandEventRow(event: event, tomorrow: section.tomorrow)
                            .id(event.id)
                            .modifier(IslandListRow())
                    }
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .environment(\.defaultMinListRowHeight, 0)
            .onAppear { scrollToNext(proxy) }
        }
        .onHover { IslandGestureGuard.overScrollingContent = $0 }
        .onDisappear { IslandGestureGuard.overScrollingContent = false }
    }

    /// boring.notch's scrollToRelevantEvent: the first timed event not over yet, else the first all-day one.
    private func scrollToNext(_ proxy: ScrollViewProxy) {
        let events = sections.flatMap(\.events)
        let now = Date()
        guard let target = events.first(where: { !$0.isAllDay && $0.end > now }) ?? events.first else { return }
        Task { @MainActor in
            withTransaction(Transaction(animation: nil)) { proxy.scrollTo(target.id, anchor: .top) }
        }
    }
}

private struct IslandListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// One event: a bar in its calendar's color (a tick circle for a reminder), the title and the time.
/// A click opens the event's details in Calendar (a reminder in Reminders).
struct IslandEventRow: View {
    let event: IslandEvent
    let tomorrow: Bool
    private var calendar: IslandCalendar { IslandCalendar.shared }

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            if case .reminder(let done) = event.kind {
                IslandReminderToggle(
                    isOn: Binding(get: { done }, set: { value in Task { await calendar.setCompleted(event, value) } }),
                    color: Color(event.calendar.color)
                )
                .padding(.top, 1)
            } else {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(event.calendar.color))
                    .frame(width: 3, height: 26)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title.isEmpty ? "Untitled" : event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(time)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.65))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .help("Show in \(event.kind.isReminder ? "Reminders" : "Calendar")")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }

    private func open() { event.open() }

    private var time: String {
        if event.isAllDay { return "All-day" }
        if event.kind.isReminder { return event.start.formatted(date: .omitted, time: .shortened) }
        if !tomorrow, event.start <= .now { return "Now – " + event.end.formatted(date: .omitted, time: .shortened) }
        return event.start.formatted(date: .omitted, time: .shortened) + " – " + event.end.formatted(date: .omitted, time: .shortened)
    }
}

/// Until Calendars is allowed: a link that brings up macOS's prompt for Calendars and Reminders
/// (or Privacy settings if access was turned off). The whole widget does the same when clicked.
struct IslandCalendarAccess: View {
    @Environment(\.islandPreview) private var preview
    private var calendar: IslandCalendar { IslandCalendar.shared }

    var body: some View {
        let denied = calendar.eventAccess == .denied || calendar.eventAccess == .restricted
        VStack(alignment: .leading, spacing: 4) {
            Text(denied ? "Calendar access is off." : "See your events and reminders here.")
                .font(.subheadline).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)   // wraps instead of clipping (B-38)
            if denied {
                // An entry for an older build can read as "off" too (B-32): resetting asks again.
                Button("Reset and Ask Again") {
                    guard !preview else { return }
                    Task { await calendar.resetAndAsk() }
                }
                Button("Open Privacy Settings") {
                    guard !preview else { return }
                    Task { await calendar.askOrOpenSettings() }
                }
            } else {
                Button("Allow Calendar Access") {
                    guard !preview else { return }
                    Task { await calendar.askOrOpenSettings() }
                }
            }
        }
        .buttonStyle(IslandLinkButtonStyle())
        .font(.callout)
        .padding(.top, 4)
    }
}

/// A link drawn by SwiftUI (B-32): Apple's `.link` style is an AppKit control that ignores the first
/// click in a window that never becomes key, like the island. Accent-colored, underlined on hover.
struct IslandLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IslandLink(configuration: configuration)
    }
}

private struct IslandLink: View {
    let configuration: ButtonStyleConfiguration
    @Environment(SettingsStore.self) private var appSettings
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(appSettings.accentColor.ensureMinimumBrightness(factor: 0.7))
            .underline(hovering)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .accessibilityAddTraits(.isLink)
    }
}

struct IslandEmptyEventsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title3)
                .foregroundColor(Color(white: 0.65))
            Text("No more events today")
                .font(.subheadline)
                .foregroundColor(.white)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
        }
        .padding(.top, 4)
    }
}

struct IslandReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color

    var body: some View {
        Button(action: {
            isOn.toggle()
        }) {
            ZStack {
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 14, height: 14)
                if isOn {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Circle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(0)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

// MARK: - Closed island

/// An event starting within 10 minutes: its color and title on the left of the notch, the time left
/// on the right (Zephydian's own, in the style of the music live activity).
struct IslandCalendarLiveActivity: View {
    let model: IslandModel
    let event: IslandEvent

    static let sideWidth: CGFloat = 130

    static func width(closed: CGFloat) -> CGFloat { closed + 28 + 2 * sideWidth }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(event.calendar.color)).frame(width: 7, height: 7)
                Text(event.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.leading, 6)
            .frame(width: Self.sideWidth, alignment: .leading)

            Rectangle()
                .fill(.black)
                .frame(width: model.closedSize.width + 8)

            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(timeLeft(at: context.date))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color(event.calendar.color).ensureMinimumBrightness(factor: 0.7))
            }
            .padding(.trailing, 6)
            .frame(width: Self.sideWidth, alignment: .trailing)
        }
        .frame(height: model.effectiveClosedHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(event.title), \(timeLeft(at: Date()))")
    }

    private func timeLeft(at date: Date) -> String {
        let minutes = Int((event.start.timeIntervalSince(date) / 60).rounded(.up))
        return minutes <= 0 ? "Now" : "in \(minutes) min"
    }
}
