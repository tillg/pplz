import Foundation

/// The fields of a contact that pplz lets you edit, as the edit screen shows them (not the note, not the related
/// names, not pplz's own link row). Rows carry the identifier they have in the address book, so that an edit
/// can change exactly the rows that changed; rows added in the form get any identifier the address book does not know.
public struct ContactEdit: Equatable, Sendable {
    /// A phone number, mail address, web address or social profile. `label` is the address book's own label
    /// (e.g. `_$!<Mobile>!$_`, or a custom one), empty for none. For a social profile it is the service, and
    /// `value` the address of the profile (or the user name, if the profile has no address).
    public struct Item: Equatable, Identifiable, Sendable {
        public var id: String
        public var label: String
        public var value: String

        public init(id: String = UUID().uuidString, label: String = "", value: String = "") {
            self.id = id
            self.label = label
            self.value = value
        }
    }

    public struct Address: Equatable, Identifiable, Sendable {
        public var id: String
        public var label: String
        public var street: String
        public var postalCode: String
        public var city: String
        public var country: String

        public init(id: String = UUID().uuidString, label: String = "", street: String = "", postalCode: String = "",
                    city: String = "", country: String = "") {
            self.id = id
            self.label = label
            self.street = street
            self.postalCode = postalCode
            self.city = city
            self.country = country
        }

        var isEmpty: Bool { [street, postalCode, city, country].allSatisfy { $0.trimmed.isEmpty } }
        /// What names this address in a message.
        var summary: String { [street, city, country, postalCode].map(\.trimmed).first { !$0.isEmpty } ?? "" }
    }

    /// Day and month, and the year if it is known: a birthday without a year stays without one.
    public struct Birthday: Equatable, Sendable {
        public var day: Int
        public var month: Int
        public var year: Int?

        public init(day: Int, month: Int, year: Int? = nil) {
            self.day = day
            self.month = month
            self.year = year
        }
    }

    public var givenName: String
    public var familyName: String
    public var nickname: String
    public var organization: String
    public var jobTitle: String
    public var phones: [Item]
    public var emails: [Item]
    public var urls: [Item]
    public var socialProfiles: [Item]
    public var addresses: [Address]
    public var birthday: Birthday?

    public init(givenName: String = "", familyName: String = "", nickname: String = "", organization: String = "", jobTitle: String = "",
                phones: [Item] = [], emails: [Item] = [], urls: [Item] = [], socialProfiles: [Item] = [],
                addresses: [Address] = [], birthday: Birthday? = nil) {
        self.givenName = givenName
        self.familyName = familyName
        self.nickname = nickname
        self.organization = organization
        self.jobTitle = jobTitle
        self.phones = phones
        self.emails = emails
        self.urls = urls
        self.socialProfiles = socialProfiles
        self.addresses = addresses
        self.birthday = birthday
    }

    /// Whether the contact has something to be listed by: a contact needs a name or a company.
    public var hasName: Bool {
        ![givenName, familyName, organization].allSatisfy { $0.trimmed.isEmpty }
    }

    /// Whether this row is pplz's own link, which belongs to pplz and is never edited here.
    public static func isPplzLink(_ item: Item) -> Bool {
        URL(string: item.value.trimmed).flatMap(PersonLink.personID) != nil
    }
}

public enum ContactChange: Equatable, Sendable {
    public enum TextField: Sendable, CaseIterable {
        case givenName, familyName, nickname, organization, jobTitle

        var title: String {
            switch self {
            case .givenName: "first name"
            case .familyName: "last name"
            case .nickname: "nickname"
            case .organization: "company"
            case .jobTitle: "job title"
            }
        }

        /// What the Contacts app calls it in scripts.
        var scriptProperty: String {
            switch self {
            case .givenName: "first name"
            case .familyName: "last name"
            case .nickname: "nickname"
            case .organization: "organization"
            case .jobTitle: "job title"
            }
        }

        func value(in edit: ContactEdit) -> String {
            switch self {
            case .givenName: edit.givenName
            case .familyName: edit.familyName
            case .nickname: edit.nickname
            case .organization: edit.organization
            case .jobTitle: edit.jobTitle
            }
        }
    }

    public enum ItemKind: Sendable, CaseIterable {
        case phone, email, url, socialProfile

        var title: String {
            switch self {
            case .phone: "phone"
            case .email: "email"
            case .url: "web address"
            case .socialProfile: "social profile"
            }
        }

        func items(in edit: ContactEdit) -> [ContactEdit.Item] {
            switch self {
            case .phone: edit.phones
            case .email: edit.emails
            case .url: edit.urls
            case .socialProfile: edit.socialProfiles
            }
        }
    }

    case text(TextField, from: String, to: String)
    case addItem(ItemKind, ContactEdit.Item)
    case updateItem(ItemKind, from: ContactEdit.Item, to: ContactEdit.Item)
    case removeItem(ItemKind, ContactEdit.Item)
    case addAddress(ContactEdit.Address)
    case updateAddress(from: ContactEdit.Address, to: ContactEdit.Address)
    case removeAddress(ContactEdit.Address)
    case birthday(from: ContactEdit.Birthday?, to: ContactEdit.Birthday?)
}

extension ContactEdit {
    /// What the user changed: the differences between the form as loaded and as saved, nothing for what is the same.
    /// Whitespace around values does not count; a row whose value was emptied is removed, an empty new row is ignored;
    /// pplz's own link row is ignored on both sides.
    public static func changes(from before: ContactEdit, to after: ContactEdit) -> [ContactChange] {
        var changes: [ContactChange] = []
        for field in ContactChange.TextField.allCases {
            let old = field.value(in: before), new = field.value(in: after).trimmed
            if old.trimmed != new { changes.append(.text(field, from: old, to: new)) }
        }
        for kind in ContactChange.ItemKind.allCases {
            let old = kind.items(in: before).filter { !isPplzLink($0) }
            let new = kind.items(in: after).filter { !isPplzLink($0) }.map { Item(id: $0.id, label: $0.label, value: $0.value.trimmed) }
            let kept = new.filter { item in !item.value.isEmpty }
            changes += old.filter { item in !kept.contains { $0.id == item.id } }.map { .removeItem(kind, $0) }
            for item in kept {
                if let was = old.first(where: { $0.id == item.id }) {
                    if was.label != item.label || was.value.trimmed != item.value { changes.append(.updateItem(kind, from: was, to: item)) }
                } else {
                    changes.append(.addItem(kind, item))
                }
            }
        }
        let kept = after.addresses.filter { !$0.isEmpty }
        changes += before.addresses.filter { address in !kept.contains { $0.id == address.id } }.map { .removeAddress($0) }
        for address in kept {
            let trimmed = Address(id: address.id, label: address.label, street: address.street.trimmed, postalCode: address.postalCode.trimmed,
                                  city: address.city.trimmed, country: address.country.trimmed)
            if let was = before.addresses.first(where: { $0.id == address.id }) {
                let same = was.label == trimmed.label && was.street.trimmed == trimmed.street && was.postalCode.trimmed == trimmed.postalCode
                    && was.city.trimmed == trimmed.city && was.country.trimmed == trimmed.country
                if !same { changes.append(.updateAddress(from: was, to: trimmed)) }
            } else {
                changes.append(.addAddress(trimmed))
            }
        }
        if before.birthday != after.birthday { changes.append(.birthday(from: before.birthday, to: after.birthday)) }
        return changes
    }

    /// The things the user wants to change that have been changed by someone else since the form was loaded:
    /// a text field or birthday that no longer holds the old value, a row that is gone or different. Adding never conflicts.
    /// Names what is in the way, e.g. `phone +49 170 0000000`, for the message to the user.
    public static func conflicts(of changes: [ContactChange], with current: ContactEdit) -> [String] {
        var result: [String] = []
        for change in changes {
            switch change {
            case .text(let field, let from, _):
                if field.value(in: current) != from { result.append(field.title) }
            case .updateItem(let kind, let from, _), .removeItem(let kind, let from):
                if kind.items(in: current).first(where: { $0.id == from.id }) != from { result.append("\(kind.title) \(from.value.trimmed)") }
            case .updateAddress(let from, _), .removeAddress(let from):
                if current.addresses.first(where: { $0.id == from.id }) != from { result.append("address \(from.summary)") }
            case .birthday(let from, _):
                if current.birthday != from { result.append("birthday") }
            case .addItem, .addAddress:
                break
            }
        }
        return result
    }
}
