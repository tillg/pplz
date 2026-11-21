import CoreGraphics
import Foundation
import ImageIO
import CXCore
import Testing
@testable import CXUI

/// The model behind the app window, on a real store in a temp file and without the address book.
@MainActor
@Suite struct PeopleModelTests {
    func makeModel(select: String? = nil) throws -> (PeopleModel, CXStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cx-ui-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.store")
        let model = PeopleModel(configuration: .init(storeURL: url, usesContacts: false, initialSelection: select))
        return (model, try CXStore(url: url))
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

        await model.open(URL(string: "cx://person/\(UUID().uuidString)")!)   // unknown person: stay
        #expect(model.card?.entry.name == "Ben Sample")
    }

    @Test func anOldPersonLinkStillShowsThatPerson() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        try store.createPerson(name: "Anna Example")
        let ben = try store.createPerson(name: "Ben Sample")
        await model.open(URL(string: "pplz://person/\(ben.uuidString.lowercased())")!)
        #expect(model.card?.entry.name == "Ben Sample")
    }

    @Test func aCaptureLinkInEitherSchemeAsksForTheInbox() async throws {
        let (model, _) = try PeopleModelTests().makeModel()
        let before = model.captureRequests
        await model.open(URL(string: "cx://capture")!)
        await model.open(URL(string: "pplz://capture")!)
        #expect(model.captureRequests == before + 2)
    }
}

@MainActor
@Suite struct EventEditingTests {
    func setUp() async throws -> (PeopleModel, CXStore, UUID, UUID) {
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
        let name = "cx-test-\(UUID().uuidString)"
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

@MainActor @Suite struct KnownTagsTests {
    @Test func theModelOffersTheTagsInUse() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cx-ui-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.store")
        let model = PeopleModel(configuration: .init(storeURL: url, usesContacts: false, initialSelection: "Anna Example"))
        let store = try CXStore(url: url)
        let anna = try store.createPerson(name: "Anna Example")
        try store.addTag("client", toPerson: anna)
        try store.logEvent(EventDraft(title: "Dinner", format: .liveMeeting, start: Date(timeIntervalSince1970: 1_800_000_000), participants: [anna], tags: ["Sailing"]))

        await model.reload()
        #expect(model.knownTags == ["client", "Sailing"])

        await model.save(PeopleModel.PersonEdit(howWeMet: "", notes: "", tags: "client, vip", keepInTouchDays: nil))
        #expect(model.knownTags == ["client", "Sailing", "vip"])
    }
}

@MainActor @Suite struct QuickLogTests {
    func makeModel() throws -> (PeopleModel, CXStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cx-ui-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.store")
        return (PeopleModel(configuration: .init(storeURL: url, usesContacts: false)), try CXStore(url: url))
    }

    @Test func logsAnEventWithSeveralPeopleWithoutACardBeingOpen() async throws {
        let (model, store) = try makeModel()
        let anna = try store.createPerson(name: "Anna Example")
        let ben = try store.createPerson(name: "Ben Sample")
        try store.createPerson(name: "Carl Other")
        await model.reload()

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        await model.logEvent(.init(format: .liveMeeting, title: "Lunch", start: start, place: "Köln", notes: "", tags: "work, vip"),
                             with: [anna.uuidString, ben.uuidString])

        #expect(model.errorMessage == nil)
        let events = try store.events()
        #expect(events.count == 1)
        #expect(events[0].participants.map(\.name) == ["Anna Example", "Ben Sample"])
        #expect(events[0].tags == ["vip", "work"])
        #expect(model.events.count == 1)
        #expect(model.knownTags == ["vip", "work"])
    }

    @Test func nothingIsLoggedWithoutPeople() async throws {
        let (model, store) = try makeModel()
        try store.createPerson(name: "Anna Example")
        await model.reload()
        await model.logEvent(.init(format: .phoneCall, title: "X"), with: [])
        await model.logEvent(.init(format: .phoneCall, title: "X"), with: ["no-such-key"])
        #expect(try store.events().isEmpty)
    }

    @Test func theFormatUsedLastIsSuggested() async throws {
        let (model, store) = try makeModel()
        let anna = try store.createPerson(name: "Anna Example")
        await model.reload()
        #expect(model.suggestedFormat == .liveMeeting)
        // logged last, although it took place earlier than the web call
        try store.logEvent(EventDraft(title: "Later", format: .webCall, start: Date(timeIntervalSince1970: 1_800_000_000), participants: [anna]))
        await model.logEvent(.init(format: .phoneCall, title: "Earlier", start: Date(timeIntervalSince1970: 1_700_000_000)), with: [anna.uuidString])
        #expect(model.suggestedFormat == .phoneCall)
    }
}

@MainActor @Suite struct EventParticipantsTests {
    func setUp() async throws -> (PeopleModel, CXStore, anna: UUID, ben: UUID, carl: UUID, event: UUID) {
        let (model, store) = try PeopleModelTests().makeModel()
        let anna = try store.createPerson(name: "Anna Example")
        let ben = try store.createPerson(name: "Ben Sample")
        let carl = try store.createPerson(name: "Carl Other")
        let event = try store.logEvent(EventDraft(title: "Dialogue", format: .liveMeeting, start: Date(timeIntervalSince1970: 1_800_000_000),
                                                  place: "Hanoi", participants: [anna, ben]))
        await model.reload()
        model.mode = .events
        model.selectedEventID = event
        return (model, store, anna, ben, carl, event)
    }

    @Test func theEditStartsWithTheEventsPeople() async throws {
        let (model, _, anna, ben, _, _) = try await setUp()
        #expect(model.selectedEventPeople.map(\.id) == [anna, ben])
    }

    @Test func peopleCanBeAddedToAndRemovedFromAnEvent() async throws {
        let (model, store, anna, _, carl, event) = try await setUp()
        await model.save(model.eventEdit!, participants: [anna.uuidString, carl.uuidString])
        #expect(model.errorMessage == nil)
        #expect(try store.event(event).participants.map(\.name) == ["Anna Example", "Carl Other"])
        #expect(try store.event(event).place == "Hanoi")
        #expect(model.selectedEvent?.participants.map(\.name) == ["Anna Example", "Carl Other"])
        #expect(try store.person(carl).eventCount == 1)
    }

    @Test func savingWithoutAPeopleListLeavesThemAlone() async throws {
        let (model, store, _, _, _, event) = try await setUp()
        await model.save(model.eventEdit!)
        #expect(try store.event(event).participants.count == 2)
    }

    @Test func anEventKeepsAtLeastOnePerson() async throws {
        let (model, store, _, _, _, event) = try await setUp()
        await model.save(model.eventEdit!, participants: [])
        #expect(try store.event(event).participants.count == 2)
    }
}

@MainActor @Suite struct NewPeopleInEventsTests {
    @Test func loggingCanCreatePeopleWhoAreNotKnownYet() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        let anna = try store.createPerson(name: "Anna Example")
        await model.reload()

        await model.logEvent(.init(format: .largerGathering, title: "Vietnam Dialogue", place: "Hanoi"),
                             with: [anna.uuidString], newPeople: ["Mai Nguyen", " Tran Duc "])

        #expect(model.errorMessage == nil)
        let event = try #require(try store.events().first)
        #expect(event.participants.map(\.name) == ["Anna Example", "Mai Nguyen", "Tran Duc"])
        // they are persons of their own now, only in cardXchange
        let mai = try #require(model.entries.first { $0.name == "Mai Nguyen" })
        #expect(mai.isCXOnly)
        #expect(mai.eventCount == 1)
    }

    @Test func anEventCanBeLoggedWithNewPeopleOnly() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        await model.reload()
        await model.logEvent(.init(format: .liveMeeting), with: [], newPeople: ["Mai Nguyen"])
        #expect(try store.events().first?.participants.map(\.name) == ["Mai Nguyen"])
    }

    @Test func aNewPersonCanBeAddedToAnExistingEvent() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        let anna = try store.createPerson(name: "Anna Example")
        let event = try store.logEvent(EventDraft(title: "Dialogue", format: .liveMeeting, start: Date(timeIntervalSince1970: 1_800_000_000), participants: [anna]))
        await model.reload()
        model.mode = .events
        model.selectedEventID = event

        await model.save(model.eventEdit!, participants: [anna.uuidString], newPeople: ["Mai Nguyen"])
        #expect(try store.event(event).participants.map(\.name) == ["Anna Example", "Mai Nguyen"])
        #expect(try store.persons().count == 2)
    }
}

@MainActor @Suite struct CaptureTests {
    let profile = CapturedProfile(name: "Dr. Oliver Massmann", jobTitle: "Partner", company: "Duane Morris LLP",
                                  linkedInID: "dr-oliver-massmann-153a405")

    /// A picture pasted or dropped into cardXchange waits in the model until the window can show it.
    @Test func picturesOfferedToTheAppWaitInOrderAndAreHandedOutOnce() throws {
        let (model, _) = try PeopleModelTests().makeModel()
        let before = model.captureRequests
        model.offerCapture(Data([1]))
        model.offerCapture(Data([2]))
        #expect(model.captureRequests == before + 2)       // the view is told each time
        #expect(model.takeOfferedCaptures() == [Data([1]), Data([2])])
        #expect(model.takeOfferedCaptures().isEmpty)
    }

    @Test func aCaptureCanBecomeANewPerson() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        await model.reload()
        let id = try #require(await model.saveCapture(profile, as: .new))
        #expect(model.errorMessage == nil)
        let person = try store.person(id)
        #expect(person.name == "Oliver Massmann")          // the title is not part of the name
        #expect(person.linkedInID == "dr-oliver-massmann-153a405")
        #expect(model.card?.entry.id == id)                // and the new person is shown
    }

    @Test func aCaptureCanUpdateAnExistingPerson() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        let oliver = try store.createPerson(name: "Olli Massmann")
        await model.reload()
        let id = await model.saveCapture(profile, as: .existing(key: oliver.uuidString))
        #expect(id == oliver)
        #expect(try store.persons().count == 1)
        #expect(try store.person(oliver).name == "Olli Massmann")     // my own name for the person stays
        #expect(try store.person(oliver).linkedInID == "dr-oliver-massmann-153a405")
    }

    @Test func anExistingLinkedInIDIsNotReplaced() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        let oliver = try store.createPerson(name: "Oliver Massmann")
        try store.setLinkedInID("the-right-one", for: oliver)
        await model.reload()
        await model.saveCapture(profile, as: .existing(key: oliver.uuidString))
        #expect(try store.person(oliver).linkedInID == "the-right-one")
    }

    @Test func thePersonWithThatLinkedInProfileIsProposedFirst() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        try store.createPerson(name: "Oliver Massmann")
        let renamed = try store.createPerson(name: "Olli M.")
        try store.setLinkedInID("dr-oliver-massmann-153a405", for: renamed)
        try store.createPerson(name: "Somebody Else")
        await model.reload()
        #expect(model.captureCandidates(for: profile).map(\.name) == ["Olli M.", "Oliver Massmann"])
    }

    @Test func onlyACertainMatchIsPreselected() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        let peter = try store.createPerson(name: "Peter Massmann")
        await model.reload()
        // the same family name alone is a proposal, never a preselection
        #expect(model.captureCandidates(for: profile).map(\.name) == ["Peter Massmann"])
        #expect(model.capturePreselection(for: profile) == nil)

        let oliver = try store.createPerson(name: "Oliver Massmann")
        await model.reload()
        #expect(model.capturePreselection(for: profile) == oliver.uuidString)      // exactly that name, once

        try store.createPerson(name: "Oliver Massmann")
        await model.reload()
        #expect(model.capturePreselection(for: profile) == nil)                    // two of that name: ask

        try store.setLinkedInID("dr-oliver-massmann-153a405", for: peter)
        await model.reload()
        #expect(model.capturePreselection(for: profile) == peter.uuidString)       // the LinkedIn profile decides
    }

    @Test func aCaptureWithoutANameIsNotSavedAsANewPerson() async throws {
        let (model, store) = try PeopleModelTests().makeModel()
        await model.reload()
        #expect(await model.saveCapture(CapturedProfile(name: "  "), as: .new) == nil)
        #expect(try store.persons().isEmpty)
    }
}

/// After a capture cardXchange asks which event the person belongs to.
@MainActor @Suite struct CaptureEventTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    var hour: TimeInterval { 3600 }

    func setUp() async throws -> (PeopleModel, CXStore, anna: UUID, oliver: UUID) {
        let (model, store) = try PeopleModelTests().makeModel()
        let anna = try store.createPerson(name: "Anna Example")
        let oliver = try store.createPerson(name: "Oliver Massmann")
        return (model, store, anna, oliver)
    }

    @Test func theEventsOfTheLastDaysAreOffered() async throws {
        let (model, store, anna, _) = try await setUp()
        try store.logEvent(EventDraft(title: "Old", format: .liveMeeting, start: now.addingTimeInterval(-30 * 24 * hour), participants: [anna]))
        try store.logEvent(EventDraft(title: "Yesterday", format: .liveMeeting, start: now.addingTimeInterval(-26 * hour), participants: [anna]))
        try store.logEvent(EventDraft(title: "Just now", format: .liveMeeting, start: now.addingTimeInterval(-hour), participants: [anna]))
        try store.logEvent(EventDraft(title: "Next week", format: .liveMeeting, start: now.addingTimeInterval(7 * 24 * hour), participants: [anna]))
        await model.reload()
        #expect(model.recentEvents(now: now).map(\.title) == ["Just now", "Yesterday"])
    }

    @Test func aPersonCanBeAddedToAnEvent() async throws {
        let (model, store, anna, oliver) = try await setUp()
        let event = try store.logEvent(EventDraft(title: "Vietnam Dialogue", format: .largerGathering, start: now, participants: [anna]))
        await model.reload()
        await model.addPerson(oliver, toEvent: event)
        await model.addPerson(oliver, toEvent: event)      // twice does no harm
        #expect(model.errorMessage == nil)
        #expect(try store.event(event).participants.map(\.name) == ["Anna Example", "Oliver Massmann"])
    }

    @Test func aCalendarEntryBecomesAnEventWithThePerson() async throws {
        let (model, store, _, oliver) = try await setUp()
        await model.reload()
        let entry = CalendarEntry(title: "Vietnam Dialogue", start: now, end: now.addingTimeInterval(2 * hour), place: "Hanoi")
        await model.logCalendarEntry(entry, with: oliver)
        let event = try #require(try store.events().first)
        #expect(event.title == "Vietnam Dialogue")
        #expect(event.start == now)
        #expect(event.end == now.addingTimeInterval(2 * hour))
        #expect(event.place == "Hanoi")
        #expect(event.participants.map(\.name) == ["Oliver Massmann"])
    }

    @Test func theSameCalendarEntryIsNotLoggedTwice() async throws {
        let (model, store, anna, oliver) = try await setUp()
        await model.reload()
        let entry = CalendarEntry(title: "Vietnam Dialogue", start: now, end: nil, place: "")
        await model.logCalendarEntry(entry, with: anna)
        await model.logCalendarEntry(entry, with: oliver)
        #expect(try store.events().count == 1)
        #expect(try store.events()[0].participants.map(\.name) == ["Anna Example", "Oliver Massmann"])
    }
}

/// The map mode: a third entry next to People and Events. Pins come from contacts' addresses, which a
/// test without the address book does not have; what can be tried here is the way from a pin to a card.
@MainActor
@Suite struct MapModeTests {
    @Test func openingAPinShowsThePersonsCard() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cx-ui-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.store")
        var configuration = PeopleModel.Configuration(storeURL: url, usesContacts: false)
        configuration.geocodeURL = dir.appendingPathComponent("geocache.json")
        let model = PeopleModel(configuration: configuration)
        let anna = try CXStore(url: url).createPerson(name: "Anna Example")
        await model.reload()

        model.mode = .map
        #expect(PeopleModel.Mode.allCases.map(\.rawValue) == ["People", "Events", "Map"])
        #expect(model.mapPins.isEmpty)
        #expect(model.locateStatus == nil)

        model.openPerson(key: anna.uuidString)
        #expect(model.mode == .people)
        #expect(model.selection == anna.uuidString)
    }
}

@MainActor
@Suite struct PersonPhotoModelTests {
    /// A drawn picture has no face; Vision finds none.
    func pictureWithoutFace() -> Data {
        let context = CGContext(data: nil, width: 300, height: 200, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 200))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    @Test func aPictureWithoutAFaceIsRefusedAndNothingIsStored() async throws {
        let (model, store) = try PeopleModelTests().makeModel(select: "Anna Example")
        let anna = try store.createPerson(name: "Anna Example")
        await model.reload()
        await model.addPhotos([pictureWithoutFace()])
        #expect(model.errorMessage == "No face found in this picture.")
        #expect(try store.photos(of: anna).isEmpty)
        #expect(model.faceChoice == nil)
    }

    @Test func severalPicturesWithoutFacesAreReportedTogether() async throws {
        let (model, store) = try PeopleModelTests().makeModel(select: "Anna Example")
        try store.createPerson(name: "Anna Example")
        await model.reload()
        await model.addPhotos([pictureWithoutFace(), pictureWithoutFace()])
        #expect(model.errorMessage == "2 of 2 pictures were not added. No face found in this picture.")
    }

    @Test func theCardShowsThePhotosAndDeletingOneRemovesIt() async throws {
        let (model, store) = try PeopleModelTests().makeModel(select: "Anna Example")
        let anna = try store.createPerson(name: "Anna Example")
        let ids = try store.addPhotos([pictureWithoutFace(), pictureWithoutFace()], toPerson: anna)
        await model.reload()
        #expect(model.card?.photos.count == 2)

        await model.deletePhoto(ids[0])
        #expect(model.card?.photos.map(\.id) == [ids[1]])
        #expect(try store.photos(of: anna).map(\.id) == [ids[1]])
    }

    @Test func withoutContactsNothingCanBecomeAContactPicture() async throws {
        let (model, store) = try PeopleModelTests().makeModel(select: "Anna Example")
        try store.createPerson(name: "Anna Example")
        await model.reload()
        #expect(!model.canUseAsContactPicture)
    }
}

@MainActor
@Suite struct ContactEditModelTests {
    @Test func withoutContactsThereIsNothingToLoadAndNothingToSave() async throws {
        let (model, store) = try PeopleModelTests().makeModel(select: "Anna Example")
        try store.createPerson(name: "Anna Example")
        await model.reload()

        #expect(await model.loadContactEdit() == nil)
        var edit = ContactEdit(givenName: "Anna", familyName: "Example", contactIdentifier: "C-1")
        #expect(await model.saveContactEdit(edit, original: edit) == nil)   // no change: nothing to do, nothing to refuse
        let original = edit
        edit.nickname = "Anni"
        #expect(await model.saveContactEdit(edit, original: original) == "cardXchange is not using Contacts.")
        #expect(await model.createContact(edit) == "cardXchange is not using Contacts.")
        // the list is as it was
        #expect(model.sections.flatMap(\.entries).map(\.name) == ["Anna Example"])
    }

    /// A save goes to the contact the form was loaded from — never to whoever is selected when Save is pressed.
    @Test func aSaveNeedsTheContactTheFormWasLoadedFrom() async throws {
        let (model, store) = try PeopleModelTests().makeModel(select: "Anna Example")
        try store.createPerson(name: "Anna Example")
        await model.reload()                      // Anna is selected, with no contact identifier of her own to fall back on
        let original = ContactEdit(givenName: "Anna")
        var edit = original
        edit.nickname = "Anni"
        #expect(await model.saveContactEdit(edit, original: original) == "This form was not loaded from a contact.")
    }

    /// The cardXchange fields go to the person the edit screen was opened for, also when another one is selected by now.
    @Test func cxFieldsAreSavedForThePersonTheScreenWasOpenedFor() async throws {
        let (model, store) = try PeopleModelTests().makeModel(select: "Anna Example")
        let anna = try store.createPerson(name: "Anna Example")
        let ben = try store.createPerson(name: "Ben Example")
        await model.reload()
        let entry = try #require(model.card?.entry)
        #expect(entry.id == anna)

        await model.showPerson(ben)
        #expect(model.card?.entry.id == ben)
        let reason = await model.saveEdit(for: entry, contact: nil, originalContact: nil,
                                          person: .init(notes: "Likes sailing", tags: "client"), originalPerson: .init())
        #expect(reason == nil)
        #expect(try store.person(anna).notes == "Likes sailing")
        #expect(try store.person(ben).notes == "")
    }

    /// The contact is written first: if it is refused, the cardXchange fields are not written either.
    @Test func nothingIsSavedWhenTheContactIsRefused() async throws {
        let (model, store) = try PeopleModelTests().makeModel(select: "Anna Example")
        let anna = try store.createPerson(name: "Anna Example")
        await model.reload()
        let entry = try #require(model.card?.entry)
        let original = ContactEdit(givenName: "Anna", contactIdentifier: "C-1")
        var edit = original
        edit.nickname = "Anni"
        let reason = await model.saveEdit(for: entry, contact: edit, originalContact: original,
                                          person: .init(notes: "Likes sailing"), originalPerson: .init())
        #expect(reason == "cardXchange is not using Contacts.")
        #expect(try store.person(anna).notes == "")
    }

    @Test func aContactNeedsANameOrACompany() async throws {
        let (model, _) = try PeopleModelTests().makeModel()
        await model.reload()
        #expect(await model.createContact(ContactEdit(nickname: "Anni")) == "A contact needs a name or a company.")
        let original = ContactEdit(givenName: "Anna")
        #expect(await model.saveContactEdit(ContactEdit(givenName: " "), original: original) == "A contact needs a name or a company.")
    }
}

/// Deleting from the card, "Recently Deleted", restoring (SPEC §3.4).
@MainActor
@Suite struct DeletePersonTests {
    func makeModel(select: String? = nil) throws -> (PeopleModel, CXStore) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cx-ui-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.store")
        let model = PeopleModel(configuration: .init(storeURL: url, usesContacts: false, initialSelection: select))
        return (model, try CXStore(url: url))
    }

    @Test func deletingTheSelectedPersonMovesThemToRecentlyDeleted() async throws {
        let (model, store) = try makeModel(select: "Anna Example")
        try store.createPerson(name: "Anna Example")
        try store.createPerson(name: "Ben Sample")
        await model.reload()

        let failure = await model.deleteSelectedPerson()

        #expect(failure == nil)
        #expect(model.entries.map(\.name) == ["Ben Sample"])
        #expect(model.recentlyDeleted.map(\.name) == ["Anna Example"])
        #expect(model.card == nil)
    }

    @Test func restoringBringsThePersonBackToTheList() async throws {
        let (model, store) = try makeModel()
        let anna = try store.createPerson(name: "Anna Example")
        try store.deletePerson(anna, contactCopy: nil, at: .now)
        await model.reload()

        let failure = await model.restore(anna)

        #expect(failure == nil)
        #expect(model.entries.map(\.name) == ["Anna Example"])
        #expect(model.recentlyDeleted.isEmpty)
    }

    @Test func deletingForGoodRemovesThePersonFromTheStore() async throws {
        let (model, store) = try makeModel()
        let anna = try store.createPerson(name: "Anna Example")
        try store.deletePerson(anna, contactCopy: nil, at: .now)
        await model.reload()

        await model.deleteForGood(anna)

        #expect(model.recentlyDeleted.isEmpty)
        #expect(throws: CXError.self) { try store.person(anna) }
    }

    @Test func loadingRemovesPersonsDeletedMoreThanThirtyDaysAgo() async throws {
        let (model, store) = try makeModel()
        let old = try store.createPerson(name: "Old Example")
        let recent = try store.createPerson(name: "Recent Example")
        try store.deletePerson(old, contactCopy: nil, at: Date.now.addingTimeInterval(-31 * 24 * 60 * 60))
        try store.deletePerson(recent, contactCopy: nil, at: Date.now.addingTimeInterval(-29 * 24 * 60 * 60))

        await model.reload()

        #expect(model.recentlyDeleted.map(\.id) == [recent])
        #expect(try store.deletedPersons().map(\.id) == [recent])
    }

    @Test func editingAnEventKeepsADeletedParticipant() async throws {
        let (model, store) = try makeModel()
        let anna = try store.createPerson(name: "Anna Example")
        let ben = try store.createPerson(name: "Ben Sample")
        let event = try store.logEvent(EventDraft(title: "Lunch", format: .liveMeeting, start: Date(timeIntervalSince1970: 1_800_000_000),
                                                  participants: [anna, ben]))
        try store.deletePerson(anna, contactCopy: nil, at: .now)
        await model.reload()
        model.mode = .events
        model.selectedEventID = event
        var edit = try #require(model.eventEdit)
        edit.title = "Long lunch"

        await model.save(edit, participants: model.selectedEventPeople.map(\.key))

        #expect(try store.event(event).title == "Long lunch")
        #expect(try store.event(event).participants.map(\.id) == [anna, ben])
    }

    @Test func withoutContactsAPersonWithAContactIsNotDeleted() async throws {
        let (model, store) = try makeModel(select: "Anna Example")
        try store.ensurePerson(for: ContactSummary(identifier: "C-1", name: "Anna Example"))
        await model.reload()

        let failure = await model.deleteSelectedPerson()

        #expect(failure != nil)
        #expect(model.entries.map(\.name) == ["Anna Example"])
        #expect(try store.deletedPersons().isEmpty)
    }
}

/// "My Card" (SPEC §4.8): the person chosen as me and the chosen fields, kept in a defaults suite of its own.
@MainActor
@Suite struct MyCardModelTests {
    func makeModel(settings: String) throws -> (PeopleModel, CXStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cx-ui-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.store")
        var configuration = PeopleModel.Configuration(storeURL: url, usesContacts: false)
        configuration.settingsSuite = settings
        return (PeopleModel(configuration: configuration), try CXStore(url: url), url)
    }

    /// A defaults suite of its own, removed again when the test ends.
    private func withFreshSettings(_ test: (String) async throws -> Void) async rethrows {
        let suite = "cx-ui-tests-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        try await test(suite)
    }

    @Test func noCardUntilSomeoneIsChosen() async throws {
        try await withFreshSettings { settings in
            let (model, store, _) = try makeModel(settings: settings)
            try store.createPerson(name: "Anna Example")
            await model.reload()
            #expect(model.myCardEntry == nil)
            #expect(model.myCard == nil)
        }
    }

    @Test func aChosenPersonWithoutAContactGivesACardWithTheName() async throws {
        try await withFreshSettings { settings in
            let (model, store, _) = try makeModel(settings: settings)
            try store.createPerson(name: "Anna Example")
            await model.reload()
            await model.chooseMe(model.entries[0].key)
            #expect(model.myCardEntry?.name == "Anna Example")
            #expect(model.myCard == SharedCard(contact: ContactEdit(givenName: "Anna", familyName: "Example")))
        }
    }

    @Test func theChoiceAndTheFieldsAreKeptForTheNextLaunch() async throws {
        try await withFreshSettings { settings in
            let (model, store, url) = try makeModel(settings: settings)
            try store.createPerson(name: "Anna Example")
            await model.reload()
            await model.chooseMe(model.entries[0].key)
            model.myCardFields.picture = true

            var configuration = PeopleModel.Configuration(storeURL: url, usesContacts: false)
            configuration.settingsSuite = settings
            let next = PeopleModel(configuration: configuration)
            await next.reload()
            #expect(next.myCard?.contact.givenName == "Anna")
            #expect(next.myCardFields.picture)
        }
    }

    @Test func choosingAnotherPersonStartsFromTheDefaultRows() async throws {
        try await withFreshSettings { settings in
            let (model, store, _) = try makeModel(settings: settings)
            try store.createPerson(name: "Anna Example")
            try store.createPerson(name: "Ben Sample")
            await model.reload()
            await model.chooseMe(model.entries[0].key)
            model.myCardFields.rows = ["P1"]
            await model.chooseMe(model.entries[0].key)
            #expect(model.myCardFields.rows == ["P1"])

            await model.chooseMe(model.entries[1].key)
            #expect(model.myCardFields.rows == nil)
        }
    }
}
