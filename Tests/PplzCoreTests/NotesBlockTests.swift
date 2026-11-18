import Foundation
import Testing
@testable import PplzCore

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
            ── pplz ──
            Met 3× · last 2026-11-12
            2026-11-12  Live meeting · Dinner at Luigi's · Köln
            2026-10-03  Web call · Project kickoff
            2026-08-21  Phone call
            ── /pplz ──
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
        let block = "── pplz ──\nMet 1× · last 2026-11-12\n── /pplz ──"
        #expect(NotesBlock.merge(note: mine, block: block) == mine + "\n\n" + block)
        #expect(NotesBlock.merge(note: "", block: block) == block)
    }

    @Test func replacesAnExistingBlockInPlace() {
        let old = "── pplz ──\nMet 1× · last 2026-01-01\n── /pplz ──"
        let new = "── pplz ──\nMet 2× · last 2026-02-02\n2026-02-02  Phone call\n── /pplz ──"
        let note = "before\n\n" + old + "\nafter, typed by me below the block"
        #expect(NotesBlock.merge(note: note, block: new) == "before\n\n" + new + "\nafter, typed by me below the block")
    }

    @Test func isIdempotentAndReversible() {
        let block = "── pplz ──\nMet 1× · last 2026-11-12\n── /pplz ──"
        for mine in ["", "one line", "trailing newline\n", "a\n\nb\n\n"] {
            let once = NotesBlock.merge(note: mine, block: block)
            #expect(NotesBlock.merge(note: once, block: block) == once)
            #expect(NotesBlock.merge(note: once, block: nil) == mine)
        }
    }

    @Test func removingFromANoteWithoutBlockChangesNothing() {
        #expect(NotesBlock.merge(note: "just mine", block: nil) == "just mine")
        #expect(NotesBlock.containsBlock("just mine") == false)
        #expect(NotesBlock.containsBlock("x\n\n── pplz ──\n── /pplz ──"))
    }

    @Test func aBrokenBlockIsNeverGuessedAt() {
        // start marker without end marker: leave the note alone and add a fresh block
        let note = "mine\n── pplz ──\nhalf deleted by hand"
        let block = "── pplz ──\nMet 1× · last 2026-11-12\n── /pplz ──"
        #expect(NotesBlock.merge(note: note, block: block) == note + "\n\n" + block)
    }
}

@Suite struct SettingsTests {
    @Test func historyInContactsIsOffUntilTurnedOn() throws {
        let (store, url) = try makeStore()
        #expect(try store.showsHistoryInContacts() == false)
        try store.setShowsHistoryInContacts(true)
        #expect(try PplzStore(url: url).showsHistoryInContacts())
        try store.setShowsHistoryInContacts(false)
        #expect(try store.showsHistoryInContacts() == false)
    }
}
