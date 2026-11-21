import Foundation

/// What the user passes on of their own contact ("My Card", issue #5, SPEC §4.8). The name is always on the card.
/// `rows` holds the identifiers of the chosen phone, mail, web, social profile and address rows; `nil` means
/// the user has not chosen yet, and `MyCard.defaultRows` applies.
public struct MyCardFields: Codable, Equatable, Sendable {
    public var company: Bool
    public var jobTitle: Bool
    public var picture: Bool
    public var rows: Set<String>?

    public init(company: Bool = true, jobTitle: Bool = true, picture: Bool = false, rows: Set<String>? = nil) {
        self.company = company
        self.jobTitle = jobTitle
        self.picture = picture
        self.rows = rows
    }

    public func includes(_ rowID: String, of contact: ContactEdit) -> Bool {
        (rows ?? MyCard.defaultRows(of: contact)).contains(rowID)
    }

    /// Adds or removes one row. The first change starts from the default rows, so the others stay as shown.
    public mutating func set(_ rowID: String, included: Bool, of contact: ContactEdit) {
        var chosen = rows ?? MyCard.defaultRows(of: contact)
        if included { chosen.insert(rowID) } else { chosen.remove(rowID) }
        rows = chosen
    }
}

/// The card that is passed on: the chosen fields of the user's contact, and the picture if it was chosen.
public struct SharedCard: Codable, Equatable, Sendable {
    public var contact: ContactEdit
    public var picture: Data?

    public init(contact: ContactEdit, picture: Data? = nil) {
        self.contact = contact
        self.picture = picture
    }
}

public enum MyCard {
    private static let mobileLabels = ["_$!<Mobile>!$_", "iPhone"]     // CNLabelPhoneNumberMobile, CNLabelPhoneNumberiPhone

    /// Keeps the name and the chosen fields; leaves out everything else, cardXchange's link row always.
    public static func card(from contact: ContactEdit, picture: Data?, fields: MyCardFields) -> SharedCard {
        let chosen = fields.rows ?? defaultRows(of: contact)
        func keep(_ items: [ContactEdit.Item]) -> [ContactEdit.Item] {
            items.filter { chosen.contains($0.id) && !ContactEdit.isCXLink($0) }
        }
        let shared = ContactEdit(givenName: contact.givenName, familyName: contact.familyName,
                                 organization: fields.company ? contact.organization : "",
                                 jobTitle: fields.jobTitle ? contact.jobTitle : "",
                                 phones: keep(contact.phones), emails: keep(contact.emails), urls: keep(contact.urls),
                                 socialProfiles: keep(contact.socialProfiles),
                                 addresses: contact.addresses.filter { chosen.contains($0.id) })
        return SharedCard(contact: shared, picture: fields.picture ? picture : nil)
    }

    /// The rows the user can choose from, in the order of the contact.
    public static func rowIDs(of contact: ContactEdit) -> [String] {
        (contact.phones + contact.emails + contact.urls + contact.socialProfiles).filter { !ContactEdit.isCXLink($0) }.map(\.id)
            + contact.addresses.map(\.id)
    }

    /// Before the user chooses: one mobile number, the first mail address and one LinkedIn profile.
    public static func defaultRows(of contact: ContactEdit) -> Set<String> {
        let mobile = mobileLabels.lazy.compactMap { label in contact.phones.first { $0.label == label } }.first
        let linkedIn = contact.socialProfiles.first { $0.label.caseInsensitiveCompare("LinkedIn") == .orderedSame }
            ?? contact.urls.first { LinkedInLink.profileID(in: $0.value) != nil }
        return Set([mobile, contact.emails.first, linkedIn].compactMap { $0?.id })
    }

    /// The card of a person who has no contact: only the name.
    public static func contact(named name: String) -> ContactEdit {
        let parts = SystemContacts.nameParts(name)
        return ContactEdit(givenName: parts.given, familyName: parts.family)
    }
}
