import Foundation

/// The link pplz puts into a contact: `pplz://person/<id>` (SPEC §3.2). Clicking it in Contacts
/// opens the person in pplz; later it is also what identifies a person across devices (SPEC R3).
public enum PersonLink {
    public static let label = "pplz"

    public static func url(for person: UUID) -> String {
        "pplz://person/\(person.uuidString.lowercased())"
    }

    public static func personID(from url: URL) -> UUID? {
        guard url.scheme == "pplz", url.host() == "person" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
