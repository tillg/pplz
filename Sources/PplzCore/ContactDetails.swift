import Foundation

public struct LabeledValue: Codable, Equatable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// The core data of a contact, read live from the address book and never stored by pplz (SPEC §3.1).
/// Deliberately has no note field (SPEC §8.1).
public struct ContactDetails: Codable, Equatable, Sendable {
    public var identifier: String
    public var givenName: String
    public var familyName: String
    public var organization: String
    public var jobTitle: String
    public var phones: [LabeledValue]
    public var emails: [LabeledValue]
    public var addresses: [LabeledValue]
    public var urls: [LabeledValue]
    public var socialProfiles: [LabeledValue]
    /// `YYYY-MM-DD`, or `--MM-DD` when the year is unknown.
    public var birthday: String?

    public init(identifier: String, givenName: String = "", familyName: String = "", organization: String = "", jobTitle: String = "",
                phones: [LabeledValue] = [], emails: [LabeledValue] = [], addresses: [LabeledValue] = [], urls: [LabeledValue] = [],
                socialProfiles: [LabeledValue] = [], birthday: String? = nil) {
        self.identifier = identifier
        self.givenName = givenName
        self.familyName = familyName
        self.organization = organization
        self.jobTitle = jobTitle
        self.phones = phones
        self.emails = emails
        self.addresses = addresses
        self.urls = urls
        self.socialProfiles = socialProfiles
        self.birthday = birthday
    }

    /// One line per field that has a value, for display.
    public var lines: [String] {
        func single(_ title: String, _ value: String) -> [String] { value.isEmpty ? [] : ["\(title): \(value)"] }
        func many(_ title: String, _ values: [LabeledValue]) -> [String] {
            values.map { $0.label.isEmpty ? "\(title): \($0.value)" : "\(title) (\($0.label)): \($0.value)" }
        }
        return single("First name", givenName) + single("Last name", familyName)
            + single("Company", organization) + single("Job title", jobTitle)
            + many("Phone", phones) + many("Email", emails) + many("Address", addresses) + many("URL", urls)
            + socialProfiles.map { "\($0.label.isEmpty ? "Social" : $0.label): \($0.value)" }
            + single("Birthday", birthday ?? "")
    }
}
