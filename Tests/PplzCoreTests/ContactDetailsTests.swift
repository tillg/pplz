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
}
