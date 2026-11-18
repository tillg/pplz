import ArgumentParser
import Foundation
import PplzCore

@main
struct Pplz: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pplz",
        abstract: "Remember when, where and how you met people.",
        discussion: """
            People are found by name (or part of it), pplz ID or contact identifier. Events and follow-ups \
            are addressed by ID or a unique ID prefix. Every command accepts --json for machine-readable output.
            """,
        subcommands: [People.self, PersonCommand.self, Log.self, Events.self, EventCommand.self, FollowUpCommand.self, Tags.self]
    )
}

// MARK: - Shared options and helpers

struct Common: ParsableArguments {
    @Option(help: "Path of the pplz store. Default: $PPLZ_STORE, else ~/Library/Application Support/pplz/pplz.store.")
    var store: String?

    @Flag(name: .customLong("no-contacts"), help: "Do not read the system address book; work with pplz data only.")
    var noContacts = false

    @Flag(help: "Print JSON.")
    var json = false

    func open() throws -> PplzStore {
        if let store { return try PplzStore(url: URL(fileURLWithPath: (store as NSString).expandingTildeInPath)) }
        return try PplzStore(url: PplzStore.defaultURL())
    }

    func contacts() throws -> [ContactSummary] {
        if noContacts || ProcessInfo.processInfo.environment["PPLZ_NO_CONTACTS"] == "1" { return [] }
        return try SystemContacts.fetchAll()
    }

    /// Live contact data for a linked person; `nil` for pplz-only persons or with --no-contacts.
    func contactDetails(_ entry: PersonEntry) throws -> ContactDetails? {
        guard let identifier = entry.contactIdentifier, !noContacts,
              ProcessInfo.processInfo.environment["PPLZ_NO_CONTACTS"] != "1" else { return nil }
        return try SystemContacts.details(identifier: identifier)
    }

    func directory(_ store: PplzStore) throws -> [PersonEntry] {
        PeopleDirectory.merge(contacts: try contacts(), persons: try store.persons())
    }

    /// Finds exactly one person; an unknown or ambiguous name ends the command with exit code 2.
    func resolve(_ query: String, in entries: [PersonEntry]) throws -> PersonEntry {
        switch PeopleDirectory.resolve(query, in: entries) {
        case .one(let entry):
            return entry
        case .none:
            throw Failure("No person matches \"\(query)\".")
        case .ambiguous(let candidates):
            throw PplzError.ambiguousPerson(query, candidates)
        }
    }

    /// The pplz ID of an entry, creating the person record for a contact on first use.
    func personID(_ entry: PersonEntry, _ store: PplzStore) throws -> UUID {
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
        } catch let error as PplzError {
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

struct People: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List people: your contacts plus pplz-only persons.")

    @Argument(help: "Only people whose name contains this text.") var query: String?
    @Flag(help: "Only people pplz has stored something about.") var known = false
    @Option(help: "Only people with this tag.") var tag: String?
    @OptionGroup var common: Common

    func run() throws {
        try attempt {
            let store = try common.open()
            var entries = try common.directory(store)
            if let query { entries = entries.filter { $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil } }
            if known { entries = entries.filter { $0.id != nil } }
            if let tag { entries = entries.filter { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } } }
            try common.emit(entries) {
                entries.map { entry in
                    var text = entry.name
                    if entry.isPplzOnly { text += "  (pplz only)" }
                    if entry.eventCount > 0 { text += "  — " + summary(count: entry.eventCount, lastMet: entry.lastMet) }
                    if !entry.tags.isEmpty { text += "  #" + entry.tags.joined(separator: " #") }
                    if let id = entry.id { text += "  [\(short(id))]" }
                    return text
                }.joined(separator: "\n")
            }
        }
    }
}

// MARK: - person

struct PersonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "person", abstract: "Show or edit one person.",
        subcommands: [Show.self, Add.self, Note.self, Met.self, TagAdd.self, TagRemove.self], defaultSubcommand: Show.self)

    struct Detail: Encodable {
        var person: PersonEntry
        var contact: ContactDetails?
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
                try common.emit(Detail(person: entry, contact: contact, howWeMet: stored?.howWeMet ?? "", notes: stored?.notes ?? "", history: history)) {
                    var lines = [entry.name + (entry.isPplzOnly ? "  (pplz only)" : "") + (entry.id.map { "  [\(short($0))]" } ?? "")]
                    lines += contact?.lines ?? []
                    if !entry.tags.isEmpty { lines.append("Tags: " + entry.tags.joined(separator: ", ")) }
                    if let stored, !stored.howWeMet.isEmpty { lines.append("How we met: " + stored.howWeMet) }
                    if let stored, !stored.notes.isEmpty { lines.append("Notes: " + stored.notes) }
                    lines.append(summary(count: entry.eventCount, lastMet: entry.lastMet))
                    lines += history.map { "  " + line($0) }
                    return lines.joined(separator: "\n")
                }
            }
        }
    }

    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Add a pplz-only person (no system contact).")
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

// MARK: - log

struct Log: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Log an event: a call, a meeting, any interaction.",
        discussion: "Example: pplz log \"Anna Example\" --format phone-call --title \"Catch-up\" --at yesterday")

    @Argument(help: "The people you met (name, part of a name, or ID).") var people: [String] = []
    @Option(help: "One of: \(EventFormat.allCases.map(\.rawValue).joined(separator: ", ")).") var format: EventFormat = .liveMeeting
    @Option var title: String = ""
    @Option(help: "Start: now, today, yesterday, YYYY-MM-DD or \"YYYY-MM-DD HH:MM\".") var at: String = "now"
    @Option(help: "Optional end, same formats as --at.") var end: String?
    @Option var place: String = ""
    @Option var notes: String = ""
    @Option(help: "Tag for the event; repeatable.") var tag: [String] = []
    @Flag(help: "Create a pplz-only person for any name that matches nobody.") var create = false
    @OptionGroup var common: Common

    func run() throws {
        try attempt {
            let store = try common.open()
            // Resolve and parse everything before the single write, so a failed command stores nothing.
            let plan: ParticipantPlan
            do {
                plan = try PeopleDirectory.participants(people, in: try common.directory(store), createMissing: create)
            } catch PplzError.notFound(let what) {
                throw Failure("Not found: \(what). Use --create to add them as a pplz-only person.")
            }
            let id = try store.logEvent(EventDraft(
                title: title, format: format, start: try DateInput.parse(at),
                end: try end.map { try DateInput.parse($0, endOfDay: true) },
                place: place, notes: notes, participants: plan.existing, tags: tag,
                additionalParticipants: plan.additional))
            let event = try store.event(id)
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
        @OptionGroup var common: Common

        func run() throws {
            try attempt {
                let store = try common.open()
                let eventID = try resolveID(id, among: try store.events().map(\.id), what: "event")
                let plan = person.isEmpty ? nil
                    : try PeopleDirectory.participants(person, in: try common.directory(store), createMissing: false)
                try store.updateEvent(eventID, EventChange(
                    title: title, format: format, start: try at.map { try DateInput.parse($0) },
                    end: try end.map { try DateInput.parse($0, endOfDay: true) }, clearEnd: noEnd, place: place, notes: notes,
                    participants: plan?.existing, tags: tag.isEmpty ? nil : tag,
                    additionalParticipants: plan?.additional ?? []))
                let event = try store.event(eventID)
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
