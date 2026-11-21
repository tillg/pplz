import Foundation
import Observation
import CXCore
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// State of the people browser: the list, the search text, the selected person's card.
@MainActor
@Observable
public final class PeopleModel {
    public struct Configuration: Sendable {
        public var storeURL: URL
        /// False = cardXchange data only; the address book is neither read nor opened.
        public var usesContacts: Bool
        /// Name or ID of a person to select after loading.
        public var initialSelection: String?
        /// Whether the store syncs through the user's private iCloud.
        public var syncsWithICloud = false
        /// Where the device counts its geocoder requests, whichever store is open.
        public var geocodeURL = GeocodeStore.defaultURL()
        /// Whether addresses are located in the background. Like iCloud sync, only for the app's own default
        /// store: a store given with `-store` (demo data, tests) must not send the whole address book again.
        public var locatesAddresses = false
        /// The defaults suite for the user's own settings (SPEC §4.8), `nil` for the app's standard defaults.
        /// They stay on this device, outside the store.
        public var settingsSuite: String?

        /// Launch options, given the Apple way as `-key value` pairs:
        /// `-store <path>`, `-noContacts YES`, `-select <name or id>`, `-noSync YES`, `-forceSync YES`.
        ///
        /// iCloud sync is on for the app's own default store only. A store given with `-store`
        /// (demo data, tests) stays local unless `-forceSync YES` says otherwise.
        public init(defaults: UserDefaults) {
            self.init(storeURL: defaults.string(forKey: "store").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
                          ?? CXStore.defaultURL(),
                      usesContacts: !defaults.bool(forKey: "noContacts"),
                      initialSelection: defaults.string(forKey: "select"))
            syncsWithICloud = defaults.bool(forKey: "forceSync")
                || (defaults.string(forKey: "store") == nil && !defaults.bool(forKey: "noSync"))
            locatesAddresses = defaults.string(forKey: "store") == nil
        }

        public init(storeURL: URL = CXStore.defaultURL(), usesContacts: Bool = true, initialSelection: String? = nil) {
            self.storeURL = storeURL
            self.usesContacts = usesContacts
            self.initialSelection = initialSelection
        }
    }

    public enum Mode: String, CaseIterable, Sendable {
        case people = "People"
        case events = "Events"
        case map = "Map"
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
    /// The persons under "Recently Deleted", newest first (SPEC §3.4).
    public private(set) var recentlyDeleted: [DeletedPerson] = []
    /// Every tag in use, offered when tagging a person or an event.
    /// False when the address book is neither read nor written (`-noContacts`).
    public var usesContacts: Bool { configuration.usesContacts }
    public private(set) var knownTags: [String] = []
    /// Counts `cx://capture` links; the view looks into the capture inbox whenever it changes.
    public private(set) var captureRequests = 0
    /// The format offered when logging: the one used last.
    public private(set) var suggestedFormat: EventFormat = .liveMeeting
    public private(set) var card: PersonCard?
    public private(set) var errorMessage: String?
    public private(set) var isLoading = false

    public var sections: [PeopleSections.Section] { PeopleSections.make(entries, search: search) }

    // MARK: Map

    /// What has been geocoded so far; refreshed as the background locating goes on.
    public private(set) var geocodes = GeocodeState()
    private var locating: Task<Void, Never>?

    /// One pin per located address of the people the search finds — the list's filter.
    public var mapPins: [LocatedPin] { LocatedPeople.pins(for: PeopleSections.matching(entries, search: search), in: geocodes) }

    /// What the map says when it shows no pin; `nil` when it shows one.
    public var mapNotice: MapNotice? {
        MapNotice.make(search: search, matches: PeopleSections.matching(entries, search: search).count, pins: mapPins.count)
    }

    /// "1 234 of 2 000 addresses located · pausing until 14:10 · done about Sat 18:40"; `nil` if nobody has an address.
    /// The expected end shows only while locating runs or is paused.
    public var locateStatus: String? {
        let counts = LocatedPeople.counts(in: entries, state: geocodes)
        var resumesAt: Date?
        if case .wait(let until) = geocodes.budget() { resumesAt = until }
        let doneAt = locating == nil ? nil
            : GeocodeBudget.finish(outstanding: counts.outstanding, now: .now, slotStart: geocodes.slotStart, sent: geocodes.sent)
        return LocatedPeople.statusLine(counts, resumesAt: resumesAt, doneAt: doneAt)
    }

    /// Shows a person's card, as when a pin is opened on the map.
    public func openPerson(key: String) {
        mode = .people
        selection = key
    }

    /// The device's budget from its file, the answers from the store plus those not saved yet.
    private func refreshGeocodes() {
        guard let store, var state = try? GeocodeStore(url: configuration.geocodeURL).state(with: store) else { return }
        state.entries.merge(unsavedLocations) { _, new in new }
        geocodes = state
    }

    /// Answers are saved in batches: every save is sent to iCloud and makes the other devices reload.
    private var unsavedLocations: [String: GeocodeState.Entry] = [:]
    private static let locationsPerSave = 25

    private func saveLocations() {
        guard let store, !unsavedLocations.isEmpty, (try? store.recordLocations(unsavedLocations)) != nil else { return }
        unsavedLocations = [:]
    }

    /// Geocodes the addresses that are still open, in the background, for as long as the app runs: one card
    /// after the other in random order (so that several devices share the work), carrying on by itself after
    /// a pause; new pins appear as they are located. The answers go into the synced store. People appear only
    /// with contacts on, so with `-noContacts` nothing is ever sent.
    private func startLocating() {
        let budget = GeocodeStore(url: configuration.geocodeURL)
        if let store { _ = try? budget.handOverIfDefault(store: configuration.storeURL, to: store) }
        refreshGeocodes()
        guard configuration.locatesAddresses, locating == nil, !LocatedPeople.outstanding(in: entries, state: geocodes).isEmpty else { return }
        locating = Task { [weak self] in
            var generator = SystemRandomNumberGenerator()
            run: while !Task.isCancelled, let self {
                self.refreshGeocodes()       // also what other devices located in the meantime
                let card = LocatedPeople.nextCard(in: self.entries, state: self.geocodes, using: &generator)
                if card.isEmpty { break }
                for address in card {
                    guard let answer = try? await AddressLocator.lookUp(address, budget: budget) else { break run }
                    switch answer {
                    case .located(let coordinate):
                        self.unsavedLocations[address.key] = .init(coordinate: coordinate, checkedAt: Date())
                        if self.unsavedLocations.count >= Self.locationsPerSave { self.saveLocations() }
                        self.refreshGeocodes()
                        try? await Task.sleep(for: AddressLocator.spacing)
                    case .stopped(let outcome):
                        self.saveLocations()
                        self.refreshGeocodes()
                        guard let until = outcome.resumesAt else { break run }
                        try? await Task.sleep(for: .seconds(max(1, until.timeIntervalSinceNow)))
                        continue run
                    }
                }
            }
            self?.saveLocations()
            self?.locating = nil
        }
    }

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

    /// The editable cardXchange fields of a person, as the edit sheet shows them.
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
    private let settings: UserDefaults
    private var store: CXStore?
    private var pendingSelection: String?

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        self.pendingSelection = configuration.initialSelection
        settings = configuration.settingsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        myCardKey = settings.string(forKey: Self.myCardKeySetting)
        myCardFields = settings.data(forKey: Self.myCardFieldsSetting)
            .flatMap { try? JSONDecoder().decode(MyCardFields.self, from: $0) } ?? MyCardFields()
    }

    /// Loads (or reloads) the list; called at launch and whenever the app becomes active,
    /// so changes made by the CLI show up.
    public func reload() async {
        isLoading = entries.isEmpty
        defer { isLoading = false }
        do {
            if self.store == nil { try CXStore.checkMigrated(configuration.storeURL) }
            let store = try self.store ?? CXStore(
                url: configuration.storeURL, syncingWith: configuration.syncsWithICloud ? CXStore.iCloudContainer : nil)
            self.store = store
            let usesContacts = configuration.usesContacts
            let contacts = try await Task.detached { usesContacts ? try SystemContacts.fetchAll() : [] }.value
            // deleted persons whose 30 days are over go for good; every device may do it, the result is the same
            let purged = try store.purgeExpired(now: .now)
            if !purged.persons.isEmpty { try syncAfterPurge(purged, store) }
            recentlyDeleted = try store.deletedPersons()
            let persons = try store.persons()
            entries = PeopleDirectory.merge(contacts: contacts, persons: persons)
            #if os(macOS)
            // persons recorded on the iPhone or iPad: tie them to this Mac's contact and give it the cardXchange link
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
            startLocating()
            errorMessage = nil
            if let wanted = pendingSelection {
                pendingSelection = nil
                await select(matching: wanted)
            } else {
                await loadCard()
            }
            await loadMyCard()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Selects a person by name, part of a name, or ID — used for `cx://person/<id>` links.
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
    /// `newPeople` are names of people cardXchange does not know yet; they become persons that exist only in cardXchange.
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

    /// Saves the edited cardXchange fields of the selected person.
    public func save(_ edit: PersonEdit) async {
        guard let entry = card?.entry else { return }
        await save(edit, for: entry)
    }

    /// Saves what the edit screen holds for the person it was opened for (`entry`), whoever is selected by now:
    /// the contact's fields first, as that save can be refused, then cardXchange's own fields; each only if it was changed.
    /// Returns the reason if something was not saved, `nil` on success.
    public func saveEdit(for entry: PersonEntry, contact: ContactEdit?, originalContact: ContactEdit?,
                         person: PersonEdit, originalPerson: PersonEdit) async -> String? {
        var contactWasWritten = false
        if let contact, let originalContact {
            if let reason = await saveContactEdit(contact, original: originalContact) { return reason }
            contactWasWritten = !ContactEdit.changes(from: originalContact, to: contact).isEmpty
        }
        guard person != originalPerson else { return nil }
        errorMessage = nil
        await save(person, for: entry)
        guard let message = errorMessage else { return nil }
        return contactWasWritten ? "The contact card was saved, but what cardXchange keeps was not: \(message)" : message
    }

    private func save(_ edit: PersonEdit, for entry: PersonEntry) async {
        guard let store else { return }
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
                // deleted persons are not in the list, so the edit cannot show them; they stay until removed for good
                let deleted = event.participants.map(\.id).filter { id in !self.entries.contains { $0.id == id } && !ids.contains(id) }
                change.participants = ids + deleted
                change.additionalParticipants = additional
            }
            try store.updateEvent(event.id, change)
            // those who left need their history updated as much as those who joined
            let now = try store.event(event.id).participants.map(\.id)
            try self.syncContacts(Array(Set(event.participants.map(\.id) + now)), store)
        }
    }

    /// Turns list keys and new names into an event's participants: persons cardXchange has, contacts it has
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
            guard !name.isEmpty else { throw CXError.invalid("Choose a relationship, e.g. friend or manager.") }
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

    /// The cardXchange ID of a row, creating the person record for a contact on first use.
    private func personID(_ entry: PersonEntry, _ store: CXStore) throws -> UUID? {
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

    /// Brings these persons' contacts up to date in the background: the cardXchange link and,
    /// if switched on, the history block in the note.
    private func syncContacts(_ ids: [UUID], _ store: CXStore,
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

    private var offeredCaptures: [Data] = []

    /// A picture handed to the app directly — pasted or dropped — to be captured as a profile.
    public func offerCapture(_ image: Data) {
        offeredCaptures.append(image)
        captureRequests += 1
    }

    /// The pictures offered since the last call, oldest first.
    public func takeOfferedCaptures() -> [Data] {
        defer { offeredCaptures = [] }
        return offeredCaptures
    }

    #if os(macOS)
    /// The picture on the clipboard: a screenshot, or a copied picture file.
    private static func clipboardImage() -> Data? {
        let board = NSPasteboard.general
        let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL]
        return files?.first.flatMap { try? Data(contentsOf: $0) } ?? board.data(forType: .png) ?? board.data(forType: .tiff)
    }

    /// Offers the picture on the clipboard (a screenshot, or a copied picture file); `false` if there is none.
    @discardableResult
    public func offerCaptureFromClipboard() -> Bool {
        guard let image = Self.clipboardImage() else { return false }
        offerCapture(image)
        return true
    }

    /// Adds the picture on the clipboard to the selected person's photos. Not ⌘V: that is a capture.
    public func addPhotoFromClipboard() async {
        guard let image = Self.clipboardImage() else {
            errorMessage = "There is no picture on the clipboard."
            return
        }
        await addPhotos([image])
    }
    #endif

    // MARK: Photos

    /// A picture that shows several faces: the user says which one is the person.
    public struct FaceChoice: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public var entry: PersonEntry
        /// The crop around each face, left to right.
        public var crops: [Data]
    }

    /// Pictures with several faces that wait for the user's choice, oldest first.
    public private(set) var faceChoices: [FaceChoice] = []
    public var faceChoice: FaceChoice? { faceChoices.first }

    /// Whether a photo can become the contact's picture: the person has a contact, and it may be written.
    public var canUseAsContactPicture: Bool { configuration.usesContacts && card?.entry.contactIdentifier != nil }

    /// Adds pictures to the selected person's photos, cropped to the face in each. A picture with one face
    /// is stored right away, one with several waits for `chooseFace`, one without is reported and left out.
    public func addPhotos(_ images: [Data]) async {
        guard let entry = card?.entry else { return }
        var single: [Data] = []
        var problems: [String] = []
        for image in images {
            do {
                let crops = try await FacePhoto.faceCrops(in: image)
                if crops.count == 1 { single += crops } else { faceChoices.append(FaceChoice(entry: entry, crops: crops)) }
            } catch {
                problems.append((error as? LocalizedError)?.errorDescription ?? "\(error)")
            }
        }
        await storePhotos(single, of: entry)
        if !problems.isEmpty {
            errorMessage = images.count == 1 ? problems[0]
                : "\(problems.count) of \(images.count) pictures were not added. " + Set(problems).sorted().joined(separator: " ")
        }
    }

    /// Stores the face the user picked for the first waiting picture; `nil` skips the picture.
    public func chooseFace(_ index: Int?) async {
        guard !faceChoices.isEmpty else { return }
        let choice = faceChoices.removeFirst()
        if let index, choice.crops.indices.contains(index) { await storePhotos([choice.crops[index]], of: choice.entry) }
    }

    private func storePhotos(_ crops: [Data], of entry: PersonEntry) async {
        guard let store, !crops.isEmpty else { return }
        do {
            guard let id = try personID(entry, store) else { return }
            try store.addPhotos(crops, toPerson: id)
            try syncContacts([id], store)
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    public func deletePhoto(_ id: UUID) async {
        guard let store else { return }
        await perform { try store.deletePhoto(id) }
    }

    /// Makes a photo the selected person's picture in Contacts.
    public func useAsContactPicture(_ id: UUID) async {
        guard canUseAsContactPicture, let store, let identifier = card?.entry.contactIdentifier else { return }
        do {
            let image = try store.photo(id).data
            try await Task.detached { try SystemContacts.setPicture(image, forContact: identifier) }.value
            errorMessage = nil
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    /// Handles a `cx://person/<id>` link, e.g. clicked in the Contacts app. The old scheme `pplz` works too.
    public func open(_ url: URL) async {
        if url.scheme == "cx" || url.scheme == "pplz", url.host == "capture" {
            captureRequests += 1      // the share extension has put something into the inbox
            return
        }
        guard let id = PersonLink.personID(from: url) else { return }
        if entries.isEmpty { await reload() }
        await showPerson(id)
    }

    /// Switches to the people list and shows this person's card. A deleted person has no card: nothing changes.
    public func showPerson(_ id: UUID) async {
        guard entries.contains(where: { $0.id == id }) else { return }
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
        let byName = (profile.name.trimmingCharacters(in: .whitespaces).isEmpty
                      ? PeopleDirectory.candidates(forLinkedInID: profile.linkedInID, in: entries)
                      : PeopleDirectory.candidates(forCapturedName: profile.name, in: entries)).filter { $0.key != known?.key }
        return (known.map { [$0] } ?? []) + byName
    }

    /// The proposal that is certain enough to be preselected (its list key): the person with that
    /// LinkedIn profile, or else the only person of exactly that name. Everything else the user decides.
    public func capturePreselection(for profile: CapturedProfile) -> String? {
        if let id = try? store?.person(withLinkedInID: profile.linkedInID), let entry = entries.first(where: { $0.id == id }) {
            return entry.key
        }
        let wanted = PeopleDirectory.nameWithoutTitles(profile.name)
        guard !wanted.isEmpty else { return nil }
        let same = entries.filter {
            PeopleDirectory.nameWithoutTitles($0.name).compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        return same.count == 1 ? same[0].key : nil
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
            // From here on the person exists in cardXchange. If Contacts refuses, that stays so and is reported —
            // failing the whole save would lose the user's input and invite a second, duplicate attempt.
            var contactProblem: String?
            if configuration.usesContacts {
                do {
                    let link = ContactMirror.Row(contactIdentifier: contactIdentifier ?? "", label: PersonLink.label, value: PersonLink.url(for: id))
                    if let contactIdentifier {
                        try await Task.detached {
                            // without the contact's current fields nothing is written: "unknown" must not count as "empty"
                            guard let existing = try SystemContacts.details(identifier: contactIdentifier) else { return }
                            let fill = ContactFill.plan(for: profile, existing: existing)
                            if !fill.isEmpty { try SystemContacts.fill(fill, intoContact: contactIdentifier) }
                        }.value
                        try syncContacts([id], store)
                    } else {
                        let name = profile.contactName
                        let identifier = try await Task.detached {
                            try SystemContacts.createContact(name: name, link: link, fill: ContactFill.plan(for: profile, existing: nil))
                        }.value
                        try store.setContactIdentifier(identifier, for: id)
                        try ContactsSync.journal(forStoreAt: configuration.storeURL).record(
                            .added, ContactMirror.Row(contactIdentifier: identifier, label: link.label, value: link.value), field: "url")
                    }
                } catch {
                    contactProblem = "Saved in cardXchange, but not in Contacts: " + ((error as? LocalizedError)?.errorDescription ?? "\(error)")
                }
            }
            await reload()
            mode = .people
            await select(matching: id.uuidString)
            errorMessage = contactProblem
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

    /// Makes a cardXchange event of a calendar entry with this person — or adds the person, if that entry
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

    /// Gives the selected person, who exists only in cardXchange, a card in Contacts — with the name and the
    /// cardXchange link — so that phone, mail, address and picture can be entered there. Returns the new
    /// contact's identifier, or `nil` if nothing was created.
    @discardableResult
    public func addSelectedPersonToContacts() async -> String? {
        guard configuration.usesContacts, let store, let entry = card?.entry, entry.isCXOnly, let id = entry.id else { return nil }
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

    // MARK: Deleting

    /// Deletes the selected person: the contact leaves Contacts at once, and cardXchange keeps a copy of it and
    /// the person's data for 30 days under "Recently Deleted" (SPEC §3.4). Returns the reason if nothing was deleted, and shows it.
    @discardableResult
    public func deleteSelectedPerson() async -> String? {
        guard let store, let entry = card?.entry else { return nil }
        let identifier = entry.contactIdentifier
        if identifier != nil, !configuration.usesContacts {
            return fail("\(entry.name) has a contact, and cardXchange is not using Contacts.")
        }
        do {
            guard let id = try personID(entry, store) else { return nil }
            var copy: ContactEdit?
            if let identifier {
                copy = try await Task.detached { try SystemContacts.contactEdit(identifier: identifier) }.value
                guard copy != nil else {
                    return fail("The contact of \(entry.name) is not on this device. Delete the person on the device that has the contact.")
                }
            }
            try store.deletePerson(id, contactCopy: copy, at: .now)
            if let identifier, copy != nil {
                do {
                    try await Task.detached { try SystemContacts.deleteContact(identifier: identifier) }.value
                } catch {
                    // the contact is still there: the person stays in the list
                    try store.restorePerson(id, contactIdentifier: identifier)
                    throw error
                }
            }
        } catch {
            return fail((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
        errorMessage = nil
        selection = nil
        await reload()
        return nil
    }

    /// Brings a deleted person back. A person who had a contact gets it again, from the copy, with the cardXchange link;
    /// the note is not in the copy. Returns the reason if nothing was restored, and shows it.
    @discardableResult
    public func restore(_ id: UUID) async -> String? {
        // a second tap while the contact is being created would create it twice
        guard let store, restoring.insert(id).inserted else { return nil }
        defer { restoring.remove(id) }
        do {
            var identifier: String?
            if let copy = try store.contactCopy(of: id) {
                guard configuration.usesContacts else { return fail("This person had a contact, and cardXchange is not using Contacts.") }
                let row = ContactMirror.Row(contactIdentifier: "", label: PersonLink.label, value: PersonLink.url(for: id))
                let created = try await Task.detached { try SystemContacts.createContact(copy, link: row) }.value
                try ContactsSync.journal(forStoreAt: configuration.storeURL).record(
                    .added, ContactMirror.Row(contactIdentifier: created, label: row.label, value: row.value), field: "url")
                identifier = created
            }
            try store.restorePerson(id, contactIdentifier: identifier)
        } catch {
            return fail((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
        errorMessage = nil
        await reload()
        return nil
    }

    private var restoring: Set<UUID> = []

    private func fail(_ reason: String) -> String {
        errorMessage = reason
        return reason
    }

    /// Removes a deleted person for good, before the 30 days are over.
    public func deleteForGood(_ id: UUID) async {
        guard let store else { return }
        await perform {
            try self.syncAfterPurge(try store.purgePersons([id]), store)
        }
    }

    /// The related names of the removed connections leave the other contacts; the history of those who shared
    /// an event with a removed person is written again.
    private func syncAfterPurge(_ purged: PurgeResult, _ store: CXStore) throws {
        let rows = purged.connections.flatMap { ContactsSync.rows($0) + ContactsSync.legacyRows($0) }
        try syncContacts(purged.otherParticipants, store, unmirror: rows)
    }

    // MARK: Editing and creating contacts

    /// The selected person's contact fields, read fresh, to start an edit from; `nil` if the person has no contact.
    public func loadContactEdit() async -> ContactEdit? {
        guard configuration.usesContacts, let identifier = card?.entry.contactIdentifier else { return nil }
        do {
            return try await Task.detached { try SystemContacts.contactEdit(identifier: identifier) }.value
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            return nil
        }
    }

    /// The selected person's contact note, to show it; `nil` where cardXchange cannot read it
    /// (iPhone and iPad without Apple's notes entitlement, or the Contacts app did not answer).
    public func loadContactNote() async -> String? {
        #if os(macOS)
        guard configuration.usesContacts, let identifier = card?.entry.contactIdentifier else { return nil }
        return await Task.detached { try? ContactsApp.readNote(identifier: identifier) }.value
        #else
        return nil
        #endif
    }

    /// Writes what the user changed in the selected person's contact (`original` is what the form loaded)
    /// and refreshes the card and the list. Returns the reason if nothing was saved, `nil` on success.
    public func saveContactEdit(_ edit: ContactEdit, original: ContactEdit) async -> String? {
        let changes = ContactEdit.changes(from: original, to: edit)
        guard !changes.isEmpty else { return nil }
        guard edit.hasName else { return "A contact needs a name or a company." }
        // the contact the form was loaded from, not the one selected now: the selection may have moved while the sheet was open
        let identifier = original.contactIdentifier
        guard !identifier.isEmpty else { return "This form was not loaded from a contact." }
        guard configuration.usesContacts else { return "cardXchange is not using Contacts." }
        do {
            try await Task.detached { try SystemContacts.apply(changes, toContact: identifier) }.value
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        errorMessage = nil
        await reload()
        return nil
    }

    /// Creates a contact with these fields and shows it. Returns the reason if nothing was created, `nil` on success.
    public func createContact(_ edit: ContactEdit) async -> String? {
        guard edit.hasName else { return "A contact needs a name or a company." }
        guard configuration.usesContacts else { return "cardXchange is not using Contacts." }
        let identifier: String
        do {
            identifier = try await Task.detached { try SystemContacts.createContact(edit) }.value
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
        errorMessage = nil
        await reload()
        mode = .people
        search = ""
        isSelectingProgrammatically = true
        selection = identifier
        isSelectingProgrammatically = false
        await loadCard()
        return nil
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

    // MARK: My card (SPEC §4.8)

    private static let myCardKeySetting = "myCardKey"
    private static let myCardFieldsSetting = "myCardFields"

    /// The row of the person the user chose as themselves; `nil` until they choose.
    public private(set) var myCardKey: String?
    /// The Mac's own "My Card" in Contacts, used while the user has not chosen.
    private var systemMeKey: String?
    /// What the user passes on of their own contact. Every change is kept for the next launch.
    public var myCardFields: MyCardFields {
        didSet { settings.set(try? JSONEncoder().encode(myCardFields), forKey: Self.myCardFieldsSetting) }
    }
    /// The fields of the user's own contact, read fresh by `loadMyCard`.
    public private(set) var myContact: ContactEdit?
    private var myPicture: Data?

    /// The person whose card is passed on: the one the user chose, else the Mac's "My Card" in Contacts.
    public var myCardEntry: PersonEntry? {
        guard let key = myCardKey ?? systemMeKey else { return nil }
        return entries.first { $0.key == key }
    }

    /// The card exactly as it is passed on.
    public var myCard: SharedCard? {
        myContact.map { MyCard.card(from: $0, picture: myPicture, fields: myCardFields) }
    }

    /// Whether this row of the user's contact goes on the card, for a toggle in the settings.
    public subscript(passesOn rowID: String) -> Bool {
        get { myContact.map { myCardFields.includes(rowID, of: $0) } ?? false }
        set { if let myContact { myCardFields.set(rowID, included: newValue, of: myContact) } }
    }

    /// Keeps `key` (a row of the people list) as the user's own person and reads its contact.
    public func chooseMe(_ key: String) async {
        // the chosen rows belong to one contact: another person starts from the default rows
        if key != myCardEntry?.key { myCardFields.rows = nil }
        myCardKey = key
        settings.set(key, forKey: Self.myCardKeySetting)
        await loadMyCard()
    }

    /// Reads the user's own contact and picture; a person without a contact gives only the name.
    public func loadMyCard() async {
        let usesContacts = configuration.usesContacts
        #if os(macOS)
        if myCardKey == nil, systemMeKey == nil, usesContacts {
            systemMeKey = await Task.detached { try? SystemContacts.meContactIdentifier() }.value
        }
        #endif
        guard let entry = myCardEntry else {
            myContact = nil
            myPicture = nil
            return
        }
        let key = entry.key
        guard usesContacts, let identifier = entry.contactIdentifier else {
            myContact = MyCard.contact(named: entry.name)
            myPicture = nil
            return
        }
        do {
            let (edit, details) = try await Task.detached {
                (try SystemContacts.contactEdit(identifier: identifier), try SystemContacts.details(identifier: identifier))
            }.value
            guard myCardEntry?.key == key else { return }   // the user chose someone else while this was read
            myContact = edit
            myPicture = details?.imageData
        } catch {
            myContact = nil
            myPicture = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }
}
