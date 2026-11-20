import Foundation
import Testing
@testable import PplzCore

@Suite struct CardPresentationTests {
    func card(name: String, contact: ContactDetails?) -> PersonCard {
        PersonCard(entry: PersonEntry(id: nil, contactIdentifier: contact?.identifier, name: name, eventCount: 0, lastMet: nil, tags: []),
                   contact: contact, stored: nil, connections: [], history: [])
    }

    /// The contact's own related names are shown too; the ones pplz mirrored from a connection only once.
    @Test func relatedNamesOfTheContactAreListedUnlessAConnectionCoversThem() {
        var c = card(name: "Anna Example", contact: ContactDetails(identifier: "C", relatedNames: [
            LabeledValue(label: "spouse", value: "Eva Example"), LabeledValue(label: "colleague", value: " ben example "),
            LabeledValue(label: "friend", value: ""),
        ]))
        c.connections = [ConnectionSnapshot(id: UUID(), kind: "colleague", other: PersonRef(id: UUID(), name: "Ben Example"), direction: .outgoing)]
        #expect(c.relatedNamesOnlyInContacts == [LabeledValue(label: "spouse", value: "Eva Example")])
        #expect(card(name: "Zoe", contact: nil).relatedNamesOnlyInContacts.isEmpty)
    }

    @Test func nicknameIsTheTitleAndTheFullNameMovesBelow() {
        let c = card(name: "Anna Example", contact: ContactDetails(identifier: "C", givenName: "Anna", familyName: "Example",
                                                                   nickname: "Annie", organization: "Example GmbH", jobTitle: "CTO"))
        #expect(c.title == "Annie")
        #expect(c.subtitle == "Anna Example · CTO · Example GmbH")
    }

    @Test func withoutNicknameTheNameIsTheTitle() {
        let c = card(name: "Anna Example", contact: ContactDetails(identifier: "C", organization: "Example GmbH"))
        #expect(c.title == "Anna Example")
        #expect(c.subtitle == "Example GmbH")
        #expect(card(name: "Only Here", contact: nil).title == "Only Here")
        #expect(card(name: "Only Here", contact: nil).subtitle == "")
    }

    @Test func nicknameIsPartOfTheTextOutput() {
        let details = ContactDetails(identifier: "C", givenName: "Anna", nickname: "Annie")
        #expect(details.lines == ["First name: Anna", "Nickname: Annie"])
    }

    @Test func pictureIsNotPartOfTheJSON() throws {
        let details = ContactDetails(identifier: "C", nickname: "Annie", imageData: Data([1, 2, 3]))
        let json = String(decoding: try JSONEncoder().encode(details), as: UTF8.self)
        #expect(json.contains("\"nickname\":\"Annie\""))
        #expect(!json.contains("imageData"))
    }

    @Test func actionLinks() {
        #expect(ContactAction.call.url(for: "+49 (89) 489 00-359")?.absoluteString == "tel:+498948900359")
        #expect(ContactAction.message.url(for: "+49 170 0000000")?.absoluteString == "sms:+491700000000")
        #expect(ContactAction.video.url(for: "+49 170 0000000")?.absoluteString == "facetime:+491700000000")
        #expect(ContactAction.mail.url(for: " anna@example.com ")?.absoluteString == "mailto:anna@example.com")
        #expect(ContactAction.map.url(for: "Musterstr. 1, 50667 Köln")?.absoluteString == "maps://?q=Musterstr.%201,%2050667%20K%C3%B6ln")
        #expect(ContactAction.web.url(for: "example.com/page")?.absoluteString == "https://example.com/page")
        #expect(ContactAction.web.url(for: "pplz://person/x")?.absoluteString == "pplz://person/x")
        #expect(ContactAction.call.url(for: "   ") == nil)
    }
}
