import Foundation
import ImageIO

public enum EventFormat: String, Codable, CaseIterable, Sendable {
    case liveMeeting = "live-meeting"
    case webCall = "web-call"
    case phoneCall = "phone-call"
    case largerGathering = "gathering"
    case writtenExchange = "written"

    public var displayName: String {
        switch self {
        case .liveMeeting: "Live meeting"
        case .webCall: "Web call"
        case .phoneCall: "Phone call"
        case .largerGathering: "Larger gathering"
        case .writtenExchange: "Written exchange"
        }
    }
}

public enum CXError: Error, Equatable, LocalizedError {
    case notFound(String)
    case invalid(String)
    case ambiguousPerson(String, [PersonEntry])

    public var errorDescription: String? {
        switch self {
        case .notFound(let what):
            return "Not found: \(what)"
        case .invalid(let why):
            return why
        case .ambiguousPerson(let query, let candidates):
            let list = candidates.prefix(20).map { "  \($0.name)  [\($0.id?.uuidString ?? $0.contactIdentifier ?? "-")]" }
            return (["\"\(query)\" matches \(candidates.count) people. Be more specific or use an ID:"] + list).joined(separator: "\n")
        }
    }
}

/// A participant who has no cardXchange person record yet; the record is created together with the event.
public enum NewParticipant: Equatable, Sendable {
    case contact(ContactSummary)
    case named(String)
}

/// A contact as read from the system address book. Never contains the note.
public struct ContactSummary: Codable, Equatable, Sendable {
    public var identifier: String
    public var name: String
    public var nickname: String
    /// The person the contact's `cx://person/<id>` link points to, if it has one.
    public var cxPersonID: UUID?
    /// For telling people of the same name apart.
    public var organization: String
    public var city: String
    public var country: String
    /// Every postal address of the contact, for the map.
    public var addresses: [PostalAddress]

    public init(identifier: String, name: String, nickname: String = "", cxPersonID: UUID? = nil, organization: String = "",
                city: String = "", country: String = "", addresses: [PostalAddress] = []) {
        self.addresses = addresses
        self.organization = organization
        self.city = city
        self.country = country
        self.identifier = identifier
        self.name = name
        self.nickname = nickname
        self.cxPersonID = cxPersonID
    }
}

public struct PersonRef: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
}

/// What cardXchange stores about a person.
public struct PersonSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var contactIdentifier: String?
    public var howWeMet: String
    public var notes: String
    public var eventCount: Int
    public var lastMet: Date?
    /// Desired number of days between meetings; `nil` = no rhythm.
    public var keepInTouchDays: Int?
    public var tags: [String]
    /// LinkedIn profile ID, empty if unknown.
    public var linkedInID: String

    public init(id: UUID, name: String, contactIdentifier: String? = nil, howWeMet: String = "", notes: String = "",
                eventCount: Int = 0, lastMet: Date? = nil, keepInTouchDays: Int? = nil, tags: [String] = [], linkedInID: String = "") {
        self.linkedInID = linkedInID
        self.keepInTouchDays = keepInTouchDays
        self.id = id
        self.name = name
        self.contactIdentifier = contactIdentifier
        self.howWeMet = howWeMet
        self.notes = notes
        self.eventCount = eventCount
        self.lastMet = lastMet
        self.tags = tags
    }
}

public struct ConnectionSnapshot: Codable, Equatable, Sendable {
    public enum Direction: String, Codable, Sendable {
        /// "this person is `kind` `other`"
        case outgoing
        /// "`other` is `kind` this person"
        case incoming
    }

    public var id: UUID
    public var kind: String
    public var other: PersonRef
    public var direction: Direction
}

/// A connection with both people, for mirroring into contacts.
public struct ConnectionRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var kind: String
    public var from: PersonSnapshot
    public var to: PersonSnapshot
}

public struct FollowUpSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var done: Bool
}

public struct OpenFollowUp: Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var eventID: UUID
    public var eventTitle: String
    public var eventStart: Date
    public var participants: [PersonRef]
}

public struct EventSnapshot: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var format: EventFormat
    public var start: Date
    public var end: Date?
    public var place: String
    public var notes: String
    public var participants: [PersonRef]
    public var tags: [String]
    public var links: [String]
    public var followUps: [FollowUpSnapshot]
}

public struct TagSummary: Codable, Equatable, Sendable {
    public var name: String
    public var personCount: Int
    public var eventCount: Int

    public init(name: String, personCount: Int, eventCount: Int) {
        self.name = name
        self.personCount = personCount
        self.eventCount = eventCount
    }
}

public struct EventDraft: Sendable {
    public var title: String
    public var format: EventFormat
    public var start: Date
    public var end: Date?
    public var place: String
    public var notes: String
    public var participants: [UUID]
    public var tags: [String]
    public var additionalParticipants: [NewParticipant]
    public var links: [String]

    public init(title: String = "", format: EventFormat, start: Date, end: Date? = nil, place: String = "",
                notes: String = "", participants: [UUID] = [], tags: [String] = [],
                additionalParticipants: [NewParticipant] = [], links: [String] = []) {
        self.additionalParticipants = additionalParticipants
        self.links = links
        self.title = title
        self.format = format
        self.start = start
        self.end = end
        self.place = place
        self.notes = notes
        self.participants = participants
        self.tags = tags
    }
}

/// Fields left `nil` stay unchanged.
public struct EventChange: Sendable {
    public var title: String?
    public var format: EventFormat?
    public var start: Date?
    public var end: Date?
    public var clearEnd: Bool
    public var place: String?
    public var notes: String?
    /// Replaces the participants (together with `additionalParticipants`).
    public var participants: [UUID]?
    public var tags: [String]?
    public var additionalParticipants: [NewParticipant]
    public var links: [String]?

    public init(title: String? = nil, format: EventFormat? = nil, start: Date? = nil, end: Date? = nil, clearEnd: Bool = false,
                place: String? = nil, notes: String? = nil, participants: [UUID]? = nil, tags: [String]? = nil,
                additionalParticipants: [NewParticipant] = [], links: [String]? = nil) {
        self.additionalParticipants = additionalParticipants
        self.links = links
        self.title = title
        self.format = format
        self.start = start
        self.end = end
        self.clearEnd = clearEnd
        self.place = place
        self.notes = notes
        self.participants = participants
        self.tags = tags
    }
}

public struct EventFilter: Sendable {
    public var person: UUID?
    public var format: EventFormat?
    public var since: Date?
    public var until: Date?
    public var place: String?
    public var tag: String?

    public init(person: UUID? = nil, format: EventFormat? = nil, since: Date? = nil, until: Date? = nil,
                place: String? = nil, tag: String? = nil) {
        self.person = person
        self.format = format
        self.since = since
        self.until = until
        self.place = place
        self.tag = tag
    }
}

/// One of a person's pictures. The image itself is left out of JSON output.
public struct PhotoSnapshot: Encodable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var data: Data

    enum CodingKeys: String, CodingKey { case id, createdAt, pixelWidth, pixelHeight }

    init(id: UUID, createdAt: Date, data: Data) {
        let size = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
        self.id = id
        self.createdAt = createdAt
        self.data = data
        pixelWidth = size?[kCGImagePropertyPixelWidth] as? Int ?? 0
        pixelHeight = size?[kCGImagePropertyPixelHeight] as? Int ?? 0
    }
}

/// Everything shown on a person's card: the contact's own data plus what cardXchange knows.
public struct PersonCard: Equatable, Sendable {
    public var entry: PersonEntry
    /// Live from the address book; `nil` for a cardXchange-only person.
    public var contact: ContactDetails?
    /// `nil` for a contact cardXchange has stored nothing about yet.
    public var stored: PersonSnapshot?
    public var connections: [ConnectionSnapshot]
    public var history: [EventSnapshot]
    public var photos: [PhotoSnapshot] = []
}
