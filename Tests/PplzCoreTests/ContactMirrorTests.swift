import Foundation
import Testing
@testable import PplzCore

@Suite struct ContactMirrorTests {
    let a = ContactMirror.Party(name: "Anna Example", contactIdentifier: "C-A")
    let b = ContactMirror.Party(name: "Ben Sample", contactIdentifier: "C-B")

    @Test func symmetricKindAppearsOnBothCards() {
        // "Anna — colleague of — Ben"
        #expect(ContactMirror.rows(from: a, kind: "colleague of", to: b) == [
            ContactMirror.Row(contactIdentifier: "C-B", label: "colleague", value: "Anna Example"),
            ContactMirror.Row(contactIdentifier: "C-A", label: "colleague", value: "Ben Sample"),
        ])
        #expect(ContactMirror.rows(from: a, kind: " Partner Of ", to: b).map(\.label) == ["Partner", "Partner"])
    }

    @Test func roleKindAppearsOnTheOtherPersonsCardOnly() {
        // "Anna — mother of — Ben": on Ben's card, Anna is his mother
        #expect(ContactMirror.rows(from: a, kind: "mother of", to: b) == [
            ContactMirror.Row(contactIdentifier: "C-B", label: "mother", value: "Anna Example"),
        ])
    }

    @Test func otherKindsAppearOnTheFirstPersonsCard() {
        // "Anna — introduced by — Ben": on Anna's card
        #expect(ContactMirror.rows(from: a, kind: "introduced by", to: b) == [
            ContactMirror.Row(contactIdentifier: "C-A", label: "introduced by", value: "Ben Sample"),
        ])
    }

    @Test func peopleWithoutContactGetNoRow() {
        let only = ContactMirror.Party(name: "Only Here", contactIdentifier: nil)
        #expect(ContactMirror.rows(from: a, kind: "colleague of", to: only) == [
            ContactMirror.Row(contactIdentifier: "C-A", label: "colleague", value: "Only Here"),
        ])
        #expect(ContactMirror.rows(from: only, kind: "introduced by", to: b).isEmpty)
    }
}

@Suite struct ContactJournalTests {
    func makeJournal() throws -> ContactJournal {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pplz-journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ContactJournal(url: dir.appendingPathComponent("contact-writes.jsonl"))
    }

    let row = ContactMirror.Row(contactIdentifier: "C-B", label: "colleague", value: "Anna Example")

    @Test func knowsWhichRowsPplzAdded() throws {
        let journal = try makeJournal()
        #expect(try journal.pplzAdded(row) == false)
        try journal.record(.added, row, at: day(2026, 11, 18))
        #expect(try journal.pplzAdded(row))
        #expect(try journal.pplzAdded(ContactMirror.Row(contactIdentifier: "C-B", label: "spouse", value: "Anna Example")) == false)
        try journal.record(.removed, row, at: day(2026, 11, 19))
        #expect(try journal.pplzAdded(row) == false)
    }

    @Test func keepsEveryEntryInOrder() throws {
        let journal = try makeJournal()
        try journal.record(.added, row, at: day(2026, 11, 18))
        try journal.record(.removed, row, at: day(2026, 11, 19))
        let entries = try journal.entries()
        #expect(entries.map(\.action) == [.added, .removed])
        #expect(entries[0].field == "related name")
        #expect(entries[0].row == row)
        // survives a new instance on the same file
        #expect(try ContactJournal(url: journal.url).entries().count == 2)
    }
}
