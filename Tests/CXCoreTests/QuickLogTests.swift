import Foundation
import Testing
@testable import CXCore

/// "Who?" in the quick log: two typed letters should be enough to find the person.
@Suite struct PersonSuggestionTests {
    static func entry(_ key: String, _ name: String, nickname: String = "", met: Date? = nil) -> PersonEntry {
        PersonEntry(id: met == nil ? nil : UUID(), contactIdentifier: key, name: name, eventCount: met == nil ? 0 : 1,
                    lastMet: met, tags: [], nickname: nickname)
    }

    let entries = [
        entry("C-1", "Achim Botz", nickname: "Aki"),
        entry("C-2", "Anna Example", met: day(2026, 11, 12)),
        entry("C-3", "Ben Sample", met: day(2026, 11, 17)),
        entry("C-4", "Hannah Bach"),
        entry("C-5", "Émile Dupont", met: day(2026, 10, 1)),
    ]

    func names(_ query: String, excluding: Set<String> = [], limit: Int = 5) -> [String] {
        PeopleDirectory.suggestions(for: query, in: entries, excluding: excluding, limit: limit).map(\.name)
    }

    @Test func withoutTypingThePeopleMetMostRecentlyAreOffered() {
        #expect(names("") == ["Ben Sample", "Anna Example", "Émile Dupont"])
    }

    @Test func aWordThatStartsWithTheTextComesBeforeOneThatContainsIt() {
        // "an": Anna (first name starts with it) before Hannah (contains it)
        #expect(names("an") == ["Anna Example", "Hannah Bach"])
        // "b": Ben, then the family names Bach and Botz — people already met first, then by name
        #expect(names("b") == ["Ben Sample", "Achim Botz", "Hannah Bach"])
    }

    @Test func nicknamesCaseAndAccentsWork() {
        #expect(names("aki") == ["Achim Botz"])
        #expect(names("EMI") == ["Émile Dupont"])
    }

    @Test func chosenPeopleAreNotOfferedAgainAndTheListIsLimited() {
        #expect(names("", excluding: ["C-3"]) == ["Anna Example", "Émile Dupont"])
        #expect(names("a", limit: 2).count == 2)
        #expect(names("zzz") == [])
    }
}

/// After a gathering some of the people are new: they can be added by name while logging.
@Suite struct NewPersonOfferTests {
    let entries = [PersonSuggestionTests.entry("C-1", "Achim Botz", nickname: "Aki"), PersonSuggestionTests.entry("C-2", "Anna Example")]

    @Test func aNameNobodyHasCanBeCreated() {
        #expect(PeopleDirectory.newPersonName(for: "  Mai   Nguyen ", in: entries, chosen: []) == "Mai Nguyen")
    }

    @Test func nothingIsOfferedForAnExistingNameWhateverTheCase() {
        #expect(PeopleDirectory.newPersonName(for: "anna example", in: entries, chosen: []) == nil)
        #expect(PeopleDirectory.newPersonName(for: "ÁCHIM BOTZ", in: entries, chosen: []) == nil)
    }

    @Test func nothingIsOfferedForANameAlreadyChosenOrTooShort() {
        #expect(PeopleDirectory.newPersonName(for: "Mai Nguyen", in: entries, chosen: ["mai nguyen"]) == nil)
        #expect(PeopleDirectory.newPersonName(for: " ", in: entries, chosen: []) == nil)
        #expect(PeopleDirectory.newPersonName(for: "M", in: entries, chosen: []) == nil)
    }

    @Test func partOfAnExistingNameCanStillBecomeANewPerson() {
        #expect(PeopleDirectory.newPersonName(for: "Anna", in: entries, chosen: []) == "Anna")
    }
}
