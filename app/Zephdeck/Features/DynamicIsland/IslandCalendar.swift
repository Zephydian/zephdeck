// The island's calendar data. Copied into Zephdeck from boring.notch (github.com/TheBoredTeam/boring.notch,
// GPL-3.0, commit e2654ee), which took the models and the EventKit service from Calendr
// (github.com/pakerwreah/Calendr, MIT, by Paker; modified by Alexander):
// - EventModel (models/EventModel.swift), CalendarModel (models/CalendarModel.swift)
// - CalendarService (Providers/CalendarServiceProviding.swift)
// - CalendarManager (managers/CalendarManager.swift, created by Harsh Vardhan Goswami)
// Zephdeck changes: one @Observable manager; only the fields the island shows; hidden calendars are
// saved (so new calendars show by default); all-day events can be hidden; shows today's rest and
// tomorrow like the iPhone's Up Next widget (the owner's choice over boring.notch's day strip); the next event drives a
// live activity 10 minutes before it starts, woken by a scheduled task (nothing polled); access is
// asked only from a button; models are nonisolated so reminders convert on EventKit's queue.

import AppKit
@preconcurrency import EventKit
import SwiftUI

// MARK: - Models

nonisolated struct IslandCalendarModel: Equatable, Identifiable, Sendable {
    let id: String
    let account: String
    let title: String
    let color: NSColor
    let isReminder: Bool

    init(from calendar: EKCalendar) {
        id = calendar.calendarIdentifier
        switch calendar.source.sourceType {
        case .local, .subscribed, .birthdays: account = "Other"
        default: account = calendar.source.title
        }
        title = calendar.title
        color = calendar.color
        isReminder = calendar.allowedEntityTypes.contains(.reminder)
    }
}

nonisolated enum IslandEventKind: Equatable, Sendable {
    case event(declined: Bool)
    case birthday
    case reminder(completed: Bool)

    var isReminder: Bool { if case .reminder = self { true } else { false } }
}

nonisolated struct IslandEvent: Equatable, Identifiable, Sendable {
    let id: String
    let start: Date
    let end: Date
    let title: String
    let location: String?
    let isAllDay: Bool
    let kind: IslandEventKind
    let calendar: IslandCalendarModel
    let hasRecurrenceRules: Bool
    /// The iCalendar UID, which Calendar's scripting calls an event's `id` (B-30).
    let externalID: String?

    init?(from event: EKEvent) {
        guard let calendar = event.calendar else { return nil }
        id = event.calendarItemIdentifier
        externalID = event.calendarItemExternalIdentifier
        start = event.startDate
        end = event.endDate
        title = event.title ?? ""
        location = event.location
        // A timed event covering whole days reads as all-day.
        let cal = Calendar.current
        isAllDay = event.isAllDay || (event.startDate == cal.startOfDay(for: event.startDate)
            && event.endDate == cal.dateInterval(of: .day, for: event.endDate)?.end)
        let me = event.attendees?.first(where: \.isCurrentUser)
        kind = event.birthdayContactIdentifier != nil ? .birthday : .event(declined: me?.participantStatus == .declined)
        self.calendar = IslandCalendarModel(from: calendar)
        hasRecurrenceRules = event.hasRecurrenceRules || event.isDetached
    }

    init?(from reminder: EKReminder) {
        guard let calendar = reminder.calendar,
              let components = reminder.dueDateComponents,
              let date = Calendar.current.date(from: components) else { return nil }
        id = reminder.calendarItemIdentifier
        externalID = reminder.calendarItemExternalIdentifier
        start = date
        end = Calendar.current.dateInterval(of: .day, for: date)?.end ?? date
        title = reminder.title ?? ""
        location = reminder.location
        isAllDay = components.hour == nil
        kind = .reminder(completed: reminder.isCompleted)
        self.calendar = IslandCalendarModel(from: calendar)
        hasRecurrenceRules = reminder.hasRecurrenceRules
    }

    var hasEnded: Bool { end <= Date() }

    /// Shows the event's details in Calendar (B-30): Calendar is asked through Apple Events to show
    /// it on its day (macOS asks once to let Zephdeck control Calendar), off the main thread; a
    /// reminder, a refusal or a failure falls back to the `ical://` link.
    func open() {
        guard !kind.isReminder, let externalID else { openLink(); return }
        let clean: (String) -> String = { $0.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "\"", with: "") }
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: start)
        let script = """
        tell application "Calendar"
            activate
            set d to current date
            set day of d to 1
            set year of d to \(parts.year ?? 2026)
            set month of d to \(parts.month ?? 1)
            set day of d to \(parts.day ?? 1)
            set time of d to \((parts.hour ?? 0) * 3600 + (parts.minute ?? 0) * 60)
            switch view to day view
            view calendar at d
            show event id "\(clean(externalID))" of calendar id "\(clean(calendar.id))"
        end tell
        """
        let fallback = self
        Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let ok: Bool
            do {
                try process.run()
                process.waitUntilExit()
                ok = process.terminationStatus == 0
            } catch { ok = false }
            if !ok { await MainActor.run { fallback.openLink() } }
        }
    }

    /// Calendr's link (its current format, with the basic ISO date for repeating events).
    func openLink() {
        if let url = appURL() { NSWorkspace.shared.open(url) }
    }

    /// Opens the event in Calendar (or the reminder in Reminders).
    func appURL() -> URL? {
        guard let id = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        if kind.isReminder { return URL(string: "x-apple-reminderkit://remcdreminder/\(id)") }
        var date = ""
        if hasRecurrenceRules {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            if !isAllDay { formatter.timeZone = .init(secondsFromGMT: 0) }
            date = "/" + formatter.string(from: start)
        }
        return URL(string: "ical://ekevent\(date)/\(id)?method=show&options=more")
    }
}

// MARK: - The manager

/// Calendars, the chosen day's events and the next event, while the island is on.
@Observable
final class IslandCalendar {
    static let shared = IslandCalendar()

    private(set) var eventAccess = EKEventStore.authorizationStatus(for: .event)
    private(set) var reminderAccess = EKEventStore.authorizationStatus(for: .reminder)
    private(set) var calendars: [IslandCalendarModel] = []
    /// What's left today (events not over yet, all-day events, reminders not done), sorted.
    private(set) var today: [IslandEvent] = []
    /// Tomorrow's events and reminders, sorted.
    private(set) var tomorrow: [IslandEvent] = []
    /// The day the widget shows (its arrows); today shows Up Next (`today` and `tomorrow`).
    private(set) var day = Calendar.current.startOfDay(for: Date())
    /// Another day's events and reminders, sorted.
    private(set) var dayEvents: [IslandEvent] = []

    var showsToday: Bool { Calendar.current.isDateInToday(day) }

    /// The arrows: a day back or ahead (and back to today when the island opens).
    func show(dayOffset: Int) async {
        let cal = Calendar.current
        day = dayOffset == 0 ? cal.startOfDay(for: Date()) : cal.date(byAdding: .day, value: dayOffset, to: day) ?? day
        await loadEvents()
    }

    /// The permission prompt, or Privacy settings if access was turned off before.
    func askOrOpenSettings() async {
        if eventAccess == .denied || eventAccess == .restricted {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
        } else {
            await requestAccess()
        }
    }
    /// An event starting within 10 minutes: the closed island shows it.
    private(set) var upcoming: IslandEvent?

    var hasAccess: Bool { eventAccess == .fullAccess }

    static let leadTime: TimeInterval = 10 * 60

    @ObservationIgnored private var store = EKEventStore()
    /// Already cleared macOS's stale entries this run (B-32), so a refusal is never repeated.
    @ObservationIgnored private var repaired = false
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var running = false
    @ObservationIgnored private let settings = IslandSettings.shared

    func start() {
        guard !running else { return }
        running = true
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = Task { await self?.reload() } }
        }
        Task { await reload() }
    }

    func stop() {
        running = false
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        wakeTask?.cancel()
        upcoming = nil
    }

    /// Asks for Calendars, then Reminders (from the tab's button). An unsigned Zephdeck gets a new
    /// signature with every build, and macOS then refuses at once, without a prompt, because of its
    /// entry for the old one (B-32): that instant refusal clears Zephdeck's own entries (`tccutil`,
    /// as Settings → Permissions → Repair does) and asks again. A refusal in the prompt itself is kept.
    func requestAccess() async {
        if await !ask(.event), !repaired {
            repaired = true
            await Self.resetPermissions(["Calendar", "Reminders"])
            store = EKEventStore()
            _ = await ask(.event)
        }
        if settings.calendarReminders, EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            if await !ask(.reminder), !repaired {
                repaired = true
                await Self.resetPermissions(["Reminders"])
                store = EKEventStore()
                _ = await ask(.reminder)
            }
        }
        eventAccess = EKEventStore.authorizationStatus(for: .event)
        reminderAccess = EKEventStore.authorizationStatus(for: .reminder)
        Permissions.shared.refresh()
        await reload()
    }

    /// Clears Zephdeck's entries and asks again (the access-off link).
    func resetAndAsk() async {
        repaired = true
        await Self.resetPermissions(["Calendar", "Reminders"])
        store = EKEventStore()
        _ = await ask(.event)
        if settings.calendarReminders { _ = await ask(.reminder) }
        eventAccess = EKEventStore.authorizationStatus(for: .event)
        reminderAccess = EKEventStore.authorizationStatus(for: .reminder)
        Permissions.shared.refresh()
        await reload()
    }

    /// True when granted, or when the person answered a real prompt (so it isn't asked twice);
    /// false when macOS refused instantly, without showing one.
    private func ask(_ type: EKEntityType) async -> Bool {
        let started = Date()
        let granted = (try? await (type == .event ? store.requestFullAccessToEvents() : store.requestFullAccessToReminders())) ?? false
        return granted || Date().timeIntervalSince(started) > 0.8
    }

    private nonisolated static func resetPermissions(_ services: [String]) async {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.zephydian.zephdeck"
        await Task.detached {
            for service in services {
                let process = Process()
                process.executableURL = URL(filePath: "/usr/bin/tccutil")
                process.arguments = ["reset", service, bundleID]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
            }
        }.value
    }

    func reload() async {
        eventAccess = EKEventStore.authorizationStatus(for: .event)
        reminderAccess = EKEventStore.authorizationStatus(for: .reminder)
        var all: [EKCalendar] = []
        if eventAccess == .fullAccess { all += store.calendars(for: .event) }
        if reminderAccess == .fullAccess, settings.calendarReminders { all += store.calendars(for: .reminder) }
        calendars = all.map(IslandCalendarModel.init(from:))
        await loadEvents()
        await planUpcoming()
    }

    func setCompleted(_ event: IslandEvent, _ completed: Bool) async {
        guard let reminder = store.calendarItem(withIdentifier: event.id) as? EKReminder else { return }
        reminder.isCompleted = completed
        try? store.save(reminder, commit: true)
        await loadEvents()
    }

    // MARK: Loading

    private var shownCalendars: [EKCalendar] {
        let hidden = Set(settings.calendarHidden)
        var list: [EKCalendar] = []
        if eventAccess == .fullAccess { list += store.calendars(for: .event) }
        if reminderAccess == .fullAccess, settings.calendarReminders { list += store.calendars(for: .reminder) }
        return list.filter { !hidden.contains($0.calendarIdentifier) }
    }

    /// Today's rest and tomorrow, like the iPhone's Up Next widget.
    private func loadEvents() async {
        guard hasAccess else { today = []; tomorrow = []; dayEvents = []; return }
        let cal = Calendar.current
        let now = Date()
        if !cal.isDateInToday(day) {
            let end = cal.date(byAdding: .day, value: 1, to: day) ?? day
            var list = fetchEvents(from: day, to: end) + (await fetchReminders(from: day, to: end))
            if settings.calendarHideAllDay { list.removeAll { $0.isAllDay && !$0.kind.isReminder } }
            list.removeAll {
                if case .reminder(true) = $0.kind { return true }
                return $0.kind == .event(declined: true)
            }
            dayEvents = list.sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
            return
        }
        let startOfToday = cal.startOfDay(for: now)
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        let endOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfTomorrow) ?? startOfTomorrow
        var list = fetchEvents(from: startOfToday, to: endOfTomorrow)
        list += await fetchReminders(from: startOfToday, to: endOfTomorrow)
        if settings.calendarHideAllDay { list.removeAll { $0.isAllDay && !$0.kind.isReminder } }
        // Completed reminders are left out (boring.notch's default), as are declined events.
        list.removeAll {
            if case .reminder(true) = $0.kind { return true }
            return $0.kind == .event(declined: true)
        }
        list.sort { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
        // Today: what isn't over yet (an all-day event or a reminder stays for the whole day).
        today = list.filter { $0.start < startOfTomorrow && ($0.isAllDay || $0.kind.isReminder || $0.end > now) }
        tomorrow = list.filter { $0.start >= startOfTomorrow }
    }

    private func fetchEvents(from start: Date, to end: Date) -> [IslandEvent] {
        let calendars = shownCalendars.filter { $0.allowedEntityTypes.contains(.event) }
        guard eventAccess == .fullAccess, !calendars.isEmpty else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).compactMap(IslandEvent.init(from:))
    }

    private func fetchReminders(from start: Date, to end: Date) async -> [IslandEvent] {
        let calendars = shownCalendars.filter { $0.allowedEntityTypes.contains(.reminder) }
        guard reminderAccess == .fullAccess, settings.calendarReminders, !calendars.isEmpty else { return [] }
        let predicate = store.predicateForReminders(in: calendars)
        return await withCheckedContinuation { continuation in
            // EventKit answers on its own queue (B-29): the callback must not be main-actor isolated,
            // or Swift's runtime check stops the app there.
            store.fetchReminders(matching: predicate) { @Sendable reminders in
                continuation.resume(returning: Self.dueEvents(reminders, from: start, to: end))
            }
        }
    }

    /// Reminders due in the range, as events. Runs on EventKit's queue.
    private nonisolated static func dueEvents(_ reminders: [EKReminder]?, from start: Date, to end: Date) -> [IslandEvent] {
        (reminders ?? []).compactMap(IslandEvent.init(from:)).filter { $0.start >= start && $0.start < end }
    }

    // MARK: The next event

    /// Finds the next timed event (not declined) and wakes at the right moments: 10 minutes before it
    /// (it shows) and when it starts (it goes away and the next one is planned).
    private func planUpcoming() async {
        wakeTask?.cancel()
        guard running, hasAccess, settings.calendarNextEvent else {
            if upcoming != nil { withAnimation(.smooth) { upcoming = nil } }
            return
        }
        let now = Date()
        let calendars = shownCalendars.filter { $0.allowedEntityTypes.contains(.event) }
        let next: IslandEvent? = calendars.isEmpty ? nil : store
            .events(matching: store.predicateForEvents(withStart: now, end: now.addingTimeInterval(36 * 3600), calendars: calendars))
            .compactMap(IslandEvent.init(from:))
            .filter { !$0.isAllDay && $0.start > now && $0.kind != .event(declined: true) }
            .min { $0.start < $1.start }
        let showing = next.map { $0.start.timeIntervalSince(now) <= Self.leadTime } ?? false
        let shown = showing ? next : nil
        if shown != upcoming { withAnimation(.smooth) { upcoming = shown } }
        guard let next else { return }
        let wake = showing ? next.start : next.start.addingTimeInterval(-Self.leadTime)
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, wake.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            await self?.planUpcoming()
        }
    }

    /// Settings changed (calendars, all-day, reminders, the next event).
    func settingsChanged() {
        Task { await reload() }
    }
}
