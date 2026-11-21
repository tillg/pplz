import CoreData
import Foundation
import SwiftData

/// The cardXchange database. App and CLI open the same store file (SPEC §8.3);
/// CloudKit sync is the app's job, so this type never talks to CloudKit.
public final class CXStore {
    let context: ModelContext

    /// The iCloud container the apps sync through.
    public static let iCloudContainer = "iCloud.me.cardxchange.app"

    /// Opens the store at `url`. It stays purely local unless `container` names an iCloud container;
    /// only the apps pass one, and only for their default store. The CLI and tests never do.
    public init(url: URL, syncingWith container: String? = nil) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let config = ModelConfiguration(url: url, cloudKitDatabase: container.map { .private($0) } ?? .none)
        let container = try ModelContainer(for: Person.self, Event.self, Tag.self, FollowUp.self, Connection.self, Setting.self, PersonPhoto.self, LocatedAddress.self, configurations: config)
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    /// Posted whenever iCloud sync starts or finishes a step; see `broughtNewData`.
    public static let syncNotification = NSPersistentCloudKitContainer.eventChangedNotification

    /// Whether a sync notification says that changes from another device have just arrived.
    public static func broughtNewData(_ notification: Notification) -> Bool {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return false }
        return event.type == .import && event.endDate != nil && event.succeeded
    }

    /// `CX_STORE` if set, otherwise `~/Library/Application Support/cardxchange/cardxchange.store`.
    public static func defaultURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                                  base: URL = .applicationSupportDirectory) -> URL {
        if let path = environment["CX_STORE"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return base.appendingPathComponent("cardxchange/cardxchange.store")
    }

    /// Stops the command if a variable of the old name is set: an ignored `PPLZ_NO_CONTACTS` would let `cx`
    /// write to the real address book (rename, D8).
    public static func checkOldVariables(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        for (old, new) in [("PPLZ_STORE", "CX_STORE"), ("PPLZ_NO_CONTACTS", "CX_NO_CONTACTS")] where environment[old] != nil {
            throw CXError.invalid("\(old) is set, but cx no longer reads it. Use \(new), and remove \(old) from your shell profile.")
        }
    }

    /// Stops a start that would create an empty default store while the data of pplz, the old name, is not migrated yet.
    /// A store given by path is never refused.
    public static func checkMigrated(_ url: URL, base: URL = .applicationSupportDirectory) throws {
        let old = base.appendingPathComponent("pplz")
        guard url.standardizedFileURL == defaultURL(environment: [:], base: base).standardizedFileURL,
              !FileManager.default.fileExists(atPath: url.path),
              FileManager.default.fileExists(atPath: old.path) else { return }
        throw CXError.invalid("The data of pplz, the old name of cardXchange, is still in \(old.path). Run scripts/migrate-from-pplz.sh first.")
    }

    /// The card for one row of the people list.
    public func card(for entry: PersonEntry, contact: ContactDetails?) throws -> PersonCard {
        guard let id = entry.id else {
            return PersonCard(entry: entry, contact: contact, stored: nil, connections: [], history: [])
        }
        return PersonCard(entry: entry, contact: contact, stored: try person(id),
                          connections: try connections(of: id), history: try history(of: id), photos: try photos(of: id))
    }

    // MARK: Settings

    /// "Show history in Contacts": whether cardXchange writes its history block into contact notes.
    /// Off until the user turns it on (SPEC §8.4).
    public func showsHistoryInContacts() throws -> Bool {
        try setting("showHistoryInContacts") == "true"
    }

    public func setShowsHistoryInContacts(_ on: Bool) throws {
        try setSetting("showHistoryInContacts", on ? "true" : "false")
    }

    private func setting(_ key: String) throws -> String? {
        try context.fetch(FetchDescriptor<Setting>(predicate: #Predicate { $0.key == key })).first?.value
    }

    private func setSetting(_ key: String, _ value: String) throws {
        if let existing = try context.fetch(FetchDescriptor<Setting>(predicate: #Predicate { $0.key == key })).first {
            existing.value = value
        } else {
            context.insert(Setting(key: key, value: value))
        }
        try context.save()
    }

    // MARK: Persons

    @discardableResult
    public func createPerson(name: String) throws -> UUID {
        let person = Person(name: try nonEmpty(name, "A person needs a name."))
        context.insert(person)
        try context.save()
        return person.uuid
    }

    public func setLinkedInID(_ id: String, for person: UUID) throws {
        try fetchPerson(person).linkedInID = id.trimmed.lowercased()
        try context.save()
    }

    /// The person with this LinkedIn profile, if cardXchange knows one.
    public func person(withLinkedInID id: String) throws -> UUID? {
        let wanted = id.trimmed.lowercased()
        guard !wanted.isEmpty else { return nil }
        return try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.linkedInID == wanted }))
            .filter { $0.deletedAt == nil }
            .min { $0.createdAt < $1.createdAt }?.uuid
    }

    /// Ties a person to this device's contact, see `PeopleDirectory.adoptions`.
    public func setContactIdentifier(_ identifier: String, for id: UUID) throws {
        try fetchPerson(id).localContactIdentifier = identifier
        try context.save()
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

    /// The persons in the list; deleted persons are left out.
    public func persons() throws -> [PersonSnapshot] {
        try context.fetch(FetchDescriptor<Person>()).filter { $0.deletedAt == nil }.map(snapshot).sorted(by: byName)
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
        if let days, days < 1 { throw CXError.invalid("A keep-in-touch rhythm needs at least 1 day.") }
        try fetchPerson(id).keepInTouchDays = days
        try context.save()
    }

    // MARK: Deleting

    /// Moves a person to "Recently deleted". `contactCopy` is the contact that is deleted with the person;
    /// with a copy the person forgets the contact's identifier, as the contact is gone.
    public func deletePerson(_ id: UUID, contactCopy: ContactEdit?, at date: Date) throws {
        try atomically {
            let person = try fetchPerson(id)
            guard person.deletedAt == nil else { throw CXError.invalid("\(person.name) is deleted already.") }
            person.deletedAt = date
            if let contactCopy {
                person.contactCopy = try JSONEncoder().encode(contactCopy)
                person.localContactIdentifier = nil
            }
        }
    }

    /// Newest first.
    public func deletedPersons() throws -> [DeletedPerson] {
        try context.fetch(FetchDescriptor<Person>()).compactMap { person in
            person.deletedAt.map { DeletedPerson(id: person.uuid, name: person.name, deletedAt: $0, hasContactCopy: person.contactCopy != nil) }
        }
        .sorted { $0.deletedAt > $1.deletedAt }
    }

    /// The contact that was deleted with the person; `nil` if there was none.
    public func contactCopy(of id: UUID) throws -> ContactEdit? {
        try fetchPerson(id).contactCopy.map { try JSONDecoder().decode(ContactEdit.self, from: $0) }
    }

    /// Brings a deleted person back to the list. `contactIdentifier` is the contact created again from the copy, if any.
    public func restorePerson(_ id: UUID, contactIdentifier: String?) throws {
        try atomically {
            let person = try fetchPerson(id)
            guard person.deletedAt != nil else { throw CXError.invalid("\(person.name) is not deleted.") }
            person.deletedAt = nil
            person.contactCopy = nil
            if let contactIdentifier { person.localContactIdentifier = contactIdentifier }
        }
    }

    /// Removes deleted persons for good, with their connections and photos. Their events stay, without them.
    @discardableResult
    public func purgePersons(_ ids: [UUID]) throws -> PurgeResult {
        try atomically {
            let persons = try ids.map(fetchPerson)
            if let alive = persons.first(where: { $0.deletedAt == nil }) {
                throw CXError.invalid("\(alive.name) is not deleted.")
            }
            let removed = Set(ids)
            var result = PurgeResult(persons: ids)
            result.connections = try allConnections().filter { removed.contains($0.from.id) || removed.contains($0.to.id) }
            var others: [UUID] = []
            for person in persons {
                for other in (person.events ?? []).flatMap({ $0.participants ?? [] })
                where !removed.contains(other.uuid) && !others.contains(other.uuid) {
                    others.append(other.uuid)
                }
            }
            result.otherParticipants = others
            persons.forEach(context.delete)
            return result
        }
    }

    /// Removes the deleted persons whose 30 days are over at `now`.
    @discardableResult
    public func purgeExpired(now: Date) throws -> PurgeResult {
        let ids = DeletedPerson.expired(try deletedPersons(), now: now)
        return ids.isEmpty ? PurgeResult() : try purgePersons(ids)
    }

    // MARK: Connections

    /// Records "`from` is `kind` `to`", e.g. "colleague of". Storing the same connection twice has no effect.
    public func connect(_ from: UUID, to: UUID, kind: String) throws {
        try atomically {
            guard from != to else { throw CXError.invalid("A person cannot be connected to themselves.") }
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

    /// Replaces all tags of a person. Empty names are skipped; a name given twice counts once.
    public func setTags(_ names: [String], forPerson id: UUID) throws {
        try atomically {
            let person = try fetchPerson(id)
            var seen: Set<String> = []
            person.tags = try names.filter { !$0.trimmed.isEmpty && seen.insert(tagKey($0)).inserted }.map(findOrCreateTag)
        }
    }

    public func removeTag(_ name: String, fromPerson id: UUID) throws {
        let person = try fetchPerson(id)
        let key = tagKey(name)
        person.tags = (person.tags ?? []).filter { tagKey($0.name) != key }
        try context.save()
    }

    /// Tags in use. Spellings that differ only in case count as one tag (see `mergeDuplicateTags`).
    public func tags() throws -> [TagSummary] {
        try tagGroups().map { group in
            TagSummary(name: group[0].name,
                       personCount: Set(group.flatMap { $0.persons ?? [] }.map(\.uuid)).count,
                       eventCount: Set(group.flatMap { $0.events ?? [] }.map(\.uuid)).count)
        }
        .filter { $0.personCount + $0.eventCount > 0 }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Two devices can create the same tag before they sync. This folds such twins into the
    /// most used spelling and returns how many tags it removed.
    @discardableResult
    public func mergeDuplicateTags() throws -> Int {
        var removed = 0
        for group in try tagGroups() where group.count > 1 {
            let keep = group[0]
            for twin in group.dropFirst() {
                for person in twin.persons ?? [] where !(keep.persons ?? []).contains(where: { $0 === person }) {
                    keep.persons = (keep.persons ?? []) + [person]
                }
                for event in twin.events ?? [] where !(keep.events ?? []).contains(where: { $0 === event }) {
                    keep.events = (keep.events ?? []) + [event]
                }
                context.delete(twin)
                removed += 1
            }
        }
        if removed > 0 { try context.save() }
        return removed
    }

    /// All tags grouped by name without regard to case; in each group the spelling to keep comes first:
    /// the most used one, then the alphabetically first — the same choice on every device.
    private func tagGroups() throws -> [[Tag]] {
        func uses(_ tag: Tag) -> Int { (tag.persons ?? []).count + (tag.events ?? []).count }
        return Dictionary(grouping: try context.fetch(FetchDescriptor<Tag>())) { tagKey($0.name) }.values.map {
            $0.sorted { uses($0) != uses($1) ? uses($0) > uses($1) : $0.name < $1.name }
        }
    }

    // MARK: Photos

    /// Adds pictures — already cropped to a face, see `FacePhoto` — to a person; returns their IDs.
    @discardableResult
    public func addPhotos(_ images: [Data], toPerson id: UUID) throws -> [UUID] {
        try atomically {
            let person = try fetchPerson(id)
            return try images.map { data in
                guard !data.isEmpty else { throw CXError.invalid("There is no picture to add.") }
                let photo = PersonPhoto(imageData: data)
                context.insert(photo)
                photo.person = person
                return photo.uuid
            }
        }
    }

    // MARK: Located addresses

    /// What is known about each address, by `PostalAddress.key`. Where two devices each stored an answer for the
    /// same address, every device picks the same one: found beats not found, then the earlier answer.
    public func locations() throws -> [String: GeocodeState.Entry] {
        var result: [String: GeocodeState.Entry] = [:]
        for row in try context.fetch(FetchDescriptor<LocatedAddress>()) {
            let entry = GeocodeState.Entry(coordinate: row.coordinate, checkedAt: row.checkedAt)
            guard let known = result[row.key] else { result[row.key] = entry; continue }
            let wins = (entry.coordinate != nil) != (known.coordinate != nil) ? entry.coordinate != nil : entry.checkedAt < known.checkedAt
            if wins { result[row.key] = entry }
        }
        return result
    }

    /// Notes answers of the geocoder. An address that has a row gets its row changed; a second row from another
    /// device is never deleted here — if two devices each deleted the other's, both would be gone.
    public func recordLocations(_ entries: [String: GeocodeState.Entry]) throws {
        guard !entries.isEmpty else { return }
        try atomically {
            let rows = Dictionary(grouping: try context.fetch(FetchDescriptor<LocatedAddress>()), by: \.key)
            for (key, entry) in entries {
                if let row = rows[key]?.min(by: { $0.checkedAt < $1.checkedAt }) {
                    row.latitude = entry.coordinate?.latitude
                    row.longitude = entry.coordinate?.longitude
                    row.checkedAt = entry.checkedAt
                } else {
                    context.insert(LocatedAddress(key: key, coordinate: entry.coordinate, checkedAt: entry.checkedAt))
                }
            }
        }
    }

    /// Newest first.
    public func photos(of id: UUID) throws -> [PhotoSnapshot] {
        (try fetchPerson(id).photos ?? []).sorted { $0.createdAt > $1.createdAt }.map(snapshot)
    }

    public func photo(_ id: UUID) throws -> PhotoSnapshot {
        snapshot(try fetchPhoto(id))
    }

    public func deletePhoto(_ id: UUID) throws {
        context.delete(try fetchPhoto(id))
        try context.save()
    }

    // MARK: Events

    /// The format of the event that was logged last (not the one that took place last).
    public func lastLoggedFormat() throws -> EventFormat? {
        try context.fetch(FetchDescriptor<Event>()).max { $0.createdAt < $1.createdAt }.flatMap { EventFormat(rawValue: $0.formatRaw) }
    }

    /// Validates everything first, then writes event, tags and any new persons in one save.
    @discardableResult
    public func logEvent(_ draft: EventDraft) throws -> UUID {
        try atomically {
            if let end = draft.end, end < draft.start {
                throw CXError.invalid("An event cannot end before it starts.")
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
                throw CXError.invalid("An event cannot end before it starts.")
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
            throw CXError.notFound("follow-up \(id.uuidString)")
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
                throw CXError.invalid("\"\(link)\" is not a link. Use a full address such as https://example.com.")
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

    func fetchPerson(_ id: UUID) throws -> Person {
        guard let person = try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.uuid == id })).first else {
            throw CXError.notFound("person \(id.uuidString)")
        }
        return person
    }

    func fetchEvent(_ id: UUID) throws -> Event {
        guard let event = try context.fetch(FetchDescriptor<Event>(predicate: #Predicate { $0.uuid == id })).first else {
            throw CXError.notFound("event \(id.uuidString)")
        }
        return event
    }

    private func fetchPhoto(_ id: UUID) throws -> PersonPhoto {
        guard let photo = try context.fetch(FetchDescriptor<PersonPhoto>(predicate: #Predicate { $0.uuid == id })).first else {
            throw CXError.notFound("photo \(id.uuidString)")
        }
        return photo
    }

    private func findOrCreateTag(_ name: String) throws -> Tag {
        let display = try nonEmpty(name, "A tag needs a name.")
        let key = tagKey(display)
        if let tag = try tagGroups().first(where: { tagKey($0[0].name) == key })?[0] {
            return tag
        }
        let tag = Tag(name: display)
        context.insert(tag)
        return tag
    }

    private func tagKey(_ name: String) -> String { name.trimmed.lowercased() }

    private func nonEmpty(_ text: String, _ message: String) throws -> String {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { throw CXError.invalid(message) }
        return trimmed
    }

    private func tagNames(_ tags: [Tag]?) -> [String] {
        let canonical = Dictionary(uniqueKeysWithValues: ((try? tagGroups()) ?? []).map { (tagKey($0[0].name), $0[0].name) })
        return Set((tags ?? []).map { canonical[tagKey($0.name)] ?? $0.name })
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
                              tags: tagNames(person.tags), linkedInID: person.linkedInID)
    }

    private func snapshot(_ photo: PersonPhoto) -> PhotoSnapshot {
        PhotoSnapshot(id: photo.uuid, createdAt: photo.createdAt, data: photo.imageData)
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
