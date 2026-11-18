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
