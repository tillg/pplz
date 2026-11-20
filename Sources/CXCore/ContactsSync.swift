import Foundation

/// Keeps the address book in step with cardXchange: related names for connections and the history block
/// in contact notes. Shared by the CLI and the app. Planning works everywhere; writing goes through
/// the Contacts app and therefore only happens on the Mac for now.
///
/// Work is split in two so that a UI stays responsive: a *plan* is read from the store
/// (cheap, on the store's thread), and *applying* it talks to the Contacts app (slow, any thread).
public enum ContactsSync {
    public struct HistoryUpdate: Equatable, Sendable {
        public var contactIdentifier: String
        public var name: String
        /// The block to write; `nil` removes cardXchange's block from the note.
        public var block: String?
    }

    /// The history blocks these persons' contacts should have. Empty unless "Show history in Contacts"
    /// is on; `remove` plans the removal of the blocks instead (also when the setting is off).
    public static func historyPlan(_ store: CXStore, persons: [UUID], remove: Bool = false) throws -> [HistoryUpdate] {
        guard try remove || store.showsHistoryInContacts() else { return [] }
        var seen: Set<UUID> = []
        return try persons.filter { seen.insert($0).inserted }.compactMap { id in
            let person = try store.person(id)
            guard let identifier = person.contactIdentifier else { return nil }
            let block = remove ? nil : NotesBlock.render(history: try store.history(of: id))
            return HistoryUpdate(contactIdentifier: identifier, name: person.name, block: block)
        }
    }

    /// The cardXchange link row each of these persons' contacts should have (SPEC §3.2).
    public static func linkPlan(_ store: CXStore, persons: [UUID]) throws -> [ContactMirror.Row] {
        var seen: Set<UUID> = []
        return try persons.filter { seen.insert($0).inserted }.compactMap { id in
            try store.person(id).contactIdentifier.map {
                ContactMirror.Row(contactIdentifier: $0, label: PersonLink.label, value: PersonLink.url(for: id))
            }
        }
    }

    /// Writes link rows: gives each contact one link in the new form and removes the old form (`PersonLink.changes`).
    /// The changes of one contact are written together and recorded in the journal after the write.
    /// Rows the journal already knows are skipped without asking Contacts, unless `recheck`.
    public static func applyLinks(_ rows: [ContactMirror.Row], journal: ContactJournal, recheck: Bool = false) -> [String] {
        rows.compactMap { row in
            do {
                if try !recheck && journal.cxAdded(row, field: "url") { return nil }
                guard let person = URL(string: row.value).flatMap(PersonLink.personID),
                      let urls = try SystemContacts.urlRows(identifier: row.contactIdentifier) else { return nil }
                let changes = PersonLink.changes(urls: urls, person: person)
                guard !changes.isEmpty else { return nil }
                #if os(macOS)
                try ContactsApp.apply(changes, identifier: row.contactIdentifier)
                #else
                try SystemContacts.applyLinkChanges(changes, toContact: row.contactIdentifier)
                #endif
                var added = false
                for change in changes {
                    switch change {
                    case .addItem(_, let item):
                        added = true
                        try journal.record(.added, ContactMirror.Row(contactIdentifier: row.contactIdentifier, label: item.label, value: item.value), field: "url")
                    case .removeItem(_, let item):
                        try journal.record(.removed, ContactMirror.Row(contactIdentifier: row.contactIdentifier, label: item.label, value: item.value), field: "url")
                    default:
                        break
                    }
                }
                return added ? "Contacts: added the cardXchange link" : "Contacts: removed an old or second link"
            } catch {
                return "Contacts: could not update the cardXchange link — \(describe(error))"
            }
        }
    }

    /// The related-name rows of a connection.
    public static func rows(_ connection: ConnectionRecord) -> [ContactMirror.Row] {
        ContactMirror.rows(from: .init(name: connection.from.name, contactIdentifier: connection.from.contactIdentifier),
                           kind: connection.kind,
                           to: .init(name: connection.to.name, contactIdentifier: connection.to.contactIdentifier))
    }

    /// Writes the planned blocks into the notes. Returns one message per contact that changed or failed.
    /// A note is only replaced if it still reads as it did when it was read here.
    public static func apply(_ updates: [HistoryUpdate], journal: ContactJournal) -> [String] {
        #if os(macOS)
        updates.compactMap { update in
            do {
                let note = try ContactsApp.readNote(identifier: update.contactIdentifier)
                let merged = NotesBlock.merge(note: note, block: update.block)
                guard merged != note else { return nil }
                guard try ContactsApp.writeNote(identifier: update.contactIdentifier, expected: note, new: merged) == .written else {
                    return "Contacts: the note of \(update.name) changed while cardXchange was updating it — nothing written; run `cx contacts sync`"
                }
                let summary = update.block?.split(separator: "\n").dropFirst().first.map(String.init) ?? "block removed"
                try journal.record(update.block == nil ? .removed : .added,
                                   ContactMirror.Row(contactIdentifier: update.contactIdentifier, label: "history", value: summary),
                                   field: "note")
                return update.block == nil
                    ? "Contacts: removed history from the note of \(update.name)"
                    : "Contacts: updated history in the note of \(update.name)"
            } catch {
                return "Contacts: could not update the note of \(update.name) — \(describe(error))"
            }
        }
        #else
        return []   // Contacts can only be scripted on the Mac
        #endif
    }

    /// The plain-label rows older versions wrote for a connection (see `ContactMirror.legacyRows`).
    public static func legacyRows(_ connection: ConnectionRecord) -> [ContactMirror.Row] {
        ContactMirror.legacyRows(from: .init(name: connection.from.name, contactIdentifier: connection.from.contactIdentifier),
                                 kind: connection.kind,
                                 to: .init(name: connection.to.name, contactIdentifier: connection.to.contactIdentifier))
    }

    /// Adds related-name rows. A failure is reported but does not undo what cardXchange stored.
    public static func mirror(_ rows: [ContactMirror.Row], journal: ContactJournal) -> [String] {
        #if os(macOS)
        rows.map { row in
            do {
                // a row cardXchange wrote earlier with the plain word is replaced by the one with Apple's label
                let legacy = ContactMirror.Row(contactIdentifier: row.contactIdentifier, label: readable(row.label), value: row.value)
                if legacy != row, try journal.cxAdded(legacy) {
                    _ = try ContactsApp.removeRelatedName(legacy)
                    try journal.record(.removed, legacy)
                }
                switch try ContactsApp.addRelatedName(row) {
                case .added:
                    try journal.record(.added, row)
                    return "Contacts: added \"\(readable(row.label)): \(row.value)\""
                default:
                    return "Contacts: \"\(readable(row.label)): \(row.value)\" was already there"
                }
            } catch {
                return "Contacts: could not add \"\(readable(row.label)): \(row.value)\" — \(describe(error))"
            }
        }
        #else
        return []   // Contacts can only be scripted on the Mac
        #endif
    }

    /// Removes related-name rows, but only those the journal says cardXchange added.
    public static func unmirror(_ rows: [ContactMirror.Row], journal: ContactJournal) -> [String] {
        #if os(macOS)
        rows.compactMap { row in
            do {
                guard try journal.cxAdded(row) else { return nil }
                let removed = try ContactsApp.removeRelatedName(row) == .removed
                try journal.record(.removed, row)
                return removed ? "Contacts: removed \"\(readable(row.label)): \(row.value)\"" : nil
            } catch {
                return "Contacts: could not remove \"\(readable(row.label)): \(row.value)\" — \(describe(error))"
            }
        }
        #else
        return []   // Contacts can only be scripted on the Mac
        #endif
    }

    /// The journal that belongs to a store: `contact-writes.jsonl` next to it.
    public static func journal(forStoreAt url: URL) -> ContactJournal {
        ContactJournal(url: url.deletingLastPathComponent().appendingPathComponent("contact-writes.jsonl"))
    }

    /// "_$!<Mother>!$_" → "mother", for messages.
    public static func readable(_ label: String) -> String {
        guard label.hasPrefix("_$!<"), label.hasSuffix(">!$_") else { return label }
        return label.dropFirst(4).dropLast(4).lowercased()
    }

    private static func describe(_ error: Error) -> String {
        (error as? CXError)?.errorDescription ?? "\(error)"
    }
}
