import ArgumentParser
import Foundation
import ImageIO
import CXCore

// async so that the geocoder's answers, which arrive on the main queue, can be awaited
@main
struct CX: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cx",
        abstract: "Remember when, where and how you met people.",
        discussion: """
            People are found by name (or part of it), cardXchange ID or contact identifier. Events and follow-ups \
            are addressed by ID or a unique ID prefix. Every command accepts --json for machine-readable output.
            """,
        subcommands: [People.self, PersonCommand.self, Log.self, Events.self, EventCommand.self, FollowUpCommand.self, Due.self, Tags.self, Capture.self,
                      ContactsCommand.self, Locate.self]
    )
}

// MARK: - Shared options and helpers

struct Common: ParsableArguments {
    @Option(help: "Path of the cardXchange store. Default: $CX_STORE, else ~/Library/Application Support/cardxchange/cardxchange.store.")
    var store: String?

    @Flag(name: .customLong("no-contacts"), help: "Do not read the system address book; work with cardXchange data only.")
    var noContacts = false

    @Flag(help: "Print JSON.")
    var json = false

    var storeURL: URL {
        store.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? CXStore.defaultURL()
    }

    func open() throws -> CXStore { try CXStore(url: storeURL) }

    /// Runs before every subcommand: refuses the variables of the old name and a default store next to data that is not migrated.
    /// Like `attempt`: the message goes to stderr, with exit code 2.
    func validate() throws {
        do {
            try CXStore.checkOldVariables()
            if store == nil { try CXStore.checkMigrated(storeURL) }
        } catch let error as CXError {
            FileHandle.standardError.write(Data(((error.errorDescription ?? "\(error)") + "\n").utf8))
            throw ExitCode(2)
        }
    }

    /// False with --no-contacts: then the address book is neither read nor written.
    var usesContacts: Bool { !noContacts && ProcessInfo.processInfo.environment["CX_NO_CONTACTS"] != "1" }

    func contacts() throws -> [ContactSummary] {
        usesContacts ? try SystemContacts.fetchAll() : []
    }

    /// Everything cardXchange writes into the address book is recorded next to the store.
    var journal: ContactJournal { ContactsSync.journal(forStoreAt: storeURL) }

    /// Writes related-name rows into Contacts (not with --no-contacts).
    func mirror(_ rows: [ContactMirror.Row]) -> [String] {
        usesContacts ? ContactsSync.mirror(rows, journal: journal) : []
    }

    /// Removes rows from Contacts, but only those the journal says cardXchange added.
    func unmirror(_ rows: [ContactMirror.Row]) -> [String] {
        usesContacts ? ContactsSync.unmirror(rows, journal: journal) : []
    }

    /// Brings the contacts of these persons up to date: the cardXchange link and — only if
    /// "Show history in Contacts" is on — the history block in the note. `remove` takes the blocks out instead.
    func syncHistory(_ ids: [UUID], _ store: CXStore, remove: Bool = false, recheckLinks: Bool = false) -> [String] {
        guard usesContacts else { return [] }
        do {
            let links = remove ? [] : ContactsSync.applyLinks(try ContactsSync.linkPlan(store, persons: ids), journal: journal, recheck: recheckLinks)
            return links + ContactsSync.apply(try ContactsSync.historyPlan(store, persons: ids, remove: remove), journal: journal)
        } catch {
            return ["Contacts: could not prepare the update — \(error)"]
        }
    }

    func report(_ messages: [String]) {
        messages.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
    }

    /// Live contact data for a linked person; `nil` for cardXchange-only persons or with --no-contacts.
    func contactDetails(_ entry: PersonEntry) throws -> ContactDetails? {
        guard let identifier = entry.contactIdentifier, !noContacts,
              ProcessInfo.processInfo.environment["CX_NO_CONTACTS"] != "1" else { return nil }
        return try SystemContacts.details(identifier: identifier)
    }

    func directory(_ store: CXStore) throws -> [PersonEntry] {
        let persons = try store.persons()
        let entries = PeopleDirectory.merge(contacts: try contacts(), persons: persons)
        // persons recorded on the iPhone or iPad: tie them to this Mac's contact and give it the cardXchange link
        let adoptions = PeopleDirectory.adoptions(in: entries, persons: persons)
        for adoption in adoptions { try store.setContactIdentifier(adoption.contactIdentifier, for: adoption.person) }
        if !adoptions.isEmpty { report(syncHistory(adoptions.map(\.person), store)) }
        return entries
    }

    /// Finds exactly one person; an unknown or ambiguous name ends the command with exit code 2.
    func resolve(_ query: String, in entries: [PersonEntry]) throws -> PersonEntry {
        switch PeopleDirectory.resolve(query, in: entries) {
        case .one(let entry):
            return entry
        case .none:
            throw Failure("No person matches \"\(query)\".")
        case .ambiguous(let candidates):
            throw CXError.ambiguousPerson(query, candidates)
        }
    }

    /// The cardXchange ID of an entry, creating the person record for a contact on first use.
    func personID(_ entry: PersonEntry, _ store: CXStore) throws -> UUID {
        if let id = entry.id { return id }
        guard let identifier = entry.contactIdentifier else { throw Failure("Person without ID.") }
        return try store.ensurePerson(for: ContactSummary(identifier: identifier, name: entry.name))
    }

    func emit<T: Encodable>(_ value: T, text: () -> String) throws {
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            print(String(decoding: try encoder.encode(value), as: UTF8.self))
        } else {
            print(text())
        }
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

extension ParsableCommand {
    /// Runs the body; expected failures go to stderr with exit code 2.
    func attempt(_ body: () throws -> Void) throws {
        do {
            try body()
        } catch let error as Failure {
            FileHandle.standardError.write(Data((error.description + "\n").utf8))
            throw ExitCode(2)
        } catch let error as CXError {
            FileHandle.standardError.write(Data(((error.errorDescription ?? "\(error)") + "\n").utf8))
            throw ExitCode(2)
        }
    }
}

extension ParsableCommand {
    /// `attempt` for async work.
    func attemptAsync(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch let error as Failure {
            FileHandle.standardError.write(Data((error.description + "\n").utf8))
            throw ExitCode(2)
        } catch let error as CXError {
            FileHandle.standardError.write(Data(((error.errorDescription ?? "\(error)") + "\n").utf8))
            throw ExitCode(2)
        }
    }
}

func resolveID(_ text: String, among ids: [UUID], what: String) throws -> UUID {
    let query = text.lowercased()
    let hits = ids.filter { $0.uuidString.lowercased().hasPrefix(query) }
    guard query.count >= 4 else { throw Failure("Give at least 4 characters of the \(what) ID.") }
    switch hits.count {
    case 1: return hits[0]
    case 0: throw Failure("No \(what) with ID \(text).")
    default: throw Failure("\(what.capitalized) ID \(text) is ambiguous; give more characters.")
    }
}

func short(_ id: UUID) -> String { String(id.uuidString.lowercased().prefix(8)) }

func format(_ date: Date) -> String {
    let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = (parts.hour == 0 && parts.minute == 0) ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
    return formatter.string(from: date)
}

func line(_ event: EventSnapshot) -> String {
    var parts = [event.format.displayName]
    if !event.title.isEmpty { parts.append(event.title) }
    if !event.place.isEmpty { parts.append(event.place) }
    var text = "\(format(event.start))  \(parts.joined(separator: " · "))"
    if !event.participants.isEmpty { text += "  — " + event.participants.map(\.name).joined(separator: ", ") }
    return text + "  [\(short(event.id))]"
}

func summary(count: Int, lastMet: Date?) -> String {
    guard count > 0, let lastMet else { return "No events yet" }
    return "Met \(count)× · last \(format(lastMet))"
}

extension EventFormat: ExpressibleByArgument {}

// MARK: - people

struct People: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List people: your contacts plus cardXchange-only persons.")

    @Argument(help: "Only people whose name contains this text.") var query: String?
    @Flag(help: "Only people cardXchange has stored something about.") var known = false
    @Option(help: "Only people with this tag.") var tag: String?
    @Option(help: "Only people with an address near this place, nearest first. Addresses are located by Apple's geocoder; see `cx locate`.")
    var near: String?
    @Option(help: "With --near: how far, e.g. 50km, 50 or 800m. Default 50km.") var within: String?
    @OptionGroup var common: Common

    func run() async throws {
        try await attemptAsync {
            let store = try common.open()
            var entries = try common.directory(store)
            if let query { entries = entries.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
            if known { entries = entries.filter { $0.id != nil } }
            if let tag { entries = entries.filter { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } } }
            if let near {
                try await listNear(near, in: entries)
                return
            }
            if within != nil { throw Failure("--within needs --near.") }
            try common.emit(entries) {
                entries.map { entry in
                    var text = entry.name
                    if entry.isCXOnly { text += "  (cardXchange only)" }
                    if entry.eventCount > 0 { text += "  — " + summary(count: entry.eventCount, lastMet: entry.lastMet) }
                    if !entry.tags.isEmpty { text += "  #" + entry.tags.joined(separator: " #") }
                    if let id = entry.id { text += "  [\(short(id))]" }
                    return text
                }.joined(separator: "\n")
            }
        }
    }
}

extension People {
    struct Nearby: Encodable {
        var person: PersonEntry
        var addressLabel: String
        var distanceKm: Double
    }

    /// People with a located address within `--within` of the place, nearest first.
    func listNear(_ place: String, in entries: [PersonEntry]) async throws {
        let km = try within.map(Distance.parseKm) ?? 50
        let geocodes = GeocodeStore(url: GeocodeStore.defaultURL())
        let store = try common.open()
        try geocodes.handOverIfDefault(store: common.storeURL, to: store)
        let center = try await coordinate(of: place, in: geocodes, store)
        let state = try geocodes.state(with: store)
        let hits = LocatedPeople.near(center, within: km, entries: entries, in: state)
        let outstanding = LocatedPeople.outstanding(in: entries, state: state).count
        if outstanding > 0 {
            common.report(["\(outstanding) addresses are not located yet, so those people cannot show up here. Run `cx locate` to locate them."])
        }
        let rows = hits.map { Nearby(person: $0.entry, addressLabel: $0.label, distanceKm: ($0.distanceKm * 10).rounded() / 10) }
        try common.emit(rows) {
            rows.isEmpty ? "Nobody within \(km) km of \(place)." : rows.map { row in
                var text = "\(row.person.name)  — \(row.distanceKm) km"
                if !row.addressLabel.isEmpty { text += " (\(row.addressLabel))" }
                if let id = row.person.id { text += "  [\(short(id))]" }
                return text
            }.joined(separator: "\n")
        }
    }

    /// The place's coordinate from the store, or from the geocoder (which counts against the hourly budget).
    private func coordinate(of place: String, in geocodes: GeocodeStore, _ store: CXStore) async throws -> Coordinate {
        let address = PostalAddress(city: place)
        if try !geocodes.state(with: store).isKnown(address.key) {
            switch try await AddressLocator.lookUp(address, budget: geocodes) {
            case .located(let coordinate):
                try store.recordLocations([address.key: .init(coordinate: coordinate, checkedAt: Date())])
            case .stopped(.paused(let until)):
                throw Failure("Cannot look up \"\(place)\" now: this hour's budget for Apple's geocoder is spent. Try again after \(format(until)).")
            case .stopped(.unreachable(let until)):
                throw Failure("Cannot look up \"\(place)\" now: Apple's geocoder cannot be reached (are you offline?). Try again after \(format(until)).")
            case .stopped(.done): break
            }
        }
        guard let center = try store.locations()[address.key]?.coordinate else { throw Failure("Apple's geocoder does not know a place called \"\(place)\".") }
        return center
    }
}

// MARK: - locate

struct Locate: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Locate the addresses of your contacts with Apple's geocoder, for `people --near` and the map.",
        discussion: """
            Sends at most \(GeocodeBudget.hourlyLimit) addresses per clock hour, one per second. When the hour's budget is spent it says \
            when it can continue, in local time, and stops; run it again then. It takes the cards in random order, and the results are \
            part of the cardXchange data that syncs through iCloud, so that several devices share the work. \
            The street, postal code, city and country of an address are sent to Apple.
            """)
    @Flag(help: "Only show how many addresses are located and what is left of this hour's budget.") var status = false
    @OptionGroup var common: Common

    struct Status: Encodable {
        var located: Int
        var notFound: Int
        var outstanding: Int
        var sentThisHour: Int
        var hourlyLimit: Int
        /// Only while the hour's budget is spent.
        var continuesAt: Date?
    }

    func run() async throws {
        try await attemptAsync {
            let store = try common.open()
            let entries = try common.directory(store)
            let geocodes = GeocodeStore(url: GeocodeStore.defaultURL())
            try geocodes.handOverIfDefault(store: common.storeURL, to: store)
            if status {
                try showStatus(entries, geocodes, store)
                return
            }
            let total = LocatedPeople.outstanding(in: entries, state: try geocodes.state(with: store)).count
            guard total > 0 else {
                common.report(["Nothing to locate."])
                try showStatus(entries, geocodes, store)
                return
            }
            // progress goes to stderr, so that --json keeps stdout clean
            common.report(["Locating \(total) addresses …"])
            var outcome = AddressLocator.Outcome.done, done = 0
            var generator = SystemRandomNumberGenerator()
            run: while true {
                // read again for every card: another device may have located some in the meantime
                let card = LocatedPeople.nextCard(in: entries, state: try geocodes.state(with: store), using: &generator)
                if card.isEmpty { break }
                for address in card {
                    switch try await AddressLocator.lookUp(address, budget: geocodes) {
                    case .located(let coordinate):
                        try store.recordLocations([address.key: .init(coordinate: coordinate, checkedAt: Date())])
                    case .stopped(let reason):
                        outcome = reason
                        break run
                    }
                    done += 1
                    FileHandle.standardError.write(Data("Located \(done) of \(total)\n".utf8))
                    try await Task.sleep(for: AddressLocator.spacing)
                }
            }
            try showStatus(entries, geocodes, store)
            switch outcome {
            case .done: break
            case .paused(let until):
                common.report(["This hour's budget is spent. Run `cx locate` again after \(format(until))."])
            case .unreachable(let until):
                common.report(["Apple's geocoder cannot be reached (are you offline?). Run `cx locate` again after \(format(until))."])
            }
        }
    }

    private func showStatus(_ entries: [PersonEntry], _ geocodes: GeocodeStore, _ store: CXStore) throws {
        let state = try geocodes.state(with: store)
        let counts = LocatedPeople.counts(in: entries, state: state)
        var continuesAt: Date?
        if case .wait(let until) = state.budget() { continuesAt = until }
        let status = Status(located: counts.located, notFound: counts.notFound, outstanding: counts.outstanding,
                            sentThisHour: GeocodeBudget.sent(now: Date(), slotStart: state.slotStart, sent: state.sent), hourlyLimit: GeocodeBudget.hourlyLimit,
                            continuesAt: continuesAt)
        try common.emit(status) {
            var lines = ["\(counts.located) of \(counts.total) addresses located, \(counts.notFound) not found, \(counts.outstanding) outstanding."]
            lines.append("This hour: \(status.sentThisHour) of \(GeocodeBudget.hourlyLimit) requests sent."
                         + (continuesAt.map { " Spent; pausing until \(format($0))." } ?? ""))
            return lines.joined(separator: "\n")
        }
    }
}

// MARK: - person

struct PersonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "person", abstract: "Show or edit one person.",
        subcommands: [Show.self, Open.self, Add.self, Note.self, Met.self, TagAdd.self, TagRemove.self, Connect.self, Disconnect.self, Rhythm.self, Photo.self],
        defaultSubcommand: Show.self)

    struct Detail: Encodable {
        var person: PersonEntry
        var contact: ContactDetails?
        var keepInTouchDays: Int?
        var connections: [ConnectionSnapshot]
        var howWeMet: String
        var notes: String
        var history: [EventSnapshot]
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show a person with their history.")
        @Argument(help: "Name, part of a name, or ID.") var person: String
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let entry = try common.resolve(person, in: try common.directory(store))
                let stored = try entry.id.map(store.person)
                let history = try entry.id.map(store.history(of:)) ?? []
                let contact = try common.contactDetails(entry)
                let connections = try entry.id.map(store.connections(of:)) ?? []
                try common.emit(Detail(person: entry, contact: contact, keepInTouchDays: stored?.keepInTouchDays, connections: connections,
                                       howWeMet: stored?.howWeMet ?? "", notes: stored?.notes ?? "", history: history)) {
                    var lines = [entry.name + (entry.isCXOnly ? "  (cardXchange only)" : "") + (entry.id.map { "  [\(short($0))]" } ?? "")]
                    lines += contact?.lines ?? []
                    if !entry.tags.isEmpty { lines.append("Tags: " + entry.tags.joined(separator: ", ")) }
                    if let stored, !stored.howWeMet.isEmpty { lines.append("How we met: " + stored.howWeMet) }
                    if let stored, !stored.notes.isEmpty { lines.append("Notes: " + stored.notes) }
                    lines += connections.map {
                        $0.direction == .outgoing ? "Connection: \($0.kind) \($0.other.name)" : "Connection: \($0.other.name) is \($0.kind) this person"
                    }
                    if let days = stored?.keepInTouchDays { lines.append("Keep in touch: every \(days) days") }
                    lines.append(summary(count: entry.eventCount, lastMet: entry.lastMet))
                    lines += history.map { "  " + line($0) }
                    return lines.joined(separator: "\n")
                }
            }
        }
    }

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Open a person's card in the Contacts app.")
        @Argument(help: "Name, part of a name, or ID.") var person: String
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let entry = try common.resolve(person, in: try common.directory(store))
                guard let identifier = entry.contactIdentifier else {
                    throw Failure("\(entry.name) exists only in cardXchange and has no card in Contacts.")
                }
                try ContactsApp.open(identifier: identifier)
                try common.emit(entry) { "Opened \(entry.name) in Contacts" }
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a cardXchange-only person (no system contact).")
        @Argument var name: String
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let id = try store.createPerson(name: name)
                try common.emit(try store.person(id)) { "Added \(name)  [\(short(id))]" }
            }
        }
    }

    struct Note: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set the notes about a person.")
        @Argument var person: String
        @Argument var text: String
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let id = try common.personID(try common.resolve(person, in: try common.directory(store)), store)
                try store.setNotes(text, for: id)
                common.report(common.syncHistory([id], store))
                try common.emit(try store.person(id)) { "Notes saved  [\(short(id))]" }
            }
        }
    }

    struct Met: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set how you met a person.")
        @Argument var person: String
        @Argument var text: String
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let id = try common.personID(try common.resolve(person, in: try common.directory(store)), store)
                try store.setHowWeMet(text, for: id)
                common.report(common.syncHistory([id], store))
                try common.emit(try store.person(id)) { "Saved  [\(short(id))]" }
            }
        }
    }

    struct TagAdd: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "tag", abstract: "Add tags to a person.")
        @Argument var person: String
        @Argument var tags: [String]
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let id = try common.personID(try common.resolve(person, in: try common.directory(store)), store)
                for tag in tags { try store.addTag(tag, toPerson: id) }
                common.report(common.syncHistory([id], store))
                let saved = try store.person(id)
                try common.emit(saved) { "Tags: " + saved.tags.joined(separator: ", ") }
            }
        }
    }

    struct TagRemove: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "untag", abstract: "Remove tags from a person.")
        @Argument var person: String
        @Argument var tags: [String]
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let id = try common.personID(try common.resolve(person, in: try common.directory(store)), store)
                for tag in tags { try store.removeTag(tag, fromPerson: id) }
                let saved = try store.person(id)
                try common.emit(saved) { "Tags: " + saved.tags.joined(separator: ", ") }
            }
        }
    }
}

extension PersonCommand {
    struct Photo: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Pictures of a person, for recognising them in new photos.",
            discussion: "Only the area around the face is kept, as a copy in cardXchange's store (and so in your private iCloud). A picture without a face is refused.",
            subcommands: [Add.self, List.self, Remove.self, Export.self], defaultSubcommand: List.self)

        struct Add: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Add pictures; each is cropped to the face in it.")
            @Argument var person: String
            @Argument(help: "Picture files.") var images: [String]
            @Option(help: "Which face, counted from the left, when a picture shows several.") var face: Int?
            @OptionGroup var common: Common

            func run() throws {
                try attempt {
                    guard !images.isEmpty else { throw Failure("Give at least one picture file.") }
                    let store = try common.open()
                    let entry = try common.resolve(person, in: try common.directory(store))
                    // every picture is checked before anything is stored
                    var crops: [Data] = []
                    for path in images {
                        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                        guard let data = FileManager.default.contents(atPath: url.path) else { throw Failure("Cannot read \(url.path).") }
                        let faces: [Data]
                        do { faces = try blocking { try await FacePhoto.faceCrops(in: data) } } catch let error as CXError {
                            throw Failure("\(url.lastPathComponent): " + (error.errorDescription ?? "\(error)"))
                        }
                        if faces.count > 1, face == nil {
                            throw Failure("\(url.lastPathComponent) shows \(faces.count) faces. Choose one with --face 1…\(faces.count), counted from the left.")
                        }
                        let index = (face ?? 1) - 1
                        guard faces.indices.contains(index) else {
                            throw Failure("\(url.lastPathComponent) shows \(faces.count) face\(faces.count == 1 ? "" : "s"); there is no --face \(face ?? 1).")
                        }
                        crops.append(faces[index])
                    }
                    let id = try common.personID(entry, store)
                    let added = try store.addPhotos(crops, toPerson: id)
                    common.report(common.syncHistory([id], store))
                    let photos = try store.photos(of: id).filter { added.contains($0.id) }
                    try common.emit(photos) { photos.map { "Added photo \(describe($0)) to \(entry.name)" }.joined(separator: "\n") }
                }
            }
        }

        struct List: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "List a person's pictures, newest first.")
            @Argument var person: String
            @OptionGroup var common: Common

            func run() throws {
                try attempt {
                    let store = try common.open()
                    let entry = try common.resolve(person, in: try common.directory(store))
                    let photos = try entry.id.map(store.photos(of:)) ?? []
                    try common.emit(photos) { photos.isEmpty ? "No photos." : photos.map(describe).joined(separator: "\n") }
                }
            }
        }

        struct Remove: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Delete a picture.")
            @Argument var person: String
            @Argument(help: "The picture's ID or the start of it.") var photo: String
            @OptionGroup var common: Common

            func run() throws {
                try attempt {
                    let store = try common.open()
                    let (entry, found) = try find(person, photo, store, common)
                    try store.deletePhoto(found.id)
                    try common.emit(found) { "Removed photo [\(short(found.id))] of \(entry.name)" }
                }
            }
        }

        struct Export: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Save a picture (the JPEG crop) to a file.")
            @Argument var person: String
            @Argument(help: "The picture's ID or the start of it.") var photo: String
            @Argument(help: "The file to write.") var file: String
            @OptionGroup var common: Common

            func run() throws {
                try attempt {
                    let store = try common.open()
                    let (_, found) = try find(person, photo, store, common)
                    let url = URL(fileURLWithPath: (file as NSString).expandingTildeInPath)
                    try found.data.write(to: url)
                    try common.emit(found) { "Saved photo [\(short(found.id))] to \(url.path)" }
                }
            }
        }

        static func describe(_ photo: PhotoSnapshot) -> String {
            "[\(short(photo.id))]  \(format(photo.createdAt))  \(photo.pixelWidth)×\(photo.pixelHeight) px"
        }

        /// One of the person's photos by ID prefix.
        static func find(_ person: String, _ photo: String, _ store: CXStore, _ common: Common) throws -> (PersonEntry, PhotoSnapshot) {
            let entry = try common.resolve(person, in: try common.directory(store))
            let photos = try entry.id.map(store.photos(of:)) ?? []
            let id = try resolveID(photo, among: photos.map(\.id), what: "photo")
            return (entry, photos.first { $0.id == id }!)
        }
    }

    struct Connect: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Connect two people.",
            discussion: """
                Reads as a sentence: cx person connect "Anna" "manager of" "Ben" — Anna is Ben's manager, \
                so Ben's card in Contacts gets "manager: Anna". Roles Contacts knows: \
                \(ContactMirror.appleRoles.joined(separator: ", ")), colleague — each followed by "of". \
                Anything else works too, e.g. "introduced by".
                """)
        @Argument var person: String
        @Argument(help: "E.g. \"colleague of\", \"introduced by\", \"partner of\".") var kind: String
        @Argument var other: String
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let entries = try common.directory(store)
                // resolve both before anything is written
                let (a, b) = (try common.resolve(person, in: entries), try common.resolve(other, in: entries))
                let from = try common.personID(a, store)
                let to = try common.personID(b, store)
                try store.connect(from, to: to, kind: kind)
                common.report(common.syncHistory([from, to], store))
                let written = try store.allConnections()
                    .filter { $0.from.id == from && $0.to.id == to && $0.kind.caseInsensitiveCompare(kind.trimmingCharacters(in: .whitespaces)) == .orderedSame }
                    .flatMap { common.mirror(ContactsSync.rows($0)) }
                written.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
                try common.emit(try store.connections(of: from)) { "\(a.name) — \(kind) — \(b.name)" }
            }
        }
    }

    struct Disconnect: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Remove all connections between two people.")
        @Argument var person: String
        @Argument var other: String
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let entries = try common.directory(store)
                let (a, b) = (try common.resolve(person, in: entries), try common.resolve(other, in: entries))
                guard let from = a.id, let to = b.id else { return try common.emit([ConnectionSnapshot]()) { "Not connected." } }
                let removed = try store.allConnections()
                    .filter { ($0.from.id == from && $0.to.id == to) || ($0.from.id == to && $0.to.id == from) }
                    .flatMap { common.unmirror(ContactsSync.rows($0) + ContactsSync.legacyRows($0)) }
                removed.forEach { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
                try store.disconnect(from, to)
                try common.emit(try store.connections(of: from)) { "Disconnected \(a.name) and \(b.name)" }
            }
        }
    }

    struct Rhythm: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set how often you want to meet a person; see `cx due`.")
        @Argument var person: String
        @Argument(help: "Days (90), or 2w, 3m, 1y — or \"off\" to remove the rhythm.") var interval: String
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let days = interval.lowercased() == "off" ? nil : try KeepInTouch.days(interval)
                let id = try common.personID(try common.resolve(person, in: try common.directory(store)), store)
                try store.setKeepInTouch(days: days, for: id)
                common.report(common.syncHistory([id], store))
                try common.emit(try store.person(id)) { days.map { "Keep in touch every \($0) days  [\(short(id))]" } ?? "Rhythm removed  [\(short(id))]" }
            }
        }
    }
}

struct Due: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "People you wanted to keep in touch with and haven't met for too long.")
    @OptionGroup var common: Common

    func run() throws {
        try attempt {
            let due = KeepInTouch.overdue(try common.open().persons())
            try common.emit(due) {
                due.isEmpty ? "Nobody is overdue." : due.map { item in
                    let status = item.daysSinceLastMet.map { "last met \($0) days ago, \(item.daysOverdue ?? 0) overdue" } ?? "never met"
                    return "\(item.person.name)  — every \(item.intervalDays) days, \(status)  [\(short(item.person.id))]"
                }.joined(separator: "\n")
            }
        }
    }
}

// MARK: - log

struct Log: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Log an event: a call, a meeting, any interaction.",
        discussion: "Example: cx log \"Anna Example\" --format phone-call --title \"Catch-up\" --at yesterday")

    @Argument(help: "The people you met (name, part of a name, or ID).") var people: [String] = []
    @Option(help: "One of: \(EventFormat.allCases.map(\.rawValue).joined(separator: ", ")).") var format: EventFormat = .liveMeeting
    @Option var title: String = ""
    @Option(help: "Start: now, today, yesterday, YYYY-MM-DD or \"YYYY-MM-DD HH:MM\".") var at: String = "now"
    @Option(help: "Optional end, same formats as --at.") var end: String?
    @Option var place: String = ""
    @Option var notes: String = ""
    @Option(help: "Tag for the event; repeatable.") var tag: [String] = []
    @Option(help: "Link to a calendar entry, meeting or document; repeatable.") var link: [String] = []
    @Flag(help: "Create a cardXchange-only person for any name that matches nobody.") var create = false
    @OptionGroup var common: Common

    func run() throws {
        try attempt {
            let store = try common.open()
            // Resolve and parse everything before the single write, so a failed command stores nothing.
            let plan: ParticipantPlan
            do {
                plan = try PeopleDirectory.participants(people, in: try common.directory(store), createMissing: create)
            } catch CXError.notFound(let what) {
                throw Failure("Not found: \(what). Use --create to add them as a cardXchange-only person.")
            }
            let id = try store.logEvent(EventDraft(
                title: title, format: format, start: try DateInput.parse(at),
                end: try end.map { try DateInput.parse($0, endOfDay: true) },
                place: place, notes: notes, participants: plan.existing, tags: tag,
                additionalParticipants: plan.additional, links: link))
            let event = try store.event(id)
            common.report(common.syncHistory(event.participants.map(\.id), store))
            try common.emit(event) { "Logged  " + line(event) }
        }
    }
}

// MARK: - events

struct Events: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List events, newest first.")

    @Option(help: "Only events with this person.") var person: String?
    @Option var format: EventFormat?
    @Option(help: "Only events starting at or after this date.") var since: String?
    @Option(help: "Only events starting at or before this date.") var until: String?
    @Option(help: "Only events whose place contains this text.") var place: String?
    @Option var tag: String?
    @Option(help: "Show at most this many events.") var limit: Int?
    @OptionGroup var common: Common

    func run() throws {
        try attempt {
            let store = try common.open()
            var filter = EventFilter(format: format, since: try since.map { try DateInput.parse($0) },
                                     until: try until.map { try DateInput.parse($0, endOfDay: true) }, place: place, tag: tag)
            if let person {
                let entry = try common.resolve(person, in: try common.directory(store))
                guard let id = entry.id else { return try common.emit([EventSnapshot]()) { "No events." } }
                filter.person = id
            }
            var events = try store.events(filter)
            if let limit { events = Array(events.prefix(max(0, limit))) }
            try common.emit(events) { events.isEmpty ? "No events." : events.map(line).joined(separator: "\n") }
        }
    }
}

struct EventCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "event", abstract: "Show, edit or delete one event.",
        subcommands: [Show.self, Edit.self, Delete.self], defaultSubcommand: Show.self)

    static func detail(_ event: EventSnapshot) -> String {
        var lines = [line(event)]
        if let end = event.end { lines.append("Ends: " + format(end)) }
        if !event.tags.isEmpty { lines.append("Tags: " + event.tags.joined(separator: ", ")) }
        if !event.notes.isEmpty { lines.append("Notes: " + event.notes) }
        lines += event.links.map { "Link: " + $0 }
        lines += event.followUps.map { "  [\($0.done ? "x" : " ")] \($0.text)  [\(short($0.id))]" }
        return lines.joined(separator: "\n")
    }

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show an event.")
        @Argument(help: "Event ID or unique prefix.") var id: String
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let event = try store.event(try resolveID(id, among: try store.events().map(\.id), what: "event"))
                try common.emit(event) { EventCommand.detail(event) }
            }
        }
    }

    struct Edit: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Change an event. Only the given fields change.")
        @Argument(help: "Event ID or unique prefix.") var id: String
        @Option var title: String?
        @Option var format: EventFormat?
        @Option var at: String?
        @Option var end: String?
        @Flag(help: "Remove the end.") var noEnd = false
        @Option var place: String?
        @Option var notes: String?
        @Option(help: "Replace the participants; repeatable.") var person: [String] = []
        @Option(help: "Replace the tags; repeatable.") var tag: [String] = []
        @Option(help: "Replace the links; repeatable.") var link: [String] = []
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let eventID = try resolveID(id, among: try store.events().map(\.id), what: "event")
                let before = try store.event(eventID).participants.map(\.id)
                let plan = person.isEmpty ? nil
                    : try PeopleDirectory.participants(person, in: try common.directory(store), createMissing: false)
                try store.updateEvent(eventID, EventChange(
                    title: title, format: format, start: try at.map { try DateInput.parse($0) },
                    end: try end.map { try DateInput.parse($0, endOfDay: true) }, clearEnd: noEnd, place: place, notes: notes,
                    participants: plan?.existing, tags: tag.isEmpty ? nil : tag,
                    additionalParticipants: plan?.additional ?? [], links: link.isEmpty ? nil : link))
                let event = try store.event(eventID)
                common.report(common.syncHistory(before + event.participants.map(\.id), store))
                try common.emit(event) { "Updated  " + EventCommand.detail(event) }
            }
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete an event and its follow-ups.")
        @Argument(help: "Event ID or unique prefix.") var id: String
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let eventID = try resolveID(id, among: try store.events().map(\.id), what: "event")
                let event = try store.event(eventID)
                try store.deleteEvent(eventID)
                common.report(common.syncHistory(event.participants.map(\.id), store))
                try common.emit(event) { "Deleted  " + line(event) }
            }
        }
    }
}

// MARK: - followup

struct FollowUpCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "followup", abstract: "Things you promised or want to do after an event.",
        subcommands: [List.self, Add.self, Done.self], defaultSubcommand: List.self)

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List open follow-ups, oldest first.")
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let open = try common.open().openFollowUps()
                try common.emit(open) {
                    open.isEmpty ? "No open follow-ups." : open.map { item in
                        var text = "[ ] \(item.text)  — \(format(item.eventStart))"
                        if !item.eventTitle.isEmpty { text += " \(item.eventTitle)" }
                        if !item.participants.isEmpty { text += " with " + item.participants.map(\.name).joined(separator: ", ") }
                        return text + "  [\(short(item.id))]"
                    }.joined(separator: "\n")
                }
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a follow-up to an event.")
        @Argument(help: "Event ID or unique prefix.") var event: String
        @Argument var text: String
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let eventID = try resolveID(event, among: try store.events().map(\.id), what: "event")
                let id = try store.addFollowUp(text, toEvent: eventID)
                try common.emit(try store.event(eventID)) { "Added follow-up  [\(short(id))]" }
            }
        }
    }

    struct Done: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mark a follow-up as done.")
        @Argument(help: "Follow-up ID or unique prefix.") var id: String
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let followUpID = try resolveID(id, among: try store.openFollowUps().map(\.id), what: "follow-up")
                try store.completeFollowUp(followUpID)
                try common.emit(try store.openFollowUps()) { "Done  [\(short(followUpID))]" }
            }
        }
    }
}

// MARK: - contacts

struct ContactsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contacts", abstract: "What cardXchange writes into your address book.",
        subcommands: [Sync.self, History.self, Journal.self], defaultSubcommand: Journal.self)

    struct Sync: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Bring Contacts up to date: connections as related names and, if switched on, the history in the notes. Safe to repeat.")
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                guard common.usesContacts else { throw Failure("Nothing to do with --no-contacts.") }
                let store = try common.open()
                let results = try store.allConnections().flatMap { common.mirror(ContactsSync.rows($0)) }
                    + common.syncHistory(try store.persons().map(\.id), store, recheckLinks: true)
                try common.emit(results) { results.isEmpty ? "Contacts are up to date." : results.joined(separator: "\n") }
            }
        }
    }

    struct History: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show history in Contacts: write the meeting history into each contact's note.",
            discussion: """
                cardXchange keeps one block between "\(NotesBlock.startMarker)" and "\(NotesBlock.endMarker)" in the note and never \
                changes your own text around it. "on" writes the block for everyone you have events with; \
                "off" removes all blocks again.
                """)
        enum Mode: String, ExpressibleByArgument, CaseIterable { case on, off, status }
        @Argument(help: "on, off or status.") var mode: Mode = .status
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                var results: [String] = []
                switch mode {
                case .status:
                    break
                case .on:
                    guard common.usesContacts else { throw Failure("Cannot switch this on with --no-contacts.") }
                    try store.setShowsHistoryInContacts(true)
                    results = common.syncHistory(try store.persons().map(\.id), store)
                case .off:
                    results = common.syncHistory(try store.persons().map(\.id), store, remove: true)
                    try store.setShowsHistoryInContacts(false)
                }
                let on = try store.showsHistoryInContacts()
                try common.emit(["showHistoryInContacts": on]) {
                    (results + ["Show history in Contacts: \(on ? "on" : "off")"]).joined(separator: "\n")
                }
            }
        }
    }

    struct Journal: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List every change cardXchange made to your address book.")
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let entries = try common.journal.entries()
                try common.emit(entries) {
                    entries.isEmpty ? "cardXchange has not changed any contact." : entries.map {
                        "\(format($0.date))  \($0.action.rawValue)  \($0.field) \"\(ContactsSync.readable($0.row.label)): \($0.row.value)\"  on contact \($0.row.contactIdentifier)"
                    }.joined(separator: "\n")
                }
            }
        }
    }
}

// MARK: - capture

struct Capture: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read a profile screenshot (e.g. LinkedIn) on this Mac: name, job, company, place, LinkedIn link and picture.",
        discussion: "Nothing is saved and nothing leaves the Mac. The fields are filled in by Apple's on-device language model.")
    @Argument(help: "The screenshot file.") var image: String
    @Option(help: "Save the cropped profile picture to this PNG file.") var picture: String?
    @Flag(help: "Print the recognised text instead of the fields.") var text = false

    func run() throws {
        let url = URL(fileURLWithPath: (image as NSString).expandingTildeInPath)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CXError.invalid("Cannot read an image from \(url.path).")
        }
        if text {
            print(try blocking { try await ProfileImage.text(in: image) }.joined(separator: "\n"))
            return
        }
        let reading = try blocking { await ProfileReader.read(image) }
        if let problem = reading.problem {
            FileHandle.standardError.write(Data("Fields are not filled in: \(problem)\n".utf8))
        }
        let profile = reading.profile
        let rows = [("First name", profile.givenName), ("Last name", profile.familyName), ("Title", profile.namePrefix), ("Job", profile.jobTitle), ("Company", profile.company),
                    ("Email", profile.email), ("Phone", profile.phone), ("Mobile", profile.mobile), ("Website", profile.website),
                    ("Street", profile.street), ("Postal code", profile.postalCode),
                    ("City", profile.city), ("Country", profile.country),
                    ("LinkedIn", profile.linkedInID.isEmpty ? "" : LinkedInLink.url(forProfileID: profile.linkedInID)),
                    ("Picture", profile.picture == nil ? "" : "found")]
        print(rows.map { "\($0.0): \($0.1)" }.joined(separator: "\n"))
        if let picture {
            guard let data = profile.picture else { throw CXError.invalid("No face found in the image.") }
            try data.write(to: URL(fileURLWithPath: (picture as NSString).expandingTildeInPath))
        }
    }
}

private final class ResultBox<Value>: @unchecked Sendable {
    var result: Result<Value, Error>?
    init() {}
}

/// Runs async work from a command and waits for it.
func blocking<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    let done = DispatchSemaphore(value: 0)
    Task.detached {
        do { box.result = .success(try await work()) } catch { box.result = .failure(error) }
        done.signal()
    }
    done.wait()
    return try box.result!.get()
}

// MARK: - tags

struct Tags: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List all tags in use.")
    @OptionGroup var common: Common

    func run() throws {
        try attempt {
            let tags = try common.open().tags()
            try common.emit(tags) {
                tags.isEmpty ? "No tags." : tags.map { "\($0.name)  — \($0.personCount) people, \($0.eventCount) events" }.joined(separator: "\n")
            }
        }
    }
}
