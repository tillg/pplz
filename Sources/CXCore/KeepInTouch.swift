import Foundation

public struct OverduePerson: Codable, Equatable, Sendable {
    public var person: PersonRef
    public var intervalDays: Int
    public var lastMet: Date?
    /// `nil` if there is no event with this person yet.
    public var daysSinceLastMet: Int?
    public var daysOverdue: Int?
}

/// The keep-in-touch rhythm: how often I want to meet someone, and who is overdue.
public enum KeepInTouch {
    /// Reads an interval: a number of days, or a number followed by d, w, m (30 days) or y (365 days).
    public static func days(_ text: String) throws -> Int {
        let input = text.trimmed.lowercased()
        let factors: [Character: Int] = ["d": 1, "w": 7, "m": 30, "y": 365]
        var number = input
        var factor = 1
        if let unit = input.last, let f = factors[unit] {
            factor = f
            number = String(input.dropLast())
        }
        guard let value = Int(number), value > 0 else {
            throw CXError.invalid("Cannot read the interval \"\(text)\". Use days (90) or a number with d, w, m or y (2w, 3m, 1y).")
        }
        return value * factor
    }

    /// People whose last meeting is longer ago than their rhythm allows.
    /// Never-met people come first, then the most overdue.
    public static func overdue(_ persons: [PersonSnapshot], now: Date = Date()) -> [OverduePerson] {
        persons.compactMap { person -> OverduePerson? in
            guard let interval = person.keepInTouchDays else { return nil }
            let ref = PersonRef(id: person.id, name: person.name)
            guard let lastMet = person.lastMet else {
                return OverduePerson(person: ref, intervalDays: interval, lastMet: nil, daysSinceLastMet: nil, daysOverdue: nil)
            }
            let since = Int(now.timeIntervalSince(lastMet) / 86_400)
            guard since > interval else { return nil }
            return OverduePerson(person: ref, intervalDays: interval, lastMet: lastMet, daysSinceLastMet: since, daysOverdue: since - interval)
        }
        .sorted { a, b in
            switch (a.daysOverdue, b.daysOverdue) {
            case (nil, nil): a.person.name.localizedCaseInsensitiveCompare(b.person.name) == .orderedAscending
            case (nil, _): true
            case (_, nil): false
            case let (x?, y?): x > y
            }
        }
    }
}
