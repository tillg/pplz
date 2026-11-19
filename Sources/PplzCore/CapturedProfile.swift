import Foundation

/// What pplz learned about a person from a capture, e.g. a screenshot of their LinkedIn profile.
/// Every field may be empty; the user reviews and corrects it before anything is saved.
public struct CapturedProfile: Equatable, Sendable {
    /// First and last name, kept apart as in Contacts. As on the profile; a title in front ("Dr.")
    /// is taken off when the name is used.
    public var givenName: String
    public var familyName: String
    public var namePrefix: String
    public var jobTitle: String
    public var company: String
    public var city: String
    public var country: String
    /// The part after "/in/" of the profile's address, see `LinkedInLink`.
    public var linkedInID: String
    /// The profile picture as PNG data.
    public var picture: Data?

    /// The full name. Setting it splits at the last word, which is a guess: set the two parts where they are known.
    public var name: String {
        get { [givenName, familyName].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ") }
        set {
            let parts = SystemContacts.nameParts(newValue)
            givenName = parts.given
            familyName = parts.family
        }
    }

    /// The name as it goes into a contact: without a title in front of the first name.
    public var contactName: SystemContacts.NameParts {
        .init(given: PeopleDirectory.nameWithoutTitles(givenName), family: familyName.trimmed)
    }

    public init(name: String = "", givenName: String = "", familyName: String = "", namePrefix: String = "", jobTitle: String = "", company: String = "", city: String = "",
                country: String = "", linkedInID: String = "", picture: Data? = nil) {
        self.givenName = givenName
        self.familyName = familyName
        self.namePrefix = namePrefix
        self.jobTitle = jobTitle
        self.company = company
        self.city = city
        self.country = country
        self.linkedInID = linkedInID
        self.picture = picture
        if givenName.isEmpty, familyName.isEmpty { self.name = name }
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
