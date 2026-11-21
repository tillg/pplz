#if canImport(Contacts)
import Contacts
import Foundation

/// Access to the system address book: mostly reading; writing is limited to the cardXchange link, what a capture fills in, the picture
/// and what the user edits (`SystemContactsEdit.swift`).
/// Never requests the note field: without Apple's notes entitlement that access fails (SPEC §8.1).
public enum SystemContacts {
    public static func fetchAll() throws -> [ContactSummary] {
        let store = CNContactStore()
        try requestAccessIfNeeded(store)

        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactUrlAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
        ]
        var result: [ContactSummary] = []
        try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName
            if !name.trimmed.isEmpty {
                let link = contact.urlAddresses.lazy.compactMap { URL(string: $0.value as String) }.compactMap(PersonLink.personID).first
                result.append(ContactSummary(identifier: contact.identifier, name: name.trimmed, nickname: contact.nickname.trimmed,
                                             cxPersonID: link, organization: contact.organizationName.trimmed,
                                             city: contact.postalAddresses.first?.value.city.trimmed ?? "",
                                             country: contact.postalAddresses.first?.value.country.trimmed ?? "",
                                             addresses: contact.postalAddresses.map { labeled in
                                                 let address = labeled.value
                                                 return PostalAddress(
                                                     label: labeled.label.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "",
                                                     street: address.street.trimmed, postalCode: address.postalCode.trimmed,
                                                     city: address.city.trimmed, country: address.country.trimmed)
                                             }))
            }
        }
        return result
    }

    public struct NameParts: Equatable, Sendable {
        public var given: String
        public var family: String
    }

    /// Splits a name as typed into first and last name: the last word is the family name.
    public static func nameParts(_ name: String) -> NameParts {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard words.count > 1 else { return NameParts(given: words.first ?? "", family: "") }
        return NameParts(given: words.dropLast().joined(separator: " "), family: words[words.count - 1])
    }

    /// Creates a contact with this name and URL row (the cardXchange link) and returns its identifier.
    /// A new contact has no note, so this works on every platform (SPEC §8.1, S1).
    public static func createContact(name: String, link: ContactMirror.Row, fill: ContactFill = ContactFill()) throws -> String {
        try createContact(name: nameParts(name), link: link, fill: fill)
    }

    /// The same with first and last name known.
    public static func createContact(name parts: NameParts, link: ContactMirror.Row, fill: ContactFill = ContactFill()) throws -> String {
        let store = CNContactStore()
        try requestAccessIfNeeded(store)
        let contact = CNMutableContact()
        contact.givenName = parts.given
        contact.familyName = parts.family
        contact.urlAddresses = [CNLabeledValue(label: link.label, value: link.value as NSString)]
        apply(fill, to: contact)
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
        return contact.identifier
    }

    /// Adds the fields of a capture to an existing contact. `fill` must come from `ContactFill.plan`
    /// with this contact's details, so that nothing the contact has is overwritten.
    /// Works on iPhone and iPad; on the Mac it fails for a contact that has a note (SPEC §8.1, S4).
    public static func fill(_ fill: ContactFill, intoContact identifier: String) throws {
        let store = CNContactStore()
        try requestAccessIfNeeded(store)
        let keys = [CNContactNamePrefixKey, CNContactJobTitleKey, CNContactOrganizationNameKey, CNContactPostalAddressesKey,
                    CNContactSocialProfilesKey, CNContactImageDataKey, CNContactEmailAddressesKey, CNContactPhoneNumbersKey,
                    CNContactUrlAddressesKey] as [CNKeyDescriptor]
        guard let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys).mutableCopy() as? CNMutableContact else { return }
        apply(fill, to: contact)
        let request = CNSaveRequest()
        request.update(contact)
        do {
            try store.execute(request)
        } catch {
            #if os(macOS)
            throw CXError.invalid("Contacts did not accept the change. On the Mac this happens for a contact that has a note — capture this person on iPhone or iPad instead.")
            #else
            throw error
            #endif
        }
    }

    /// Makes this picture the contact's picture in Contacts, replacing the one it has.
    /// On the Mac a contact that has a note refuses a direct save (SPEC §8.1, S4); then the Contacts app is asked to set it.
    public static func setPicture(_ image: Data, forContact identifier: String) throws {
        let store = CNContactStore()
        try requestAccessIfNeeded(store)
        guard let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: [CNContactImageDataKey as CNKeyDescriptor])
            .mutableCopy() as? CNMutableContact else { return }
        contact.imageData = image
        let request = CNSaveRequest()
        request.update(contact)
        do {
            try store.execute(request)
        } catch {
            #if os(macOS)
            do {
                try ContactsApp.setImage(image, identifier: identifier)
            } catch {
                throw CXError.invalid("Contacts did not accept the picture. On the Mac this happens for a contact that has a note, and cardXchange could not set it through the Contacts app either (\((error as? LocalizedError)?.errorDescription ?? "\(error)")).")
            }
            #else
            throw error
            #endif
        }
    }

    private static func apply(_ fill: ContactFill, to contact: CNMutableContact) {
        if let prefix = fill.namePrefix { contact.namePrefix = prefix }
        if let jobTitle = fill.jobTitle { contact.jobTitle = jobTitle }
        if let organization = fill.organization { contact.organizationName = organization }
        if let email = fill.email { contact.emailAddresses.append(CNLabeledValue(label: CNLabelWork, value: email as NSString)) }
        if let phone = fill.phone { contact.phoneNumbers.append(CNLabeledValue(label: CNLabelWork, value: CNPhoneNumber(stringValue: phone))) }
        if let mobile = fill.mobile {
            contact.phoneNumbers.append(CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: mobile)))
        }
        // added to the other addresses: the cardXchange link is one of them
        if let website = fill.website { contact.urlAddresses.append(CNLabeledValue(label: CNLabelURLAddressHomePage, value: website as NSString)) }
        if fill.city != nil || fill.country != nil || fill.street != nil || fill.postalCode != nil {
            let address = CNMutablePostalAddress()
            address.street = fill.street ?? ""
            address.postalCode = fill.postalCode ?? ""
            address.city = fill.city ?? ""
            address.country = fill.country ?? ""
            contact.postalAddresses.append(CNLabeledValue(label: CNLabelWork, value: address))
        }
        if let url = fill.linkedInURL {
            let profile = CNSocialProfile(urlString: url, username: LinkedInLink.profileID(in: url), userIdentifier: nil,
                                          service: CNSocialProfileServiceLinkedIn)
            contact.socialProfiles.append(CNLabeledValue(label: nil, value: profile))
        }
        if let picture = fill.picture { contact.imageData = picture }
    }

    /// Everything cardXchange shows about one contact; `nil` if the contact no longer exists.
    public static func details(identifier: String) throws -> ContactDetails? {
        let store = CNContactStore()
        try requestAccessIfNeeded(store)
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactImageDataKey, CNContactThumbnailImageDataKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactPostalAddressesKey, CNContactUrlAddressesKey,
            CNContactSocialProfilesKey, CNContactBirthdayKey, CNContactRelationsKey,
        ] as [CNKeyDescriptor]
        guard let contact = try store.unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers: [identifier]),
                                                      keysToFetch: keys).first else { return nil }

        func label(_ raw: String?) -> String { raw.map { CNLabeledValue<NSString>.localizedString(forLabel: $0) } ?? "" }
        var birthday: String?
        if let parts = contact.birthday, let month = parts.month, let day = parts.day {
            birthday = (parts.year.map { String(format: "%04d", $0) } ?? "-") + String(format: "-%02d-%02d", month, day)
        }
        return ContactDetails(
            identifier: contact.identifier, givenName: contact.givenName, familyName: contact.familyName,
            nickname: contact.nickname, organization: contact.organizationName, jobTitle: contact.jobTitle,
            phones: contact.phoneNumbers.map { LabeledValue(label: label($0.label), value: $0.value.stringValue) },
            emails: contact.emailAddresses.map { LabeledValue(label: label($0.label), value: $0.value as String) },
            addresses: contact.postalAddresses.map {
                LabeledValue(label: label($0.label),
                             value: CNPostalAddressFormatter.string(from: $0.value, style: .mailingAddress)
                                 .split(whereSeparator: \.isNewline).joined(separator: ", "))
            },
            // cardXchange's own link is its bookkeeping, not something to show on the cardXchange card
            urls: contact.urlAddresses.filter { URL(string: $0.value as String).flatMap(PersonLink.personID) == nil }
                .map { LabeledValue(label: label($0.label), value: $0.value as String) },
            socialProfiles: contact.socialProfiles.map {
                LabeledValue(label: $0.value.service, value: $0.value.urlString.isEmpty ? $0.value.username : $0.value.urlString)
            },
            birthday: birthday, imageData: contact.imageData ?? contact.thumbnailImageData,   // some contacts only carry the thumbnail
            relatedNames: contact.contactRelations.map { LabeledValue(label: label($0.label), value: $0.value.name) })
    }

    #if os(macOS)
    /// The contact that Contacts on this Mac marks as "My Card"; `nil` if there is none.
    public static func meContactIdentifier() throws -> String? {
        let store = CNContactStore()
        try requestAccessIfNeeded(store)
        return try? store.unifiedMeContactWithKeys(toFetch: []).identifier
    }
    #endif

    static func requestAccessIfNeeded(_ store: CNContactStore) throws {
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            let done = DispatchSemaphore(value: 0)
            store.requestAccess(for: .contacts) { _, _ in done.signal() }
            done.wait()
        }
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .denied, .restricted, .notDetermined:
            throw CXError.invalid("cardXchange has no access to Contacts. Allow it in System Settings → Privacy & Security → Contacts, or pass --no-contacts.")
        default:
            break
        }
    }
}
#endif
