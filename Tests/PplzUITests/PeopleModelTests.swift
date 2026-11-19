import Foundation
import PplzCore
import Testing
@testable import PplzUI

/// The model behind the app window, on a real store in a temp file and without the address book.
@MainActor
@Suite struct PeopleModelTests {
    func makeModel(select: String? = nil) throws -> (PeopleModel, PplzStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pplz-ui-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.store")
        let model = PeopleModel(configuration: .init(storeURL: url, usesContacts: false, initialSelection: select))
        return (model, try PplzStore(url: url))
    }

    @Test func loadsPeopleAndTheSelectedCard() async throws {
        let (model, store) = try makeModel(select: "Anna Example")
        let anna = try store.createPerson(name: "Anna Example")
        try store.createPerson(name: "Ben Sample")
        try store.logEvent(EventDraft(title: "Dinner", format: .liveMeeting, start: Date(timeIntervalSince1970: 1_800_000_000), participants: [anna]))

        await model.reload()
        #expect(model.sections.map(\.title) == ["A", "B"])
        #expect(model.card?.entry.name == "Anna Example")
        #expect(model.card?.history.map(\.title) == ["Dinner"])
    }

    @Test func loggingAnEventFromTheCardUpdatesCardAndList() async throws {
        let (model, store) = try makeModel(select: "Anna Example")
        try store.createPerson(name: "Anna Example")
        await model.reload()

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        await model.logEvent(.init(format: .phoneCall, title: "  Catch-up ", start: start, place: "Köln", notes: "talked about sailing"))

        #expect(model.errorMessage == nil)
        #expect(model.card?.history.count == 1)
        #expect(model.card?.history.first?.title == "Catch-up")
        #expect(model.card?.history.first?.format == .phoneCall)
        #expect(model.card?.history.first?.place == "Köln")
        #expect(model.sections.first?.entries.first?.eventCount == 1)
        // it is really in the store, not just on screen
        #expect(try store.events().map(\.notes) == ["talked about sailing"])
    }

    @Test func loggingWithoutASelectionDoesNothing() async throws {
        let (model, store) = try makeModel()
        try store.createPerson(name: "Anna Example")
        await model.reload()
        await model.logEvent(.init(format: .phoneCall, title: "X", start: Date(), place: "", notes: ""))
        #expect(try store.events().isEmpty)
    }
}

@MainActor
@Suite struct PersonEditTests {
    @Test func savingEditsStoresThemAndRefreshesTheCard() async throws {
        let (model, store) = try PeopleModelTests().makeModel(select: "Anna Example")
        let anna = try store.createPerson(name: "Anna Example")
        await model.reload()

        #expect(model.personEdit == PeopleModel.PersonEdit())
        await model.save(PeopleModel.PersonEdit(howWeMet: "At the fair", notes: "Likes sailing", tags: "client, Sailing ,client", keepInTouchDays: 90))

        #expect(model.errorMessage == nil)
        #expect(model.card?.stored?.howWeMet == "At the fair")
        #expect(model.card?.stored?.notes == "Likes sailing")
        #expect(model.card?.entry.tags == ["client", "Sailing"])
        #expect(model.card?.stored?.keepInTouchDays == 90)
        #expect(try store.person(anna).notes == "Likes sailing")
        // the edit form starts from what is stored
        #expect(model.personEdit == PeopleModel.PersonEdit(howWeMet: "At the fair", notes: "Likes sailing", tags: "client, Sailing", keepInTouchDays: 90))

        await model.save(PeopleModel.PersonEdit(howWeMet: "", notes: "", tags: "", keepInTouchDays: nil))
        #expect(model.card?.entry.tags == [])
        #expect(model.card?.stored?.keepInTouchDays == nil)
    }
}

@MainActor
@Suite struct EventsBrowserTests {
    @Test func listsEventsByMonthAndShowsTheSelectedOne() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        let anna = try store.createPerson(name: "Anna Example")
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 12; c.hour = 12
        let nov = Calendar.current.date(from: c)!
        c.month = 10; c.day = 3
        let oct = Calendar.current.date(from: c)!
        let dinner = try store.logEvent(EventDraft(title: "Dinner", format: .liveMeeting, start: nov, participants: [anna]))
        try store.logEvent(EventDraft(title: "Kickoff", format: .webCall, start: oct, participants: [anna]))
        try store.logEvent(EventDraft(title: "Lunch", format: .liveMeeting, start: nov.addingTimeInterval(-86_400), participants: [anna]))

        await model.reload()
        #expect(model.eventSections.map { $0.events.map(\.title) } == [["Dinner", "Lunch"], ["Kickoff"]])
        #expect(model.eventSections.count == 2)

        model.selectedEventID = dinner
        #expect(model.selectedEvent?.title == "Dinner")

        model.search = "kick"
        #expect(model.eventSections.flatMap(\.events).map(\.title) == ["Kickoff"])
    }

    @Test func tickingAFollowUpCompletesIt() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        let event = try store.logEvent(EventDraft(title: "Call", format: .phoneCall, start: Date()))
        let followUp = try store.addFollowUp("send book title", toEvent: event)
        await model.reload()
        model.selectedEventID = event
        #expect(model.selectedEvent?.followUps.map(\.done) == [false])

        await model.completeFollowUp(followUp)
        #expect(model.selectedEvent?.followUps.map(\.done) == [true])
        #expect(try store.openFollowUps().isEmpty)
    }

    @Test func showingAParticipantSwitchesToThatPersonsCard() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        let anna = try store.createPerson(name: "Anna Example")
        try store.logEvent(EventDraft(title: "Call", format: .phoneCall, start: Date(), participants: [anna]))
        await model.reload()
        model.mode = .events

        await model.showPerson(anna)
        #expect(model.mode == .people)
        #expect(model.card?.entry.name == "Anna Example")
    }
}

@MainActor
@Suite struct LinkOpeningTests {
    @Test func openingAPersonLinkShowsThatPerson() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        try store.createPerson(name: "Anna Example")
        let ben = try store.createPerson(name: "Ben Sample")
        model.mode = .events

        await model.open(URL(string: PersonLink.url(for: ben))!)   // before the first load, as at launch
        #expect(model.mode == .people)
        #expect(model.card?.entry.name == "Ben Sample")

        await model.open(URL(string: "pplz://person/\(UUID().uuidString)")!)   // unknown person: stay
        #expect(model.card?.entry.name == "Ben Sample")
    }
}

@MainActor
@Suite struct EventEditingTests {
    func setUp() async throws -> (PeopleModel, PplzStore, UUID, UUID) {
        let (model, store) = try PeopleModelTests().makeModel()
        let anna = try store.createPerson(name: "Anna Example")
        let event = try store.logEvent(EventDraft(title: "Call", format: .phoneCall, start: Date(timeIntervalSince1970: 1_800_000_000),
                                                  place: "Köln", notes: "old", participants: [anna], tags: ["work"],
                                                  links: ["https://example.com/a"]))
        await model.reload()
        model.mode = .events
        model.selectedEventID = event
        return (model, store, anna, event)
    }

    @Test func theEditFormStartsFromTheEvent() async throws {
        let (model, _, _, _) = try await setUp()
        #expect(model.eventEdit == PeopleModel.EventEdit(format: .phoneCall, title: "Call", start: Date(timeIntervalSince1970: 1_800_000_000),
                                                         hasEnd: false, end: Date(timeIntervalSince1970: 1_800_000_000),
                                                         place: "Köln", notes: "old", tags: "work", links: "https://example.com/a"))
    }

    @Test func savingAnEventEditStoresIt() async throws {
        let (model, store, anna, event) = try await setUp()
        var edit = model.eventEdit!
        edit.title = "Long call"
        edit.format = .webCall
        edit.hasEnd = true
        edit.end = edit.start.addingTimeInterval(3600)
        edit.tags = "work, urgent"
        edit.links = "https://example.com/a\nhttps://example.com/b"
        edit.notes = "new"
        await model.save(edit)

        #expect(model.errorMessage == nil)
        let saved = try store.event(event)
        #expect(saved.title == "Long call")
        #expect(saved.format == .webCall)
        #expect(saved.end == saved.start.addingTimeInterval(3600))
        #expect(saved.tags == ["urgent", "work"])
        #expect(saved.links == ["https://example.com/a", "https://example.com/b"])
        #expect(saved.participants.map(\.id) == [anna])   // untouched
        #expect(model.selectedEvent?.title == "Long call")

        edit.hasEnd = false
        await model.save(edit)
        #expect(try store.event(event).end == nil)
    }

    @Test func anInvalidEditIsReportedAndNothingChanges() async throws {
        let (model, store, _, event) = try await setUp()
        var edit = model.eventEdit!
        edit.title = "Broken"
        edit.links = "not a link"
        await model.save(edit)
        #expect(model.errorMessage != nil)
        #expect(try store.event(event).title == "Call")
    }

    @Test func addsFollowUpsAndDeletesTheEvent() async throws {
        let (model, store, anna, event) = try await setUp()
        await model.addFollowUp("  send book title ")
        await model.addFollowUp("   ")
        #expect(model.selectedEvent?.followUps.map(\.text) == ["send book title"])

        await model.deleteSelectedEvent()
        #expect(model.selectedEvent == nil)
        #expect(model.selectedEventID == nil)
        #expect(try store.events().isEmpty)
        #expect(try store.history(of: anna).isEmpty)
        _ = event
    }
}

@MainActor
@Suite struct ConnectionEditingTests {
    @Test func connectsAndDisconnectsTheSelectedPerson() async throws {
        let (model, store) = try PeopleModelTests().makeModel(select: "Anna Example")
        let anna = try store.createPerson(name: "Anna Example")
        let ben = try store.createPerson(name: "Ben Sample")
        await model.reload()

        #expect(model.connectionCandidates.map(\.name) == ["Ben Sample"])   // not Anna herself
        // "Ben is Anna's manager": shown on Anna's card as "manager · Ben Sample", like in Contacts
        await model.connect(role: "manager", to: model.connectionCandidates[0])
        #expect(model.errorMessage == nil)
        #expect(model.card?.connections.map(\.displayLabel) == ["manager"])
        #expect(model.card?.connections.map(\.other.name) == ["Ben Sample"])
        #expect(try store.connections(of: ben).map(\.other.id) == [anna])
        #expect(try store.connections(of: ben).map(\.displayLabel) == ["manager of"])

        await model.disconnect(from: ben)
        #expect(model.card?.connections.isEmpty == true)
        #expect(try store.connections(of: anna).isEmpty)
    }

    @Test func anEmptyKindIsReported() async throws {
        let (model, store) = try PeopleModelTests().makeModel(select: "Anna Example")
        try store.createPerson(name: "Anna Example")
        try store.createPerson(name: "Ben Sample")
        await model.reload()
        await model.connect(role: "  ", to: model.connectionCandidates[0])
        #expect(model.errorMessage != nil)
        #expect(model.card?.connections.isEmpty == true)
    }
}

/// iCloud sync must be an explicit choice of the app's own default store — never of a demo,
/// test or scratch store, whose rows would otherwise land in the user's iCloud.
@Suite struct SyncOptInTests {
    func defaults(_ values: [String: Any]) -> UserDefaults {
        let name = "pplz-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        for (key, value) in values { defaults.set(value, forKey: key) }
        return defaults
    }

    @Test func theDefaultStoreSyncs() {
        #expect(PeopleModel.Configuration(defaults: defaults([:])).syncsWithICloud)
    }

    @Test func aCustomStoreNeverSyncsUnlessForced() {
        #expect(PeopleModel.Configuration(defaults: defaults(["store": "/tmp/x.store"])).syncsWithICloud == false)
        #expect(PeopleModel.Configuration(defaults: defaults(["store": "/tmp/x.store", "forceSync": true])).syncsWithICloud)
    }

    @Test func syncCanBeSwitchedOff() {
        #expect(PeopleModel.Configuration(defaults: defaults(["noSync": true])).syncsWithICloud == false)
    }

    @Test func codeThatBuildsAConfigurationItselfDoesNotSync() {
        #expect(PeopleModel.Configuration().syncsWithICloud == false)
        #expect(PeopleModel.Configuration(storeURL: URL(fileURLWithPath: "/tmp/x.store")).syncsWithICloud == false)
    }
}
