import Foundation

/// The link cardXchange puts into a contact: `cx://person/<id>` (SPEC §3.2). Clicking it in Contacts
/// opens the person in cardXchange; later it is also what identifies a person across devices (SPEC R3).
/// The old form `pplz://person/<id>` with the label `pplz` is still read, and replaced when the contact is synced.
public enum PersonLink {
    public static let label = "cardxchange"
    static let scheme = "cx"
    /// The form written before the rename (`docs/changes/01_rename_to_cardxchange`).
    static let oldLabel = "pplz"
    static let oldScheme = "pplz"

    public static func url(for person: UUID) -> String {
        "\(scheme)://person/\(person.uuidString.lowercased())"
    }

    public static func personID(from url: URL) -> UUID? {
        guard url.scheme == scheme || url.scheme == oldScheme, url.host() == "person" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    /// What the URL rows of one contact need so that they hold exactly one link to this person in the new form:
    /// the new row if there is none, the removal of a second identical new row and of each old row. An old row is
    /// one with the old label and the old scheme (SPEC §3.2). Every other row is left alone.
    public static func changes(urls: [ContactEdit.Item], person: UUID) -> [ContactChange] {
        func link(_ item: ContactEdit.Item) -> URL? {
            URL(string: item.value.trimmed).flatMap { personID(from: $0) == person ? $0 : nil }
        }
        let new = urls.filter { link($0)?.scheme == scheme }
        let old = urls.filter { $0.label == oldLabel && link($0)?.scheme == oldScheme }
        var result: [ContactChange] = []
        if new.isEmpty {
            result.append(.addItem(.url, ContactEdit.Item(label: label, value: url(for: person))))
        }
        var kept: Set<String> = []
        for item in new where !kept.insert(item.value.trimmed).inserted {
            result.append(.removeItem(.url, item))
        }
        result += old.map { .removeItem(.url, $0) }
        return result
    }
}
