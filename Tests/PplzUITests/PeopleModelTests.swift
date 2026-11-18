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
