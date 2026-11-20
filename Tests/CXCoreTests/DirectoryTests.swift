import Foundation
import Testing
@testable import CXCore

@Suite struct PeopleDirectoryTests {
    let linkedID = UUID()
    let onlyID = UUID()

    var entries: [PersonEntry] {
        let contacts = [
            ContactSummary(identifier: "C-1", name: "Anna Example"),
            ContactSummary(identifier: "C-2", name: "Ben Sample"),
        ]
        let persons = [
            PersonSnapshot(id: linkedID, name: "Anna (old name)", contactIdentifier: "C-1", eventCount: 2, lastMet: day(2026, 11, 12), tags: ["client"]),
            PersonSnapshot(id: onlyID, name: "Carl Only"),
        ]
        return PeopleDirectory.merge(contacts: contacts, persons: persons)
    }

    @Test func mergesContactsWithPersons() {
        let e = entries
        #expect(e.map(\.name) == ["Anna Example", "Ben Sample", "Carl Only"])
        // linked: one entry, current contact name, cardXchange data attached
        #expect(e[0].id == linkedID)
        #expect(e[0].contactIdentifier == "C-1")
        #expect(e[0].eventCount == 2)
        #expect(e[0].tags == ["client"])
        #expect(e[0].isCXOnly == false)
        // contact without cardXchange data yet
        #expect(e[1].id == nil)
        #expect(e[1].contactIdentifier == "C-2")
        #expect(e[1].eventCount == 0)
        // cardXchange-only person
        #expect(e[2].id == onlyID)
        #expect(e[2].isCXOnly)
    }

    @Test func linkedPersonWithoutVisibleContactKeepsCachedName() {
        let persons = [PersonSnapshot(id: linkedID, name: "Cached Name", contactIdentifier: "C-9")]
        let e = PeopleDirectory.merge(contacts: [], persons: persons)
        #expect(e.map(\.name) == ["Cached Name"])
        #expect(e[0].isCXOnly == false)
    }

    @Test func resolvesExactNameBeforePartialMatches() {
        let contacts = [
            ContactSummary(identifier: "C-1", name: "Anna"),
            ContactSummary(identifier: "C-2", name: "Anna Example"),
        ]
        let e = PeopleDirectory.merge(contacts: contacts, persons: [])
        #expect(PeopleDirectory.resolve("anna", in: e) == .one(e[0]))
    }

    @Test func resolvesUniquePartialMatch() {
        #expect(PeopleDirectory.resolve("samp", in: entries) == .one(entries[1]))
    }

    @Test func reportsAmbiguousAndMissing() {
        #expect(PeopleDirectory.resolve("a", in: entries) == .ambiguous(entries))
        #expect(PeopleDirectory.resolve("zzz", in: entries) == .none)
        #expect(PeopleDirectory.resolve("  ", in: entries) == .none)
    }

    @Test func resolvesByIDOrContactIdentifier() {
        #expect(PeopleDirectory.resolve(onlyID.uuidString.lowercased(), in: entries) == .one(entries[2]))
        #expect(PeopleDirectory.resolve("C-2", in: entries) == .one(entries[1]))
    }
}

@Suite struct DateInputTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    var now: Date { day(2026, 11, 18, 15) }

    @Test func parsesKeywords() throws {
        #expect(try DateInput.parse("now", now: now, calendar: calendar) == now)
        #expect(try DateInput.parse("today", now: now, calendar: calendar) == day(2026, 11, 18, 0))
        #expect(try DateInput.parse("Yesterday", now: now, calendar: calendar) == day(2026, 11, 17, 0))
    }

    @Test func parsesDatesAndTimes() throws {
        #expect(try DateInput.parse("2026-11-12", now: now, calendar: calendar) == day(2026, 11, 12, 0))
        #expect(try DateInput.parse("2026-11-12T19:30", now: now, calendar: calendar) == day(2026, 11, 12, 19).addingTimeInterval(1800))
        #expect(try DateInput.parse("2026-11-12 19:30", now: now, calendar: calendar) == day(2026, 11, 12, 19).addingTimeInterval(1800))
    }

    @Test func rejectsGarbage() {
        #expect(throws: CXError.self) { try DateInput.parse("next week-ish", now: now, calendar: calendar) }
        #expect(throws: CXError.self) { try DateInput.parse("2026-13-40", now: now, calendar: calendar) }
    }
}

/// With iCloud sync, a person record made on the Mac arrives on the phone carrying the Mac's
/// contact identifier, which means nothing there. The `cx://person/<id>` link inside the contact
/// (synced by iCloud Contacts) is what ties the two together on every device (SPEC R3).
@Suite struct CrossDeviceIdentityTests {
    let anna = UUID()

    @Test func aPersonIsMatchedToTheLocalContactThroughTheCXLink() {
        let contacts = [ContactSummary(identifier: "PHONE-1", name: "Anna Example", cxPersonID: anna),
                        ContactSummary(identifier: "PHONE-2", name: "Ben Sample")]
        let persons = [PersonSnapshot(id: anna, name: "Anna Example", contactIdentifier: "MAC-1", eventCount: 3, tags: ["client"])]

        let entries = PeopleDirectory.merge(contacts: contacts, persons: persons)
        #expect(entries.count == 2)                       // not three: no duplicate Anna
        #expect(entries[0].id == anna)
        #expect(entries[0].contactIdentifier == "PHONE-1")   // the identifier that works on this device
        #expect(entries[0].eventCount == 3)
        #expect(entries[0].tags == ["client"])
        #expect(entries[0].isCXOnly == false)
    }

    @Test func theLinkWinsOverAStaleIdentifierMatch() {
        // "MAC-1" happens to exist here too, but belongs to someone else
        let contacts = [ContactSummary(identifier: "MAC-1", name: "Somebody Else"),
                        ContactSummary(identifier: "PHONE-1", name: "Anna Example", cxPersonID: anna)]
        let persons = [PersonSnapshot(id: anna, name: "Anna Example", contactIdentifier: "MAC-1", eventCount: 1)]
        let entries = PeopleDirectory.merge(contacts: contacts, persons: persons)
        #expect(entries.map(\.name) == ["Anna Example", "Somebody Else"])
        #expect(entries[0].id == anna)
        #expect(entries[1].id == nil)
        #expect(entries[1].eventCount == 0)
    }

    @Test func withoutALinkTheLocalIdentifierStillMatches() {
        let contacts = [ContactSummary(identifier: "C-1", name: "Anna Example")]
        let persons = [PersonSnapshot(id: anna, name: "Anna", contactIdentifier: "C-1", eventCount: 2)]
        let entries = PeopleDirectory.merge(contacts: contacts, persons: persons)
        #expect(entries.count == 1)
        #expect(entries[0].id == anna)
    }

    @Test func aLinkToAnUnknownPersonIsIgnored() {
        let contacts = [ContactSummary(identifier: "C-1", name: "Anna Example", cxPersonID: UUID())]
        let entries = PeopleDirectory.merge(contacts: contacts, persons: [])
        #expect(entries.count == 1)
        #expect(entries[0].id == nil)
    }
}
