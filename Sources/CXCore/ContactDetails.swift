import Foundation

public struct LabeledValue: Codable, Equatable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// The core data of a contact, read live from the address book and never stored by cardXchange (SPEC §3.1).
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
    /// The related names on the contact card ("spouse — Eva Example"). Shown in the app; left out of JSON output.
    public var relatedNames: [LabeledValue] = []

    private enum CodingKeys: String, CodingKey {
        case identifier, givenName, familyName, nickname, organization, jobTitle, phones, emails, addresses, urls, socialProfiles, birthday
    }

    public init(identifier: String, givenName: String = "", familyName: String = "", nickname: String = "",
                organization: String = "", jobTitle: String = "",
                phones: [LabeledValue] = [], emails: [LabeledValue] = [], addresses: [LabeledValue] = [], urls: [LabeledValue] = [],
                socialProfiles: [LabeledValue] = [], birthday: String? = nil, imageData: Data? = nil,
                relatedNames: [LabeledValue] = []) {
        self.relatedNames = relatedNames
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
        case .message: return URL(string: "sms:" + Self.addressee(text))
        case .video: return URL(string: "facetime:" + Self.addressee(text))
        case .mail: return URL(string: "mailto:" + text)
        case .map:
            return text.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: "maps://?q=" + $0) }
        case .web:
            return URL(string: text.contains("://") ? text : "https://" + text)
        }
    }

    /// A phone number as digits, or a mail address as it is (iMessage and FaceTime take both).
    private static func addressee(_ value: String) -> String {
        value.contains("@") ? value : dialable(value)
    }

    private static func dialable(_ number: String) -> String {
        number.filter { $0.isNumber || $0 == "+" }
    }
}

/// The big round buttons on a card, as in Contacts.
public enum QuickAction: CaseIterable, Sendable {
    case message, call, video, mail

    var action: ContactAction {
        switch self {
        case .message: .message
        case .call: .call
        case .video: .video
        case .mail: .mail
        }
    }
}

/// One value a quick action can act on, e.g. "mobile  +49 170 0000000".
public struct QuickActionChoice: Equatable, Sendable {
    public var label: String
    public var value: String
    public var url: URL

    public init(label: String, value: String, url: URL) {
        self.label = label
        self.value = value
        self.url = url
    }
}

extension ContactDetails {
    /// What a quick action offers: call the phone numbers, mail the mail addresses; message and video the phone
    /// numbers first, then the mail addresses (iMessage and FaceTime take both). Values without a link are left out.
    public func choices(for quick: QuickAction) -> [QuickActionChoice] {
        func choices(_ values: [LabeledValue], fallbackLabel: String) -> [QuickActionChoice] {
            values.compactMap { item in
                quick.action.url(for: item.value).map {
                    QuickActionChoice(label: item.label.isEmpty ? fallbackLabel : item.label, value: item.value, url: $0)
                }
            }
        }
        let phoneChoices = choices(phones, fallbackLabel: "phone")
        let mailChoices = choices(emails, fallbackLabel: "email")
        switch quick {
        case .call: return phoneChoices
        case .mail: return mailChoices
        case .message, .video: return phoneChoices + mailChoices
        }
    }

    /// The quick actions that have at least one value, in the order of the buttons.
    public var availableQuickActions: [QuickAction] {
        QuickAction.allCases.filter { !choices(for: $0).isEmpty }
    }
}

extension PersonCard {
    /// The related names on the contact card that no cardXchange connection stands for: cardXchange writes a row for each of its
    /// connections into the contact, and those are shown as connections already.
    public var relatedNamesOnlyInContacts: [LabeledValue] {
        let connected = Set(connections.map { $0.other.name.trimmed.lowercased() })
        return (contact?.relatedNames ?? []).compactMap {
            let name = $0.value.trimmed
            return name.isEmpty || connected.contains(name.lowercased()) ? nil : LabeledValue(label: $0.label, value: name)
        }
    }

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
