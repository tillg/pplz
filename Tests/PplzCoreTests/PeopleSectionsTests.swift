import Foundation
import Testing
@testable import PplzCore

@Suite struct PeopleSectionsTests {
    func entry(_ name: String, tags: [String] = [], contact: String? = "C") -> PersonEntry {
        PersonEntry(id: nil, contactIdentifier: contact.map { $0 + name }, name: name, eventCount: 0, lastMet: nil, tags: tags)
    }

    @Test func groupsByFirstLetterLikeContacts() {
        let sections = PeopleSections.make([entry("anna"), entry("Ärmel"), entry("Ben"), entry("Émile"), entry("42 GmbH"), entry("ben two"), entry("#tag")])
        #expect(sections.map(\.title) == ["A", "B", "E", "#"])
        #expect(sections[0].entries.map(\.name) == ["anna", "Ärmel"])
        #expect(sections[1].entries.map(\.name) == ["Ben", "ben two"])
        #expect(sections[3].entries.map(\.name) == ["#tag", "42 GmbH"])
    }

    @Test func searchMatchesNamesAndTagsIgnoringCaseAndAccents() {
        let all = [entry("Jörg Müller"), entry("Anna", tags: ["Client"]), entry("Ben")]
        #expect(PeopleSections.make(all, search: "muller").flatMap(\.entries).map(\.name) == ["Jörg Müller"])
        #expect(PeopleSections.make(all, search: "client").flatMap(\.entries).map(\.name) == ["Anna"])
        #expect(PeopleSections.make(all, search: "  ").flatMap(\.entries).count == 3)
        #expect(PeopleSections.make(all, search: "zzz").isEmpty)
    }

    @Test func everyEntryHasAStableKeyForSelection() {
        let id = UUID()
        #expect(PersonEntry(id: id, contactIdentifier: "C-1", name: "A", eventCount: 0, lastMet: nil, tags: []).key == "C-1")
        #expect(PersonEntry(id: id, contactIdentifier: nil, name: "A", eventCount: 0, lastMet: nil, tags: []).key == id.uuidString)
    }

    @Test func initialsForTheAvatar() {
        #expect(PeopleSections.initials("Anna Example") == "AE")
        #expect(PeopleSections.initials("  till ") == "T")
        #expect(PeopleSections.initials("Hans Peter von Beispiel") == "HB")
        #expect(PeopleSections.initials("42 GmbH") == "4G")
        #expect(PeopleSections.initials("") == "")
    }
}
