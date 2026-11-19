import Foundation
import Testing
@testable import PplzCore

/// A person first recorded on the iPad arrives on the Mac with the iPad's contact identifier and
/// without a link in the contact (only the Mac can write it). It must still be recognised as the
/// contact it belongs to — by name — instead of showing up a second time.
@Suite struct ForeignPersonTests {
    let paul = UUID()
    var fromIPad: PersonSnapshot { PersonSnapshot(id: paul, name: "Paul Beittel", contactIdentifier: "IPAD-7", tags: ["Tps"]) }

    @Test func aPersonFromAnotherDeviceIsMatchedToTheContactOfTheSameName() {
        let contacts = [ContactSummary(identifier: "MAC-1", name: "Paul Beittel"), ContactSummary(identifier: "MAC-2", name: "Karin Beittel")]
        let entries = PeopleDirectory.merge(contacts: contacts, persons: [fromIPad])
        #expect(entries.map(\.name) == ["Karin Beittel", "Paul Beittel"])
        #expect(entries[1].id == paul)
        #expect(entries[1].contactIdentifier == "MAC-1")
        #expect(entries[1].tags == ["Tps"])
    }

    @Test func caseAndSurroundingSpacesDoNotMatter() {
        let entries = PeopleDirectory.merge(contacts: [ContactSummary(identifier: "MAC-1", name: " paul beittel ")], persons: [fromIPad])
        #expect(entries.count == 1)
        #expect(entries[0].id == paul)
    }

    @Test func twoContactsOfThatNameAreNotGuessedAt() {
        let contacts = [ContactSummary(identifier: "MAC-1", name: "Paul Beittel"), ContactSummary(identifier: "MAC-2", name: "Paul Beittel")]
        let entries = PeopleDirectory.merge(contacts: contacts, persons: [fromIPad])
        #expect(entries.count == 3)
        #expect(entries.filter { $0.id == paul }.map(\.contactIdentifier) == ["IPAD-7"])
    }

    @Test func twoPersonsOfThatNameAreNotGuessedAt() {
        let other = PersonSnapshot(id: UUID(), name: "Paul Beittel", contactIdentifier: "IPHONE-3")
        let entries = PeopleDirectory.merge(contacts: [ContactSummary(identifier: "MAC-1", name: "Paul Beittel")], persons: [fromIPad, other])
        #expect(entries.count == 3)
        #expect(entries.first { $0.contactIdentifier == "MAC-1" }?.id == nil)
    }

    @Test func aContactThatAlreadyHasItsPersonIsNotTakenOver() {
        let own = PersonSnapshot(id: UUID(), name: "Paul Beittel", contactIdentifier: "MAC-1")
        let entries = PeopleDirectory.merge(contacts: [ContactSummary(identifier: "MAC-1", name: "Paul Beittel")], persons: [own, fromIPad])
        #expect(entries.count == 2)
        #expect(entries.first { $0.contactIdentifier == "MAC-1" }?.id == own.id)
    }

    @Test func aPplzOnlyPersonStaysSeparateFromAContactOfTheSameName() {
        let only = PersonSnapshot(id: UUID(), name: "Paul Beittel")
        let entries = PeopleDirectory.merge(contacts: [ContactSummary(identifier: "MAC-1", name: "Paul Beittel")], persons: [only])
        #expect(entries.count == 2)
    }

    /// The Mac then takes the person over: it stores its own identifier, so that the link,
    /// history and relationships can be written into the right contact.
    @Test func personsMatchedToAnotherIdentifierAreListedForAdoption() {
        let linked = UUID(), settled = UUID()
        let contacts = [ContactSummary(identifier: "MAC-1", name: "Paul Beittel"),
                        ContactSummary(identifier: "MAC-2", name: "Achim Botz", pplzPersonID: linked),
                        ContactSummary(identifier: "MAC-3", name: "Till Gartner")]
        let persons = [fromIPad,
                       PersonSnapshot(id: linked, name: "Achim Botz", contactIdentifier: "IPHONE-9"),
                       PersonSnapshot(id: settled, name: "Till Gartner", contactIdentifier: "MAC-3"),
                       PersonSnapshot(id: UUID(), name: "Only Pplz")]
        let adoptions = PeopleDirectory.adoptions(in: PeopleDirectory.merge(contacts: contacts, persons: persons), persons: persons)
        #expect(adoptions == [PeopleDirectory.Adoption(person: linked, contactIdentifier: "MAC-2"),
                              PeopleDirectory.Adoption(person: paul, contactIdentifier: "MAC-1")])
    }

    @Test func theStoreTakesTheNewIdentifier() throws {
        let (store, _) = try makeStore()
        let id = try store.ensurePerson(for: ContactSummary(identifier: "IPAD-7", name: "Paul Beittel"))
        try store.setContactIdentifier("MAC-1", for: id)
        #expect(try store.person(id).contactIdentifier == "MAC-1")
        #expect(try store.ensurePerson(for: ContactSummary(identifier: "MAC-1", name: "Paul Beittel")) == id)
    }
}
