import Foundation
import Testing
@testable import PplzCore

@Suite struct ConnectionTests {
    @Test func connectsPeopleAndShowsBothDirections() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        let b = try store.createPerson(name: "B")
        try store.connect(a, to: b, kind: " colleague of ")

        let fromA = try store.connections(of: a)
        #expect(fromA.count == 1)
        #expect(fromA[0].kind == "colleague of")
        #expect(fromA[0].other == PersonRef(id: b, name: "B"))
        #expect(fromA[0].direction == .outgoing)

        let fromB = try store.connections(of: b)
        #expect(fromB.map(\.other.name) == ["A"])
        #expect(fromB[0].direction == .incoming)
    }

    @Test func sameConnectionIsStoredOnce() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        let b = try store.createPerson(name: "B")
        try store.connect(a, to: b, kind: "colleague of")
        try store.connect(a, to: b, kind: "Colleague Of")
        try store.connect(a, to: b, kind: "introduced by")
        #expect(try store.connections(of: a).map(\.kind) == ["colleague of", "introduced by"])
    }

    @Test func rejectsSelfAndEmptyKind() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        let b = try store.createPerson(name: "B")
        #expect(throws: PplzError.self) { try store.connect(a, to: a, kind: "x") }
        #expect(throws: PplzError.self) { try store.connect(a, to: b, kind: "  ") }
        #expect(throws: PplzError.self) { try store.connect(a, to: UUID(), kind: "x") }
        #expect(try store.connections(of: a).isEmpty)
    }

    @Test func disconnectRemovesAllConnectionsBetweenTwoPeople() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        let b = try store.createPerson(name: "B")
        let c = try store.createPerson(name: "C")
        try store.connect(a, to: b, kind: "colleague of")
        try store.connect(b, to: a, kind: "introduced by")
        try store.connect(a, to: c, kind: "partner of")
        try store.disconnect(a, b)
        #expect(try store.connections(of: a).map(\.other.name) == ["C"])
        #expect(try store.connections(of: b).isEmpty)
    }
}

@Suite struct KeepInTouchTests {
    @Test func parsesIntervals() throws {
        #expect(try KeepInTouch.days("90") == 90)
        #expect(try KeepInTouch.days("10d") == 10)
        #expect(try KeepInTouch.days("2w") == 14)
        #expect(try KeepInTouch.days("3m") == 90)
        #expect(try KeepInTouch.days("1y") == 365)
        #expect(throws: PplzError.self) { try KeepInTouch.days("soon") }
        #expect(throws: PplzError.self) { try KeepInTouch.days("0") }
    }

    @Test func listsOverduePeopleMostOverdueFirst() {
        let now = day(2026, 11, 18)
        let fine = PersonSnapshot(id: UUID(), name: "Fine", lastMet: day(2026, 11, 1), keepInTouchDays: 30)
        let late = PersonSnapshot(id: UUID(), name: "Late", lastMet: day(2026, 9, 19), keepInTouchDays: 30)
        let later = PersonSnapshot(id: UUID(), name: "Later", lastMet: day(2026, 1, 18), keepInTouchDays: 90)
        let never = PersonSnapshot(id: UUID(), name: "Never", keepInTouchDays: 30)
        let noRhythm = PersonSnapshot(id: UUID(), name: "NoRhythm", lastMet: day(2020, 1, 1))

        let due = KeepInTouch.overdue([fine, late, later, never, noRhythm], now: now)
        #expect(due.map(\.person.name) == ["Never", "Later", "Late"])
        #expect(due[0].daysSinceLastMet == nil)
        #expect(due[1].daysSinceLastMet == 304)
        #expect(due[1].daysOverdue == 214)
        #expect(due[2].daysOverdue == 30)
    }

    @Test func storesAndClearsTheRhythm() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        try store.setKeepInTouch(days: 90, for: a)
        #expect(try store.person(a).keepInTouchDays == 90)
        try store.setKeepInTouch(days: nil, for: a)
        #expect(try store.person(a).keepInTouchDays == nil)
        #expect(throws: PplzError.self) { try store.setKeepInTouch(days: 0, for: a) }
    }
}

@Suite struct EventLinkTests {
    @Test func eventsCarryLinks() throws {
        let (store, url) = try makeStore()
        let id = try store.logEvent(EventDraft(title: "Call", format: .webCall, start: day(2026, 1, 1),
                                               links: ["https://example.com/meet", " https://example.com/doc "]))
        #expect(try store.event(id).links == ["https://example.com/meet", "https://example.com/doc"])
        try store.updateEvent(id, EventChange(links: ["https://example.com/only"]))
        #expect(try PplzStore(url: url).event(id).links == ["https://example.com/only"])
        #expect(throws: PplzError.self) { try store.updateEvent(id, EventChange(links: ["not a link"])) }
    }
}

@Suite struct ReplaceTagsTests {
    @Test func replacesAPersonsTags() throws {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        try store.addTag("old", toPerson: a)
        try store.setTags([" Client ", "sailing", "client", ""], forPerson: a)
        #expect(try store.person(a).tags == ["Client", "sailing"])
        try store.setTags([], forPerson: a)
        #expect(try store.person(a).tags == [])
        #expect(try store.tags().isEmpty)
    }
}
