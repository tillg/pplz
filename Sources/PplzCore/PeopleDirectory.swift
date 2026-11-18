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

    /// A person that exists only in pplz, without a system contact.
    public var isPplzOnly: Bool { contactIdentifier == nil }

    /// Stable identity of the row in a list: the contact, or the pplz ID for a pplz-only person.
    public var key: String { contactIdentifier ?? id?.uuidString ?? name }

    private enum CodingKeys: String, CodingKey {
        case id, contactIdentifier, name, eventCount, lastMet, tags, isPplzOnly
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(contactIdentifier, forKey: .contactIdentifier)
        try container.encode(name, forKey: .name)
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
    public static func merge(contacts: [ContactSummary], persons: [PersonSnapshot]) -> [PersonEntry] {
        var linked: [String: PersonSnapshot] = [:]
        for person in persons {
            if let identifier = person.contactIdentifier, linked[identifier] == nil { linked[identifier] = person }
        }
        var entries: [PersonEntry] = []
        var seen: Set<String> = []
        for contact in contacts {
            let person = linked[contact.identifier]
            seen.insert(contact.identifier)
            entries.append(PersonEntry(id: person?.id, contactIdentifier: contact.identifier, name: contact.name,
                                       eventCount: person?.eventCount ?? 0, lastMet: person?.lastMet, tags: person?.tags ?? []))
        }
        for person in persons where person.contactIdentifier.map({ !seen.contains($0) }) ?? true {
            entries.append(PersonEntry(id: person.id, contactIdentifier: person.contactIdentifier, name: person.name,
                                       eventCount: person.eventCount, lastMet: person.lastMet, tags: person.tags))
        }
        return entries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
    /// or part of the name — in that order.
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

        let partial = entries.filter { $0.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        switch partial.count {
        case 0: return .none
        case 1: return .one(partial[0])
        default: return .ambiguous(partial)
        }
    }
}
