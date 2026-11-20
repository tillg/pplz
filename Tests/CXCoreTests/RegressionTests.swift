import Foundation
import Testing
@testable import CXCore

@Suite struct EndOfDayTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    var now: Date { day(2026, 11, 18, 15) }

    @Test func dateOnlyEndCoversTheWholeDay() throws {
        let end = try DateInput.parse("2026-10-05", endOfDay: true, now: now, calendar: calendar)
        #expect(end == day(2026, 10, 6, 0).addingTimeInterval(-1))
        #expect(try DateInput.parse("today", endOfDay: true, now: now, calendar: calendar) == day(2026, 11, 19, 0).addingTimeInterval(-1))
    }

    @Test func explicitTimeIsKept() throws {
        #expect(try DateInput.parse("2026-10-05 14:00", endOfDay: true, now: now, calendar: calendar) == day(2026, 10, 5, 14))
        #expect(try DateInput.parse("now", endOfDay: true, now: now, calendar: calendar) == now)
    }
}

@Suite struct ParticipantPlanTests {
    let known = UUID()
    var entries: [PersonEntry] {
        PeopleDirectory.merge(
            contacts: [ContactSummary(identifier: "C-1", name: "Anna Example"), ContactSummary(identifier: "C-2", name: "Ben Sample")],
            persons: [PersonSnapshot(id: known, name: "Anna Example", contactIdentifier: "C-1")])
    }

    @Test func plansExistingContactAndNewPeopleWithoutDuplicates() throws {
        let plan = try PeopleDirectory.participants(["anna", "Ben Sample", "ben", "Carl New", "carl new"], in: entries, createMissing: true)
        #expect(plan.existing == [known])
        #expect(plan.additional == [.contact(ContactSummary(identifier: "C-2", name: "Ben Sample")), .named("Carl New")])
    }

    @Test func unknownNameFailsUnlessCreationIsAllowed() {
        #expect(throws: CXError.notFound("a person matching \"Carl New\"")) {
            try PeopleDirectory.participants(["Carl New"], in: entries, createMissing: false)
        }
    }

    @Test func ambiguousNameFailsEvenWhenCreationIsAllowed() {
        #expect(throws: CXError.ambiguousPerson("a", entries)) {
            try PeopleDirectory.participants(["a"], in: entries, createMissing: true)
        }
    }

    @Test func resolvesUniqueIDPrefix() {
        let prefix = String(known.uuidString.lowercased().prefix(8))
        #expect(PeopleDirectory.resolve(prefix, in: entries) == .one(entries[0]))
    }

    @Test func jsonStatesWhetherAPersonIsCXOnly() throws {
        let json = String(decoding: try JSONEncoder().encode(entries[0]), as: UTF8.self)
        #expect(json.contains("\"isCXOnly\":false"))
    }
}

@Suite struct AtomicWriteTests {
    @Test func failedLogLeavesNothingBehind() throws {
        let (store, _) = try makeStore()
        // invalid tag, with people that would have to be created
        #expect(throws: CXError.self) {
            try store.logEvent(EventDraft(title: "Bad", format: .phoneCall, start: day(2026, 1, 1), tags: ["ok", "  "],
                                          additionalParticipants: [.named("New One"), .contact(ContactSummary(identifier: "C-1", name: "Contact"))]))
        }
        // invalid dates
        #expect(throws: CXError.self) {
            try store.logEvent(EventDraft(title: "Bad", format: .phoneCall, start: day(2026, 1, 2), end: day(2026, 1, 1),
                                          additionalParticipants: [.named("New Two")]))
        }
        // the next valid write on the same store must not carry leftovers along
        let a = try store.createPerson(name: "A")
        let id = try store.logEvent(EventDraft(title: "Good", format: .phoneCall, start: day(2026, 1, 3), participants: [a]))
        #expect(try store.events().map(\.id) == [id])
        #expect(try store.persons().map(\.name) == ["A"])
        #expect(try store.tags().isEmpty)
    }

    @Test func logCreatesAdditionalParticipantsInTheSameWrite() throws {
        let (store, _) = try makeStore()
        let contact = ContactSummary(identifier: "C-1", name: "Contact One")
        let id = try store.logEvent(EventDraft(title: "X", format: .liveMeeting, start: day(2026, 1, 1),
                                               additionalParticipants: [.contact(contact), .named("New One")]))
        #expect(try store.event(id).participants.map(\.name) == ["Contact One", "New One"])
        // the contact's person is reused afterwards
        let again = try store.ensurePerson(for: contact)
        #expect(try store.history(of: again).map(\.id) == [id])
        #expect(try store.persons().count == 2)
    }

    @Test func failedUpdateLeavesEventAndPeopleUnchanged() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        let id = try store.logEvent(EventDraft(title: "Old", format: .phoneCall, start: day(2026, 1, 10), participants: [a]))
        #expect(throws: CXError.self) {
            try store.updateEvent(id, EventChange(title: "New", end: day(2026, 1, 1), participants: [], additionalParticipants: [.named("Ghost")]))
        }
        _ = try store.createPerson(name: "B")
        #expect(try store.event(id).title == "Old")
        #expect(try store.event(id).participants.map(\.name) == ["A"])
        #expect(try store.persons().map(\.name) == ["A", "B"])
    }
}
