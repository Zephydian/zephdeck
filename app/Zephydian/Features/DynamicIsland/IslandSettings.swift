import Foundation
import CoreGraphics

/// The Dynamic Island's settings, saved as they change.
@Observable
final class IslandSettings {
    static let shared = IslandSettings()

    /// The island's body: solid black like the notch, or Liquid Glass once it opens (black while closed).
    enum Look: String, CaseIterable, Identifiable {
        case black, glass
        var id: String { rawValue }
        var title: String { self == .black ? "Black" : "Liquid Glass" }
    }

    /// What opens it (Vorssaint's four modes). `hover` is "Expand fully on hover" (its raw value
    /// is kept from before, so saved choices stay).
    enum Opening: String, CaseIterable, Identifiable {
        case click, preview, hover, hidden
        var id: String { rawValue }
        var title: String {
            switch self {
            case .click: "Click to open"
            case .preview: "Preview on hover"
            case .hover: "Expand fully on hover"
            case .hidden: "Hidden until hover"
            }
        }
        var symbol: String {
            switch self {
            case .click: "cursorarrow"
            case .preview: "rectangle.topthird.inset.filled"
            case .hover: "arrow.up.left.and.arrow.down.right"
            case .hidden: "eye.slash"
            }
        }
        /// Resting the pointer on the island does something (the activation time applies).
        var usesHover: Bool { self != .click }
    }

    /// Which display shows the island (Vorssaint's NotchDisplay).
    enum Display: String, CaseIterable, Identifiable {
        case automatic, builtIn, main, pointer, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .automatic: "Automatic"
            case .builtIn: "Built-in display"
            case .main: "Main display"
            case .pointer: "Follow the pointer"
            case .all: "All displays"
            }
        }
        var symbol: String {
            switch self {
            case .automatic: "display.2"
            case .builtIn: "laptopcomputer"
            case .main: "display"
            case .pointer: "cursorarrow.motionlines"
            case .all: "rectangle.on.rectangle"
            }
        }
    }

    /// What the closed island shows when nothing else is going on (Vorssaint's At rest).
    enum Rest: String, CaseIterable, Identifiable {
        case nothing, battery, music
        var id: String { rawValue }
    }

    /// The island appears in screenshots, recordings and screen sharing (Vorssaint's privacy switch).
    var showInCaptures: Bool { didSet { defaults.set(showInCaptures, forKey: "island.showInCaptures") } }

    var restWith: Rest { didSet { defaults.set(restWith.rawValue, forKey: "island.restWith") } }
    /// The closed island's activity may cover the menus beside the notch (Vorssaint's Show over the
    /// menus); off, it gives way when they need the room.
    var coversMenus: Bool { didSet { defaults.set(coversMenus, forKey: "island.coversMenus") } }
    /// Short notices in the closed island (Vorssaint's indicators).
    var noticeCaptures: Bool { didSet { defaults.set(noticeCaptures, forKey: "island.noticeCaptures") } }
    var noticeSong: Bool { didSet { defaults.set(noticeSong, forKey: "island.noticeSong") } }
    var noticeMic: Bool { didSet { defaults.set(noticeMic, forKey: "island.noticeMic") } }
    var noticeClipboard: Bool { didSet { defaults.set(noticeClipboard, forKey: "island.noticeClipboard") } }

    var display: Display { didSet { defaults.set(display.rawValue, forKey: "island.display") } }
    /// Live activities in the closed island hide while a full-screen app is in front (alerts and
    /// recordings still show).
    var hideInFullScreen: Bool { didSet { defaults.set(hideInFullScreen, forKey: "island.hideInFullScreen") } }

    /// Where the island opens when nothing live takes it: "" the last page, "grid" all tabs, or a tab.
    var reopenTo: String { didSet { defaults.set(reopenTo, forKey: "island.reopenTo") } }
    /// A live activity in the closed island (music, a timer…) opens its own page (Vorssaint's switch).
    var opensActivity: Bool { didSet { defaults.set(opensActivity, forKey: "island.opensActivity") } }

    /// On a display without a notch, while nothing is live.
    enum NoNotch: String, CaseIterable, Identifiable {
        case pill, hidden
        var id: String { rawValue }
        var title: String { self == .pill ? "Always a small pill" : "Hidden until something is live" }
    }

    /// How big the open island is (Vorssaint's sizes, in Zephydian's wide shape).
    enum Size: String, CaseIterable, Identifiable {
        case compact, spacious, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .compact: "Compact"
            case .spacious: "Spacious"
            case .custom: "Custom"
            }
        }

        static let widthRange = 520.0...760.0
        static let heightRange = 170.0...280.0
        static let defaultWidth = 640.0
        static let defaultHeight = 190.0

        static func clamped(_ value: Double, to range: ClosedRange<Double>, fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
    }

    var size: Size { didSet { defaults.set(size.rawValue, forKey: "island.size") } }
    var customWidth: Double { didSet { defaults.set(customWidth, forKey: "island.customWidth") } }
    var customHeight: Double { didSet { defaults.set(customHeight, forKey: "island.customHeight") } }

    /// The open island's size for the chosen preset (Spacious is the original 640 × 190).
    var openSize: CGSize {
        switch size {
        case .compact: CGSize(width: 560, height: 170)
        case .spacious: CGSize(width: Size.defaultWidth, height: Size.defaultHeight)
        case .custom: CGSize(width: Size.clamped(customWidth, to: Size.widthRange, fallback: Size.defaultWidth).rounded(),
                             height: Size.clamped(customHeight, to: Size.heightRange, fallback: Size.defaultHeight).rounded())
        }
    }

    /// How the closed island meets the top of a display without a notch (Vorssaint's silhouette):
    /// a capsule floating in the menu bar, or a notch hanging from the top edge.
    enum Silhouette: String, CaseIterable, Identifiable {
        case capsule, notch
        var id: String { rawValue }
    }

    /// Vorssaint's fit ranges (NotchCameraFit, NotchCapsuleFit).
    enum Fit {
        static let cameraWidth = -10.0...10.0
        static let cameraHeight = -6.0...6.0
        static let capsuleWidth = -40.0...40.0
        static let capsuleHeight = -4.0...4.0
        static let capsuleDrop = 0.0...20.0
    }

    /// The open island blurs what's behind it (Black look only; Liquid Glass is see-through already).
    var translucent: Bool { didSet { defaults.set(translucent, forKey: "island.translucent") } }
    /// A thin line in the accent color around the island.
    var outline: Bool { didSet { defaults.set(outline, forKey: "island.outline") } }
    /// Corrections to the notch size macOS reports, so no edge of the real notch shows.
    var cameraFitWidth: Double { didSet { defaults.set(cameraFitWidth, forKey: "island.cameraFitWidth") } }
    var cameraFitHeight: Double { didSet { defaults.set(cameraFitHeight, forKey: "island.cameraFitHeight") } }
    var silhouette: Silhouette { didSet { defaults.set(silhouette.rawValue, forKey: "island.silhouette") } }
    /// The capsule's own size and distance from the top of the screen.
    var capsuleFitWidth: Double { didSet { defaults.set(capsuleFitWidth, forKey: "island.capsuleFitWidth") } }
    var capsuleFitHeight: Double { didSet { defaults.set(capsuleFitHeight, forKey: "island.capsuleFitHeight") } }
    var capsuleFitDrop: Double { didSet { defaults.set(capsuleFitDrop, forKey: "island.capsuleFitDrop") } }

    /// The camera fit in whole points across and half points down (Vorssaint's steps).
    var cameraFit: CGSize {
        CGSize(width: Size.clamped(cameraFitWidth, to: Fit.cameraWidth, fallback: 0).rounded(),
               height: (Size.clamped(cameraFitHeight, to: Fit.cameraHeight, fallback: 0) * 2).rounded() / 2)
    }

    /// The capsule fit: even widths keep it centred, whole points keep its edges on pixels.
    var capsuleFit: (width: CGFloat, height: CGFloat, drop: CGFloat) {
        ((Size.clamped(capsuleFitWidth, to: Fit.capsuleWidth, fallback: 0) / 2).rounded() * 2,
         Size.clamped(capsuleFitHeight, to: Fit.capsuleHeight, fallback: 0).rounded(),
         Size.clamped(capsuleFitDrop, to: Fit.capsuleDrop, fallback: 0).rounded())
    }

    var look: Look { didSet { defaults.set(look.rawValue, forKey: "island.look") } }
    var opening: Opening { didSet { defaults.set(opening.rawValue, forKey: "island.opening") } }
    /// Seconds the pointer rests on the notch before it opens (Hover only).
    var hoverDelay: Double { didSet { defaults.set(hoverDelay, forKey: "island.hoverDelay") } }
    var noNotch: NoNotch { didSet { defaults.set(noNotch.rawValue, forKey: "island.noNotch") } }
    /// Two-finger swipe down opens, up closes.
    var gestures: Bool { didSet { defaults.set(gestures, forKey: "island.gestures") } }
    /// A trackpad tick when the pointer reaches the notch and when a swipe opens or closes it.
    var haptics: Bool { didSet { defaults.set(haptics, forKey: "island.haptics") } }
    /// A shadow under the open island.
    var shadow: Bool { didSet { defaults.set(shadow, forKey: "island.shadow") } }

    /// Follow every player (browsers, videos, podcasts), not only music apps.
    var otherPlayers: Bool { didSet { defaults.set(otherPlayers, forKey: "island.otherPlayers") } }

    /// Battery alerts in the closed island, each on its own.
    var batteryPlugAlert: Bool { didSet { defaults.set(batteryPlugAlert, forKey: "island.batteryPlugAlert") } }
    var batteryLowPowerAlert: Bool { didSet { defaults.set(batteryLowPowerAlert, forKey: "island.batteryLowPowerAlert") } }
    var batteryLowAlert: Bool { didSet { defaults.set(batteryLowAlert, forKey: "island.batteryLowAlert") } }
    var batteryFullAlert: Bool { didSet { defaults.set(batteryFullAlert, forKey: "island.batteryFullAlert") } }
    /// The battery's percentage and icon in the open island's header.
    var batteryInHeader: Bool { didSet { defaults.set(batteryInHeader, forKey: "island.batteryInHeader") } }

    /// Calendars left out of the island (new calendars show by default).
    var calendarHidden: [String] { didSet { defaults.set(calendarHidden, forKey: "island.calendarHidden"); IslandCalendar.shared.settingsChanged() } }
    var calendarHideAllDay: Bool { didSet { defaults.set(calendarHideAllDay, forKey: "island.calendarHideAllDay"); IslandCalendar.shared.settingsChanged() } }
    /// Reminders due that day show with the events (asks for Reminders).
    var calendarReminders: Bool { didSet { defaults.set(calendarReminders, forKey: "island.calendarReminders"); IslandCalendar.shared.settingsChanged() } }
    /// The next event shows in the closed island 10 minutes before it starts.
    var calendarNextEvent: Bool { didSet { defaults.set(calendarNextEvent, forKey: "island.calendarNextEvent"); IslandCalendar.shared.settingsChanged() } }

    /// The buttons beside the open island (none by default).
    var buttons: [IslandButton] { didSet { Self.saveButtons(buttons, defaults) } }

    /// What the Home tab shows, in order (at most three).
    var homeItems: [IslandHomeItem] { didSet { defaults.set(homeItems.map(\.rawValue), forKey: "island.homeItems") } }

    /// Every tab in the island's order (the grid and the editor).
    var tabOrder: [IslandTab] { didSet { defaults.set(tabOrder.map(\.rawValue), forKey: "island.tabOrder") } }
    /// The tabs switched on.
    var shownTabs: Set<IslandTab> { didSet { defaults.set(shownTabs.map(\.rawValue).sorted(), forKey: "island.shownTabs") } }
    /// The tab open last, which the island opens to when nothing is live.
    var lastTab: IslandTab { didSet { defaults.set(lastTab.rawValue, forKey: "island.lastTab") } }

    /// The island has a Shelf: its tab, or Home showing it.
    var showsShelf: Bool {
        shownTabs.contains(.shelf) || (shownTabs.contains(.home) && homeItems.contains(.shelf))
    }

    /// The switched-on tabs, in order.
    var visibleTabs: [IslandTab] { tabOrder.filter { shownTabs.contains($0) } }

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        size = Size(rawValue: defaults.string(forKey: "island.size") ?? "") ?? .spacious
        customWidth = defaults.object(forKey: "island.customWidth") as? Double ?? Size.defaultWidth
        customHeight = defaults.object(forKey: "island.customHeight") as? Double ?? Size.defaultHeight
        showInCaptures = defaults.object(forKey: "island.showInCaptures") as? Bool ?? true
        restWith = Rest(rawValue: defaults.string(forKey: "island.restWith") ?? "") ?? .music
        coversMenus = defaults.object(forKey: "island.coversMenus") as? Bool ?? true
        noticeCaptures = defaults.object(forKey: "island.noticeCaptures") as? Bool ?? true
        noticeSong = defaults.object(forKey: "island.noticeSong") as? Bool ?? true
        noticeMic = defaults.object(forKey: "island.noticeMic") as? Bool ?? true
        noticeClipboard = defaults.object(forKey: "island.noticeClipboard") as? Bool ?? true
        display = Display(rawValue: defaults.string(forKey: "island.display") ?? "") ?? .automatic
        hideInFullScreen = defaults.object(forKey: "island.hideInFullScreen") as? Bool ?? true
        reopenTo = defaults.string(forKey: "island.reopenTo") ?? ""
        opensActivity = defaults.object(forKey: "island.opensActivity") as? Bool ?? true
        translucent = defaults.object(forKey: "island.translucent") as? Bool ?? false
        outline = defaults.object(forKey: "island.outline") as? Bool ?? false
        cameraFitWidth = defaults.double(forKey: "island.cameraFitWidth")
        cameraFitHeight = defaults.double(forKey: "island.cameraFitHeight")
        silhouette = Silhouette(rawValue: defaults.string(forKey: "island.silhouette") ?? "") ?? .capsule
        capsuleFitWidth = defaults.double(forKey: "island.capsuleFitWidth")
        capsuleFitHeight = defaults.double(forKey: "island.capsuleFitHeight")
        capsuleFitDrop = defaults.double(forKey: "island.capsuleFitDrop")
        look = Look(rawValue: defaults.string(forKey: "island.look") ?? "") ?? .black
        opening = Opening(rawValue: defaults.string(forKey: "island.opening") ?? "") ?? .hover
        hoverDelay = defaults.object(forKey: "island.hoverDelay") as? Double ?? 0.3
        noNotch = NoNotch(rawValue: defaults.string(forKey: "island.noNotch") ?? "") ?? .hidden
        gestures = defaults.object(forKey: "island.gestures") as? Bool ?? true
        haptics = defaults.object(forKey: "island.haptics") as? Bool ?? true
        shadow = defaults.object(forKey: "island.shadow") as? Bool ?? true
        otherPlayers = defaults.object(forKey: "island.otherPlayers") as? Bool ?? false
        batteryPlugAlert = defaults.object(forKey: "island.batteryPlugAlert") as? Bool ?? true
        batteryLowPowerAlert = defaults.object(forKey: "island.batteryLowPowerAlert") as? Bool ?? true
        batteryLowAlert = defaults.object(forKey: "island.batteryLowAlert") as? Bool ?? true
        batteryFullAlert = defaults.object(forKey: "island.batteryFullAlert") as? Bool ?? true
        batteryInHeader = defaults.object(forKey: "island.batteryInHeader") as? Bool ?? true
        calendarHidden = defaults.stringArray(forKey: "island.calendarHidden") ?? []
        calendarHideAllDay = defaults.object(forKey: "island.calendarHideAllDay") as? Bool ?? false
        calendarReminders = defaults.object(forKey: "island.calendarReminders") as? Bool ?? true
        calendarNextEvent = defaults.object(forKey: "island.calendarNextEvent") as? Bool ?? true
        buttons = Self.loadButtons(defaults)
        homeItems = defaults.stringArray(forKey: "island.homeItems").map { Array($0.compactMap(IslandHomeItem.init(rawValue:)).prefix(IslandHomeItem.maximum)) }
            ?? IslandHomeItem.defaultItems
        // Saved tabs first, then any tab added since (unknown ones are dropped).
        let saved = (defaults.stringArray(forKey: "island.tabOrder") ?? []).compactMap(IslandTab.init(rawValue:))
        tabOrder = saved + IslandTab.allCases.filter { !saved.contains($0) }
        shownTabs = defaults.stringArray(forKey: "island.shownTabs").map { Set($0.compactMap(IslandTab.init(rawValue:))) }
            ?? IslandTab.defaultShown
        lastTab = IslandTab(rawValue: defaults.string(forKey: "island.lastTab") ?? "") ?? .home
    }
}
