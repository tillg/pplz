import Foundation
import Testing
@testable import PplzCore

/// A person known to pplz only can be given a card in Contacts. Contacts wants first and last name apart.
@Suite struct NewContactNameTests {
    @Test func theLastWordIsTheFamilyName() {
        #expect(SystemContacts.nameParts("Mai Nguyen") == .init(given: "Mai", family: "Nguyen"))
        #expect(SystemContacts.nameParts("  Anna  Maria   Example ") == .init(given: "Anna Maria", family: "Example"))
    }

    @Test func aSingleWordIsTheGivenName() {
        #expect(SystemContacts.nameParts("Mai") == .init(given: "Mai", family: ""))
    }
}
