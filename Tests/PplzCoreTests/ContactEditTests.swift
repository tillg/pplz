import Foundation
import Testing
@testable import PplzCore

@Suite struct ContactEditTests {
    typealias Item = ContactEdit.Item
    typealias Address = ContactEdit.Address

    private let mobile = Item(id: "P1", label: "_$!<Mobile>!$_", value: "+49 170 0000000")
    private let work = Item(id: "P2", label: "_$!<Work>!$_", value: "+49 221 0000000")
    private let boat = Item(id: "P3", label: "Boat", value: "+49 171 0000000")
    private let home = Address(id: "A1", label: "_$!<Home>!$_", street: "Musterstr. 1", postalCode: "50667", city: "Köln", country: "Germany")

    private func anna() -> ContactEdit {
        ContactEdit(givenName: "Anna", familyName: "Example", nickname: "Anni", organization: "Example GmbH", jobTitle: "CTO",
                    phones: [mobile, work, boat], emails: [Item(id: "E1", label: "_$!<Work>!$_", value: "anna@example.com")],
                    urls: [Item(id: "U1", label: "_$!<HomePage>!$_", value: "https://example.com")],
                    socialProfiles: [Item(id: "S1", label: "LinkedIn", value: "https://www.linkedin.com/in/anna-example")],
                    addresses: [home], birthday: .init(day: 17, month: 5, year: nil))
    }

    // MARK: diff

    @Test func nothingChangedGivesNoChanges() {
        #expect(ContactEdit.changes(from: anna(), to: anna()).isEmpty)
    }

    @Test func changedNameFieldsAreReportedWithTheirOldValue() {
        var after = anna()
        after.givenName = "Anne"
        after.jobTitle = ""
        #expect(ContactEdit.changes(from: anna(), to: after) == [
            .text(.givenName, from: "Anna", to: "Anne"),
            .text(.jobTitle, from: "CTO", to: ""),
        ])
    }

    @Test func whitespaceOnlyDifferencesAreNoChange() {
        var after = anna()
        after.givenName = " Anna "
        after.phones[0].value = "+49 170 0000000 "
        #expect(ContactEdit.changes(from: anna(), to: after).isEmpty)
    }

    @Test func changedLabelOrValueOfAPhoneIsAnUpdateOfThatItemOnly() {
        var after = anna()
        after.phones[1].value = "+49 221 9999999"
        after.phones[0].label = "_$!<Home>!$_"
        #expect(ContactEdit.changes(from: anna(), to: after) == [
            .updateItem(.phone, from: mobile, to: Item(id: "P1", label: "_$!<Home>!$_", value: "+49 170 0000000")),
            .updateItem(.phone, from: work, to: Item(id: "P2", label: "_$!<Work>!$_", value: "+49 221 9999999")),
        ])
    }

    @Test func addedAndRemovedPhones() {
        var after = anna()
        after.phones.remove(at: 1)
        after.phones.append(Item(id: "new-1", label: "_$!<Home>!$_", value: "+49 30 0000000"))
        #expect(ContactEdit.changes(from: anna(), to: after) == [
            .removeItem(.phone, work),
            .addItem(.phone, Item(id: "new-1", label: "_$!<Home>!$_", value: "+49 30 0000000")),
        ])
    }

    @Test func aPhoneWhoseValueWasClearedIsRemovedAndANewEmptyRowIsIgnored() {
        var after = anna()
        after.phones[2].value = "  "
        after.phones.append(Item(id: "new-1", label: "_$!<Home>!$_", value: ""))
        #expect(ContactEdit.changes(from: anna(), to: after) == [.removeItem(.phone, boat)])
    }

    @Test func aCustomLabelSurvivesAValueChange() {
        var after = anna()
        after.phones[2].value = "+49 171 1111111"
        #expect(ContactEdit.changes(from: anna(), to: after)
            == [.updateItem(.phone, from: boat, to: Item(id: "P3", label: "Boat", value: "+49 171 1111111"))])
    }

    @Test func mailsUrlsAndProfilesAreDiffedLikePhones() {
        var after = anna()
        after.emails[0].value = "anna@example.org"
        after.urls = []
        after.socialProfiles.append(Item(id: "new-2", label: "Twitter", value: "anna"))
        #expect(ContactEdit.changes(from: anna(), to: after) == [
            .updateItem(.email, from: after.emails[0].with(value: "anna@example.com"), to: after.emails[0]),
            .removeItem(.url, anna().urls[0]),
            .addItem(.socialProfile, Item(id: "new-2", label: "Twitter", value: "anna")),
        ])
    }

    @Test func addressChangesAddAndRemove() {
        var after = anna()
        after.addresses[0].city = "Bonn"
        after.addresses.append(Address(id: "new-3", label: "_$!<Work>!$_", street: "Neustr. 2", postalCode: "10115", city: "Berlin", country: "Germany"))
        var bonn = home
        bonn.city = "Bonn"
        #expect(ContactEdit.changes(from: anna(), to: after) == [
            .updateAddress(from: home, to: bonn),
            .addAddress(Address(id: "new-3", label: "_$!<Work>!$_", street: "Neustr. 2", postalCode: "10115", city: "Berlin", country: "Germany")),
        ])
        after.addresses = []
        #expect(ContactEdit.changes(from: anna(), to: after) == [.removeAddress(home)])
    }

    @Test func anAddressWithAllPartsEmptyIsRemovedOrIgnored() {
        var after = anna()
        after.addresses[0] = Address(id: "A1", label: "_$!<Home>!$_", street: "", postalCode: " ", city: "", country: "")
        after.addresses.append(Address(id: "new-3", label: "_$!<Work>!$_", street: "", postalCode: "", city: "", country: ""))
        #expect(ContactEdit.changes(from: anna(), to: after) == [.removeAddress(home)])
    }

    /// An address that only holds state / country code (the form shows it empty) must survive a save of something else.
    @Test func anUnchangedRowThatLoadsAsEmptyIsNeverRemoved() {
        var before = anna()
        before.addresses.append(Address(id: "A2", label: "_$!<Work>!$_"))                              // street, city … all empty
        before.socialProfiles.append(Item(id: "S2", label: "Twitter", value: ""))                      // service only
        before.phones.append(Item(id: "P4", label: "_$!<Other>!$_", value: " "))
        var after = before
        after.jobTitle = "CEO"
        #expect(ContactEdit.changes(from: before, to: after) == [.text(.jobTitle, from: "CTO", to: "CEO")])
    }

    @Test func aRowTheUserEmptiedIsRemovedButAnEmptyRowOnlyRelabelledIsUpdated() {
        var before = anna()
        before.addresses.append(Address(id: "A2", label: "_$!<Work>!$_"))
        var after = before
        after.addresses[0] = Address(id: "A1", label: "_$!<Home>!$_")           // emptied by the user
        after.addresses[1].label = "_$!<Other>!$_"                                // was empty, only relabelled
        var relabelled = before.addresses[1]
        relabelled.label = "_$!<Other>!$_"
        #expect(ContactEdit.changes(from: before, to: after) == [.removeAddress(home), .updateAddress(from: before.addresses[1], to: relabelled)])
    }

    @Test func birthdaySetChangedAndRemoved() {
        var none = anna()
        none.birthday = nil
        #expect(ContactEdit.changes(from: none, to: anna()) == [.birthday(from: nil, to: .init(day: 17, month: 5, year: nil))])

        var changed = anna()
        changed.birthday = .init(day: 17, month: 5, year: 1980)
        #expect(ContactEdit.changes(from: anna(), to: changed)
            == [.birthday(from: .init(day: 17, month: 5, year: nil), to: .init(day: 17, month: 5, year: 1980))])
        #expect(ContactEdit.changes(from: changed, to: anna())
            == [.birthday(from: .init(day: 17, month: 5, year: 1980), to: .init(day: 17, month: 5, year: nil))])
        #expect(ContactEdit.changes(from: anna(), to: none) == [.birthday(from: .init(day: 17, month: 5, year: nil), to: nil)])
    }

    @Test func aBirthdayWithoutAYearStaysWithoutOne() {
        var after = anna()
        after.birthday = .init(day: 18, month: 5, year: nil)
        #expect(ContactEdit.changes(from: anna(), to: after)
            == [.birthday(from: .init(day: 17, month: 5, year: nil), to: .init(day: 18, month: 5, year: nil))])
    }

    @Test func thePplzLinkIsNeverPartOfADiff() {
        let link = Item(id: "L1", label: "pplz", value: "pplz://person/6f1c5a52-0000-4000-8000-000000000001")
        var before = anna()
        before.urls.append(link)
        // removed from the form, or changed in it: no change for the link
        #expect(ContactEdit.changes(from: before, to: anna()).isEmpty)
        var changed = before
        changed.urls[1].value = "pplz://person/6f1c5a52-0000-4000-8000-000000000002"
        #expect(ContactEdit.changes(from: before, to: changed).isEmpty)
        // a link that is only in the form is not added either
        #expect(ContactEdit.changes(from: anna(), to: before).isEmpty)
    }

    // MARK: conflicts

    @Test func noConflictWhenTheContactIsAsItWasLoaded() {
        var after = anna()
        after.givenName = "Anne"
        after.phones.remove(at: 0)
        #expect(ContactEdit.conflicts(of: ContactEdit.changes(from: anna(), to: after), with: anna()).isEmpty)
    }

    @Test func noConflictForFieldsTheUserDidNotTouch() {
        var after = anna()
        after.givenName = "Anne"
        var current = anna()
        current.familyName = "Other"
        current.phones[0].value = "+49 170 5555555"
        #expect(ContactEdit.conflicts(of: ContactEdit.changes(from: anna(), to: after), with: current).isEmpty)
    }

    @Test func conflictWhenATouchedFieldChangedInTheMeantime() {
        var after = anna()
        after.givenName = "Anne"
        after.phones[0].value = "+49 170 1111111"
        after.phones[1].value = "+49 221 1111111"
        after.birthday = nil
        var current = anna()
        current.givenName = "Annabelle"
        current.phones[0].value = "+49 170 5555555"   // changed by someone else
        current.birthday = .init(day: 1, month: 1, year: nil)
        let conflicts = ContactEdit.conflicts(of: ContactEdit.changes(from: anna(), to: after), with: current)
        #expect(conflicts == ["first name", "phone +49 170 0000000", "birthday"])
    }

    @Test func conflictWhenARemovedOrUpdatedItemIsGone() {
        var after = anna()
        after.phones.remove(at: 1)
        after.addresses[0].city = "Bonn"
        var current = anna()
        current.phones.remove(at: 1)
        current.addresses = []
        #expect(ContactEdit.conflicts(of: ContactEdit.changes(from: anna(), to: after), with: current)
            == ["phone +49 221 0000000", "address Musterstr. 1"])
    }

    @Test func addingNeverConflicts() {
        var after = anna()
        after.phones.append(Item(id: "new-1", label: "", value: "+49 30 0000000"))
        var current = anna()
        current.phones = []
        #expect(ContactEdit.conflicts(of: ContactEdit.changes(from: anna(), to: after), with: current).isEmpty)
    }

    // MARK: labels

    @Test func theFormRemembersWhichContactItWasLoadedFrom() {
        #expect(ContactEdit().contactIdentifier == "")
        let loaded = ContactEdit(givenName: "Anna", contactIdentifier: "C-1")
        var edited = loaded
        edited.nickname = "Anni"
        // the identifier is not a field: it never shows up as a change
        #expect(ContactEdit.changes(from: loaded, to: edited) == [.text(.nickname, from: "", to: "Anni")])
        #expect(edited.contactIdentifier == "C-1")
    }

    @Test func nameIsUsableOnlyWithANameOrACompany() {
        #expect(!ContactEdit().hasName)
        #expect(ContactEdit(givenName: " ", organization: "Example GmbH").hasName)
        #expect(ContactEdit(familyName: "Example").hasName)
    }
}

private extension ContactEdit.Item {
    func with(value: String) -> Self { var copy = self; copy.value = value; return copy }
}
