import Foundation

/// What pplz learned about a person from a capture, e.g. a screenshot of their LinkedIn profile.
/// Every field may be empty; the user reviews and corrects it before anything is saved.
public struct CapturedProfile: Equatable, Sendable {
    /// As on the profile; a title in front ("Dr.") is taken off when the name is used.
    public var name: String
    public var namePrefix: String
    public var jobTitle: String
    public var company: String
    public var city: String
    public var country: String
    /// The part after "/in/" of the profile's address, see `LinkedInLink`.
    public var linkedInID: String
    /// The profile picture as PNG data.
    public var picture: Data?

    public init(name: String = "", namePrefix: String = "", jobTitle: String = "", company: String = "", city: String = "",
                country: String = "", linkedInID: String = "", picture: Data? = nil) {
        self.name = name
        self.namePrefix = namePrefix
        self.jobTitle = jobTitle
        self.company = company
        self.city = city
        self.country = country
        self.linkedInID = linkedInID
        self.picture = picture
    }
}

/// The fields a capture adds to a contact. `nil` = leave alone.
public struct ContactFill: Equatable, Sendable {
    public var namePrefix: String?
    public var jobTitle: String?
    public var organization: String?
    public var city: String?
    public var country: String?
    public var linkedInURL: String?
    public var picture: Data?

    public init(namePrefix: String? = nil, jobTitle: String? = nil, organization: String? = nil, city: String? = nil,
                country: String? = nil, linkedInURL: String? = nil, picture: Data? = nil) {
        self.namePrefix = namePrefix
        self.jobTitle = jobTitle
        self.organization = organization
        self.city = city
        self.country = country
        self.linkedInURL = linkedInURL
        self.picture = picture
    }

    public var isEmpty: Bool { self == ContactFill() }

    /// What to write: everything the profile knows for a new contact (`existing == nil`); for an
    /// existing one only what it lacks — a capture never overwrites what is in the address book.
    public static func plan(for profile: CapturedProfile, existing: ContactDetails?) -> ContactFill {
        func value(_ text: String, unless taken: Bool) -> String? {
            let text = text.trimmed
            return text.isEmpty || taken ? nil : text
        }
        let hasLinkedIn = existing?.socialProfiles.contains {
            ($0.label + " " + $0.value).range(of: "linkedin", options: .caseInsensitive) != nil
        } ?? false
        let hasAddress = !(existing?.addresses.isEmpty ?? true)
        return ContactFill(
            namePrefix: value(profile.namePrefix, unless: existing != nil),
            jobTitle: value(profile.jobTitle, unless: !(existing?.jobTitle.isEmpty ?? true)),
            organization: value(profile.company, unless: !(existing?.organization.isEmpty ?? true)),
            city: value(profile.city, unless: hasAddress),
            country: value(profile.country, unless: hasAddress),
            linkedInURL: profile.linkedInID.trimmed.isEmpty || hasLinkedIn ? nil : LinkedInLink.url(forProfileID: profile.linkedInID.trimmed),
            picture: existing?.imageData == nil ? profile.picture : nil)
    }
}
