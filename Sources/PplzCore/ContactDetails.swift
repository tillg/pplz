import Foundation

public struct LabeledValue: Codable, Equatable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// The core data of a contact, read live from the address book and never stored by pplz (SPEC §3.1).
/// Deliberately has no note field (SPEC §8.1).
public struct ContactDetails: Codable, Equatable, Sendable {
    public var identifier: String
    public var givenName: String
    public var familyName: String
    public var nickname: String
    public var organization: String
    public var jobTitle: String
    public var phones: [LabeledValue]
    public var emails: [LabeledValue]
    public var addresses: [LabeledValue]
    public var urls: [LabeledValue]
    public var socialProfiles: [LabeledValue]
    /// `YYYY-MM-DD`, or `--MM-DD` when the year is unknown.
    public var birthday: String?
    /// The contact's picture. Shown in the app; left out of JSON output.
    public var imageData: Data? = nil

    private enum CodingKeys: String, CodingKey {
        case identifier, givenName, familyName, nickname, organization, jobTitle, phones, emails, addresses, urls, socialProfiles, birthday
    }

    public init(identifier: String, givenName: String = "", familyName: String = "", nickname: String = "",
                organization: String = "", jobTitle: String = "",
                phones: [LabeledValue] = [], emails: [LabeledValue] = [], addresses: [LabeledValue] = [], urls: [LabeledValue] = [],
                socialProfiles: [LabeledValue] = [], birthday: String? = nil, imageData: Data? = nil) {
        self.nickname = nickname
        self.imageData = imageData
        self.identifier = identifier
        self.givenName = givenName
        self.familyName = familyName
        self.organization = organization
        self.jobTitle = jobTitle
        self.phones = phones
        self.emails = emails
        self.addresses = addresses
        self.urls = urls
        self.socialProfiles = socialProfiles
        self.birthday = birthday
    }

    /// Completed years since the birthday; nil when the year is unknown or the date lies in the future.
    public func age(on today: Date = .now, calendar: Calendar = .current) -> Int? {
        let parts = (birthday ?? "").split(separator: "-").compactMap { Int($0) }
        let now = calendar.dateComponents([.year, .month, .day], from: today)
        guard parts.count == 3, let year = now.year, let month = now.month, let day = now.day else { return nil }
        let hadBirthday = (month, day) >= (parts[1], parts[2])   // born on 29 February: a year older on 1 March
        let age = year - parts[0] - (hadBirthday ? 0 : 1)
        return age >= 0 ? age : nil
    }

    /// The birthday with the age next to it, e.g. `1980-05-17 · 46 years`.
    public func birthdayWithAge(on today: Date = .now, calendar: Calendar = .current) -> String? {
        guard let birthday else { return nil }
        guard let age = age(on: today, calendar: calendar) else { return birthday }
        return "\(birthday) · \(age) \(age == 1 ? "year" : "years")"
    }

    /// One line per field that has a value, for display.
    public var lines: [String] {
        func single(_ title: String, _ value: String) -> [String] { value.isEmpty ? [] : ["\(title): \(value)"] }
        func many(_ title: String, _ values: [LabeledValue]) -> [String] {
            values.map { $0.label.isEmpty ? "\(title): \($0.value)" : "\(title) (\($0.label)): \($0.value)" }
        }
        return single("First name", givenName) + single("Last name", familyName) + single("Nickname", nickname)
            + single("Company", organization) + single("Job title", jobTitle)
            + many("Phone", phones) + many("Email", emails) + many("Address", addresses) + many("URL", urls)
            + socialProfiles.map { "\($0.label.isEmpty ? "Social" : $0.label): \($0.value)" }
            + single("Birthday", birthday ?? "")
    }
}

/// What can be done with a contact field: the link that starts a call, a mail, a map search, ….
public enum ContactAction: Sendable {
    case call, message, video, mail, map, web

    public func url(for value: String) -> URL? {
        let text = value.trimmed
        guard !text.isEmpty else { return nil }
        switch self {
        case .call: return URL(string: "tel:" + Self.dialable(text))
        case .message: return URL(string: "sms:" + Self.dialable(text))
        case .video: return URL(string: "facetime:" + Self.dialable(text))
        case .mail: return URL(string: "mailto:" + text)
        case .map:
            return text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: "maps://?q=" + $0) }
        case .web:
            return URL(string: text.contains("://") ? text : "https://" + text)
        }
    }

    private static func dialable(_ number: String) -> String {
        number.filter { $0.isNumber || $0 == "+" }
    }
}

extension PersonCard {
    /// The big line on the card: the nickname if the contact has one, as in Contacts.
    public var title: String {
        let nickname = contact?.nickname.trimmed ?? ""
        return nickname.isEmpty ? entry.name : nickname
    }

    /// The small line: full name (when the nickname is the title), job title and company.
    public var subtitle: String {
        guard let contact else { return "" }
        let fullName = contact.nickname.trimmed.isEmpty ? "" : entry.name
        return [fullName, contact.jobTitle, contact.organization].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
