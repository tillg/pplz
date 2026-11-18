#if canImport(Contacts)
import Contacts
import Foundation

/// Read-only access to the system address book.
/// Never requests the note field: without Apple's notes entitlement that access fails (SPEC §8.1).
public enum SystemContacts {
    public static func fetchAll() throws -> [ContactSummary] {
        let store = CNContactStore()
        try requestAccessIfNeeded(store)

        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
        ]
        var result: [ContactSummary] = []
        try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? contact.organizationName
            if !name.trimmed.isEmpty {
                result.append(ContactSummary(identifier: contact.identifier, name: name.trimmed))
            }
        }
        return result
    }

    /// Everything pplz shows about one contact; `nil` if the contact no longer exists.
    public static func details(identifier: String) throws -> ContactDetails? {
        let store = CNContactStore()
        try requestAccessIfNeeded(store)
        let keys = [
            CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
            CNContactImageDataKey, CNContactThumbnailImageDataKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactPostalAddressesKey, CNContactUrlAddressesKey,
            CNContactSocialProfilesKey, CNContactBirthdayKey,
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
            urls: contact.urlAddresses.map { LabeledValue(label: label($0.label), value: $0.value as String) },
            socialProfiles: contact.socialProfiles.map {
                LabeledValue(label: $0.value.service, value: $0.value.urlString.isEmpty ? $0.value.username : $0.value.urlString)
            },
            birthday: birthday, imageData: contact.imageData ?? contact.thumbnailImageData)   // some contacts only carry the thumbnail
    }

    private static func requestAccessIfNeeded(_ store: CNContactStore) throws {
        if CNContactStore.authorizationStatus(for: .contacts) == .notDetermined {
            let done = DispatchSemaphore(value: 0)
            store.requestAccess(for: .contacts) { _, _ in done.signal() }
            done.wait()
        }
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .denied, .restricted, .notDetermined:
            throw PplzError.invalid("pplz has no access to Contacts. Allow it in System Settings → Privacy & Security → Contacts, or pass --no-contacts.")
        default:
            break
        }
    }
}
#endif
