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

        public init(storeURL: URL = PplzStore.defaultURL(), usesContacts: Bool = true, initialSelection: String? = nil) {
            self.storeURL = storeURL
            self.usesContacts = usesContacts
            self.initialSelection = initialSelection
        }
    }

    public var search = ""
    /// The selected row's key. Set by the list; the card then loads in the background.
    public var selection: String? {
        didSet { if selection != oldValue, !isSelectingProgrammatically { Task { await loadCard() } } }
    }
    private var isSelectingProgrammatically = false
    public private(set) var entries: [PersonEntry] = []
    public private(set) var card: PersonCard?
    public private(set) var errorMessage: String?
    public private(set) var isLoading = false

    public var sections: [PeopleSections.Section] { PeopleSections.make(entries, search: search) }

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
            let store = try self.store ?? PplzStore(url: configuration.storeURL)
            self.store = store
            let usesContacts = configuration.usesContacts
            let contacts = try await Task.detached { usesContacts ? try SystemContacts.fetchAll() : [] }.value
            entries = PeopleDirectory.merge(contacts: contacts, persons: try store.persons())
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

        public init(format: EventFormat = .liveMeeting, title: String = "", start: Date = Date(), place: String = "", notes: String = "") {
            self.format = format
            self.title = title
            self.start = start
            self.place = place
            self.notes = notes
        }
    }

    /// Logs an event with the selected person, then refreshes the card and — if switched on —
    /// the history in the person's contact note.
    public func logEvent(_ input: LogInput) async {
        guard let store, let entry = card?.entry else { return }
        do {
            var draft = EventDraft(title: input.title, format: input.format, start: input.start, place: input.place, notes: input.notes)
            if let id = entry.id {
                draft.participants = [id]
            } else if let identifier = entry.contactIdentifier {
                draft.additionalParticipants = [.contact(ContactSummary(identifier: identifier, name: entry.name))]
            }
            let event = try store.event(try store.logEvent(draft))
            errorMessage = nil
            #if os(macOS)
            if configuration.usesContacts {
                let plan = try ContactsSync.historyPlan(store, persons: event.participants.map(\.id))
                let journal = ContactsSync.journal(forStoreAt: configuration.storeURL)
                Task.detached { _ = ContactsSync.apply(plan, journal: journal) }
            }
            #endif
            await reload()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "\(error)"
        }
    }

    public func openInContacts() {
        guard let identifier = card?.entry.contactIdentifier else { return }
        Task.detached { try? ContactsApp.open(identifier: identifier) }
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
