import Foundation

/// One row in the people list: a contact, a pplz person, or both.
public struct PersonEntry: Encodable, Equatable, Sendable {
    /// pplz ID; `nil` for a contact pplz has stored nothing about yet.
    public var id: UUID?
    public var contactIdentifier: String?
    public var name: String
    public var eventCount: Int
    public var lastMet: Date?
    public var tags: [String]
    /// The contact's nickname; people can be found by it, as in Contacts.
    public var nickname: String = ""
    /// The contact's company and place, for telling people of the same name apart: "Firm · City · Country".
    public var context: String = ""
    /// The contact's postal addresses, for the map. Not part of the JSON output.
    public var addresses: [PostalAddress] = []

    /// Someone typed in by name who is neither a contact nor a person in pplz yet.
    public static func new(named name: String) -> PersonEntry {
        PersonEntry(id: nil, contactIdentifier: nil, name: name, eventCount: 0, lastMet: nil, tags: [])
    }

    /// A person that exists only in pplz, without a system contact.
    public var isPplzOnly: Bool { contactIdentifier == nil }

    /// Stable identity of the row in a list: the contact, or the pplz ID for a pplz-only person.
    public var key: String { contactIdentifier ?? id?.uuidString ?? name }

    private enum CodingKeys: String, CodingKey {
        case id, contactIdentifier, name, nickname, eventCount, lastMet, tags, isPplzOnly
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(contactIdentifier, forKey: .contactIdentifier)
        try container.encode(name, forKey: .name)
        if !nickname.isEmpty { try container.encode(nickname, forKey: .nickname) }
        try container.encode(eventCount, forKey: .eventCount)
        try container.encodeIfPresent(lastMet, forKey: .lastMet)
        try container.encode(tags, forKey: .tags)
        try container.encode(isPplzOnly, forKey: .isPplzOnly)
    }
}

/// Who takes part in an event: persons pplz already knows, plus people to create with the event.
public struct ParticipantPlan: Equatable, Sendable {
    public var existing: [UUID] = []
    public var additional: [NewParticipant] = []
}

public enum PersonMatch: Equatable, Sendable {
    case none
    case one(PersonEntry)
    case ambiguous([PersonEntry])
}

/// The people list is built at read time from the address book and the pplz store;
/// contacts are never imported (SPEC §3.1).
public enum PeopleDirectory {
    /// A person belongs to the contact whose `pplz` link names them; failing that, to the contact
    /// with the identifier stored for them. The link comes first because contact identifiers differ
    /// from device to device, while the link travels with the contact (SPEC R3).
    public static func merge(contacts: [ContactSummary], persons: [PersonSnapshot]) -> [PersonEntry] {
        let byID = Dictionary(persons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var byIdentifier: [String: PersonSnapshot] = [:]
        for person in persons {
            if let identifier = person.contactIdentifier, byIdentifier[identifier] == nil { byIdentifier[identifier] = person }
        }
        // links first, so that a person claimed through a link is not also matched by a stale identifier
        var claimed: Set<UUID> = []
        var matches: [String: PersonSnapshot] = [:]
        for contact in contacts {
            if let id = contact.pplzPersonID, let person = byID[id], claimed.insert(id).inserted { matches[contact.identifier] = person }
        }
        for contact in contacts where matches[contact.identifier] == nil {
            if let person = byIdentifier[contact.identifier], claimed.insert(person.id).inserted { matches[contact.identifier] = person }
        }

        var entries = contacts.map { contact in
            let person = matches[contact.identifier]
            return PersonEntry(id: person?.id, contactIdentifier: contact.identifier, name: contact.name,
                               eventCount: person?.eventCount ?? 0, lastMet: person?.lastMet, tags: person?.tags ?? [],
                               nickname: contact.nickname,
                               context: [contact.organization, contact.city, contact.country].filter { !$0.isEmpty }.joined(separator: " · "),
                               addresses: contact.addresses)
        }
        for person in persons where !claimed.contains(person.id) {
            entries.append(PersonEntry(id: person.id, contactIdentifier: person.contactIdentifier, name: person.name,
                                       eventCount: person.eventCount, lastMet: person.lastMet, tags: person.tags))
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Whom to offer while the user types a name, e.g. in the quick log. Without text: the people met
    /// most recently. With text: names or nicknames with a word that starts with it come first, then
    /// those that merely contain it; within each group people already met first (latest first), then by name.
    public static func suggestions(for query: String, in entries: [PersonEntry], excluding: Set<String> = [], limit: Int = 5) -> [PersonEntry] {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let query = query.trimmed
        let candidates = entries.filter { !excluding.contains($0.key) }
        func byRecency(_ a: PersonEntry, _ b: PersonEntry) -> Bool {
            if a.lastMet != b.lastMet { return (a.lastMet ?? .distantPast) > (b.lastMet ?? .distantPast) }
            return a.name.compare(b.name, options: options) == .orderedAscending
        }
        guard !query.isEmpty else { return Array(candidates.filter { $0.lastMet != nil }.sorted(by: byRecency).prefix(limit)) }
        func rank(_ entry: PersonEntry) -> Int? {
            let words = (entry.name + " " + entry.nickname).split(whereSeparator: \.isWhitespace)
            if words.contains(where: { $0.range(of: query, options: options.union(.anchored)) != nil }) { return 0 }
            let whole = entry.name.range(of: query, options: options) ?? entry.nickname.range(of: query, options: options)
            return whole == nil ? nil : 1
        }
        return Array(candidates.compactMap { entry in rank(entry).map { (rank: $0, entry: entry) } }
            .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : byRecency($0.entry, $1.entry) }
            .prefix(limit).map(\.entry))
    }

    /// The name under which the typed text can become a new person, or `nil` if someone of exactly
    /// that name exists or is chosen already (case and accents ignored), or if it is too short to be a name.
    public static func newPersonName(for query: String, in entries: [PersonEntry], chosen: [String]) -> String? {
        let name = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard name.count >= 2 else { return nil }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let taken = (entries.map(\.name) + chosen).contains { $0.compare(name, options: options) == .orderedSame }
        return taken ? nil : name
    }

    /// A name as it stands on a profile, without academic titles in front ("Dr.", "Prof. Dr.-Ing.",
    /// "Dr. h.c.") and without degrees after a comma ("…, MBA"). Careful on purpose: "Phil Collins"
    /// and "C. S. Lewis" are names, so a word only counts as a title if it is written like one.
    public static func nameWithoutTitles(_ name: String) -> String {
        let dotted: Set<String> = ["dr", "prof", "dipl", "ing", "mag", "med", "rer", "nat", "phil", "jur", "habil"]
        func isTitle(_ word: Substring) -> Bool {
            let lower = word.lowercased()
            if lower == "dr" || lower == "prof" { return true }        // the two that are written without a full stop
            guard lower.contains(".") else { return false }
            let parts = lower.split(whereSeparator: { $0 == "." || $0 == "-" }).map(String.init)
            if parts == ["h", "c"] { return true }
            return !parts.isEmpty && parts.allSatisfy(dotted.contains)
        }
        func isDegree(_ word: Substring) -> Bool {
            let letters = word.filter(\.isLetter)
            return !letters.isEmpty && letters.count <= 5 && letters.first!.isUppercase && letters.filter(\.isUppercase).count * 2 >= letters.count
                && (word.contains(".") || letters.allSatisfy(\.isUppercase) || letters == "PhD")
        }
        var text = name[...]
        let parts = name.split(separator: ",")
        if parts.count > 1, parts.dropFirst().allSatisfy({ part in
            let words = part.split(whereSeparator: \.isWhitespace)
            return !words.isEmpty && words.allSatisfy(isDegree)
        }) {
            text = parts[0]
        }
        return text.split(whereSeparator: \.isWhitespace).drop(while: isTitle).joined(separator: " ")
    }

    /// Who a captured name could be: people of exactly that name first, then those sharing the family
    /// name. Titles, case and accents are ignored ("ß" counts as "ss"). Only proposals — the user chooses.
    public static func candidates(forCapturedName name: String, in entries: [PersonEntry], limit: Int = 5) -> [PersonEntry] {
        func fold(_ text: String) -> [String] {
            nameWithoutTitles(text).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .lowercased().replacingOccurrences(of: "ß", with: "ss").split(whereSeparator: \.isWhitespace).map(String.init)
        }
        let wanted = fold(name)
        guard let family = wanted.last else { return [] }
        let ranked: [(rank: Int, entry: PersonEntry)] = entries.compactMap { entry in
            let words = fold(entry.name)
            if words == wanted { return (0, entry) }
            return words.last == family && wanted.count > 1 ? (1, entry) : nil
        }
        return Array(ranked.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.entry.name < $1.entry.name }.prefix(limit).map(\.entry))
    }

    /// People a LinkedIn profile ID may belong to, when no name is known: those whose whole name is
    /// in the ID ("anna-london-99"), then those whose family name is ("jdlondon"). Family names
    /// shorter than four letters propose nothing — they are part of too many IDs.
    public static func candidates(forLinkedInID id: String, in entries: [PersonEntry], limit: Int = 5) -> [PersonEntry] {
        func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased() }
        let id = fold(id)
        let ranked: [(rank: Int, entry: PersonEntry)] = entries.compactMap { entry in
            let words = fold(nameWithoutTitles(entry.name)).split(whereSeparator: \.isWhitespace).map(String.init)
            guard let family = words.last, family.count >= 4, id.contains(family) else { return nil }
            return (words.allSatisfy { id.contains($0) } ? 0 : 1, entry)
        }
        return Array(ranked.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.entry.name < $1.entry.name }.prefix(limit).map(\.entry))
    }

    /// A person that belongs to a contact of this device but is stored with another device's identifier.
    public struct Adoption: Equatable, Sendable {
        public var person: UUID
        public var contactIdentifier: String
    }

    /// The persons whose stored contact identifier is not the one of the contact they were matched to.
    public static func adoptions(in entries: [PersonEntry], persons: [PersonSnapshot]) -> [Adoption] {
        let stored = Dictionary(persons.map { ($0.id, $0.contactIdentifier) }, uniquingKeysWith: { first, _ in first })
        return entries.compactMap { entry in
            guard let id = entry.id, let identifier = entry.contactIdentifier, let known = stored[id], known != nil, known != identifier
            else { return nil }
            return Adoption(person: id, contactIdentifier: identifier)
        }
    }

    /// Turns the names given for an event into participants, without writing anything.
    /// Repeated names count once. An ambiguous name always fails; an unknown name fails unless `createMissing`.
    public static func participants(_ names: [String], in entries: [PersonEntry], createMissing: Bool) throws -> ParticipantPlan {
        var plan = ParticipantPlan()
        var newNames: Set<String> = []
        for name in names {
            switch resolve(name, in: entries) {
            case .one(let entry):
                if let id = entry.id {
                    if !plan.existing.contains(id) { plan.existing.append(id) }
                } else if let identifier = entry.contactIdentifier {
                    let participant = NewParticipant.contact(ContactSummary(identifier: identifier, name: entry.name))
                    if !plan.additional.contains(participant) { plan.additional.append(participant) }
                }
            case .ambiguous(let candidates):
                throw PplzError.ambiguousPerson(name, candidates)
            case .none:
                guard createMissing, !name.trimmed.isEmpty else {
                    throw PplzError.notFound("a person matching \"\(name)\"")
                }
                if newNames.insert(name.trimmed.lowercased()).inserted { plan.additional.append(.named(name.trimmed)) }
            }
        }
        return plan
    }

    /// Finds a person by pplz ID (or a unique prefix of it), contact identifier, exact name,
    /// exact nickname, or part of the name or nickname — in that order.
    public static func resolve(_ query: String, in entries: [PersonEntry]) -> PersonMatch {
        let q = query.trimmed
        guard !q.isEmpty else { return .none }

        if let id = UUID(uuidString: q), let hit = entries.first(where: { $0.id == id }) { return .one(hit) }
        if let hit = entries.first(where: { $0.contactIdentifier == q }) { return .one(hit) }
        if q.count >= 4, q.allSatisfy({ $0.isHexDigit || $0 == "-" }) {
            let byPrefix = entries.filter { $0.id?.uuidString.lowercased().hasPrefix(q.lowercased()) ?? false }
            if byPrefix.count == 1 { return .one(byPrefix[0]) }
        }

        let exact = entries.filter { $0.name.compare(q, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
        if exact.count == 1 { return .one(exact[0]) }
        if exact.count > 1 { return .ambiguous(exact) }

        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let byNickname = entries.filter { $0.nickname.compare(q, options: options) == .orderedSame }
        if byNickname.count == 1 { return .one(byNickname[0]) }
        if byNickname.count > 1 { return .ambiguous(byNickname) }

        let partial = entries.filter { $0.name.range(of: q, options: options) != nil || $0.nickname.range(of: q, options: options) != nil }
        switch partial.count {
        case 0: return .none
        case 1: return .one(partial[0])
        default: return .ambiguous(partial)
        }
    }
}
