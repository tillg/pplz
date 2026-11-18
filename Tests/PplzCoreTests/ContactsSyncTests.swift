#if os(macOS)
import Foundation
import Testing
@testable import PplzCore

/// What pplz would write into contact notes — decided from the store alone, before Contacts is touched.
@Suite struct ContactsSyncPlanTests {
    @Test func nothingIsPlannedWhileTheSettingIsOff() throws {
        let (store, _) = try makeStore()
        let a = try store.ensurePerson(for: ContactSummary(identifier: "C-A", name: "Anna"))
        try store.logEvent(EventDraft(title: "Dinner", format: .liveMeeting, start: day(2026, 11, 12), participants: [a]))
        #expect(try ContactsSync.historyPlan(store, persons: [a]).isEmpty)
    }

    @Test func plansABlockForEachLinkedPersonOnce() throws {
        let (store, _) = try makeStore()
        let a = try store.ensurePerson(for: ContactSummary(identifier: "C-A", name: "Anna"))
        let only = try store.createPerson(name: "Only In Pplz")
        try store.logEvent(EventDraft(title: "Dinner", format: .liveMeeting, start: day(2026, 11, 12), participants: [a, only]))
        try store.setShowsHistoryInContacts(true)

        let plan = try ContactsSync.historyPlan(store, persons: [a, only, a])
        #expect(plan.count == 1)
        #expect(plan[0].contactIdentifier == "C-A")
        #expect(plan[0].name == "Anna")
        #expect(plan[0].block?.contains("Dinner") == true)
        #expect(plan[0].block?.hasPrefix(NotesBlock.startMarker) == true)
    }

    @Test func aPersonWithoutEventsGetsTheirBlockRemoved() throws {
        let (store, _) = try makeStore()
        let a = try store.ensurePerson(for: ContactSummary(identifier: "C-A", name: "Anna"))
        try store.setShowsHistoryInContacts(true)
        #expect(try ContactsSync.historyPlan(store, persons: [a]) == [ContactsSync.HistoryUpdate(contactIdentifier: "C-A", name: "Anna", block: nil)])
    }

    @Test func removalIsPlannedEvenWhenTheSettingIsOff() throws {
        let (store, _) = try makeStore()
        let a = try store.ensurePerson(for: ContactSummary(identifier: "C-A", name: "Anna"))
        try store.logEvent(EventDraft(title: "Dinner", format: .liveMeeting, start: day(2026, 11, 12), participants: [a]))
        #expect(try ContactsSync.historyPlan(store, persons: [a], remove: true) == [ContactsSync.HistoryUpdate(contactIdentifier: "C-A", name: "Anna", block: nil)])
    }
}
#endif
