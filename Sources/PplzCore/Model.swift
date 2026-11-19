import Foundation
import SwiftData

// Persistent model. Shaped for CloudKit sync from day one (SPEC §8.3):
// every attribute has a default or is optional, every relationship is optional
// and has an inverse, and there are no unique constraints.

@Model
final class Person {
    /// pplz's own identity for a person; becomes `pplz://person/<uuid>`.
    var uuid: UUID = UUID()
    /// Name of a pplz-only person, or the last known name of a linked contact.
    var name: String = ""
    /// `CNContact.identifier` — only valid on this device (SPEC R3).
    /// Slice 2 replaces this with the `pplz` link field stored in the contact.
    var localContactIdentifier: String?
    var howWeMet: String = ""
    var notes: String = ""
    /// The person's LinkedIn profile ID (the part after "/in/"), lower-cased; empty if unknown.
    var linkedInID: String = ""
    var createdAt: Date = Date()
    /// Desired number of days between meetings; `nil` = no rhythm.
    var keepInTouchDays: Int?

    @Relationship(inverse: \Event.participants) var events: [Event]? = []
    var tags: [Tag]? = []
    @Relationship(deleteRule: .cascade, inverse: \Connection.from) var outgoingConnections: [Connection]? = []
    @Relationship(deleteRule: .cascade, inverse: \Connection.to) var incomingConnections: [Connection]? = []
    @Relationship(deleteRule: .cascade, inverse: \PersonPhoto.person) var photos: [PersonPhoto]? = []

    init(name: String, localContactIdentifier: String? = nil) {
        self.name = name
        self.localContactIdentifier = localContactIdentifier
    }
}

@Model
final class Event {
    var uuid: UUID = UUID()
    var title: String = ""
    var formatRaw: String = EventFormat.liveMeeting.rawValue
    var start: Date = Date()
    var end: Date?
    var place: String = ""
    var notes: String = ""
    var links: [String] = []
    var createdAt: Date = Date()

    var participants: [Person]? = []
    var tags: [Tag]? = []
    @Relationship(deleteRule: .cascade, inverse: \FollowUp.event) var followUps: [FollowUp]? = []

    init(title: String, format: EventFormat, start: Date) {
        self.title = title
        self.formatRaw = format.rawValue
        self.start = start
    }
}

@Model
final class Tag {
    var name: String = ""
    @Relationship(inverse: \Person.tags) var persons: [Person]? = []
    @Relationship(inverse: \Event.tags) var events: [Event]? = []

    init(name: String) { self.name = name }
}

/// "`from` is `kind` `to`", e.g. Anna — colleague of — Ben.
@Model
final class Connection {
    var uuid: UUID = UUID()
    var kind: String = ""
    var createdAt: Date = Date()
    var from: Person?
    var to: Person?

    init(kind: String) { self.kind = kind }
}

/// A picture of a person for later face recognition: a real copy of the area around their face,
/// kept in the synced store so that every device has it (SPEC §2.1).
@Model
final class PersonPhoto {
    var uuid: UUID = UUID()
    var createdAt: Date = Date()
    /// JPEG; kept outside the database file, and synced as a CloudKit asset.
    @Attribute(.externalStorage) var imageData: Data = Data()
    var person: Person?

    init(imageData: Data) { self.imageData = imageData }
}

/// A synced app setting.
@Model
final class Setting {
    var key: String = ""
    var value: String = ""

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

@Model
final class FollowUp {
    var uuid: UUID = UUID()
    var text: String = ""
    var done: Bool = false
    var createdAt: Date = Date()
    var event: Event?

    init(text: String) { self.text = text }
}
