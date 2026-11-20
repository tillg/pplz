import Foundation
import SwiftData
import Testing
@testable import CXCore

/// The tag field in the edit sheets: chosen tags are kept as comma-separated text,
/// existing tags are offered so that people reuse them instead of inventing variants.
@Suite struct TagInputTests {
    let known = ["client", "Sailing", "TPS"]

    @Test func readsTheChosenTags() {
        #expect(TagInput.names(in: " client, Sailing ,, CLIENT ") == ["client", "Sailing"])
        #expect(TagInput.names(in: "") == [])
    }

    @Test func addingUsesTheExistingSpelling() {
        #expect(TagInput.adding("tps", to: "client", known: known) == "client, TPS")
        #expect(TagInput.adding(" Brand New ", to: "client", known: known) == "client, Brand New")
    }

    @Test func addingTwiceOrNothingChangesNothing() {
        #expect(TagInput.adding("CLIENT", to: "client, Sailing", known: known) == "client, Sailing")
        #expect(TagInput.adding("  ", to: "client", known: known) == "client")
    }

    @Test func removes() {
        #expect(TagInput.removing("sailing", from: "client, Sailing") == "client")
    }

    @Test func suggestsExistingTagsThatAreNotChosenYet() {
        #expect(TagInput.suggestions(known: known, chosen: "client", query: "") == ["Sailing", "TPS"])
        #expect(TagInput.suggestions(known: known, chosen: "", query: "s") == ["Sailing", "TPS"])
        #expect(TagInput.suggestions(known: known, chosen: "", query: "sai") == ["Sailing"])
    }

    @Test func offersToCreateOnlyWhatDoesNotExist() {
        #expect(TagInput.canCreate("sail", known: known, chosen: "") == true)
        #expect(TagInput.canCreate("sailing", known: known, chosen: "") == false)
        #expect(TagInput.canCreate("new", known: known, chosen: "New") == false)
        #expect(TagInput.canCreate(" ", known: known, chosen: "") == false)
    }
}

/// Two devices can each create "tps" before they sync; afterwards the store holds two tags.
@Suite struct DuplicateTagTests {
    func storeWithDuplicates() throws -> (CXStore, a: UUID, b: UUID, c: UUID, event: UUID) {
        let (store, _) = try makeStore()
        let a = try store.createPerson(name: "A")
        let b = try store.createPerson(name: "B")
        let c = try store.createPerson(name: "C")
        try store.addTag("Tps", toPerson: a)
        try store.addTag("Tps", toPerson: b)
        try store.logEvent(EventDraft(title: "Y", format: .phoneCall, start: day(2026, 1, 9), participants: [b], tags: ["Tps"]))
        try store.logEvent(EventDraft(title: "Z", format: .phoneCall, start: day(2026, 1, 8), participants: [b], tags: ["Tps"]))
        let event = try store.logEvent(EventDraft(title: "X", format: .phoneCall, start: day(2026, 1, 10), participants: [a]))
        // what sync brings in from the other device: a second tag with the same name in other letters
        let twin = CXCore.Tag(name: "tps")
        store.context.insert(twin)
        twin.persons = [try store.fetchPerson(c), try store.fetchPerson(a)]
        twin.events = [try store.fetchEvent(event)]
        try store.context.save()
        return (store, a, b, c, event)
    }

    @Test func duplicatesAreListedAsOneTag() throws {
        let (store, _, _, _, _) = try storeWithDuplicates()
        #expect(try store.tags() == [TagSummary(name: "Tps", personCount: 3, eventCount: 3)])
    }

    @Test func mergingKeepsTheMostUsedSpellingAndEveryAssignment() throws {
        let (store, a, b, c, event) = try storeWithDuplicates()
        #expect(try store.mergeDuplicateTags() == 1)
        #expect(try store.context.fetch(FetchDescriptor<CXCore.Tag>()).map(\.name) == ["Tps"])
        for id in [a, b, c] { #expect(try store.person(id).tags == ["Tps"]) }
        #expect(try store.event(event).tags == ["Tps"])
        #expect(try store.tags() == [TagSummary(name: "Tps", personCount: 3, eventCount: 3)])
        #expect(try store.mergeDuplicateTags() == 0)
    }

    @Test func aPersonHoldingBothSpellingsShowsTheTagOnce() throws {
        let (store, a, _, _, _) = try storeWithDuplicates()
        #expect(try store.person(a).tags == ["Tps"])
    }

    @Test func newAssignmentsGoToTheSpellingThatWillSurvive() throws {
        let (store, _, _, _, _) = try storeWithDuplicates()
        let d = try store.createPerson(name: "D")
        try store.addTag("TPS", toPerson: d)
        #expect(try store.person(d).tags == ["Tps"])
    }
}
