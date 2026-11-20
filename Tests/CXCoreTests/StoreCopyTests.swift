import Foundation
import SwiftData
import Testing
@testable import CXCore

/// The copy of every record into a new store, for the rename (`docs/changes/01_rename_to_cardxchange/02-data-migration.md` §2.5).
@Suite struct StoreCopyTests {
    /// A store with each kind of record and each relationship, every attribute set to a value that is not its default.
    func filledStore() throws -> (CXStore, URL) {
        let (store, url) = try makeStore()
        let context = store.context
        let anna = Person(name: "Anna Example", localContactIdentifier: "C-A")
        anna.howWeMet = "At the fair"
        anna.notes = "Likes tea"
        anna.linkedInID = "anna-example"
        anna.createdAt = day(2026, 1, 2)
        anna.keepInTouchDays = 90
        let ben = Person(name: "Ben Sample")
        ben.createdAt = day(2026, 1, 3)
        let work = Tag(name: "work"), fair = Tag(name: "fair"), twin = Tag(name: "work")   // a duplicate, as CloudKit can leave one
        let event = Event(title: "Lunch", format: .webCall, start: day(2026, 3, 4, 13))
        event.end = day(2026, 3, 4, 14)
        event.place = "Köln"
        event.notes = "About the book"
        event.links = ["https://example.com/a", "https://example.com/b"]
        event.createdAt = day(2026, 3, 5)
        let connection = Connection(kind: "_$!<Friend>!$_")
        connection.createdAt = day(2026, 2, 1)
        let photo = PersonPhoto(imageData: Data((0..<1_000_000).map { UInt8($0 % 251) }))   // large enough for external storage
        photo.createdAt = day(2026, 2, 2)
        let followUp = FollowUp(text: "Send the title")
        followUp.done = true
        followUp.createdAt = day(2026, 3, 6)
        for model in [anna, ben] as [any PersistentModel] + [work, fair, twin, event, connection, photo, followUp] as [any PersistentModel] {
            context.insert(model)
        }
        anna.tags = [work, twin]
        event.tags = [fair]
        event.participants = [anna, ben]
        connection.from = anna
        connection.to = ben
        photo.person = anna
        followUp.event = event
        context.insert(Setting(key: "showHistoryInContacts", value: "true"))
        context.insert(LocatedAddress(key: "köln|de", coordinate: Coordinate(latitude: 50.94, longitude: 6.96), checkedAt: day(2026, 3, 7)))
        context.insert(LocatedAddress(key: "nowhere", coordinate: nil, checkedAt: day(2026, 3, 8)))
        try context.save()
        return (store, url)
    }

    func target() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("cx-copy-\(UUID().uuidString)/cardxchange.store")
    }

    func all<T: PersistentModel>(_ type: T.Type, in store: CXStore) throws -> [T] {
        try store.context.fetch(FetchDescriptor<T>())
    }

    @Test func everyPersonKeepsItsIDAndValues() throws {
        let (old, url) = try filledStore()
        let copyURL = target()
        try CXStore.copyAll(from: url, to: copyURL)
        let new = try CXStore(url: copyURL)
        let before = try all(Person.self, in: old).sorted { $0.name < $1.name }
        let after = try all(Person.self, in: new).sorted { $0.name < $1.name }
        #expect(after.map(\.uuid) == before.map(\.uuid))
        for (a, b) in zip(before, after) {
            #expect([a.name, a.howWeMet, a.notes, a.linkedInID] == [b.name, b.howWeMet, b.notes, b.linkedInID])
            #expect(a.localContactIdentifier == b.localContactIdentifier)
            #expect(a.createdAt == b.createdAt)
            #expect(a.keepInTouchDays == b.keepInTouchDays)
            #expect(Set((a.tags ?? []).map(\.name)) == Set((b.tags ?? []).map(\.name)))
            #expect((a.tags ?? []).count == (b.tags ?? []).count)
        }
    }

    @Test func eventsKeepTheirValuesPeopleTagsAndFollowUps() throws {
        let (old, url) = try filledStore()
        let copyURL = target()
        try CXStore.copyAll(from: url, to: copyURL)
        let a = try #require(try all(Event.self, in: old).first)
        let b = try #require(try all(Event.self, in: try CXStore(url: copyURL)).first)
        #expect(b.uuid == a.uuid)
        #expect([b.title, b.formatRaw, b.place, b.notes] == [a.title, a.formatRaw, a.place, a.notes])
        #expect([b.start, b.createdAt] == [a.start, a.createdAt])
        #expect(b.end == a.end)
        #expect(b.links == a.links)
        #expect(Set((b.participants ?? []).map(\.uuid)) == Set((a.participants ?? []).map(\.uuid)))
        #expect((b.tags ?? []).map(\.name) == ["fair"])
        let followUp = try #require(b.followUps?.first)
        #expect(followUp.uuid == a.followUps?.first?.uuid)
        #expect(followUp.text == "Send the title")
        #expect(followUp.done)
        #expect(followUp.createdAt == day(2026, 3, 6))
    }

    @Test func connectionsPhotosSettingsAndAddressesAreCopied() throws {
        let (old, url) = try filledStore()
        let copyURL = target()
        try CXStore.copyAll(from: url, to: copyURL)
        let new = try CXStore(url: copyURL)

        let c = try #require(try all(Connection.self, in: new).first)
        let oc = try #require(try all(Connection.self, in: old).first)
        #expect(c.uuid == oc.uuid)
        #expect(c.kind == oc.kind)
        #expect(c.createdAt == oc.createdAt)
        #expect(c.from?.uuid == oc.from?.uuid)
        #expect(c.to?.uuid == oc.to?.uuid)

        let p = try #require(try all(PersonPhoto.self, in: new).first)
        let op = try #require(try all(PersonPhoto.self, in: old).first)
        #expect(p.uuid == op.uuid)
        #expect(p.createdAt == op.createdAt)
        #expect(p.imageData == op.imageData)
        #expect(p.person?.uuid == op.person?.uuid)

        #expect(try all(Setting.self, in: new).map { "\($0.key)=\($0.value)" } == ["showHistoryInContacts=true"])
        let addresses = try all(LocatedAddress.self, in: new).sorted { $0.key < $1.key }
        #expect(addresses.map(\.key) == ["köln|de", "nowhere"])
        #expect(addresses[0].coordinate == Coordinate(latitude: 50.94, longitude: 6.96))
        #expect(addresses[0].checkedAt == day(2026, 3, 7))
        #expect(addresses[1].coordinate == nil)
    }

    @Test func duplicatesAreCopiedRowForRow() throws {
        let (_, url) = try filledStore()
        let copyURL = target()
        try CXStore.copyAll(from: url, to: copyURL)
        #expect(try all(Tag.self, in: try CXStore(url: copyURL)).map(\.name).sorted() == ["fair", "work", "work"])
    }

    @Test func anExistingTargetIsRefused() throws {
        let (_, url) = try filledStore()
        let (_, existing) = try makeStore()
        #expect(throws: CXError.self) { try CXStore.copyAll(from: url, to: existing) }
        #expect(try CXStore(url: existing).persons().isEmpty)
    }
}
