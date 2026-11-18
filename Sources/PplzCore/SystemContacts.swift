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
