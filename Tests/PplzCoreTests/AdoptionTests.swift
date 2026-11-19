import Foundation
import Testing
@testable import PplzCore

/// Contacts have no identifier that is the same on every device, so pplz brings its own: the
/// `pplz://person/<id>` link in the contact, written by whichever device records the person first.
/// Names are content, not identity (people marry, get renamed) and never decide a match.
@Suite struct ForeignPersonTests {
    let paul = UUID()
    var fromIPad: PersonSnapshot { PersonSnapshot(id: paul, name: "Paul Beittel", contactIdentifier: "IPAD-7", tags: ["Tps"]) }

    @Test func theSameNameAloneDoesNotMatchAPersonToAContact() {
        let entries = PeopleDirectory.merge(contacts: [ContactSummary(identifier: "MAC-1", name: "Paul Beittel")], persons: [fromIPad])
        #expect(entries.count == 2)
        #expect(entries.first { $0.contactIdentifier == "MAC-1" }?.id == nil)
    }

    @Test func theLinkMatchesWhateverTheNameIsNow() {
        let contacts = [ContactSummary(identifier: "MAC-1", name: "Paula Married", pplzPersonID: paul)]
        let entries = PeopleDirectory.merge(contacts: contacts, persons: [fromIPad])
        #expect(entries.count == 1)
        #expect(entries[0].id == paul)
        #expect(entries[0].name == "Paula Married")
        #expect(entries[0].tags == ["Tps"])
    }

    /// The Mac stores its own identifier for such a person, so that history and relationships
    /// can be written into the right contact.
    @Test func personsMatchedToAnotherIdentifierAreListedForAdoption() {
        let linked = UUID(), settled = UUID()
        let contacts = [ContactSummary(identifier: "MAC-1", name: "Paul Beittel", pplzPersonID: paul),
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
