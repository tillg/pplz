import Foundation

/// Decides what pplz writes into contacts for a connection (SPEC §3.2): "related name" rows,
/// the same field that holds e.g. "spouse".
public enum ContactMirror {
    public struct Party: Equatable, Sendable {
        public var name: String
        /// `nil` for a pplz-only person, who has no card to write to.
        public var contactIdentifier: String?

        public init(name: String, contactIdentifier: String?) {
            self.name = name
            self.contactIdentifier = contactIdentifier
        }
    }

    /// One related-name row on one contact card.
    public struct Row: Codable, Equatable, Hashable, Sendable {
        public var contactIdentifier: String
        public var label: String
        public var value: String

        public init(contactIdentifier: String, label: String, value: String) {
            self.contactIdentifier = contactIdentifier
            self.label = label
            self.value = value
        }
    }

    /// Kinds that hold in both directions and therefore appear on both cards.
    static let symmetric: Set<String> = [
        "colleague", "partner", "friend", "spouse", "sibling", "cousin", "neighbour", "neighbor",
        "classmate", "roommate", "flatmate", "teammate", "co-founder", "cofounder",
    ]

    /// Rows for the connection "`from` is `kind` `to`".
    ///
    /// A related name describes the *other* person from the card owner's point of view:
    /// - "Anna — colleague of — Ben": Ben's card gets `colleague: Anna`; symmetric, so Anna's card gets `colleague: Ben` too.
    /// - "Anna — mother of — Ben": only Ben's card gets `mother: Anna`.
    /// - "Anna — introduced by — Ben" (no "… of"): Anna's card gets `introduced by: Ben`.
    public static func rows(from: Party, kind: String, to: Party) -> [Row] {
        let text = kind.trimmed
        func row(on owner: Party, label: String, naming other: Party) -> [Row] {
            owner.contactIdentifier.map { [Row(contactIdentifier: $0, label: label, value: other.name)] } ?? []
        }
        guard text.lowercased().hasSuffix(" of") else {
            return row(on: from, label: text, naming: to)
        }
        let role = String(text.dropLast(3)).trimmed
        var rows = row(on: to, label: role, naming: from)
        if symmetric.contains(role.lowercased()) { rows += row(on: from, label: role, naming: to) }
        return rows
    }
}

/// Append-only record of everything pplz wrote into the address book, so that each change can be
/// traced and so that pplz only ever removes rows it added itself.
public struct ContactJournal: Sendable {
    public enum Action: String, Codable, Sendable { case added, removed }

    public struct Entry: Codable, Equatable, Sendable {
        public var date: Date
        public var action: Action
        public var field: String
        public var row: ContactMirror.Row
    }

    public let url: URL

    public init(url: URL) { self.url = url }

    public func record(_ action: Action, _ row: ContactMirror.Row, field: String = "related name", at date: Date = Date()) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var line = try encoder.encode(Entry(date: date, action: action, field: field, row: row))
        line.append(0x0A)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try line.write(to: url)
        } else {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        }
    }

    public func entries() throws -> [Entry] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try String(contentsOf: url, encoding: .utf8).split(whereSeparator: \.isNewline)
            .map { try decoder.decode(Entry.self, from: Data($0.utf8)) }
    }

    /// Whether the row is currently in the address book because pplz put it there.
    public func pplzAdded(_ row: ContactMirror.Row, field: String = "related name") throws -> Bool {
        try entries().last { $0.row == row && $0.field == field }?.action == .added
    }
}
