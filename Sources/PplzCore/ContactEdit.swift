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
    /// The contact this was read from; empty for a new contact. A save goes to exactly this contact, whatever else
    /// is selected in the meantime. Not a field: it is never part of a diff.
    public var contactIdentifier: String

    public init(givenName: String = "", familyName: String = "", nickname: String = "", organization: String = "", jobTitle: String = "",
                phones: [Item] = [], emails: [Item] = [], urls: [Item] = [], socialProfiles: [Item] = [],
                addresses: [Address] = [], birthday: Birthday? = nil, contactIdentifier: String = "") {
        self.contactIdentifier = contactIdentifier
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

extension ContactEdit.Birthday {
    /// Written out the way the region does it: "2. September 1963", or "2. September" without a year.
    public func text(locale: Locale) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        // 2000 is a leap year, so 29 February without a year can be written too
        guard let date = calendar.date(from: DateComponents(year: year ?? 2000, month: month, day: day)) else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = .gmt
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(year == nil ? "dMMMM" : "dMMMMy")
        return formatter.string(from: date)
    }

    /// Reads a typed date, with or without a year: "2. September 1963", "2 Sep", "2.9.", "1963-09-02".
    /// Month names are read in the region's language and in English; numbers alone follow the region's order
    /// (day first in Germany, month first in the US). A year has four digits. `nil` for anything that is not a date.
    public static func parse(_ text: String, locale: Locale) -> ContactEdit.Birthday? {
        let tokens = text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        var numbers: [Int] = [], year: Int?, namedMonth: Int?, startsWithYear = false
        for (index, token) in tokens.enumerated() {
            if let number = Int(token) {
                if token.count == 4 {
                    guard year == nil else { return nil }
                    year = number
                    startsWithYear = index == 0
                } else if token.count <= 2 {
                    numbers.append(number)
                } else {
                    return nil
                }
            } else if let month = month(named: token, locale: locale), namedMonth == nil {
                namedMonth = month
            } else {
                return nil
            }
        }
        let day: Int, month: Int
        if let namedMonth, numbers.count == 1 {
            (day, month) = (numbers[0], namedMonth)
        } else if namedMonth == nil, numbers.count == 2 {
            let monthFirst = startsWithYear || monthComesFirst(in: locale)
            (day, month) = monthFirst ? (numbers[1], numbers[0]) : (numbers[0], numbers[1])
        } else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(year: year ?? 2000, month: month, day: day)
        guard (1...12).contains(month), day >= 1, components.isValidDate(in: calendar) else { return nil }
        return ContactEdit.Birthday(day: day, month: month, year: year)
    }

    private static func month(named token: String, locale: Locale) -> Int? {
        let word = token.lowercased()
        for identifier in [locale.identifier, "en_GB"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: identifier)
            let names = (formatter.monthSymbols ?? []).map { $0.lowercased() }
            if let index = names.firstIndex(of: word) { return index + 1 }
            // a shortened name, from three letters on: "Sep", "Sept", "Okt"
            let matches = names.indices.filter { word.count >= 3 && names[$0].hasPrefix(word) }
            if matches.count == 1 { return matches[0] + 1 }
        }
        return nil
    }

    private static func monthComesFirst(in locale: Locale) -> Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "dM"
        guard let month = format.firstIndex(of: "M"), let day = format.firstIndex(of: "d") else { return false }
        return month < day
    }
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
            // a row that is the same as when the form loaded never produces a change, whatever it holds
            for was in old {
                guard let item = new.first(where: { $0.id == was.id }) else { changes.append(.removeItem(kind, was)); continue }
                if was.label == item.label && was.value.trimmed == item.value { continue }
                changes.append(item.value.isEmpty && !was.value.trimmed.isEmpty ? .removeItem(kind, was) : .updateItem(kind, from: was, to: item))
            }
            changes += new.filter { item in !item.value.isEmpty && !old.contains { $0.id == item.id } }.map { .addItem(kind, $0) }
        }
        for was in before.addresses {
            guard let address = after.addresses.first(where: { $0.id == was.id }) else { changes.append(.removeAddress(was)); continue }
            let item = Address(id: address.id, label: address.label, street: address.street.trimmed, postalCode: address.postalCode.trimmed,
                               city: address.city.trimmed, country: address.country.trimmed)
            let same = was.label == item.label && was.street.trimmed == item.street && was.postalCode.trimmed == item.postalCode
                && was.city.trimmed == item.city && was.country.trimmed == item.country
            if same { continue }
            changes.append(item.isEmpty && !was.isEmpty ? .removeAddress(was) : .updateAddress(from: was, to: item))
        }
        for address in after.addresses where !address.isEmpty && !before.addresses.contains(where: { $0.id == address.id }) {
            changes.append(.addAddress(Address(id: address.id, label: address.label, street: address.street.trimmed, postalCode: address.postalCode.trimmed,
                                               city: address.city.trimmed, country: address.country.trimmed)))
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
