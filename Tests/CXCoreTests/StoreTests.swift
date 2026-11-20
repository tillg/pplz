import Foundation
import Testing
@testable import CXCore

/// Every test works on its own real store in a temporary file.
func makeStore() throws -> (CXStore, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cx-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("test.store")
    return (try CXStore(url: url), url)
}

func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = h
    c.timeZone = TimeZone(identifier: "UTC")
    return Calendar(identifier: .gregorian).date(from: c)!
}

@Suite struct PersonTests {
    @Test func createsCXOnlyPerson() throws {
        let (store, _) = try makeStore()
        let id = try store.createPerson(name: "  Test Person  ")
        let persons = try store.persons()
        #expect(persons.count == 1)
        #expect(persons[0].id == id)
        #expect(persons[0].name == "Test Person")
        #expect(persons[0].contactIdentifier == nil)
    }

    @Test func rejectsEmptyName() throws {
        let (store, _) = try makeStore()
        #expect(throws: CXError.self) { try store.createPerson(name: "   ") }
    }

    @Test func ensurePersonForContactIsIdempotent() throws {
        let (store, _) = try makeStore()
        let contact = ContactSummary(identifier: "C-1", name: "Contact One")
        let first = try store.ensurePerson(for: contact)
        let second = try store.ensurePerson(for: contact)
        #expect(first == second)
        #expect(try store.persons().count == 1)
        #expect(try store.persons()[0].contactIdentifier == "C-1")
    }

    @Test func storesNotesAndHowWeMet() throws {
        let (store, _) = try makeStore()
        let id = try store.createPerson(name: "A")
        try store.setNotes("likes sailing", for: id)
        try store.setHowWeMet("at the fair", for: id)
        let p = try store.person(id)
        #expect(p.notes == "likes sailing")
        #expect(p.howWeMet == "at the fair")
    }

    @Test func unknownPersonThrows() throws {
        let (store, _) = try makeStore()
        #expect(throws: CXError.self) { try store.person(UUID()) }
    }

    @Test func tagsAreCaseInsensitiveAndIdempotent() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        let b = try store.createPerson(name: "B")
        try store.addTag("Client", toPerson: a)
        try store.addTag("client ", toPerson: a)
        try store.addTag("CLIENT", toPerson: b)
        #expect(try store.person(a).tags == ["Client"])
        #expect(try store.person(b).tags == ["Client"])
        #expect(try store.tags() == [TagSummary(name: "Client", personCount: 2, eventCount: 0)])
        try store.removeTag("client", fromPerson: a)
        #expect(try store.person(a).tags == [])
        #expect(try store.person(b).tags == ["Client"])
    }
}

@Suite struct EventTests {
    @Test func logsEventAndBuildsHistoryNewestFirst() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        let b = try store.createPerson(name: "B")
        let old = try store.logEvent(EventDraft(title: "Kickoff", format: .webCall, start: day(2026, 10, 3), participants: [a, b]))
        let new = try store.logEvent(EventDraft(title: "Dinner", format: .liveMeeting, start: day(2026, 11, 12), place: "Köln", participants: [a]))

        let historyA = try store.history(of: a)
        #expect(historyA.map(\.id) == [new, old])
        #expect(historyA[0].place == "Köln")
        #expect(historyA[0].format == .liveMeeting)
        #expect(historyA[1].participants.map(\.name) == ["A", "B"])
        #expect(try store.history(of: b).map(\.id) == [old])

        let pa = try store.person(a)
        #expect(pa.eventCount == 2)
        #expect(pa.lastMet == day(2026, 11, 12))
    }

    @Test func endIsOptionalButMustNotPrecedeStart() throws {
        let (store, _) = try makeStore()
        let id = try store.logEvent(EventDraft(title: "Conf", format: .largerGathering, start: day(2026, 5, 1), end: day(2026, 5, 3)))
        #expect(try store.event(id).end == day(2026, 5, 3))
        #expect(throws: CXError.self) {
            try store.logEvent(EventDraft(title: "Bad", format: .phoneCall, start: day(2026, 5, 3), end: day(2026, 5, 1)))
        }
    }

    @Test func unknownParticipantIsRejectedAndNothingIsSaved() throws {
        let (store, _) = try makeStore()
        #expect(throws: CXError.self) {
            try store.logEvent(EventDraft(title: "X", format: .phoneCall, start: day(2026, 1, 1), participants: [UUID()]))
        }
        #expect(try store.events().isEmpty)
    }

    @Test func filtersEvents() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        let b = try store.createPerson(name: "B")
        let e1 = try store.logEvent(EventDraft(title: "One", format: .phoneCall, start: day(2026, 1, 10), participants: [a]))
        let e2 = try store.logEvent(EventDraft(title: "Two", format: .liveMeeting, start: day(2026, 3, 10), place: "Frankfurt am Main", participants: [a, b], tags: ["work"]))
        let e3 = try store.logEvent(EventDraft(title: "Three", format: .liveMeeting, start: day(2026, 6, 10), place: "Berlin", participants: [b]))

        #expect(try store.events().map(\.id) == [e3, e2, e1])
        #expect(try store.events(EventFilter(person: a)).map(\.id) == [e2, e1])
        #expect(try store.events(EventFilter(format: .liveMeeting)).map(\.id) == [e3, e2])
        #expect(try store.events(EventFilter(since: day(2026, 2, 1), until: day(2026, 4, 1))).map(\.id) == [e2])
        #expect(try store.events(EventFilter(place: "frankfurt")).map(\.id) == [e2])
        #expect(try store.events(EventFilter(tag: "WORK")).map(\.id) == [e2])
    }

    @Test func updatesEvent() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        let b = try store.createPerson(name: "B")
        let id = try store.logEvent(EventDraft(title: "Old", format: .phoneCall, start: day(2026, 1, 10), participants: [a]))
        try store.updateEvent(id, EventChange(title: "New", format: .webCall, place: "Online", notes: "talked", participants: [b]))
        let e = try store.event(id)
        #expect(e.title == "New")
        #expect(e.format == .webCall)
        #expect(e.place == "Online")
        #expect(e.notes == "talked")
        #expect(e.start == day(2026, 1, 10))
        #expect(e.participants.map(\.name) == ["B"])
        #expect(try store.history(of: a).isEmpty)
    }

    @Test func deletingEventRemovesItFromHistoryAndDropsFollowUps() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        let id = try store.logEvent(EventDraft(title: "X", format: .phoneCall, start: day(2026, 1, 10), participants: [a]))
        _ = try store.addFollowUp("send book title", toEvent: id)
        try store.deleteEvent(id)
        #expect(try store.history(of: a).isEmpty)
        #expect(try store.openFollowUps().isEmpty)
        #expect(try store.person(a).eventCount == 0)
    }

    @Test func followUpsCanBeAddedAndCompleted() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        let id = try store.logEvent(EventDraft(title: "X", format: .phoneCall, start: day(2026, 1, 10), participants: [a]))
        let f1 = try store.addFollowUp("send book title", toEvent: id)
        let f2 = try store.addFollowUp("intro to B", toEvent: id)
        #expect(try store.event(id).followUps.map(\.text) == ["send book title", "intro to B"])
        try store.completeFollowUp(f1)
        let open = try store.openFollowUps()
        #expect(open.map(\.id) == [f2])
        #expect(open[0].eventID == id)
        #expect(open[0].eventTitle == "X")
        #expect(try store.event(id).followUps.first { $0.id == f1 }?.done == true)
    }

    @Test func dataSurvivesReopeningTheStore() throws {
        let (store, url) = try makeStore()
        let a = try store.createPerson(name: "A")
        let id = try store.logEvent(EventDraft(title: "X", format: .phoneCall, start: day(2026, 1, 10), participants: [a], tags: ["t"]))
        let reopened = try CXStore(url: url)
        #expect(try reopened.history(of: a).map(\.id) == [id])
        #expect(try reopened.event(id).tags == ["t"])
    }
}
