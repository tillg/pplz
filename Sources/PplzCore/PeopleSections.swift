import Foundation

/// The people list as the Contacts app shows it: alphabetical sections, filtered by a search text.
public enum PeopleSections {
    public struct Section: Equatable, Identifiable, Sendable {
        public var title: String
        public var entries: [PersonEntry]
        public var id: String { title }
    }

    /// `search` matches names, nicknames and tags, ignoring case and accents. The list and the map both use it.
    public static func matching(_ entries: [PersonEntry], search: String) -> [PersonEntry] {
        let query = search.trimmed
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return query.isEmpty ? entries : entries.filter { entry in
            entry.name.range(of: query, options: options) != nil
                || entry.nickname.range(of: query, options: options) != nil
                || entry.tags.contains { $0.range(of: query, options: options) != nil }
        }
    }

    /// Sections A–Z by first letter (accents ignored), everything else under "#" at the end.
    public static func make(_ entries: [PersonEntry], search: String = "") -> [Section] {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let matching = matching(entries, search: search)
        var groups: [String: [PersonEntry]] = [:]
        for entry in matching { groups[title(for: entry.name), default: []].append(entry) }
        return groups.keys
            .sorted { a, b in a == "#" ? false : (b == "#" ? true : a < b) }
            .map { title in
                Section(title: title, entries: groups[title]!.sorted { $0.name.compare($1.name, options: options) == .orderedAscending })
            }
    }

    static func title(for name: String) -> String {
        let folded = name.trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).uppercased()
        guard let first = folded.first, first.isLetter, first.isASCII else { return "#" }
        return String(first)
    }

    /// Up to two initials for the avatar: first and last word of the name.
    public static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        guard let first = words.first?.first else { return "" }
        let last = words.count > 1 ? words.last?.first.map(String.init) ?? "" : ""
        return (String(first) + last).uppercased()
    }
}
