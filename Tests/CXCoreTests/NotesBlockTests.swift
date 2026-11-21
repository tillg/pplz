import SwiftData
import Foundation
import Testing
@testable import CXCore

@Suite struct NotesBlockTests {
    let utc = TimeZone(identifier: "UTC")!

    func event(_ title: String, _ format: EventFormat, _ start: Date, place: String = "") -> EventSnapshot {
        EventSnapshot(id: UUID(), title: title, format: format, start: start, end: nil, place: place, notes: "secret notes",
                      participants: [], tags: [], links: [], followUps: [])
    }

    @Test func rendersSummaryAndNewestEvents() {
        let history = [
            event("Dinner at Luigi's", .liveMeeting, day(2026, 11, 12, 19), place: "Köln"),
            event("Project kickoff", .webCall, day(2026, 10, 3)),
            event("", .phoneCall, day(2026, 8, 21)),
        ]
        #expect(NotesBlock.render(history: history, timeZone: utc) == """
            ── cardxchange ──
            Met 3× · last 2026-11-12
            2026-11-12  Live meeting · Dinner at Luigi's · Köln
            2026-10-03  Web call · Project kickoff
            2026-08-21  Phone call
            ── /cardxchange ──
            """)
    }

    @Test func showsAtMostTenEventsButCountsAll() {
        let history = (1...12).map { event("E\($0)", .phoneCall, day(2026, 12, 13 - $0)) }
        let lines = NotesBlock.render(history: history, timeZone: utc)!.split(separator: "\n")
        #expect(lines[1] == "Met 12× · last 2026-12-12")
        #expect(lines.count == 2 + 1 + 10)
        #expect(lines[11] == "2026-12-03  Phone call · E10")
    }

    @Test func noHistoryMeansNoBlock() {
        #expect(NotesBlock.render(history: [], timeZone: utc) == nil)
    }

    @Test func appendsBlockAndLeavesMyTextUntouched() {
        let mine = "Bank details\n  IBAN …\n\nsecond paragraph"
        let block = "── cardxchange ──\nMet 1× · last 2026-11-12\n── /cardxchange ──"
        #expect(NotesBlock.merge(note: mine, block: block) == mine + "\n\n" + block)
        #expect(NotesBlock.merge(note: "", block: block) == block)
    }

    @Test func replacesAnExistingBlockInPlace() {
        let old = "── cardxchange ──\nMet 1× · last 2026-01-01\n── /cardxchange ──"
        let new = "── cardxchange ──\nMet 2× · last 2026-02-02\n2026-02-02  Phone call\n── /cardxchange ──"
        let note = "before\n\n" + old + "\nafter, typed by me below the block"
        #expect(NotesBlock.merge(note: note, block: new) == "before\n\n" + new + "\nafter, typed by me below the block")
    }

    @Test func isIdempotentAndReversible() {
        let block = "── cardxchange ──\nMet 1× · last 2026-11-12\n── /cardxchange ──"
        for mine in ["", "one line", "trailing newline\n", "a\n\nb\n\n"] {
            let once = NotesBlock.merge(note: mine, block: block)
            #expect(NotesBlock.merge(note: once, block: block) == once)
            #expect(NotesBlock.merge(note: once, block: nil) == mine)
        }
    }

    @Test func removingFromANoteWithoutBlockChangesNothing() {
        #expect(NotesBlock.merge(note: "just mine", block: nil) == "just mine")
        #expect(NotesBlock.containsBlock("just mine") == false)
        #expect(NotesBlock.containsBlock("x\n\n── cardxchange ──\n── /cardxchange ──"))
    }

    @Test func aBrokenBlockIsNeverGuessedAt() {
        // start marker without end marker: leave the note alone and add a fresh block
        let note = "mine\n── cardxchange ──\nhalf deleted by hand"
        let block = "── cardxchange ──\nMet 1× · last 2026-11-12\n── /cardxchange ──"
        #expect(NotesBlock.merge(note: note, block: block) == note + "\n\n" + block)
    }

    // MARK: the old markers (02-data-migration.md §4)

    let oldBlock = "── pplz ──\nMet 1× · last 2026-01-01\n── /pplz ──"
    let newBlock = "── cardxchange ──\nMet 2× · last 2026-02-02\n── /cardxchange ──"

    @Test func anOldBlockIsReplacedInPlace() {
        let note = "before\n\n" + oldBlock + "\nafter, typed by me"
        #expect(NotesBlock.containsBlock(note))
        #expect(NotesBlock.merge(note: note, block: newBlock) == "before\n\n" + newBlock + "\nafter, typed by me")
    }

    @Test func switchingOffRemovesAnOldBlock() {
        let note = "mine\n\n" + oldBlock
        #expect(NotesBlock.merge(note: note, block: nil) == "mine")
    }

    @Test func aNoteWithBothBlocksKeepsOneNewBlock() {
        let note = "a\n\n" + oldBlock + "\nb\n\n" + "── cardxchange ──\nMet 1× · last 2026-01-01\n── /cardxchange ──" + "\nc"
        #expect(NotesBlock.merge(note: note, block: newBlock) == "a\nb\n\n" + newBlock + "\nc")
        #expect(NotesBlock.merge(note: note, block: nil) == "a\nb\nc")
    }

    @Test func anOldStartMarkerWithoutEndMarkerIsNotABlock() {
        let note = "mine\n── pplz ──\nhalf deleted by hand"
        #expect(NotesBlock.containsBlock(note) == false)
        #expect(NotesBlock.merge(note: note, block: newBlock) == note + "\n\n" + newBlock)
    }

    @Test func markersOfTheTwoFormsAreNeverPaired() {
        let note = "mine\n── pplz ──\nx\n── /cardxchange ──"
        #expect(NotesBlock.containsBlock(note) == false)
    }

    // MARK: the user's text, for the card (the card shows the history itself)

    @Test func userTextLeavesANoteWithoutBlockAlone() {
        #expect(NotesBlock.userText("Bank details\n  IBAN …\n\nsecond paragraph") == "Bank details\n  IBAN …\n\nsecond paragraph")
    }

    @Test func userTextDropsABlockAtTheStart() {
        #expect(NotesBlock.userText(newBlock + "\n\nmine") == "mine")
    }

    @Test func userTextDropsABlockInTheMiddle() {
        #expect(NotesBlock.userText("before\n\n" + newBlock + "\n\nafter") == "before\n\nafter")
    }

    @Test func userTextDropsABlockAtTheEnd() {
        #expect(NotesBlock.userText("mine\n\n" + newBlock) == "mine")
    }

    @Test func userTextDropsOldAndNewBlocks() {
        #expect(NotesBlock.userText("a\n\n" + oldBlock + "\nb\n\n" + newBlock + "\nc") == "a\nb\nc")
    }

    @Test func userTextOfOnlyABlockIsEmpty() {
        #expect(NotesBlock.userText(newBlock) == "")
        #expect(NotesBlock.userText("\n" + oldBlock + "\n") == "")
    }

    @Test func userTextKeepsABrokenBlock() {
        let note = "mine\n── cardxchange ──\nhalf deleted by hand"
        #expect(NotesBlock.userText(note) == note)
    }
}

@Suite struct SettingsTests {
    @Test func historyInContactsIsOffUntilTurnedOn() throws {
        let (store, url) = try makeStore()
        #expect(try store.showsHistoryInContacts() == false)
        try store.setShowsHistoryInContacts(true)
        #expect(try CXStore(url: url).showsHistoryInContacts())
        try store.setShowsHistoryInContacts(false)
        #expect(try store.showsHistoryInContacts() == false)
    }

    @Test func meIsNobodyUntilChosenAndIsKeptInTheStore() throws {
        let (store, url) = try makeStore()
        #expect(try store.mePerson() == nil)
        let anna = try store.createPerson(name: "Anna Example")
        try store.setMePerson(anna)
        #expect(try CXStore(url: url).mePerson() == anna)
    }
    @Test func meWrittenOnTwoDevicesBeforeTheySyncedReadsTheSameAndIsReplacedAsOne() throws {
        let (store, _) = try makeStore()
        let anna = UUID(), ben = UUID(), clara = UUID()
        let values = [anna, ben].map(\.uuidString)
        for value in values { store.context.insert(Setting(key: "mePerson", value: value)) }
        try store.context.save()
        #expect(try store.mePerson() == UUID(uuidString: values.min()!))
        try store.setMePerson(clara)
        #expect(try store.context.fetch(FetchDescriptor<Setting>()).map(\.value) == [clara.uuidString, clara.uuidString])
        #expect(try store.mePerson() == clara)
    }
}
