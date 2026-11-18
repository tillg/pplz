import Foundation
import SwiftData

/// The pplz database. App and CLI open the same store file (SPEC §8.3);
/// CloudKit sync is the app's job, so this type never talks to CloudKit.
public final class PplzStore {
    private let context: ModelContext

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config = ModelConfiguration(url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Person.self, Event.self, Tag.self, FollowUp.self, Connection.self, configurations: config)
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    /// `PPLZ_STORE` if set, otherwise `~/Library/Application Support/pplz/pplz.store`.
    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let path = environment["PPLZ_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return URL.applicationSupportDirectory.appendingPathComponent("pplz/pplz.store")
    }

    // MARK: Persons

    @discardableResult
    public func createPerson(name: String) throws -> UUID {
        let person = Person(name: try nonEmpty(name, "A person needs a name."))
        context.insert(person)
        try context.save()
        return person.uuid
    }

    /// Returns the person linked to this contact, creating it on first use.
    @discardableResult
    public func ensurePerson(for contact: ContactSummary) throws -> UUID {
        let identifier = contact.identifier
        let existing = try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.localContactIdentifier == identifier }))
        if let person = existing.min(by: { $0.createdAt < $1.createdAt }) {
            if person.name != contact.name, !contact.name.isEmpty {
                person.name = contact.name
                try context.save()
            }
            return person.uuid
        }
        let person = Person(name: contact.name, localContactIdentifier: identifier)
        context.insert(person)
        try context.save()
        return person.uuid
    }

    public func persons() throws -> [PersonSnapshot] {
        try context.fetch(FetchDescriptor<Person>()).map(snapshot).sorted(by: byName)
    }

    public func person(_ id: UUID) throws -> PersonSnapshot {
        snapshot(try fetchPerson(id))
    }

    public func setNotes(_ notes: String, for id: UUID) throws {
        try fetchPerson(id).notes = notes
        try context.save()
    }

    public func setHowWeMet(_ text: String, for id: UUID) throws {
        try fetchPerson(id).howWeMet = text
        try context.save()
    }

    /// Sets the desired number of days between meetings; `nil` removes the rhythm.
    public func setKeepInTouch(days: Int?, for id: UUID) throws {
        if let days, days < 1 { throw PplzError.invalid("A keep-in-touch rhythm needs at least 1 day.") }
        try fetchPerson(id).keepInTouchDays = days
        try context.save()
    }

    // MARK: Connections

    /// Records "`from` is `kind` `to`", e.g. "colleague of". Storing the same connection twice has no effect.
    public func connect(_ from: UUID, to: UUID, kind: String) throws {
        try atomically {
            guard from != to else { throw PplzError.invalid("A person cannot be connected to themselves.") }
            let label = try nonEmpty(kind, "A connection needs a kind, e.g. \"colleague of\".")
            let a = try fetchPerson(from)
            let b = try fetchPerson(to)
            let exists = (a.outgoingConnections ?? []).contains {
                $0.to?.uuid == to && $0.kind.caseInsensitiveCompare(label) == .orderedSame
            }
            if !exists {
                let connection = Connection(kind: label)
                context.insert(connection)
                connection.from = a
                connection.to = b
            }
        }
    }

    /// Removes every connection between the two people, in both directions.
    public func disconnect(_ a: UUID, _ b: UUID) throws {
        try atomically {
            let first = try fetchPerson(a)
            _ = try fetchPerson(b)
            let between = (first.outgoingConnections ?? []).filter { $0.to?.uuid == b }
                + (first.incomingConnections ?? []).filter { $0.from?.uuid == b }
            between.forEach(context.delete)
        }
    }

    /// Every connection in the store, oldest first.
    public func allConnections() throws -> [ConnectionRecord] {
        try context.fetch(FetchDescriptor<Connection>(sortBy: [SortDescriptor(\.createdAt)])).compactMap { connection in
            guard let from = connection.from, let to = connection.to else { return nil }
            return ConnectionRecord(id: connection.uuid, kind: connection.kind, from: snapshot(from), to: snapshot(to))
        }
    }

    /// Outgoing first, then incoming; each group oldest first.
    public func connections(of id: UUID) throws -> [ConnectionSnapshot] {
        let person = try fetchPerson(id)
        func snapshots(_ list: [Connection]?, _ direction: ConnectionSnapshot.Direction, _ other: (Connection) -> Person?) -> [ConnectionSnapshot] {
            (list ?? []).sorted { $0.createdAt < $1.createdAt }.compactMap { connection in
                other(connection).map {
                    ConnectionSnapshot(id: connection.uuid, kind: connection.kind,
                                       other: PersonRef(id: $0.uuid, name: $0.name), direction: direction)
                }
            }
        }
        return snapshots(person.outgoingConnections, .outgoing, \.to) + snapshots(person.incomingConnections, .incoming, \.from)
    }

    // MARK: Tags

    public func addTag(_ name: String, toPerson id: UUID) throws {
        let person = try fetchPerson(id)
        let tag = try findOrCreateTag(name)
        if !(person.tags ?? []).contains(where: { $0 === tag }) {
            person.tags = (person.tags ?? []) + [tag]
        }
        try context.save()
    }

    public func removeTag(_ name: String, fromPerson id: UUID) throws {
        let person = try fetchPerson(id)
        let key = tagKey(name)
        person.tags = (person.tags ?? []).filter { tagKey($0.name) != key }
        try context.save()
    }

    public func tags() throws -> [TagSummary] {
        try context.fetch(FetchDescriptor<Tag>())
            .map { TagSummary(name: $0.name, personCount: ($0.persons ?? []).count, eventCount: ($0.events ?? []).count) }
            .filter { $0.personCount + $0.eventCount > 0 }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Events

    /// Validates everything first, then writes event, tags and any new persons in one save.
    @discardableResult
    public func logEvent(_ draft: EventDraft) throws -> UUID {
        try atomically {
            if let end = draft.end, end < draft.start {
                throw PplzError.invalid("An event cannot end before it starts.")
            }
            try validate(tags: draft.tags, new: draft.additionalParticipants)
            let links = try cleaned(links: draft.links)
            let participants = try draft.participants.map(fetchPerson) + draft.additionalParticipants.map(person(for:))
            let event = Event(title: draft.title.trimmed, format: draft.format, start: draft.start)
            event.end = draft.end
            event.place = draft.place.trimmed
            event.notes = draft.notes
            event.links = links
            context.insert(event)
            event.participants = participants
            event.tags = try draft.tags.map(findOrCreateTag)
            return event.uuid
        }
    }

    public func updateEvent(_ id: UUID, _ change: EventChange) throws {
        try atomically {
            let event = try fetchEvent(id)
            let start = change.start ?? event.start
            let end = change.clearEnd ? nil : (change.end ?? event.end)
            if let end, end < start {
                throw PplzError.invalid("An event cannot end before it starts.")
            }
            try validate(tags: change.tags ?? [], new: change.additionalParticipants)
            let links = try change.links.map(cleaned(links:))
            var participants = try change.participants.map { try $0.map(fetchPerson) }
            if !change.additionalParticipants.isEmpty {
                participants = try (participants ?? []) + change.additionalParticipants.map(person(for:))
            }
            let tags = try change.tags.map { try $0.map(findOrCreateTag) }

            event.start = start
            event.end = end
            if let title = change.title { event.title = title.trimmed }
            if let format = change.format { event.formatRaw = format.rawValue }
            if let place = change.place { event.place = place.trimmed }
            if let notes = change.notes { event.notes = notes }
            if let participants { event.participants = participants }
            if let tags { event.tags = tags }
            if let links { event.links = links }
        }
    }

    public func deleteEvent(_ id: UUID) throws {
        context.delete(try fetchEvent(id))
        try context.save()
    }

    public func event(_ id: UUID) throws -> EventSnapshot {
        snapshot(try fetchEvent(id))
    }

    /// Newest first.
    public func events(_ filter: EventFilter = EventFilter()) throws -> [EventSnapshot] {
        let tagFilter = filter.tag.map(tagKey)
        return try context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start, order: .reverse)]))
            .filter { event in
                if let person = filter.person, !(event.participants ?? []).contains(where: { $0.uuid == person }) { return false }
                if let format = filter.format, event.formatRaw != format.rawValue { return false }
                if let since = filter.since, event.start < since { return false }
                if let until = filter.until, event.start > until { return false }
                if let place = filter.place, !event.place.localizedCaseInsensitiveContains(place) { return false }
                if let tagFilter, !(event.tags ?? []).contains(where: { tagKey($0.name) == tagFilter }) { return false }
                return true
            }
            .map(snapshot)
    }

    /// All events the person took part in, newest first.
    public func history(of person: UUID) throws -> [EventSnapshot] {
        _ = try fetchPerson(person)
        return try events(EventFilter(person: person))
    }

    // MARK: Follow-ups

    @discardableResult
    public func addFollowUp(_ text: String, toEvent id: UUID) throws -> UUID {
        let event = try fetchEvent(id)
        let followUp = FollowUp(text: try nonEmpty(text, "A follow-up needs a text."))
        context.insert(followUp)
        followUp.event = event
        try context.save()
        return followUp.uuid
    }

    public func completeFollowUp(_ id: UUID) throws {
        guard let followUp = try context.fetch(FetchDescriptor<FollowUp>(predicate: #Predicate { $0.uuid == id })).first else {
            throw PplzError.notFound("follow-up \(id.uuidString)")
        }
        followUp.done = true
        try context.save()
    }

    /// Oldest first.
    public func openFollowUps() throws -> [OpenFollowUp] {
        try context.fetch(FetchDescriptor<FollowUp>(predicate: #Predicate { !$0.done }, sortBy: [SortDescriptor(\.createdAt)]))
            .compactMap { followUp in
                guard let event = followUp.event else { return nil }
                return OpenFollowUp(id: followUp.uuid, text: followUp.text, eventID: event.uuid, eventTitle: event.title,
                                    eventStart: event.start, participants: refs(event.participants))
            }
    }

    // MARK: Internals

    /// Runs `body` and saves; on any error every pending change is discarded.
    private func atomically<T>(_ body: () throws -> T) throws -> T {
        do {
            let result = try body()
            try context.save()
            return result
        } catch {
            context.rollback()
            throw error
        }
    }

    private func cleaned(links: [String]) throws -> [String] {
        try links.map { link in
            let text = link.trimmed
            guard !text.contains(" "), let url = URL(string: text), url.scheme != nil else {
                throw PplzError.invalid("\"\(link)\" is not a link. Use a full address such as https://example.com.")
            }
            return text
        }
    }

    private func validate(tags: [String], new: [NewParticipant]) throws {
        for tag in tags { _ = try nonEmpty(tag, "A tag needs a name.") }
        for case .named(let name) in new { _ = try nonEmpty(name, "A person needs a name.") }
    }

    /// Finds or inserts the person for a new participant, without saving.
    private func person(for participant: NewParticipant) throws -> Person {
        switch participant {
        case .named(let name):
            let person = Person(name: try nonEmpty(name, "A person needs a name."))
            context.insert(person)
            return person
        case .contact(let contact):
            let identifier = contact.identifier
            if let existing = try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.localContactIdentifier == identifier }))
                .min(by: { $0.createdAt < $1.createdAt }) {
                return existing
            }
            let person = Person(name: contact.name, localContactIdentifier: identifier)
            context.insert(person)
            return person
        }
    }

    private func fetchPerson(_ id: UUID) throws -> Person {
        guard let person = try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.uuid == id })).first else {
            throw PplzError.notFound("person \(id.uuidString)")
        }
        return person
    }

    private func fetchEvent(_ id: UUID) throws -> Event {
        guard let event = try context.fetch(FetchDescriptor<Event>(predicate: #Predicate { $0.uuid == id })).first else {
            throw PplzError.notFound("event \(id.uuidString)")
        }
        return event
    }

    private func findOrCreateTag(_ name: String) throws -> Tag {
        let display = try nonEmpty(name, "A tag needs a name.")
        let key = tagKey(display)
        if let tag = try context.fetch(FetchDescriptor<Tag>()).first(where: { tagKey($0.name) == key }) {
            return tag
        }
        let tag = Tag(name: display)
        context.insert(tag)
        return tag
    }

    private func tagKey(_ name: String) -> String { name.trimmed.lowercased() }

    private func nonEmpty(_ text: String, _ message: String) throws -> String {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { throw PplzError.invalid(message) }
        return trimmed
    }

    private func tagNames(_ tags: [Tag]?) -> [String] {
        (tags ?? []).map(\.name).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func refs(_ persons: [Person]?) -> [PersonRef] {
        (persons ?? []).map { PersonRef(id: $0.uuid, name: $0.name) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func byName(_ a: PersonSnapshot, _ b: PersonSnapshot) -> Bool {
        a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
    }

    private func snapshot(_ person: Person) -> PersonSnapshot {
        let events = person.events ?? []
        return PersonSnapshot(id: person.uuid, name: person.name, contactIdentifier: person.localContactIdentifier,
                              howWeMet: person.howWeMet, notes: person.notes, eventCount: events.count,
                              lastMet: events.map(\.start).max(), keepInTouchDays: person.keepInTouchDays,
                              tags: tagNames(person.tags))
    }

    private func snapshot(_ event: Event) -> EventSnapshot {
        EventSnapshot(
            id: event.uuid, title: event.title, format: EventFormat(rawValue: event.formatRaw) ?? .liveMeeting,
            start: event.start, end: event.end, place: event.place, notes: event.notes,
            participants: refs(event.participants), tags: tagNames(event.tags), links: event.links,
            followUps: (event.followUps ?? []).sorted { $0.createdAt < $1.createdAt }
                .map { FollowUpSnapshot(id: $0.uuid, text: $0.text, done: $0.done) })
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
