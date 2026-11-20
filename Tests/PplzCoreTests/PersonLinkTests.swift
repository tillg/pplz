#if os(macOS)
import Foundation
import Testing
@testable import PplzCore

@Suite struct PersonLinkTests {
    @Test func linkRoundTrips() {
        let id = UUID()
        let link = PersonLink.url(for: id)
        #expect(link == "cx://person/\(id.uuidString.lowercased())")
        #expect(PersonLink.personID(from: URL(string: link)!) == id)
        #expect(PersonLink.personID(from: URL(string: "cx://person/\(id.uuidString)")!) == id)
    }

    @Test func anOldLinkGivesTheSamePersonID() {
        let id = UUID()
        #expect(PersonLink.personID(from: URL(string: "pplz://person/\(id.uuidString.lowercased())")!) == id)
        #expect(PersonLink.personID(from: URL(string: "pplz://person/\(id.uuidString)")!) == id)
    }

    @Test func theLinkIsWrittenWithTheNewLabel() {
        #expect(PersonLink.label == "cardxchange")
    }

    @Test func foreignLinksAreIgnored() {
        #expect(PersonLink.personID(from: URL(string: "https://example.com/person/\(UUID().uuidString)")!) == nil)
        #expect(PersonLink.personID(from: URL(string: "cx://event/\(UUID().uuidString)")!) == nil)
        #expect(PersonLink.personID(from: URL(string: "cx://person/not-an-id")!) == nil)
        #expect(PersonLink.personID(from: URL(string: "pplz://event/\(UUID().uuidString)")!) == nil)
    }

    @Test func plansALinkForEveryLinkedPersonOnly() throws {
        let (store, _) = try makeStore()
        let anna = try store.ensurePerson(for: ContactSummary(identifier: "C-A", name: "Anna"))
        let only = try store.createPerson(name: "Only In Pplz")
        #expect(try ContactsSync.linkPlan(store, persons: [anna, only, anna]) == [
            ContactMirror.Row(contactIdentifier: "C-A", label: "cardxchange", value: PersonLink.url(for: anna)),
        ])
    }

    @Test func journalTellsFieldsApart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pplz-journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let journal = ContactJournal(url: dir.appendingPathComponent("j.jsonl"))
        let row = ContactMirror.Row(contactIdentifier: "C-A", label: "cardxchange", value: "cx://person/x")
        try journal.record(.added, row, field: "url")
        #expect(try journal.pplzAdded(row, field: "url"))
        #expect(try journal.pplzAdded(row) == false)   // not a related name
    }
}

/// What the link rows of one contact need (`02-data-migration.md` §3.2): one row in the new form, no row in the old form.
@Suite struct LinkRepairTests {
    typealias Item = ContactEdit.Item
    let person = UUID(uuidString: "6F1C5A52-0000-4000-8000-000000000001")!
    let other = UUID(uuidString: "6F1C5A52-0000-4000-8000-000000000002")!

    var newRow: Item { Item(id: "N1", label: "cardxchange", value: "cx://person/6f1c5a52-0000-4000-8000-000000000001") }
    var oldRow: Item { Item(id: "O1", label: "pplz", value: "pplz://person/6f1c5a52-0000-4000-8000-000000000001") }
    var homePage: Item { Item(id: "H1", label: "_$!<HomePage>!$_", value: "https://example.com") }

    func added(_ changes: [ContactChange]) -> [Item] {
        changes.compactMap { if case .addItem(.url, let item) = $0 { item } else { nil } }
    }

    func removed(_ changes: [ContactChange]) -> [String] {
        changes.compactMap { if case .removeItem(.url, let item) = $0 { item.id } else { nil } }
    }

    @Test func noLinkGetsTheNewRow() {
        let changes = PersonLink.changes(urls: [homePage], person: person)
        #expect(added(changes).map(\.label) == ["cardxchange"])
        #expect(added(changes).map(\.value) == [PersonLink.url(for: person)])
        #expect(removed(changes).isEmpty)
    }

    @Test func oneNewRowNeedsNothing() {
        #expect(PersonLink.changes(urls: [homePage, newRow], person: person).isEmpty)
    }

    @Test func theValueDecidesNotTheLabel() {
        var relabelled = newRow
        relabelled.label = "_$!<HomePage>!$_"
        #expect(PersonLink.changes(urls: [relabelled], person: person).isEmpty)
        // also with upper-case letters in the ID
        let upper = Item(id: "U1", label: "cardxchange", value: "cx://person/6F1C5A52-0000-4000-8000-000000000001")
        #expect(PersonLink.changes(urls: [upper], person: person).isEmpty)
    }

    @Test func anOldRowIsReplaced() {
        let changes = PersonLink.changes(urls: [homePage, oldRow], person: person)
        #expect(added(changes).map(\.value) == [PersonLink.url(for: person)])
        #expect(removed(changes) == ["O1"])
    }

    @Test func anOldRowNextToANewRowIsRemoved() {
        let changes = PersonLink.changes(urls: [oldRow, newRow], person: person)
        #expect(added(changes).isEmpty)
        #expect(removed(changes) == ["O1"])
    }

    @Test func identicalNewRowsAreReducedToOne() {
        var second = newRow, third = newRow
        second.id = "N2"
        third.id = "N3"
        let changes = PersonLink.changes(urls: [newRow, second, third], person: person)
        #expect(added(changes).isEmpty)
        #expect(removed(changes) == ["N2", "N3"])
    }

    @Test func rowsThatAreNotALinkForThisPersonAreNeverTouched() {
        let othersNew = Item(id: "X1", label: "cardxchange", value: PersonLink.url(for: other))
        let othersOld = Item(id: "X2", label: "pplz", value: "pplz://person/\(other.uuidString.lowercased())")
        let changes = PersonLink.changes(urls: [homePage, othersNew, othersOld, newRow], person: person)
        #expect(changes.isEmpty)
    }

    /// An old value without the old label was not written by pplz (D13 needs both): it stays, and the new row is added.
    @Test func anOldValueWithAnotherLabelIsKept() {
        var typed = oldRow
        typed.label = "_$!<HomePage>!$_"
        let changes = PersonLink.changes(urls: [typed], person: person)
        #expect(added(changes).map(\.value) == [PersonLink.url(for: person)])
        #expect(removed(changes).isEmpty)
    }
}
#endif
