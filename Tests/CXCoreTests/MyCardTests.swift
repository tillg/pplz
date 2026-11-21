import Foundation
import Testing
@testable import CXCore

@Suite struct MyCardTests {
    typealias Item = ContactEdit.Item
    typealias Address = ContactEdit.Address

    private let home = Item(id: "P1", label: "_$!<Home>!$_", value: "+49 221 1111111")
    private let mobile = Item(id: "P2", label: "_$!<Mobile>!$_", value: "+49 170 0000000")
    private let iPhone = Item(id: "P3", label: "iPhone", value: "+49 171 0000000")
    private let privateMail = Item(id: "E1", label: "_$!<Home>!$_", value: "anna@example.org")
    private let workMail = Item(id: "E2", label: "_$!<Work>!$_", value: "anna@example.com")
    private let homepage = Item(id: "U1", label: "_$!<HomePage>!$_", value: "https://example.com")
    private let linkedInURL = Item(id: "U2", label: "", value: "https://www.linkedin.com/in/anna-example")
    private let twitter = Item(id: "S1", label: "Twitter", value: "https://twitter.com/anna")
    private let linkedIn = Item(id: "S2", label: "LinkedIn", value: "https://www.linkedin.com/in/anna-example")
    private let office = Address(id: "A1", label: "_$!<Work>!$_", street: "Musterstr. 1", postalCode: "50667", city: "Köln", country: "Germany")
    private let picture = Data([1, 2, 3])

    private func anna() -> ContactEdit {
        ContactEdit(givenName: "Anna", familyName: "Example", nickname: "Anni", organization: "Example GmbH", jobTitle: "CTO",
                    phones: [home, mobile, iPhone], emails: [privateMail, workMail], urls: [homepage, linkedInURL],
                    socialProfiles: [twitter, linkedIn], addresses: [office], birthday: .init(day: 17, month: 5, year: 1980),
                    contactIdentifier: "C1")
    }

    // MARK: default choice

    @Test func defaultCardHasNameCompanyJobOneMobileOneMailAndLinkedIn() {
        let card = MyCard.card(from: anna(), picture: picture, fields: MyCardFields())
        #expect(card.contact == ContactEdit(givenName: "Anna", familyName: "Example", organization: "Example GmbH", jobTitle: "CTO",
                                            phones: [mobile], emails: [privateMail], socialProfiles: [linkedIn]))
        #expect(card.picture == nil)
    }

    @Test func defaultPhoneIsAnIPhoneNumberWhenThereIsNoMobile() {
        var contact = anna()
        contact.phones = [home, iPhone]
        #expect(MyCard.card(from: contact, picture: nil, fields: MyCardFields()).contact.phones == [iPhone])
    }

    @Test func defaultHasNoPhoneWhenThereIsNoMobileNumber() {
        var contact = anna()
        contact.phones = [home]
        #expect(MyCard.card(from: contact, picture: nil, fields: MyCardFields()).contact.phones.isEmpty)
    }

    @Test func defaultLinkedInCanBeAWebAddress() {
        var contact = anna()
        contact.socialProfiles = [twitter]
        let card = MyCard.card(from: contact, picture: nil, fields: MyCardFields())
        #expect(card.contact.urls == [linkedInURL])
        #expect(card.contact.socialProfiles.isEmpty)
    }

    @Test func defaultTakesOnlyOneLinkedInWhenTheContactHasTwo() {
        let card = MyCard.card(from: anna(), picture: nil, fields: MyCardFields())
        #expect(card.contact.socialProfiles == [linkedIn])
        #expect(card.contact.urls.isEmpty)
    }

    // MARK: chosen fields

    @Test func companyJobTitleAndPictureCanBeLeftOutOrAdded() {
        var fields = MyCardFields()
        fields.company = false
        fields.jobTitle = false
        fields.picture = true
        let card = MyCard.card(from: anna(), picture: picture, fields: fields)
        #expect(card.contact.organization.isEmpty)
        #expect(card.contact.jobTitle.isEmpty)
        #expect(card.picture == picture)
    }

    @Test func theNameIsAlwaysPassedOnAndNicknameBirthdayAndContactIdentifierNever() {
        var fields = MyCardFields()
        for row in MyCard.rowIDs(of: anna()) { fields.set(row, included: true, of: anna()) }
        let card = MyCard.card(from: anna(), picture: nil, fields: fields)
        #expect(card.contact.givenName == "Anna")
        #expect(card.contact.familyName == "Example")
        #expect(card.contact.nickname.isEmpty)
        #expect(card.contact.birthday == nil)
        #expect(card.contact.contactIdentifier.isEmpty)
    }

    @Test func addingARowKeepsTheDefaultRows() {
        var fields = MyCardFields()
        fields.set(office.id, included: true, of: anna())
        fields.set(workMail.id, included: true, of: anna())
        let card = MyCard.card(from: anna(), picture: nil, fields: fields)
        #expect(card.contact.phones == [mobile])
        #expect(card.contact.emails == [privateMail, workMail])
        #expect(card.contact.socialProfiles == [linkedIn])
        #expect(card.contact.addresses == [office])
    }

    @Test func removingADefaultRowLeavesItOut() {
        var fields = MyCardFields()
        fields.set(mobile.id, included: false, of: anna())
        #expect(!fields.includes(mobile.id, of: anna()))
        #expect(fields.includes(linkedIn.id, of: anna()))
        #expect(MyCard.card(from: anna(), picture: nil, fields: fields).contact.phones.isEmpty)
    }

    @Test func rowsKeepTheOrderOfTheContact() {
        var fields = MyCardFields()
        fields.set(iPhone.id, included: true, of: anna())
        fields.set(home.id, included: true, of: anna())
        #expect(MyCard.card(from: anna(), picture: nil, fields: fields).contact.phones == [home, mobile, iPhone])
    }

    @Test func theCardXchangeLinkIsNeverPassedOn() {
        var contact = anna()
        let link = Item(id: "U9", label: "cardxchange", value: "cx://person/6F1C2D9E-1D2B-4C3A-9F00-000000000001")
        contact.urls.append(link)
        var fields = MyCardFields()
        fields.set(link.id, included: true, of: contact)
        #expect(!MyCard.rowIDs(of: contact).contains(link.id))
        #expect(!MyCard.card(from: contact, picture: nil, fields: fields).contact.urls.contains(link))
    }

    @Test func chosenFieldsSurviveEncoding() throws {
        var fields = MyCardFields()
        fields.picture = true
        fields.set(office.id, included: true, of: anna())
        let decoded = try JSONDecoder().decode(MyCardFields.self, from: JSONEncoder().encode(fields))
        #expect(decoded == fields)
    }

    @Test func theCardCanBeEncoded() throws {
        let card = MyCard.card(from: anna(), picture: picture, fields: MyCardFields(picture: true))
        #expect(try JSONDecoder().decode(SharedCard.self, from: JSONEncoder().encode(card)) == card)
    }

    @Test func theCardBecomesAVCardWithOnlyTheChosenFields() throws {
        let card = MyCard.card(from: anna(), picture: nil, fields: MyCardFields())
        let vCard = String(decoding: try SystemContacts.vCard(for: card), as: UTF8.self)
        #expect(vCard.contains("FN:Anna Example"))
        #expect(vCard.contains("ORG:Example GmbH"))
        #expect(vCard.contains("+49 170 0000000"))
        #expect(vCard.contains("anna@example.org"))
        #expect(vCard.contains("linkedin.com/in/anna-example"))
        #expect(!vCard.contains("+49 221 1111111"))
        #expect(!vCard.contains("anna@example.com"))
        #expect(!vCard.contains("Musterstr"))
    }

    // MARK: person without a contact

    @Test func aPersonWithoutAContactPassesOnTheName() {
        #expect(MyCard.contact(named: "Anna Maria Example") == ContactEdit(givenName: "Anna Maria", familyName: "Example"))
    }
}

/// Which "Me" wins on the Mac: the choice in the store or "My Card" in Contacts (issue #16).
@Suite struct MeSyncTests {
    private let anna = UUID(), ben = UUID(), clara = UUID()

    @Test func nothingToDoWhenStoreAndContactsAgree() {
        #expect(MyCard.meSync(stored: anna, applied: nil, system: anna) == .none)
        #expect(MyCard.meSync(stored: nil, applied: nil, system: nil) == .none)
    }

    @Test func contactsGivesMeWhenTheStoreHasNone() {
        #expect(MyCard.meSync(stored: nil, applied: nil, system: anna) == .takeFromContacts)
    }

    @Test func storeGivesMyCardWhenContactsHasNone() {
        #expect(MyCard.meSync(stored: anna, applied: anna, system: nil) == .applyToContacts)
    }

    @Test func aChangeInCardXchangeIsAppliedToContacts() {
        // Contacts still has what the Mac applied last: the user changed "Me" in cardXchange
        #expect(MyCard.meSync(stored: ben, applied: anna, system: anna) == .applyToContacts)
    }

    @Test func aChangeInContactsIsTakenIntoTheStore() {
        // the store still has what the Mac applied last: the user changed "My Card" in Contacts
        #expect(MyCard.meSync(stored: anna, applied: anna, system: ben) == .takeFromContacts)
    }

    @Test func cardXchangeWinsWhenBothChangedOrNothingWasAppliedYet() {
        #expect(MyCard.meSync(stored: ben, applied: anna, system: clara) == .applyToContacts)
        #expect(MyCard.meSync(stored: ben, applied: nil, system: anna) == .applyToContacts)
    }
}
