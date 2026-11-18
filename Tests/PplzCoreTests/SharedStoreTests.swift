import Foundation
import Testing
@testable import PplzCore

/// The app keeps one store open while the CLI writes to the same file.
@Suite struct SharedStoreTests {
    @Test func aLongLivedStoreSeesChangesMadeThroughAnotherOne() throws {
        let (app, url) = try makeStore()
        let cli = try PplzStore(url: url)

        let person = try cli.createPerson(name: "A")
        let event = try cli.logEvent(EventDraft(title: "Old", format: .phoneCall, start: day(2026, 1, 1), participants: [person]))

        // the app loads everything once …
        #expect(try app.event(event).title == "Old")
        #expect(try app.person(person).eventCount == 1)
        #expect(try app.persons().count == 1)

        // … then the CLI changes, adds and deletes
        try cli.updateEvent(event, EventChange(title: "New"))
        try cli.setNotes("note from cli", for: person)
        let second = try cli.logEvent(EventDraft(title: "Second", format: .webCall, start: day(2026, 2, 1), participants: [person]))
        _ = try cli.createPerson(name: "B")

        // … and the app must see all of it on its next read
        #expect(try app.event(event).title == "New")
        #expect(try app.person(person).notes == "note from cli")
        #expect(try app.person(person).eventCount == 2)
        #expect(try app.history(of: person).map(\.id) == [second, event])
        #expect(try app.persons().map(\.name) == ["A", "B"])

        try cli.deleteEvent(second)
        #expect(try app.history(of: person).map(\.id) == [event])
    }
}
