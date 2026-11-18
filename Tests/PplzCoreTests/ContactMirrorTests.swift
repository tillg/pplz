import Foundation
import Testing
@testable import PplzCore

@Suite struct ContactMirrorTests {
    let a = ContactMirror.Party(name: "Anna Example", contactIdentifier: "C-A")
    let b = ContactMirror.Party(name: "Ben Sample", contactIdentifier: "C-B")

    // Rows carry Apple's own relationship labels where one exists, so Contacts shows them
    // like the ones picked from its menu (and translates them).
    let colleague = "_$!<Colleague>!$_"

    @Test func symmetricKindAppearsOnBothCards() {
        // "Anna — colleague of — Ben"
        #expect(ContactMirror.rows(from: a, kind: "colleague of", to: b) == [
            ContactMirror.Row(contactIdentifier: "C-B", label: colleague, value: "Anna Example"),
            ContactMirror.Row(contactIdentifier: "C-A", label: colleague, value: "Ben Sample"),
        ])
        #expect(ContactMirror.rows(from: a, kind: " Partner Of ", to: b).map(\.label) == ["_$!<Partner>!$_", "_$!<Partner>!$_"])
        #expect(ContactMirror.rows(from: a, kind: "friend of", to: b).map(\.label) == ["_$!<Friend>!$_", "_$!<Friend>!$_"])
    }

    @Test func familyAndWorkRolesGetTheMatchingRowOnTheOtherCard() {
        // "Anna — mother of — Ben": on Ben's card Anna is his mother, on Anna's card Ben is her child
        #expect(ContactMirror.rows(from: a, kind: "mother of", to: b) == [
            ContactMirror.Row(contactIdentifier: "C-B", label: "_$!<Mother>!$_", value: "Anna Example"),
            ContactMirror.Row(contactIdentifier: "C-A", label: "_$!<Child>!$_", value: "Ben Sample"),
        ])
        #expect(ContactMirror.rows(from: a, kind: "daughter of", to: b).map(\.label) == ["_$!<Daughter>!$_", "_$!<Parent>!$_"])
        #expect(ContactMirror.rows(from: a, kind: "sister of", to: b).map(\.label) == ["_$!<Sister>!$_", "_$!<Sibling>!$_"])
        #expect(ContactMirror.rows(from: a, kind: "assistant of", to: b).map(\.label) == ["_$!<Assistant>!$_", "_$!<Manager>!$_"])
    }

    @Test func rolesWithoutAClearCounterpartAppearOnOneCardOnly() {
        // Ben's manager is Anna — but that does not make Ben her assistant
        #expect(ContactMirror.rows(from: a, kind: "manager of", to: b) == [
            ContactMirror.Row(contactIdentifier: "C-B", label: "_$!<Manager>!$_", value: "Anna Example"),
        ])
        #expect(ContactMirror.rows(from: a, kind: "other of", to: b).map(\.label) == ["_$!<Other>!$_"])
        #expect(ContactMirror.rows(from: a, kind: "mentor of", to: b) == [
            ContactMirror.Row(contactIdentifier: "C-B", label: "mentor", value: "Anna Example"),
        ])
    }

    @Test func otherKindsAppearOnTheFirstPersonsCard() {
        // "Anna — introduced by — Ben": on Anna's card
        #expect(ContactMirror.rows(from: a, kind: "introduced by", to: b) == [
            ContactMirror.Row(contactIdentifier: "C-A", label: "introduced by", value: "Ben Sample"),
        ])
    }

    @Test func rowsWrittenBeforeAppleLabelsWereUsedAreStillFound() {
        // older versions wrote the plain word; disconnecting must still be able to remove those
        #expect(ContactMirror.legacyRows(from: a, kind: "colleague of", to: b) == [
            ContactMirror.Row(contactIdentifier: "C-B", label: "colleague", value: "Anna Example"),
            ContactMirror.Row(contactIdentifier: "C-A", label: "colleague", value: "Ben Sample"),
        ])
    }

    @Test func appleRelationshipListAndDisplay() {
        #expect(ContactMirror.appleRoles == ["mother", "father", "parent", "son", "daughter", "brother", "sister", "child",
                                             "friend", "spouse", "partner", "assistant", "manager", "other"])
        let ben = PersonRef(id: UUID(), name: "Ben Sample")
        // on Anna's card: stored as "Ben — manager of — Anna", shown as in Contacts: "manager · Ben"
        #expect(ConnectionSnapshot(id: UUID(), kind: "manager of", other: ben, direction: .incoming).displayLabel == "manager")
        #expect(ConnectionSnapshot(id: UUID(), kind: "manager of", other: ben, direction: .outgoing).displayLabel == "manager of")
        #expect(ConnectionSnapshot(id: UUID(), kind: "introduced by", other: ben, direction: .outgoing).displayLabel == "introduced by")
        #expect(ConnectionSnapshot(id: UUID(), kind: "introduced by", other: ben, direction: .incoming).displayLabel == "introduced by (from them)")
    }

    @Test func peopleWithoutContactGetNoRow() {
        let only = ContactMirror.Party(name: "Only Here", contactIdentifier: nil)
        #expect(ContactMirror.rows(from: a, kind: "colleague of", to: only) == [
            ContactMirror.Row(contactIdentifier: "C-A", label: colleague, value: "Only Here"),
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
