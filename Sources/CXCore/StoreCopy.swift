import Foundation
import SwiftData

/// The copy of every record into a new store, for the rename from pplz
/// (`docs/changes/01_rename_to_cardxchange/02-data-migration.md` §2.5).
/// A store that synced with one iCloud container cannot sync with another: Core Data takes the new container for
/// a new account and deletes the local data. A new store holds no sync data, so the app uploads all its records.
extension CXStore {
    /// Copies every record from the store at `source` into a new store at `target`. Each record keeps its ID and its values,
    /// and the relationships point to the copies. Records are copied row for row; duplicates stay duplicates.
    /// Opening `source` can change it, so give it a copy of the old store.
    public static func copyAll(from source: URL, to target: URL) throws {
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw CXError.invalid("\(target.path) exists already. Nothing was copied.")
        }
        let old = try CXStore(url: source).context
        let new = try CXStore(url: target).context

        var persons: [PersistentIdentifier: Person] = [:]
        for item in try old.fetch(FetchDescriptor<Person>()) {
            let copy = Person(name: item.name, localContactIdentifier: item.localContactIdentifier)
            copy.uuid = item.uuid
            copy.howWeMet = item.howWeMet
            copy.notes = item.notes
            copy.linkedInID = item.linkedInID
            copy.createdAt = item.createdAt
            copy.keepInTouchDays = item.keepInTouchDays
            copy.deletedAt = item.deletedAt
            copy.contactCopy = item.contactCopy
            new.insert(copy)
            persons[item.persistentModelID] = copy
        }
        func person(_ item: Person?) -> Person? { item.flatMap { persons[$0.persistentModelID] } }

        var tags: [PersistentIdentifier: Tag] = [:]
        for item in try old.fetch(FetchDescriptor<Tag>()) {
            let copy = Tag(name: item.name)
            new.insert(copy)
            tags[item.persistentModelID] = copy
            copy.persons = (item.persons ?? []).compactMap(person)
        }

        var events: [PersistentIdentifier: Event] = [:]
        for item in try old.fetch(FetchDescriptor<Event>()) {
            let copy = Event(title: item.title, format: .liveMeeting, start: item.start)
            copy.uuid = item.uuid
            copy.formatRaw = item.formatRaw
            copy.end = item.end
            copy.place = item.place
            copy.notes = item.notes
            copy.links = item.links
            copy.createdAt = item.createdAt
            new.insert(copy)
            events[item.persistentModelID] = copy
            copy.participants = (item.participants ?? []).compactMap(person)
            copy.tags = (item.tags ?? []).compactMap { tags[$0.persistentModelID] }
        }

        for item in try old.fetch(FetchDescriptor<Connection>()) {
            let copy = Connection(kind: item.kind)
            copy.uuid = item.uuid
            copy.createdAt = item.createdAt
            new.insert(copy)
            copy.from = person(item.from)
            copy.to = person(item.to)
        }
        for item in try old.fetch(FetchDescriptor<PersonPhoto>()) {
            let copy = PersonPhoto(imageData: item.imageData)
            copy.uuid = item.uuid
            copy.createdAt = item.createdAt
            new.insert(copy)
            copy.person = person(item.person)
        }
        for item in try old.fetch(FetchDescriptor<FollowUp>()) {
            let copy = FollowUp(text: item.text)
            copy.uuid = item.uuid
            copy.done = item.done
            copy.createdAt = item.createdAt
            new.insert(copy)
            copy.event = item.event.flatMap { events[$0.persistentModelID] }
        }
        for item in try old.fetch(FetchDescriptor<Setting>()) {
            new.insert(Setting(key: item.key, value: item.value))
        }
        for item in try old.fetch(FetchDescriptor<LocatedAddress>()) {
            new.insert(LocatedAddress(key: item.key, coordinate: item.coordinate, checkedAt: item.checkedAt))
        }
        try new.save()
    }
}
