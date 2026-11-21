import Foundation
import Testing
@testable import CXCore

/// Deleting a person: 30 days under "Recently deleted", then removed for good (SPEC §3.4).
@Suite struct DeletionTests {
    let copy = ContactEdit(givenName: "Anna", familyName: "Example", organization: "Example GmbH",
                           phones: [.init(id: "P1", label: "_$!<Mobile>!$_", value: "+49 170 0000000")],
                           emails: [.init(id: "E1", label: "_$!<Work>!$_", value: "anna@example.com")],
                           addresses: [.init(id: "A1", label: "_$!<Work>!$_", street: "Musterweg 1", postalCode: "50667", city: "Köln", country: "Germany")],
                           birthday: .init(day: 2, month: 9), contactIdentifier: "C-1")

    @Test func aDeletedPersonLeavesTheListButKeepsTheirData() throws {
        let (store, _) = try makeStore()
        let anna = try store.createPerson(name: "Anna Example")
        let ben = try store.createPerson(name: "Ben Sample")
        try store.setNotes("Likes tea", for: anna)
        try store.addTag("work", toPerson: anna)
        let event = try store.logEvent(EventDraft(title: "Lunch", format: .liveMeeting, start: day(2026, 11, 1), participants: [anna, ben]))

        try store.deletePerson(anna, contactCopy: nil, at: day(2026, 11, 21))

        #expect(try store.persons().map(\.id) == [ben])
        #expect(try store.deletedPersons() == [DeletedPerson(id: anna, name: "Anna Example", deletedAt: day(2026, 11, 21), hasContactCopy: false)])
        #expect(try store.person(anna).notes == "Likes tea")
        #expect(try store.person(anna).tags == ["work"])
        #expect(try store.event(event).participants.map(\.name) == ["Anna Example", "Ben Sample"])
    }

    @Test func deletingKeepsACopyOfTheContactAndForgetsItsIdentifier() throws {
        let (store, _) = try makeStore()
        let anna = try store.ensurePerson(for: ContactSummary(identifier: "C-1", name: "Anna Example"))

        try store.deletePerson(anna, contactCopy: copy, at: day(2026, 11, 21))

        #expect(try store.contactCopy(of: anna) == copy)
        #expect(try store.person(anna).contactIdentifier == nil)
        #expect(try store.deletedPersons().map(\.hasContactCopy) == [true])
    }

    @Test func aPersonCanOnlyBeDeletedOnce() throws {
        let (store, _) = try makeStore()
        let anna = try store.createPerson(name: "Anna Example")
        try store.deletePerson(anna, contactCopy: nil, at: day(2026, 11, 20))
        #expect(throws: CXError.self) { try store.deletePerson(anna, contactCopy: nil, at: day(2026, 11, 21)) }
        #expect(try store.deletedPersons().map(\.deletedAt) == [day(2026, 11, 20)])
    }

    @Test func restoringBringsThePersonBackWithTheNewContact() throws {
        let (store, _) = try makeStore()
        let anna = try store.ensurePerson(for: ContactSummary(identifier: "C-1", name: "Anna Example"))
        try store.deletePerson(anna, contactCopy: copy, at: day(2026, 11, 21))

        try store.restorePerson(anna, contactIdentifier: "C-2")

        #expect(try store.persons().map(\.contactIdentifier) == ["C-2"])
        #expect(try store.deletedPersons().isEmpty)
        #expect(try store.contactCopy(of: anna) == nil)
    }

    @Test func restoringAPersonWithoutContactKeepsThemWithoutContact() throws {
        let (store, _) = try makeStore()
        let anna = try store.createPerson(name: "Anna Example")
        try store.deletePerson(anna, contactCopy: nil, at: day(2026, 11, 21))
        try store.restorePerson(anna, contactIdentifier: nil)
        #expect(try store.persons().map(\.id) == [anna])
        #expect(try store.person(anna).contactIdentifier == nil)
    }

    @Test func onlyADeletedPersonCanBeRestoredOrRemovedForGood() throws {
        let (store, _) = try makeStore()
        let anna = try store.createPerson(name: "Anna Example")
        #expect(throws: CXError.self) { try store.restorePerson(anna, contactIdentifier: nil) }
        #expect(throws: CXError.self) { try store.purgePersons([anna]) }
        #expect(try store.persons().map(\.id) == [anna])
    }

    @Test func removingForGoodTakesThePersonOutOfEventsAndConnections() throws {
        let (store, _) = try makeStore()
        let anna = try store.createPerson(name: "Anna Example")
        let ben = try store.createPerson(name: "Ben Sample")
        try store.addTag("work", toPerson: anna)
        try store.addPhotos([Data([1, 2, 3])], toPerson: anna)
        try store.connect(ben, to: anna, kind: "colleague of")
        let event = try store.logEvent(EventDraft(title: "Lunch", format: .liveMeeting, start: day(2026, 11, 1), participants: [anna, ben]))
        try store.deletePerson(anna, contactCopy: nil, at: day(2026, 11, 21))

        let purged = try store.purgePersons([anna])

        #expect(purged.connections.map(\.kind) == ["colleague of"])
        #expect(purged.otherParticipants == [ben])
        #expect(try store.deletedPersons().isEmpty)
        #expect(throws: CXError.self) { try store.person(anna) }
        #expect(try store.event(event).participants.map(\.id) == [ben])
        #expect(try store.connections(of: ben).isEmpty)
        #expect(try store.tags().isEmpty)
        #expect(try store.allConnections().isEmpty)
    }

    @Test func aDeletedPersonIsKeptForThirtyDays() {
        let id = UUID()
        let deleted = [DeletedPerson(id: id, name: "Anna Example", deletedAt: day(2026, 11, 1), hasContactCopy: false)]
        #expect(deleted[0].removalDate == day(2026, 12, 1))
        #expect(DeletedPerson.expired(deleted, now: day(2026, 12, 1).addingTimeInterval(-1)).isEmpty)
        #expect(DeletedPerson.expired(deleted, now: day(2026, 12, 1)) == [id])
    }

    @Test func removesOnlyThePersonsWhoseThirtyDaysAreOver() throws {
        let (store, _) = try makeStore()
        let old = try store.createPerson(name: "Old Example")
        let recent = try store.createPerson(name: "Recent Example")
        try store.deletePerson(old, contactCopy: nil, at: day(2026, 10, 1))
        try store.deletePerson(recent, contactCopy: nil, at: day(2026, 11, 20))

        let purged = try store.purgeExpired(now: day(2026, 11, 21))

        #expect(purged.persons == [old])
        #expect(try store.deletedPersons().map(\.id) == [recent])
    }

    @Test func recentlyDeletedIsNewestFirst() throws {
        let (store, _) = try makeStore()
        let first = try store.createPerson(name: "First Example")
        let second = try store.createPerson(name: "Second Example")
        try store.deletePerson(first, contactCopy: nil, at: day(2026, 11, 1))
        try store.deletePerson(second, contactCopy: nil, at: day(2026, 11, 2))
        #expect(try store.deletedPersons().map(\.id) == [second, first])
    }

    @Test func aContactDoesNotLeadToADeletedPerson() throws {
        let (store, _) = try makeStore()
        let anna = try store.ensurePerson(for: ContactSummary(identifier: "C-1", name: "Anna Example"))
        try store.deletePerson(anna, contactCopy: nil, at: day(2026, 11, 21))

        let again = try store.ensurePerson(for: ContactSummary(identifier: "C-1", name: "Anna Example"))
        let event = try store.logEvent(EventDraft(title: "Call", format: .phoneCall, start: day(2026, 11, 22),
                                                  additionalParticipants: [.contact(ContactSummary(identifier: "C-1", name: "Anna Example"))]))

        #expect(again != anna)
        #expect(try store.event(event).participants.map(\.id) == [again])
    }

    @Test func aDeletedPersonIsNotFoundByTheirLinkedInProfile() throws {
        let (store, _) = try makeStore()
        let anna = try store.createPerson(name: "Anna Example")
        try store.setLinkedInID("anna-example", for: anna)
        try store.deletePerson(anna, contactCopy: nil, at: day(2026, 11, 21))
        #expect(try store.person(withLinkedInID: "anna-example") == nil)
    }

    @Test func theCopyOfAStoreKeepsWhatIsDeleted() throws {
        let (store, url) = try makeStore()
        let anna = try store.ensurePerson(for: ContactSummary(identifier: "C-1", name: "Anna Example"))
        try store.deletePerson(anna, contactCopy: copy, at: day(2026, 11, 21))
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("cx-copy-\(UUID().uuidString)/cardxchange.store")

        try CXStore.copyAll(from: url, to: target)

        let new = try CXStore(url: target)
        #expect(try new.deletedPersons() == store.deletedPersons())
        #expect(try new.contactCopy(of: anna) == copy)
    }
}
