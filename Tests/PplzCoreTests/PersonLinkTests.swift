#if os(macOS)
import Foundation
import Testing
@testable import PplzCore

@Suite struct PersonLinkTests {
    @Test func linkRoundTrips() {
        let id = UUID()
        let link = PersonLink.url(for: id)
        #expect(link == "pplz://person/\(id.uuidString.lowercased())")
        #expect(PersonLink.personID(from: URL(string: link)!) == id)
        #expect(PersonLink.personID(from: URL(string: "pplz://person/\(id.uuidString)")!) == id)
    }

    @Test func foreignLinksAreIgnored() {
        #expect(PersonLink.personID(from: URL(string: "https://example.com/person/\(UUID().uuidString)")!) == nil)
        #expect(PersonLink.personID(from: URL(string: "pplz://event/\(UUID().uuidString)")!) == nil)
        #expect(PersonLink.personID(from: URL(string: "pplz://person/not-an-id")!) == nil)
    }

    @Test func plansALinkForEveryLinkedPersonOnly() throws {
        let (store, _) = try makeStore()
        let anna = try store.ensurePerson(for: ContactSummary(identifier: "C-A", name: "Anna"))
        let only = try store.createPerson(name: "Only In Pplz")
        #expect(try ContactsSync.linkPlan(store, persons: [anna, only, anna]) == [
            ContactMirror.Row(contactIdentifier: "C-A", label: "pplz", value: PersonLink.url(for: anna)),
        ])
    }

    @Test func journalTellsFieldsApart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pplz-journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let journal = ContactJournal(url: dir.appendingPathComponent("j.jsonl"))
        let row = ContactMirror.Row(contactIdentifier: "C-A", label: "pplz", value: "pplz://person/x")
        try journal.record(.added, row, field: "url")
        #expect(try journal.pplzAdded(row, field: "url"))
        #expect(try journal.pplzAdded(row) == false)   // not a related name
    }
}
#endif
