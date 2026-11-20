import Foundation

/// What cardXchange learned about a person from a capture, e.g. a screenshot of their LinkedIn profile.
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
    /// What a business card adds.
    public var email: String
    public var phone: String
    public var mobile: String
    public var website: String
    public var street: String
    public var postalCode: String
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

    public init(name: String = "", givenName: String = "", familyName: String = "", namePrefix: String = "", jobTitle: String = "", company: String = "",
                email: String = "", phone: String = "", mobile: String = "", website: String = "", street: String = "", postalCode: String = "",
                city: String = "", country: String = "", linkedInID: String = "", picture: Data? = nil) {
        self.email = email
        self.phone = phone
        self.mobile = mobile
        self.website = website
        self.street = street
        self.postalCode = postalCode
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
    public var email: String?
    public var phone: String?
    public var mobile: String?
    public var website: String?
    public var street: String?
    public var postalCode: String?
    public var city: String?
    public var country: String?
    public var linkedInURL: String?
    public var picture: Data?

    public init(namePrefix: String? = nil, jobTitle: String? = nil, organization: String? = nil, email: String? = nil, phone: String? = nil,
                mobile: String? = nil, website: String? = nil, street: String? = nil, postalCode: String? = nil, city: String? = nil,
                country: String? = nil, linkedInURL: String? = nil, picture: Data? = nil) {
        self.email = email
        self.phone = phone
        self.mobile = mobile
        self.website = website
        self.street = street
        self.postalCode = postalCode
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
    /// A mail address, phone number or website is added unless the contact has that very one.
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
            email: value(profile.email, unless: existing?.emails.contains { $0.value.caseInsensitiveCompare(profile.email.trimmed) == .orderedSame } ?? false),
            phone: value(profile.phone, unless: existing?.phones.contains { BusinessCard.isSamePhone($0.value, profile.phone) } ?? false),
            mobile: value(profile.mobile, unless: existing?.phones.contains { BusinessCard.isSamePhone($0.value, profile.mobile) } ?? false),
            website: value(profile.website, unless: existing?.urls.contains { BusinessCard.host(of: $0.value) == BusinessCard.host(of: profile.website.trimmed) } ?? false),
            street: value(profile.street, unless: hasAddress),
            postalCode: value(profile.postalCode, unless: hasAddress),
            city: value(profile.city, unless: hasAddress),
            country: value(profile.country, unless: hasAddress),
            linkedInURL: profile.linkedInID.trimmed.isEmpty || hasLinkedIn ? nil : LinkedInLink.url(forProfileID: profile.linkedInID.trimmed),
            picture: existing?.imageData == nil ? profile.picture : nil)
    }
}
