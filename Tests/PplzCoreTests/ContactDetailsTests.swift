import Foundation
import Testing
@testable import PplzCore

@Suite struct ContactDetailsTests {
    @Test func rendersOnlyTheFieldsThatHaveValues() {
        let details = ContactDetails(
            identifier: "C-1", givenName: "Anna", familyName: "Example", organization: "Example GmbH", jobTitle: "CTO",
            phones: [LabeledValue(label: "mobile", value: "+49 170 0000000")],
            emails: [LabeledValue(label: "work", value: "anna@example.com"), LabeledValue(label: "", value: "a@example.org")],
            addresses: [LabeledValue(label: "home", value: "Musterstr. 1, 50667 Köln, Germany")],
            urls: [], socialProfiles: [LabeledValue(label: "LinkedIn", value: "https://www.linkedin.com/in/anna-example")],
            birthday: "1980-05-17")
        #expect(details.lines == [
            "First name: Anna",
            "Last name: Example",
            "Company: Example GmbH",
            "Job title: CTO",
            "Phone (mobile): +49 170 0000000",
            "Email (work): anna@example.com",
            "Email: a@example.org",
            "Address (home): Musterstr. 1, 50667 Köln, Germany",
            "LinkedIn: https://www.linkedin.com/in/anna-example",
            "Birthday: 1980-05-17",
        ])
    }

    @Test func emptyContactRendersNothing() {
        #expect(ContactDetails(identifier: "C-2").lines.isEmpty)
    }

    private func day(_ text: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let parts = text.split(separator: "-").map { Int($0)! }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))!
    }

    private func age(_ birthday: String?, on today: String) -> Int? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return ContactDetails(identifier: "C-3", birthday: birthday).age(on: day(today), calendar: calendar)
    }

    @Test func ageCountsCompletedYears() {
        #expect(age("1980-05-17", on: "2026-05-16") == 45)   // the day before the birthday
        #expect(age("1980-05-17", on: "2026-05-17") == 46)   // on the birthday
        #expect(age("1980-05-17", on: "2026-11-19") == 46)
    }

    @Test func ageOfSomeoneBornOnLeapDay() {
        #expect(age("2000-02-29", on: "2026-02-28") == 25)
        #expect(age("2000-02-29", on: "2026-03-01") == 26)
    }

    @Test func noAgeWithoutABirthYear() {
        #expect(age("--05-17", on: "2026-11-19") == nil)
        #expect(age(nil, on: "2026-11-19") == nil)
    }

    @Test func noAgeForABirthdayInTheFuture() {
        #expect(age("2030-01-01", on: "2026-11-19") == nil)
    }

    @Test func birthdayIsShownWithTheAge() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let today = day("2026-11-19")
        #expect(ContactDetails(identifier: "C-4", birthday: "1980-05-17").birthdayWithAge(on: today, calendar: calendar) == "1980-05-17 · 46 years")
        #expect(ContactDetails(identifier: "C-5", birthday: "2025-05-17").birthdayWithAge(on: today, calendar: calendar) == "2025-05-17 · 1 year")
        #expect(ContactDetails(identifier: "C-6", birthday: "--05-17").birthdayWithAge(on: today, calendar: calendar) == "--05-17")
        #expect(ContactDetails(identifier: "C-7").birthdayWithAge(on: today, calendar: calendar) == nil)
    }

    // MARK: quick actions

    private let mobile = LabeledValue(label: "mobile", value: "+49 170 0000000")
    private let workPhone = LabeledValue(label: "work", value: "+49 221 0000000")
    private let workMail = LabeledValue(label: "work", value: "anna@example.com")
    private let otherMail = LabeledValue(label: "", value: "a@example.org")

    @Test func quickActionsOfferNothingWithoutPhonesAndMails() {
        let details = ContactDetails(identifier: "C-3", givenName: "Anna")
        for action in QuickAction.allCases { #expect(details.choices(for: action).isEmpty) }
        #expect(details.availableQuickActions.isEmpty)
    }

    @Test func quickActionWithOneValueOffersIt() {
        let details = ContactDetails(identifier: "C-4", phones: [mobile], emails: [workMail])
        #expect(details.choices(for: .call) == [QuickActionChoice(label: "mobile", value: "+49 170 0000000", url: URL(string: "tel:+491700000000")!)])
        #expect(details.choices(for: .mail) == [QuickActionChoice(label: "work", value: "anna@example.com", url: URL(string: "mailto:anna@example.com")!)])
    }

    @Test func severalPhonesAndMailsKeepTheirOrder() {
        let details = ContactDetails(identifier: "C-5", phones: [mobile, workPhone], emails: [workMail, otherMail])
        #expect(details.choices(for: .call).map(\.value) == ["+49 170 0000000", "+49 221 0000000"])
        #expect(details.choices(for: .mail).map(\.value) == ["anna@example.com", "a@example.org"])
        // message and video: phone numbers first, then mail addresses
        #expect(details.choices(for: .message).map(\.value) == ["+49 170 0000000", "+49 221 0000000", "anna@example.com", "a@example.org"])
        #expect(details.choices(for: .video).map(\.url.absoluteString)
            == ["facetime:+491700000000", "facetime:+492210000000", "facetime:anna@example.com", "facetime:a@example.org"])
        #expect(details.choices(for: .message).map(\.url.absoluteString).prefix(3)
            == ["sms:+491700000000", "sms:+492210000000", "sms:anna@example.com"])
        #expect(details.availableQuickActions == [.message, .call, .video, .mail])
    }

    @Test func phoneOnlyHasNoMailButton() {
        let details = ContactDetails(identifier: "C-6", phones: [mobile])
        #expect(details.availableQuickActions == [.message, .call, .video])
    }

    @Test func mailOnlyHasNoCallButton() {
        let details = ContactDetails(identifier: "C-7", emails: [workMail])
        #expect(details.availableQuickActions == [.message, .video, .mail])
        #expect(details.choices(for: .call).isEmpty)
    }

    @Test func emptyLabelsFallBackToPhoneAndEmail() {
        let details = ContactDetails(identifier: "C-8", phones: [LabeledValue(label: "", value: "+49 170 0000000")], emails: [otherMail])
        #expect(details.choices(for: .message).map(\.label) == ["phone", "email"])
    }

    @Test func valuesWithoutALinkAreLeftOut() {
        let details = ContactDetails(identifier: "C-9", phones: [LabeledValue(label: "x", value: "  ")], emails: [workMail])
        #expect(details.choices(for: .call).isEmpty)
    }
}
