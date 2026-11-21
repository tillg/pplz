#if canImport(Contacts)
import Contacts
import Foundation

/// Editing and creating contacts: reads a contact as a `ContactEdit` and writes back only what changed.
extension SystemContacts {
    private static var editKeys: [CNKeyDescriptor] {
        [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactNicknameKey, CNContactOrganizationNameKey, CNContactJobTitleKey,
         CNContactPhoneNumbersKey, CNContactEmailAddressesKey, CNContactUrlAddressesKey, CNContactSocialProfilesKey,
         CNContactPostalAddressesKey, CNContactBirthdayKey] as [CNKeyDescriptor]
    }

    /// The editable fields of one contact, read fresh; `nil` if the contact no longer exists.
    /// Labels are the address book's own (`_$!<Mobile>!$_` or a custom one). cardXchange's link row is left out.
    public static func contactEdit(identifier: String) throws -> ContactEdit? {
        let store = CNContactStore()
        try requestAccessIfNeeded(store)
        guard let contact = try store.unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers: [identifier]),
                                                      keysToFetch: editKeys).first else { return nil }
        var result = edit(from: contact)
        result.contactIdentifier = contact.identifier
        return result
    }

    private static func edit(from contact: CNContact) -> ContactEdit {
        func items<V>(_ values: [CNLabeledValue<V>], _ text: (V) -> String) -> [ContactEdit.Item] {
            values.map { ContactEdit.Item(id: $0.identifier, label: $0.label ?? "", value: text($0.value)) }
        }
        var birthday: ContactEdit.Birthday?
        if let parts = contact.birthday, let month = parts.month, let day = parts.day {
            birthday = .init(day: day, month: month, year: parts.year == 1604 ? nil : parts.year)   // 1604: Contacts' "no year"
        }
        return ContactEdit(
            givenName: contact.givenName, familyName: contact.familyName, nickname: contact.nickname,
            organization: contact.organizationName, jobTitle: contact.jobTitle,
            phones: items(contact.phoneNumbers) { $0.stringValue },
            emails: items(contact.emailAddresses) { $0 as String },
            urls: items(contact.urlAddresses) { $0 as String }.filter { !ContactEdit.isCXLink($0) },
            socialProfiles: contact.socialProfiles.map {
                ContactEdit.Item(id: $0.identifier, label: $0.value.service, value: $0.value.urlString.isEmpty ? $0.value.username : $0.value.urlString)
            },
            addresses: contact.postalAddresses.map {
                ContactEdit.Address(id: $0.identifier, label: $0.label ?? "", street: $0.value.street, postalCode: $0.value.postalCode,
                                    city: $0.value.city, country: $0.value.country)
            },
            birthday: birthday)
    }

    /// All URL rows of one contact, the link rows included; `nil` if the contact no longer exists.
    /// Reading works on the Mac also for a contact that has a note; only a save is refused there (SPEC §8.1, S4).
    public static func urlRows(identifier: String) throws -> [ContactEdit.Item]? {
        let store = CNContactStore()
        try requestAccessIfNeeded(store)
        guard let contact = try store.unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers: [identifier]),
                                                      keysToFetch: [CNContactUrlAddressesKey as CNKeyDescriptor]).first else { return nil }
        return contact.urlAddresses.map { ContactEdit.Item(id: $0.identifier, label: $0.label ?? "", value: $0.value as String) }
    }

    /// Writes the changes of `PersonLink.changes` to the link rows of one contact. Used on iPhone and iPad; the Mac
    /// goes through the Contacts app. `apply(_:toContact:)` does not fit: it leaves the link rows out of its check.
    public static func applyLinkChanges(_ changes: [ContactChange], toContact identifier: String) throws {
        guard !changes.isEmpty else { return }
        let store = CNContactStore()
        try requestAccessIfNeeded(store)
        guard let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: [CNContactUrlAddressesKey as CNKeyDescriptor])
            .mutableCopy() as? CNMutableContact else { return }
        apply(changes, to: contact)
        let request = CNSaveRequest()
        request.update(contact)
        try store.execute(request)
    }

    /// Creates a contact with these fields and returns its identifier. A new contact has no note, so this works
    /// on every platform (SPEC §8.1, S1). `link` adds cardXchange's link row, e.g. for a restored person.
    public static func createContact(_ edit: ContactEdit, link: ContactMirror.Row? = nil) throws -> String {
        let store = CNContactStore()
        try requestAccessIfNeeded(store)
        let contact = CNMutableContact()
        apply(ContactEdit.changes(from: ContactEdit(), to: edit), to: contact)
        if let link { contact.urlAddresses.append(CNLabeledValue(label: link.label, value: link.value as NSString)) }
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
        return contact.identifier
    }

    /// Writes these changes into the contact, and nothing else: rows that did not change keep their identity,
    /// and the note, the related names and cardXchange's link are not touched. Refuses, writing nothing, if the contact
    /// was changed in the meantime in something the user also changed.
    /// On the Mac a contact that has a note refuses a direct save (SPEC §8.1, S4); then the Contacts app is asked to do it.
    public static func apply(_ changes: [ContactChange], toContact identifier: String) throws {
        guard !changes.isEmpty else { return }
        let store = CNContactStore()
        try requestAccessIfNeeded(store)
        guard let current = try contactEdit(identifier: identifier) else {
            throw CXError.invalid("This contact no longer exists in Contacts.")
        }
        let conflicts = ContactEdit.conflicts(of: changes, with: current)
        guard conflicts.isEmpty else {
            throw CXError.invalid("This contact was changed in Contacts in the meantime (\(conflicts.joined(separator: ", "))). Nothing was saved. Close this form and open it again.")
        }
        guard let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: editKeys).mutableCopy() as? CNMutableContact else { return }
        apply(changes, to: contact)
        let request = CNSaveRequest()
        request.update(contact)
        do {
            try store.execute(request)
        } catch {
            #if os(macOS)
            guard refusesBecauseOfNote(error) else { throw error }
            do {
                try ContactsApp.apply(changes, identifier: identifier)
            } catch {
                throw CXError.invalid("This contact has a note, so the Mac only lets the Contacts app change it. \((error as? LocalizedError)?.errorDescription ?? "\(error)")")
            }
            #else
            throw error
            #endif
        }
    }

    /// Deletes the contact from the address book (SPEC §3.4). Nothing happens if it is gone already.
    /// On the Mac a contact that has a note refuses a direct save (SPEC §8.1, S4); then the Contacts app is asked to do it.
    public static func deleteContact(identifier: String) throws {
        let store = CNContactStore()
        try requestAccessIfNeeded(store)
        guard let contact = try store.unifiedContacts(matching: CNContact.predicateForContacts(withIdentifiers: [identifier]),
                                                      keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor]).first?
            .mutableCopy() as? CNMutableContact else { return }
        let request = CNSaveRequest()
        request.delete(contact)
        do {
            try store.execute(request)
        } catch {
            #if os(macOS)
            guard refusesBecauseOfNote(error) else { throw error }
            _ = try ContactsApp.deletePerson(identifier: identifier)
            #else
            throw error
            #endif
        }
    }

    #if os(macOS)
    /// The Mac refuses to save a contact that has a note without Apple's notes entitlement: Cocoa error 134092 (SPEC §8.1, S4).
    static func refusesBecauseOfNote(_ error: Error) -> Bool {
        let error = error as NSError
        return error.code == 134092 || (error.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == 134092
    }
    #endif

    private static func apply(_ changes: [ContactChange], to contact: CNMutableContact) {
        var phones = Rows<CNPhoneNumber>(), emails = Rows<NSString>(), urls = Rows<NSString>()
        var profiles = Rows<CNSocialProfile>(), addresses = Rows<CNPostalAddress>()
        var birthday: DateComponents??
        for change in changes {
            switch change {
            case .text(let field, _, let value):
                switch field {
                case .givenName: contact.givenName = value
                case .familyName: contact.familyName = value
                case .nickname: contact.nickname = value
                case .organization: contact.organizationName = value
                case .jobTitle: contact.jobTitle = value
                }
            case .addItem(let kind, let item):
                switch kind {
                case .phone: phones.adds.append((item.label, CNPhoneNumber(stringValue: item.value)))
                case .email: emails.adds.append((item.label, item.value as NSString))
                case .url: urls.adds.append((item.label, item.value as NSString))
                case .socialProfile: profiles.adds.append(("", profile(item, from: nil)))
                }
            case .updateItem(let kind, _, let item):
                switch kind {
                case .phone: phones.updates.append((item.id, item.label, { _ in CNPhoneNumber(stringValue: item.value) }))
                case .email: emails.updates.append((item.id, item.label, { _ in item.value as NSString }))
                case .url: urls.updates.append((item.id, item.label, { _ in item.value as NSString }))
                case .socialProfile: profiles.updates.append((item.id, nil, { profile(item, from: $0) }))
                }
            case .removeItem(let kind, let item):
                switch kind {
                case .phone: phones.removes.insert(item.id)
                case .email: emails.removes.insert(item.id)
                case .url: urls.removes.insert(item.id)
                case .socialProfile: profiles.removes.insert(item.id)
                }
            case .addAddress(let address):
                addresses.adds.append((address.label, postalAddress(address, from: nil)))
            case .updateAddress(_, let address):
                addresses.updates.append((address.id, address.label, { postalAddress(address, from: $0) }))
            case .removeAddress(let address):
                addresses.removes.insert(address.id)
            case .birthday(_, let new):
                birthday = .some(new.map {
                    DateComponents(calendar: Calendar(identifier: .gregorian), year: $0.year, month: $0.month, day: $0.day)
                })
            }
        }
        if !phones.isEmpty { contact.phoneNumbers = phones.apply(to: contact.phoneNumbers) }
        if !emails.isEmpty { contact.emailAddresses = emails.apply(to: contact.emailAddresses) }
        if !urls.isEmpty { contact.urlAddresses = urls.apply(to: contact.urlAddresses) }
        if !profiles.isEmpty { contact.socialProfiles = profiles.apply(to: contact.socialProfiles) }
        if !addresses.isEmpty { contact.postalAddresses = addresses.apply(to: contact.postalAddresses) }
        if let birthday { contact.birthday = birthday }
    }

    /// Adds, changes and removes rows of one kind, by the rows' identifiers; every other row is passed on as it is.
    private struct Rows<V: NSCopying & NSSecureCoding> {
        var adds: [(label: String, value: V)] = []
        /// `label` is nil to keep the row's label.
        var updates: [(id: String, label: String?, merge: (V) -> V)] = []
        var removes: Set<String> = []

        var isEmpty: Bool { adds.isEmpty && updates.isEmpty && removes.isEmpty }

        func apply(to values: [CNLabeledValue<V>]) -> [CNLabeledValue<V>] {
            var result = values.filter { !removes.contains($0.identifier) }
            for update in updates {
                guard let index = result.firstIndex(where: { $0.identifier == update.id }) else { continue }
                let row = result[index]
                result[index] = (update.label.map { row.settingLabel($0.isEmpty ? nil : $0) } ?? row).settingValue(update.merge(row.value))
            }
            return result + adds.map { CNLabeledValue(label: $0.label.isEmpty ? nil : $0.label, value: $0.value) }
        }
    }

    /// A social profile: the service is the item's label, the value an address (kept as the URL) or a user name.
    /// Parts the form does not show (the user identifier) are kept.
    private static func profile(_ item: ContactEdit.Item, from old: CNSocialProfile?) -> CNSocialProfile {
        let value = item.value.trimmed
        if let old, value == (old.urlString.isEmpty ? old.username : old.urlString) {
            return CNSocialProfile(urlString: old.urlString, username: old.username, userIdentifier: old.userIdentifier, service: item.label)
        }
        let isURL = value.contains("/")
        return CNSocialProfile(urlString: isURL ? value : "", username: isURL ? (URL(string: value)?.lastPathComponent ?? "") : value,
                               userIdentifier: old?.userIdentifier, service: item.label)
    }

    /// A postal address with the shown parts set; state, the country code and the rest of an existing address are kept.
    private static func postalAddress(_ address: ContactEdit.Address, from old: CNPostalAddress?) -> CNPostalAddress {
        let result = (old?.mutableCopy() as? CNMutablePostalAddress) ?? CNMutablePostalAddress()
        result.street = address.street
        result.postalCode = address.postalCode
        result.city = address.city
        if result.country != address.country { result.isoCountryCode = "" }
        result.country = address.country
        return result
    }
}
#endif
