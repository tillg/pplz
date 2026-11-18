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

    /// The relationships the Contacts app offers in its menu, in its order.
    public static let appleRoles = ["mother", "father", "parent", "son", "daughter", "brother", "sister", "child",
                                    "friend", "spouse", "partner", "assistant", "manager", "other"]

    /// Roles Apple has a built-in label for (its menu plus a few it knows but does not list).
    private static let standardRoles = Set(appleRoles + ["sibling", "colleague"])

    /// The role the *other* person has in return, where that is unambiguous.
    /// A manager's counterpart is not necessarily an assistant, so "manager" has none.
    private static let counterpart: [String: String] = [
        "friend": "friend", "spouse": "spouse", "partner": "partner", "colleague": "colleague", "sibling": "sibling",
        "cousin": "cousin", "neighbour": "neighbour", "neighbor": "neighbor", "classmate": "classmate",
        "roommate": "roommate", "flatmate": "flatmate", "teammate": "teammate", "co-founder": "co-founder", "cofounder": "cofounder",
        "mother": "child", "father": "child", "parent": "child",
        "son": "parent", "daughter": "parent", "child": "parent",
        "brother": "sibling", "sister": "sibling",
        "assistant": "manager",
    ]

    /// Apple's own label for a role ("_$!<Mother>!$_"), so Contacts shows and translates it like
    /// one picked from its menu; any other role is used as written.
    static func label(for role: String) -> String {
        standardRoles.contains(role.lowercased()) ? "_$!<\(role.prefix(1).uppercased() + role.dropFirst().lowercased())>!$_" : role
    }

    /// Rows for the connection "`from` is `kind` `to`".
    ///
    /// A related name describes the *other* person from the card owner's point of view:
    /// - "Anna — colleague of — Ben": Ben's card gets `colleague: Anna`, and Anna's card `colleague: Ben`.
    /// - "Anna — mother of — Ben": Ben's card gets `mother: Anna`, and Anna's card `child: Ben`.
    /// - "Anna — manager of — Ben": only Ben's card gets `manager: Anna`.
    /// - "Anna — introduced by — Ben" (no "… of"): Anna's card gets `introduced by: Ben`.
    public static func rows(from: Party, kind: String, to: Party) -> [Row] {
        rows(from: from, kind: kind, to: to, label: label(for:))
    }

    /// The same rows with plain-word labels, as versions before Apple's labels were used wrote them.
    /// Only needed to find and remove such older rows.
    public static func legacyRows(from: Party, kind: String, to: Party) -> [Row] {
        rows(from: from, kind: kind, to: to, label: { $0 })
    }

    private static func rows(from: Party, kind: String, to: Party, label: (String) -> String) -> [Row] {
        let text = kind.trimmed
        func row(on owner: Party, role: String, naming other: Party) -> [Row] {
            owner.contactIdentifier.map { [Row(contactIdentifier: $0, label: label(role), value: other.name)] } ?? []
        }
        guard text.lowercased().hasSuffix(" of") else {
            return row(on: from, role: text, naming: to)
        }
        let role = String(text.dropLast(3)).trimmed
        var rows = row(on: to, role: role, naming: from)
        if let back = counterpart[role.lowercased()] {
            // keep the user's spelling for a symmetric role ("Partner"), use ours for a different one ("child")
            rows += row(on: from, role: back == role.lowercased() ? role : back, naming: to)
        }
        return rows
    }
}

extension ConnectionSnapshot {
    /// How the connection reads on this person's card. A role stored as "Ben — manager of — Anna"
    /// shows on Anna's card as in Contacts: "manager", next to Ben's name.
    public var displayLabel: String {
        let isRole = kind.lowercased().hasSuffix(" of")
        switch (direction, isRole) {
        case (.incoming, true): return String(kind.dropLast(3)).trimmed
        case (.incoming, false): return "\(kind) (from them)"
        case (.outgoing, _): return kind
        }
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
