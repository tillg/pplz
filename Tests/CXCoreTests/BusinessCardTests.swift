import Foundation
import Testing
@testable import CXCore

/// A photo of a business card is read like a profile screenshot. What has a fixed shape — mail
/// address, phone numbers, website, postal address — is found by rule, so it is there even on a
/// device without a language model. All people, firms and numbers here are invented.
@Suite struct BusinessCardTests {
    let card = ["NORDWIND LOGISTIK GmbH", "Dr. Anna Beispiel", "Leiterin Vertrieb", "Hafenstraße 12", "20457 Hamburg",
                "T +49 40 555 01 23", "F +49 40 555 01 99", "M +49 151 5550 1234",
                "anna.beispiel@nordwind-logistik.example", "www.nordwind-logistik.example"]
    let oneLiner = ["Ben Muster", "Musterbau AG", "Tel.: 030 5550123 | Mobil: 0171 5550123 | Fax: 030 5550199",
                    "E-Mail: Ben@Muster.example", "Musterweg 3a, 10115 Berlin, Germany"]

    @Test func aProfileScreenshotIsNoCard() {
        #expect(BusinessCard.isCard(card))
        #expect(BusinessCard.isCard(["Anna Example · 1st", "Head of Sales", "Cologne, Germany", "500+ connections"]) == false)
        #expect(BusinessCard.isCard(["Anna Example", "Head of Sales", "3,533 followers"]) == false)
        #expect(BusinessCard.isCard([]) == false)
    }

    @Test func mailPhonesAndWebsiteAreFound() {
        var profile = CapturedProfile()
        BusinessCard.fill(&profile, from: card)
        #expect(profile.email == "anna.beispiel@nordwind-logistik.example")
        #expect(profile.phone == "+49 40 555 01 23")
        #expect(profile.mobile == "+49 151 5550 1234")           // and the fax number is nobody's phone
        #expect(profile.website == "www.nordwind-logistik.example")
    }

    @Test func severalNumbersInOneLineAreToldApartByTheirLabels() {
        var profile = CapturedProfile()
        BusinessCard.fill(&profile, from: oneLiner)
        #expect(profile.phone == "030 5550123")
        #expect(profile.mobile == "0171 5550123")
        #expect(profile.email == "Ben@Muster.example")
        #expect(profile.website == "")                            // the mail address's domain is no website
    }

    @Test func numbersAreWrittenWithBlanksOnly() {
        #expect(BusinessCard.formatted("+49.40.5550123") == "+49 40 5550123")
        #expect(BusinessCard.formatted("030 / 555-01-23") == "030 555 01 23")
        #expect(BusinessCard.formatted("+49 (0) 40 555 01 23") == "+49 40 555 01 23")
        #expect(BusinessCard.formatted("(040) 5550123") == "040 5550123")
        #expect(BusinessCard.formatted("+49 40 555 01 23") == "+49 40 555 01 23")
    }

    @Test func aGermanMobileNumberIsMobileEvenWithoutALabel() {
        var profile = CapturedProfile()
        BusinessCard.fill(&profile, from: ["carl@muster.example • +49.151.55501234", "Tel 040 5550123"])
        #expect(profile.mobile == "+49 151 55501234")
        #expect(profile.phone == "040 5550123")
        profile = CapturedProfile()
        BusinessCard.fill(&profile, from: ["0171/5550123"])
        #expect(profile.mobile == "0171 5550123" && profile.phone == "")
    }

    @Test func theAddressIsTakenApart() {
        var profile = CapturedProfile()
        BusinessCard.fill(&profile, from: card)
        #expect(profile.street == "Hafenstraße 12" && profile.postalCode == "20457" && profile.city == "Hamburg" && profile.country == "")
        profile = CapturedProfile()
        BusinessCard.fill(&profile, from: oneLiner)
        #expect(profile.street == "Musterweg 3a" && profile.postalCode == "10115" && profile.city == "Berlin" && profile.country == "Germany")
    }

    @Test func aWebsiteWithoutWwwCountsWhenItIsLabelledOrMatchesTheMailAddress() {
        var profile = CapturedProfile()
        BusinessCard.fill(&profile, from: ["Web: muster.example/team", "Muster & Co.KG"])
        #expect(profile.website == "muster.example/team")
        profile = CapturedProfile()
        BusinessCard.fill(&profile, from: ["carl@muster.example", "muster.example", "linkedin.com/in/carl-muster"])
        #expect(profile.website == "muster.example")
    }

    @Test func whatTheModelSaysMustBeWrittenOnTheCard() {
        #expect(BusinessCard.onlyWhatIsWritten("Jan René", in: ["Jan René Fricke", "Frankfurt, Hesse"]) == "Jan René")
        #expect(BusinessCard.onlyWhatIsWritten("Frank", in: ["Jan René Fricke", "Frankfurt, Hesse"]) == "")
        #expect(BusinessCard.onlyWhatIsWritten("anna", in: ["Dr. ANNA BEISPIEL"]) == "anna")
        #expect(BusinessCard.onlyWhatIsWritten("", in: ["Anna"]) == "")
    }
}

@Suite struct CardIntoContactTests {
    let profile = CapturedProfile(givenName: "Anna", familyName: "Beispiel", email: "anna@nordwind.example", phone: "+49 40 555 01 23",
                                  mobile: "+49 151 5550 1234", website: "www.nordwind.example", street: "Hafenstraße 12",
                                  postalCode: "20457", city: "Hamburg")

    @Test func aNewContactGetsTheCardsDetails() {
        let fill = ContactFill.plan(for: profile, existing: nil)
        #expect(fill.email == "anna@nordwind.example" && fill.phone == "+49 40 555 01 23" && fill.mobile == "+49 151 5550 1234")
        #expect(fill.website == "www.nordwind.example" && fill.street == "Hafenstraße 12" && fill.postalCode == "20457" && fill.city == "Hamburg")
    }

    @Test func whatTheContactAlreadyHasIsNotAddedAgain() {
        let existing = ContactDetails(identifier: "C-1", givenName: "Anna", familyName: "Beispiel",
                                      phones: [LabeledValue(label: "work", value: "040 5550123"), LabeledValue(label: "mobile", value: "+49 (151) 5550-1234")],
                                      emails: [LabeledValue(label: "work", value: "Anna@Nordwind.example")],
                                      urls: [LabeledValue(label: "homepage", value: "https://www.nordwind.example/")])
        let fill = ContactFill.plan(for: profile, existing: existing)
        #expect(fill.email == nil)                       // the same address in other letters
        #expect(fill.mobile == nil)                      // the same number written differently
        #expect(fill.phone == nil)                       // national and international form of one number
        #expect(fill.website == nil)
        #expect(fill.street == "Hafenstraße 12")         // the contact had no address
    }

    @Test func aNumberOrAddressTheContactLacksIsAdded() {
        let existing = ContactDetails(identifier: "C-1", phones: [LabeledValue(label: "home", value: "0221 5550100")],
                                      emails: [LabeledValue(label: "home", value: "anna@privat.example")])
        let fill = ContactFill.plan(for: profile, existing: existing)
        #expect(fill.email == "anna@nordwind.example" && fill.phone == "+49 40 555 01 23" && fill.mobile == "+49 151 5550 1234")
    }
}

/// When choosing whom a capture belongs to, a name alone is not enough to tell people apart.
@Suite struct PersonContextTests {
    @Test func aContactsCompanyAndPlaceTravelIntoTheList() {
        let contacts = [ContactSummary(identifier: "1", name: "Anna Beispiel", organization: "Nordwind Logistik", city: "Hamburg", country: "Germany"),
                        ContactSummary(identifier: "2", name: "Ben Muster", city: "Berlin"),
                        ContactSummary(identifier: "3", name: "Carl Muster")]
        let entries = PeopleDirectory.merge(contacts: contacts, persons: [PersonSnapshot(id: UUID(), name: "Dora Only")])
        #expect(entries.map(\.context) == ["Nordwind Logistik · Hamburg · Germany", "Berlin", "", ""])
    }
}

/// Seen on 2026-11-19: the language model refused a profile ("safety guardrails"). Name and place
/// can still be taken from where they stand on the page.
@Suite struct FieldsByRuleTests {
    @Test func nameAndPlaceAreReadWithoutTheModel() {
        let lines = ["Developing people", "Dr. Anna Beispiel ø • 2nd", "Asia will come to you!", "Hamburg, Germany • Contact info",
                     "500+ connections", "Message"]
        let profile = ProfileReader.fieldsByRule(lines)
        #expect(profile.givenName == "Anna" && profile.familyName == "Beispiel" && profile.namePrefix == "Dr.")
        #expect(profile.city == "Hamburg" && profile.country == "Germany")
        #expect(profile.jobTitle == "" && profile.company == "")
    }

    @Test func aDegreeOnItsOwnLineIsNoPartOfTheName() {
        let profile = ProfileReader.fieldsByRule(["Ben Muster", "• 3rd+", "Consultant", "Berlin, Germany", "12 followers"])
        #expect(profile.givenName == "Ben" && profile.familyName == "Muster")
    }

    @Test func withoutANameLineNothingIsGuessed() {
        #expect(ProfileReader.fieldsByRule(["NORDWIND LOGISTIK GmbH", "Dr. Anna Beispiel"]) == CapturedProfile())
    }
}
