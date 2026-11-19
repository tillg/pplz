import Foundation
import Observation
import PplzCore

/// State of the people browser: the list, the search text, the selected person's card.
@MainActor
@Observable
public final class PeopleModel {
    public struct Configuration: Sendable {
        public var storeURL: URL
        /// False = pplz data only; the address book is neither read nor opened.
        public var usesContacts: Bool
        /// Name or ID of a person to select after loading.
        public var initialSelection: String?
        /// Whether the store syncs through the user's private iCloud.
        public var syncsWithICloud = false

        /// Launch options, given the Apple way as `-key value` pairs:
        /// `-store <path>`, `-noContacts YES`, `-select <name or id>`, `-noSync YES`, `-forceSync YES`.
        ///
        /// iCloud sync is on for the app's own default store only. A store given with `-store`
        /// (demo data, tests) stays local unless `-forceSync YES` says otherwise.
        public init(defaults: UserDefaults) {
            self.init(storeURL: defaults.string(forKey: "store").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                          ?? PplzStore.defaultURL(),
                      usesContacts: !defaults.bool(forKey: "noContacts"),
                      initialSelection: defaults.string(forKey: "select"))
            syncsWithICloud = defaults.bool(forKey: "forceSync")
                || (defaults.string(forKey: "store") == nil && !defaults.bool(forKey: "noSync"))
        }

        public init(storeURL: URL = PplzStore.defaultURL(), usesContacts: Bool = true, initialSelection: String? = nil) {
            self.storeURL = storeURL
            self.usesContacts = usesContacts
            self.initialSelection = initialSelection
        }
    }

    public enum Mode: String, CaseIterable, Sendable {
        case people = "People"
        case events = "Events"
    }

    /// What the sidebar lists.
    public var mode: Mode = .people
    public var search = ""
    public var selectedEventID: UUID?
    public private(set) var events: [EventSnapshot] = []
    /// The selected row's key. Set by the list; the card then loads in the background.
    public var selection: String? {
        didSet { if selection != oldValue, !isSelectingProgrammatically { Task { await loadCard() } } }
    }
    private var isSelectingProgrammatically = false
    public private(set) var entries: [PersonEntry] = []
    /// Every tag in use, offered when tagging a person or an event.
    /// False when the address book is neither read nor written (`-noContacts`).
    public var usesContacts: Bool { configuration.usesContacts }
    public private(set) var knownTags: [String] = []
    /// Counts `pplz://capture` links; the view looks into the capture inbox whenever it changes.
    public private(set) var captureRequests = 0
    /// The format offered when logging: the one used last.
    public private(set) var suggestedFormat: EventFormat = .liveMeeting
    public private(set) var card: PersonCard?
    public private(set) var errorMessage: String?
    public private(set) var isLoading = false

    public var sections: [PeopleSections.Section] { PeopleSections.make(entries, search: search) }

    public struct EventSection: Identifiable, Equatable, Sendable {
        /// E.g. "November 2026".
        public var title: String
        public var events: [EventSnapshot]
        public var id: String { title }
    }

    /// All events, newest first, grouped by month; `search` matches title, place and participants.
    public var eventSections: [EventSection] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let matching = query.isEmpty ? events : events.filter { event in
            ([event.title, event.place, event.format.displayName] + event.participants.map(\.name))
                .contains { $0.range(of: query, options: options) != nil }
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var sections: [EventSection] = []
        for event in matching {
            let title = formatter.string(from: event.start)
            if sections.last?.title == title {
                sections[sections.count - 1].events.append(event)
            } else {
                sections.append(EventSection(title: title, events: [event]))
            }
        }
        return sections
    }

    public var selectedEvent: EventSnapshot? { events.first { $0.id == selectedEventID } }

    /// The editable pplz fields of a person, as the edit sheet shows them.
    public struct PersonEdit: Equatable, Sendable {
        public var howWeMet: String
        public var notes: String
        /// Comma-separated.
        public var tags: String
        public var keepInTouchDays: Int?

        public init(howWeMet: String = "", notes: String = "", tags: String = "", keepInTouchDays: Int? = nil) {
            self.howWeMet = howWeMet
            self.notes = notes
            self.tags = tags
            self.keepInTouchDays = keepInTouchDays
        }
    }

    /// The selected person's current values, to start an edit from.
    public var personEdit: PersonEdit {
        PersonEdit(howWeMet: card?.stored?.howWeMet ?? "", notes: card?.stored?.notes ?? "",
                   tags: (card?.entry.tags ?? []).joined(separator: ", "), keepInTouchDays: card?.stored?.keepInTouchDays)
    }

    private let configuration: Configuration
    private var store: PplzStore?
    private var pendingSelection: String?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.pendingSelection = configuration.initialSelection
    }

    /// Loads (or reloads) the list; called at launch and whenever the app becomes active,
    /// so changes made by the CLI show up.
    public func reload() async {
        isLoading = entries.isEmpty
        defer { isLoading = false }
        do {
            let store = try self.store ?? PplzStore(
                url: configuration.storeURL, syncingWith: configuration.syncsWithICloud ? PplzStore.iCloudContainer : nil)
            self.store = store
            let usesContacts = configuration.usesContacts
            let contacts = try await Task.detached { usesContacts ? try SystemContacts.fetchAll() : [] }.value
            let persons = try store.persons()
            entries = PeopleDirectory.merge(contacts: contacts, persons: persons)
            #if os(macOS)
            // persons recorded on the iPhone or iPad: tie them to this Mac's contact and give it the pplz link
            let adoptions = PeopleDirectory.adoptions(in: entries, persons: persons)
            for adoption in adoptions { try store.setContactIdentifier(adoption.contactIdentifier, for: adoption.person) }
            if !adoptions.isEmpty { try syncContacts(adoptions.map(\.person), store) }
            #endif
            #if os(macOS)
            // tags created on two devices before they synced; only the Mac merges, so two devices never undo each other
            try store.mergeDuplicateTags()
            #endif
            events = try store.events()
            knownTags = try store.tags().map(\.name)
            suggestedFormat = try store.lastLoggedFormat() ?? .liveMeeting
            errorMessage = nil
            if let wanted = pendingSelection {
                pendingSelection = nil
                await select(matching: wanted)
            } else {
                await loadCard()
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Selects a person by name, part of a name, or ID — used for `pplz://person/<id>` links.
    /// Returns once the person's card is loaded.
    public func select(matching query: String) async {
        guard case .one(let entry) = PeopleDirectory.resolve(query, in: entries) else { return }
        search = ""
        isSelectingProgrammatically = true
        selection = entry.key
        isSelectingProgrammatically = false
        await loadCard()
    }

    /// What the "Log event" sheet collects.
    public struct LogInput: Sendable {
        public var format: EventFormat
        public var title: String
        public var start: Date
        public var place: String
        public var notes: String

        /// Comma-separated, as in the edit sheets.
        public var tags: String

        public init(format: EventFormat = .liveMeeting, title: String = "", start: Date = Date(), place: String = "", notes: String = "",
                    tags: String = "") {
            self.format = format
            self.title = title
            self.start = start
            self.place = place
            self.notes = notes
            self.tags = tags
        }
    }

    /// Logs an event with the selected person, then refreshes the card and — if switched on —
    /// the history in the person's contact note.
    public func logEvent(_ input: LogInput) async {
        guard let entry = card?.entry else { return }
        await logEvent(input, with: [entry.key])
    }

    /// Logs an event with the people given by their list keys — the quick log, which needs no open card.
    /// `newPeople` are names of people pplz does not know yet; they become persons that exist only in pplz.
    public func logEvent(_ input: LogInput, with keys: [String], newPeople: [String] = []) async {
        let (ids, additional) = participants(keys, newPeople)
        guard let store, !ids.isEmpty || !additional.isEmpty else { return }
        do {
            var draft = EventDraft(title: input.title, format: input.format, start: input.start, place: input.place, notes: input.notes,
                                   tags: TagInput.names(in: input.tags))
            draft.participants = ids
            draft.additionalParticipants = additional
            let event = try store.event(try store.logEvent(draft))
            errorMessage = nil
            try syncContacts(event.participants.map(\.id), store)
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Saves the edited pplz fields of the selected person.
    public func save(_ edit: PersonEdit) async {
        guard let store, let entry = card?.entry else { return }
        do {
            let id: UUID
            if let existing = entry.id {
                id = existing
            } else if let identifier = entry.contactIdentifier {
                id = try store.ensurePerson(for: ContactSummary(identifier: identifier, name: entry.name))
            } else {
                return
            }
            try store.setHowWeMet(edit.howWeMet.trimmingCharacters(in: .whitespacesAndNewlines), for: id)
            try store.setNotes(edit.notes.trimmingCharacters(in: .whitespacesAndNewlines), for: id)
            try store.setTags(edit.tags.split(separator: ",").map(String.init), forPerson: id)
            try store.setKeepInTouch(days: edit.keepInTouchDays, for: id)
            try syncContacts([id], store)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    // MARK: Events

    /// The editable fields of an event, as the edit sheet shows them.
    public struct EventEdit: Equatable, Sendable {
        public var format: EventFormat
        public var title: String
        public var start: Date
        public var hasEnd: Bool
        public var end: Date
        public var place: String
        public var notes: String
        /// Comma-separated.
        public var tags: String
        /// One per line.
        public var links: String

        public init(format: EventFormat, title: String, start: Date, hasEnd: Bool, end: Date, place: String,
                    notes: String, tags: String, links: String) {
            self.format = format
            self.title = title
            self.start = start
            self.hasEnd = hasEnd
            self.end = end
            self.place = place
            self.notes = notes
            self.tags = tags
            self.links = links
        }
    }

    /// The selected event's current values, to start an edit from.
    public var eventEdit: EventEdit? {
        selectedEvent.map {
            EventEdit(format: $0.format, title: $0.title, start: $0.start, hasEnd: $0.end != nil, end: $0.end ?? $0.start,
                      place: $0.place, notes: $0.notes, tags: $0.tags.joined(separator: ", "), links: $0.links.joined(separator: "\n"))
        }
    }

    /// The selected event's people as list entries, to start an edit from.
    public var selectedEventPeople: [PersonEntry] {
        (selectedEvent?.participants ?? []).compactMap { person in entries.first { $0.id == person.id } }
    }

    /// Saves the edited fields of the selected event. `keys` replaces its people (list keys, as in
    /// the quick log); `nil` or an empty list leaves them as they are — an event keeps at least one person.
    public func save(_ edit: EventEdit, participants keys: [String]? = nil, newPeople: [String] = []) async {
        guard let store, let event = selectedEvent else { return }
        let (ids, additional) = participants(keys ?? [], newPeople)
        await perform {
            var change = EventChange(
                title: edit.title, format: edit.format, start: edit.start, end: edit.hasEnd ? edit.end : nil, clearEnd: !edit.hasEnd,
                place: edit.place, notes: edit.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                tags: edit.tags.split(separator: ",").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty },
                links: edit.links.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            if !ids.isEmpty || !additional.isEmpty {
                change.participants = ids
                change.additionalParticipants = additional
            }
            try store.updateEvent(event.id, change)
            // those who left need their history updated as much as those who joined
            let now = try store.event(event.id).participants.map(\.id)
            try self.syncContacts(Array(Set(event.participants.map(\.id) + now)), store)
        }
    }

    /// Turns list keys and new names into an event's participants: persons pplz has, contacts it has
    /// nothing about yet, and people to create.
    private func participants(_ keys: [String], _ newPeople: [String]) -> ([UUID], [NewParticipant]) {
        let people = keys.compactMap { key in entries.first { $0.key == key || $0.id?.uuidString == key } }
        let contacts: [NewParticipant] = people.filter { $0.id == nil }.compactMap { entry in
            entry.contactIdentifier.map { .contact(ContactSummary(identifier: $0, name: entry.name)) }
        }
        let names = newPeople.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return (people.compactMap(\.id), contacts + names.map { .named($0) })
    }

    public func addFollowUp(_ text: String) async {
        guard let store, let event = selectedEvent, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await perform { try store.addFollowUp(text, toEvent: event.id) }
    }

    public func deleteSelectedEvent() async {
        guard let store, let event = selectedEvent else { return }
        await perform {
            try store.deleteEvent(event.id)
            self.selectedEventID = nil
            try self.syncContacts(event.participants.map(\.id), store)
        }
    }

    // MARK: Connections

    /// Everyone the selected person could be connected to.
    public var connectionCandidates: [PersonEntry] {
        entries.filter { $0.key != card?.entry.key }
    }

    /// Records that `other` is the selected person's `role` — "Ben is Anna's manager" — the way
    /// Contacts phrases relationships, and mirrors it into Contacts.
    public func connect(role: String, to other: PersonEntry) async {
        guard let store, let entry = card?.entry else { return }
        await perform {
            let name = role.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw PplzError.invalid("Choose a relationship, e.g. friend or manager.") }
            let label = name + " of"
            // stored as the sentence "other — role of — selected person"
            guard let to = try self.personID(entry, store), let from = try self.personID(other, store) else { return }
            try store.connect(from, to: to, kind: label)
            let rows = try store.allConnections()
                .filter { $0.from.id == from && $0.to.id == to && $0.kind.caseInsensitiveCompare(label) == .orderedSame }
                .flatMap(ContactsSync.rows)
            try self.syncContacts([from, to], store, mirror: rows)
        }
    }

    /// Removes every connection between the selected person and the other one.
    public func disconnect(from other: UUID) async {
        guard let store, let me = card?.entry.id else { return }
        await perform {
            let rows = try store.allConnections()
                .filter { ($0.from.id == me && $0.to.id == other) || ($0.from.id == other && $0.to.id == me) }
                .flatMap { ContactsSync.rows($0) + ContactsSync.legacyRows($0) }
            try store.disconnect(me, other)
            try self.syncContacts([], store, unmirror: rows)
        }
    }

    /// The pplz ID of a row, creating the person record for a contact on first use.
    private func personID(_ entry: PersonEntry, _ store: PplzStore) throws -> UUID? {
        if let id = entry.id { return id }
        guard let identifier = entry.contactIdentifier else { return nil }
        return try store.ensurePerson(for: ContactSummary(identifier: identifier, name: entry.name))
    }

    /// Runs a write, reports a failure, and refreshes what is on screen.
    private func perform(_ work: () throws -> Void) async {
        do {
            try work()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return
        }
        await reload()
    }

    public func dismissError() { errorMessage = nil }

    /// Brings these persons' contacts up to date in the background: the `pplz` link and,
    /// if switched on, the history block in the note.
    private func syncContacts(_ ids: [UUID], _ store: PplzStore,
                              mirror: [ContactMirror.Row] = [], unmirror: [ContactMirror.Row] = []) throws {
        guard configuration.usesContacts else { return }
        let links = try ContactsSync.linkPlan(store, persons: ids)
        let history = try ContactsSync.historyPlan(store, persons: ids)
        let journal = ContactsSync.journal(forStoreAt: configuration.storeURL)
        Task.detached {
            _ = ContactsSync.applyLinks(links, journal: journal)
            _ = ContactsSync.apply(history, journal: journal)
            _ = ContactsSync.mirror(mirror, journal: journal)
            _ = ContactsSync.unmirror(unmirror, journal: journal)
        }
    }

    public func completeFollowUp(_ id: UUID) async {
        guard let store else { return }
        do {
            try store.completeFollowUp(id)
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Handles a `pplz://person/<id>` link, e.g. clicked in the Contacts app.
    public func open(_ url: URL) async {
        if url.scheme == "pplz", url.host == "capture" {
            captureRequests += 1      // the share extension has put something into the inbox
            return
        }
        guard let id = PersonLink.personID(from: url) else { return }
        if entries.isEmpty { await reload() }
        await showPerson(id)
    }

    /// Switches to the people list and shows this person's card.
    public func showPerson(_ id: UUID) async {
        mode = .people
        await select(matching: id.uuidString)
    }

    // MARK: Capture

    /// Whom a capture is about: someone in the list, or a new person.
    public enum CaptureTarget: Equatable, Sendable {
        case existing(key: String)
        case new
    }

    /// Who the captured profile could be: the person with that LinkedIn profile first, then people
    /// of that name or family name. Only proposals — the user chooses.
    public func captureCandidates(for profile: CapturedProfile) -> [PersonEntry] {
        let known = (try? store?.person(withLinkedInID: profile.linkedInID)).flatMap { id in entries.first { $0.id == id } }
        let byName = PeopleDirectory.candidates(forCapturedName: profile.name, in: entries).filter { $0.key != known?.key }
        return (known.map { [$0] } ?? []) + byName
    }

    /// Saves a reviewed capture: creates the person or updates the chosen one, and — unless contacts
    /// are off — creates or fills the contact. Nothing the person or contact already has is overwritten.
    /// Returns the person's ID and shows their card.
    @discardableResult
    public func saveCapture(_ profile: CapturedProfile, as target: CaptureTarget) async -> UUID? {
        guard let store else { return nil }
        do {
            let id: UUID
            var contactIdentifier: String?
            switch target {
            case .new:
                let name = PeopleDirectory.nameWithoutTitles(profile.name)
                guard !name.isEmpty else { return nil }
                id = try store.createPerson(name: name)
            case .existing(let key):
                guard let entry = entries.first(where: { $0.key == key || $0.id?.uuidString == key }) else { return nil }
                contactIdentifier = entry.contactIdentifier
                if let existing = entry.id {
                    id = existing
                } else if let identifier = entry.contactIdentifier {
                    id = try store.ensurePerson(for: ContactSummary(identifier: identifier, name: entry.name))
                } else {
                    return nil
                }
            }
            if !profile.linkedInID.isEmpty, try store.person(id).linkedInID.isEmpty {
                try store.setLinkedInID(profile.linkedInID, for: id)
            }
            if configuration.usesContacts {
                let link = ContactMirror.Row(contactIdentifier: contactIdentifier ?? "", label: PersonLink.label, value: PersonLink.url(for: id))
                if let contactIdentifier {
                    try await Task.detached {
                        let fill = ContactFill.plan(for: profile, existing: try SystemContacts.details(identifier: contactIdentifier))
                        if !fill.isEmpty { try SystemContacts.fill(fill, intoContact: contactIdentifier) }
                    }.value
                    try syncContacts([id], store)
                } else {
                    let name = try store.person(id).name
                    let identifier = try await Task.detached {
                        try SystemContacts.createContact(name: name, link: link, fill: ContactFill.plan(for: profile, existing: nil))
                    }.value
                    try store.setContactIdentifier(identifier, for: id)
                    try ContactsSync.journal(forStoreAt: configuration.storeURL).record(
                        .added, ContactMirror.Row(contactIdentifier: identifier, label: link.label, value: link.value), field: "url")
                }
            }
            errorMessage = nil
            await reload()
            mode = .people
            await select(matching: id.uuidString)
            return id
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            await reload()
            return nil
        }
    }

    /// The events to offer for "which event was this?": started within the last `days` days, latest first.
    public func recentEvents(now: Date = Date(), days: Int = 3, limit: Int = 5) -> [EventSnapshot] {
        let from = now.addingTimeInterval(-Double(days) * 86_400)
        return Array(events.filter { $0.start <= now && $0.start >= from }.sorted { $0.start > $1.start }.prefix(limit))
    }

    /// Adds a person to an event's people.
    public func addPerson(_ id: UUID, toEvent eventID: UUID) async {
        guard let store else { return }
        await perform {
            let people = try store.event(eventID).participants.map(\.id)
            guard !people.contains(id) else { return }
            try store.updateEvent(eventID, EventChange(participants: people + [id]))
            try self.syncContacts([id], store)
        }
    }

    /// Makes a pplz event of a calendar entry with this person — or adds the person, if that entry
    /// has become an event already (same title and start).
    public func logCalendarEntry(_ entry: CalendarEntry, with id: UUID) async {
        guard let store else { return }
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = events.first(where: { $0.title == title && $0.start == entry.start }) {
            await addPerson(id, toEvent: existing.id)
            return
        }
        await perform {
            try store.logEvent(EventDraft(title: title, format: .liveMeeting, start: entry.start, end: entry.end, place: entry.place,
                                          participants: [id]))
            try self.syncContacts([id], store)
        }
    }

    /// Gives the selected person, who exists only in pplz, a card in Contacts — with the name and the
    /// `pplz` link — so that phone, mail, address and picture can be entered there. Returns the new
    /// contact's identifier, or `nil` if nothing was created.
    @discardableResult
    public func addSelectedPersonToContacts() async -> String? {
        guard configuration.usesContacts, let store, let entry = card?.entry, entry.isPplzOnly, let id = entry.id else { return nil }
        do {
            let row = ContactMirror.Row(contactIdentifier: "", label: PersonLink.label, value: PersonLink.url(for: id))
            let name = entry.name
            let identifier = try await Task.detached { try SystemContacts.createContact(name: name, link: row) }.value
            try store.setContactIdentifier(identifier, for: id)
            try ContactsSync.journal(forStoreAt: configuration.storeURL).record(
                .added, ContactMirror.Row(contactIdentifier: identifier, label: row.label, value: row.value), field: "url")
            errorMessage = nil
            await reload()
            await select(matching: id.uuidString)
            return identifier
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return nil
        }
    }

    public func openInContacts() {
        #if os(macOS)
        guard let identifier = card?.entry.contactIdentifier else { return }
        Task.detached { try? ContactsApp.open(identifier: identifier) }
        #endif
    }

    private func loadCard() async {
        guard let store, let key = selection, let entry = entries.first(where: { $0.key == key }) else {
            card = nil
            return
        }
        do {
            var details: ContactDetails?
            if configuration.usesContacts, let identifier = entry.contactIdentifier {
                details = try await Task.detached { try SystemContacts.details(identifier: identifier) }.value
            }
            guard selection == key else { return }   // the user moved on while we were loading
            card = try store.card(for: entry, contact: details)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
