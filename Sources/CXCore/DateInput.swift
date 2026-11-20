import Foundation

/// Parses the dates people (and agents) type on the command line.
public enum DateInput {
    /// Accepts `now`, `today`, `yesterday`, `YYYY-MM-DD` and `YYYY-MM-DD HH:MM` (or with `T`).
    /// A value without a time means the start of that day — or, with `endOfDay`, its last second,
    /// so that an end or "until" date covers the whole day.
    public static func parse(_ text: String, endOfDay: Bool = false, now: Date = Date(), calendar: Calendar = .current) throws -> Date {
        let input = text.trimmed.lowercased()
        func wholeDay(_ start: Date) -> Date {
            endOfDay ? calendar.date(byAdding: .day, value: 1, to: start)!.addingTimeInterval(-1) : start
        }
        switch input {
        case "now": return now
        case "today": return wholeDay(calendar.startOfDay(for: now))
        case "yesterday": return wholeDay(calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!)
        default: break
        }

        let parts = input.split(whereSeparator: { $0 == "t" || $0 == " " })
        let dateFields = parts.first?.split(separator: "-").compactMap { Int($0) } ?? []
        let timeFields = parts.count > 1 ? parts[1].split(separator: ":").compactMap { Int($0) } : [0, 0]
        guard parts.count <= 2, dateFields.count == 3, timeFields.count == 2 else {
            throw CXError.invalid("Cannot read the date \"\(text)\". Use YYYY-MM-DD, YYYY-MM-DD HH:MM, today, yesterday or now.")
        }
        var components = DateComponents()
        components.year = dateFields[0]; components.month = dateFields[1]; components.day = dateFields[2]
        components.hour = timeFields[0]; components.minute = timeFields[1]
        guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else {
            throw CXError.invalid("\"\(text)\" is not a valid date.")
        }
        return parts.count == 1 ? wholeDay(date) : date
    }
}
