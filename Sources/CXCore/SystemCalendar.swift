import EventKit
import Foundation

/// An entry of the system calendar, reduced to what cardXchange needs to make an event of it.
public struct CalendarEntry: Equatable, Sendable, Identifiable {
    public var title: String
    public var start: Date
    public var end: Date?
    public var place: String
    public var isAllDay: Bool
    public var id: String { "\(key)|\(end?.timeIntervalSince1970 ?? 0)|\(place)" }
    /// What makes a calendar entry and a cardXchange event "the same meeting": title and start.
    public var key: String { "\(title.trimmed)|\(start.timeIntervalSince1970)" }

    public init(title: String, start: Date, end: Date? = nil, place: String = "", isAllDay: Bool = false) {
        self.title = title
        self.start = start
        self.end = end
        self.place = place
        self.isAllDay = isAllDay
    }

    /// What to offer when asking "which event was this?": entries going on right now first, then
    /// those that already started, latest first. Entries without a title and future ones are left out.
    public static func relevant(_ entries: [CalendarEntry], now: Date = Date(), limit: Int = 6) -> [CalendarEntry] {
        var seen = Set<String>()     // the same meeting in two calendars is offered once
        let started = entries.filter { !$0.title.trimmed.isEmpty && $0.start <= now && seen.insert($0.key).inserted }
        func isCurrent(_ entry: CalendarEntry) -> Bool { (entry.end ?? entry.start) >= now }
        return Array(started.sorted { a, b in
            isCurrent(a) != isCurrent(b) ? isCurrent(a) : a.start > b.start
        }.prefix(limit))
    }
}

/// Read-only access to the system calendar.
public enum SystemCalendar {
    /// Today's and the last days' entries, most relevant first; asks for access on first use.
    public static func recentEntries(now: Date = Date(), days: Int = 3) async throws -> [CalendarEntry] {
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else {
            throw CXError.invalid("cardXchange has no access to your calendar. Allow it in Settings → Privacy & Security → Calendars.")
        }
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
        let predicate = store.predicateForEvents(withStart: from, end: now.addingTimeInterval(60), calendars: nil)
        let entries = store.events(matching: predicate).map {
            CalendarEntry(title: $0.title ?? "", start: $0.startDate, end: $0.endDate, place: $0.location ?? "", isAllDay: $0.isAllDay)
        }
        return CalendarEntry.relevant(entries, now: now)
    }
}
