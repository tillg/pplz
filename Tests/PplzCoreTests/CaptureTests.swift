import Foundation
import Testing
@testable import PplzCore

/// A captured profile (e.g. a LinkedIn screenshot) names a person. pplz proposes who that could be;
/// the user decides — a name is a hint here, never the identity.
@Suite struct CaptureMatchTests {
    static func entry(_ key: String, _ name: String, nickname: String = "") -> PersonEntry {
        PersonEntry(id: nil, contactIdentifier: key, name: name, eventCount: 0, lastMet: nil, tags: [], nickname: nickname)
    }

    let entries = [
        entry("C-1", "Oliver Massmann"),
        entry("C-2", "Olivia Massmann"),
        entry("C-3", "Oliver Schmidt"),
        entry("C-4", "Dr. Karl Maßmann"),
        entry("C-5", "Anna Example", nickname: "Olli"),
    ]

    func matches(_ name: String) -> [String] { PeopleDirectory.candidates(forCapturedName: name, in: entries).map(\.name) }

    @Test func theSameNameComesFirstThenTheSameFamilyName() {
        #expect(matches("Oliver Massmann") == ["Oliver Massmann", "Dr. Karl Maßmann", "Olivia Massmann"])
    }

    @Test func titlesCaseAndAccentsAreIgnored() {
        #expect(matches("Dr. OLIVER MASSMANN").first == "Oliver Massmann")
        #expect(matches("Prof. Dr. Karl Massmann").first == "Dr. Karl Maßmann")
    }

    @Test func aSharedFirstNameAloneIsNoMatch() {
        #expect(matches("Oliver Twist") == [])
        #expect(matches("") == [])
    }

    @Test func titlesAreStrippedFromACapturedName() {
        #expect(PeopleDirectory.nameWithoutTitles("Dr. Oliver Massmann") == "Oliver Massmann")
        #expect(PeopleDirectory.nameWithoutTitles("Prof. Dr.-Ing. Eva  Klein, MBA") == "Eva Klein")
        #expect(PeopleDirectory.nameWithoutTitles("Dr Who") == "Who")
        #expect(PeopleDirectory.nameWithoutTitles("Drake Bell") == "Drake Bell")
    }

    @Test func realNamesThatLookLikeTitlesAreKept() {
        #expect(PeopleDirectory.nameWithoutTitles("Phil Collins") == "Phil Collins")
        #expect(PeopleDirectory.nameWithoutTitles("C. S. Lewis") == "C. S. Lewis")
        #expect(PeopleDirectory.nameWithoutTitles("Mag Ruffman") == "Mag Ruffman")
        #expect(PeopleDirectory.nameWithoutTitles("Ing Chang") == "Ing Chang")
        #expect(PeopleDirectory.nameWithoutTitles("Dr. h.c. Max Muster") == "Max Muster")
        #expect(PeopleDirectory.nameWithoutTitles("Dipl.-Ing. Eva Klein") == "Eva Klein")
    }

    @Test func onlyDegreesAreCutOffAfterAComma() {
        #expect(PeopleDirectory.nameWithoutTitles("Eva Klein, MBA, PhD") == "Eva Klein")
        #expect(PeopleDirectory.nameWithoutTitles("Eva Klein, M.Sc.") == "Eva Klein")
        #expect(PeopleDirectory.nameWithoutTitles("Müller, Anna") == "Müller, Anna")
    }
}

/// The profile picture is found by looking for faces. The screenshot is searched tile by tile, at two
/// sizes, because a small face gets lost when a whole phone or tablet screenshot is scaled down for detection.
@Suite struct ProfilePictureGeometryTests {
    @Test func tilesOfOneSizeOverlapByHalfAndReachEveryEdge() {
        #expect(ProfileImage.tiles(width: 1000, height: 2200, side: 1000) == [
            CGRect(x: 0, y: 0, width: 1000, height: 1000), CGRect(x: 0, y: 500, width: 1000, height: 1000),
            CGRect(x: 0, y: 1000, width: 1000, height: 1000), CGRect(x: 0, y: 1200, width: 1000, height: 1000)])
        #expect(ProfileImage.tiles(width: 900, height: 600, side: 600) == [
            CGRect(x: 0, y: 0, width: 600, height: 600), CGRect(x: 300, y: 0, width: 600, height: 600)])
    }

    @Test func theImageIsSearchedAtFullAndAtHalfTheShortSide() {
        let tiles = ProfileImage.tiles(width: 2000, height: 1500)
        #expect(Set(tiles.map(\.width)) == [1500, 750])
        #expect(tiles.filter { $0.width == 1500 }.count == 2)
        #expect(tiles.filter { $0.width == 750 }.count == 5 * 3)
        // every tile lies inside the image
        #expect(tiles.allSatisfy { $0.minX >= 0 && $0.minY >= 0 && $0.maxX <= 2000 && $0.maxY <= 1500 })
    }

    @Test func thePictureIsASquareAroundTheFaceWithRoomForTheHead() {
        let crop = ProfileImage.pictureRect(aroundFace: CGRect(x: 450, y: 450, width: 100, height: 100), width: 1000, height: 2000)
        #expect(crop == CGRect(x: 380, y: 380, width: 240, height: 240))
    }

    @Test func thePictureStaysInsideTheImage() {
        let crop = ProfileImage.pictureRect(aroundFace: CGRect(x: 10, y: 20, width: 100, height: 100), width: 1000, height: 2000)
        #expect(crop == CGRect(x: 0, y: 0, width: 240, height: 240))
    }
}

/// A LinkedIn profile is identified by the part after "/in/". pplz stores one canonical link per
/// person, whatever shape the shared or recognised address had.
@Suite struct LinkedInLinkTests {
    @Test func theProfileIDIsReadFromTheUsualAddresses() {
        #expect(LinkedInLink.profileID(in: "https://www.linkedin.com/in/dr-oliver-massmann-153a405/") == "dr-oliver-massmann-153a405")
        #expect(LinkedInLink.profileID(in: "linkedin.com/in/anna-example") == "anna-example")
        #expect(LinkedInLink.profileID(in: "https://de.linkedin.com/in/anna-example/en?trk=public_profile&utm_source=share") == "anna-example")
        #expect(LinkedInLink.profileID(in: "https://www.linkedin.com/mwlite/in/anna-example") == "anna-example")
        #expect(LinkedInLink.profileID(in: "HTTPS://WWW.LINKEDIN.COM/in/Anna-Example/") == "anna-example")
    }

    @Test func namesWithOtherLettersSurvive() {
        #expect(LinkedInLink.profileID(in: "https://www.linkedin.com/in/j%C3%B6rg-m%C3%BCller-12345/") == "jörg-müller-12345")
        #expect(LinkedInLink.profileID(in: "https://www.linkedin.com/in/jörg-müller-12345") == "jörg-müller-12345")
        #expect(LinkedInLink.profileID(in: "https://www.linkedin.com/in/ACoAAB1x_Yz-9kQ") == "acoaab1x_yz-9kq")
    }

    @Test func itIsFoundInsideOtherText() {
        // the address bar in a browser screenshot, as text recognition returns it
        #expect(LinkedInLink.profileID(in: "Search\nwww.linkedin.com/in/dr-oliver-massmann-153a405/\nHome Network Jobs") == "dr-oliver-massmann-153a405")
        #expect(LinkedInLink.profileID(in: "Check out Anna's profile https://www.linkedin.com/in/anna-example?utm_medium=ios_app") == "anna-example")
    }

    @Test func punctuationAroundTheAddressIsNotPartOfTheID() {
        #expect(LinkedInLink.profileID(in: "See linkedin.com/in/anna-example.") == "anna-example")
        #expect(LinkedInLink.profileID(in: "(https://www.linkedin.com/in/anna-example), thanks") == "anna-example")
    }

    @Test func anAddressCutOffOnScreenIsNotTrusted() {
        // a narrow address bar shows "linkedin.com/in/dr-oliver-mass…": half an ID would be a wrong ID
        #expect(LinkedInLink.profileID(in: "www.linkedin.com/in/dr-oliver-mass…") == nil)
        #expect(LinkedInLink.profileID(in: "www.linkedin.com/in/dr-oliver-mass...") == nil)
    }

    @Test func whatIsTypedIntoTheLinkedInFieldMayBeTheBareID() {
        #expect(LinkedInLink.profileID(typed: "Anna-Example-123 ") == "anna-example-123")
        #expect(LinkedInLink.profileID(typed: "https://www.linkedin.com/in/anna-example/") == "anna-example")
        #expect(LinkedInLink.profileID(typed: "anna example") == nil)
        #expect(LinkedInLink.profileID(typed: "https://example.com/anna") == nil)
        #expect(LinkedInLink.profileID(typed: "") == nil)
    }

    @Test func otherAddressesAreNotProfiles() {
        #expect(LinkedInLink.profileID(in: "https://www.linkedin.com/company/duane-morris") == nil)
        #expect(LinkedInLink.profileID(in: "https://example.com/in/anna") == nil)
        #expect(LinkedInLink.profileID(in: "https://lnkd.in/abc123") == nil)
        #expect(LinkedInLink.profileID(in: "Dr. Oliver Massmann") == nil)
    }

    @Test func thereIsOneCanonicalLinkPerProfile() {
        #expect(LinkedInLink.url(forProfileID: "dr-oliver-massmann-153a405") == "https://www.linkedin.com/in/dr-oliver-massmann-153a405")
        #expect(LinkedInLink.url(forProfileID: "jörg-müller-12345") == "https://www.linkedin.com/in/j%C3%B6rg-m%C3%BCller-12345")
    }
}

/// What a capture writes into an existing contact: only what the contact does not have yet.
@Suite struct ContactFillTests {
    let profile = CapturedProfile(name: "Oliver Massmann", namePrefix: "Dr.", jobTitle: "Partner", company: "Duane Morris LLP",
                                  city: "Hanoi", country: "Vietnam", linkedInID: "dr-oliver-massmann-153a405", picture: Data([1, 2, 3]))

    @Test func aNewContactGetsEverything() {
        let fill = ContactFill.plan(for: profile, existing: nil)
        #expect(fill == ContactFill(namePrefix: "Dr.", jobTitle: "Partner", organization: "Duane Morris LLP", city: "Hanoi", country: "Vietnam",
                                    linkedInURL: "https://www.linkedin.com/in/dr-oliver-massmann-153a405", picture: Data([1, 2, 3])))
        #expect(fill.isEmpty == false)
    }

    @Test func whatTheContactHasIsNeverOverwritten() {
        let existing = ContactDetails(identifier: "C-1", givenName: "Oliver", familyName: "Massmann", organization: "Old Firm", jobTitle: "",
                                      addresses: [LabeledValue(label: "work", value: "Somewhere 1, Berlin")],
                                      socialProfiles: [LabeledValue(label: "LinkedIn", value: "https://www.linkedin.com/in/someone-else")],
                                      imageData: Data([9]))
        let fill = ContactFill.plan(for: profile, existing: existing)
        #expect(fill == ContactFill(jobTitle: "Partner"))
    }

    @Test func nothingToWriteIsRecognised() {
        #expect(ContactFill.plan(for: CapturedProfile(name: "Anna Example"), existing: nil).isEmpty)
    }
}

@Suite struct LinkedInOnPersonTests {
    @Test func aPersonKeepsItsLinkedInIDAndIsFoundByIt() throws {
        let (store, _) = try makeStore()
        let anna = try store.createPerson(name: "Anna Example")
        #expect(try store.person(anna).linkedInID == "")
        try store.setLinkedInID("Anna-Example-123", for: anna)
        #expect(try store.person(anna).linkedInID == "anna-example-123")
        #expect(try store.person(withLinkedInID: "ANNA-example-123") == anna)
        #expect(try store.person(withLinkedInID: "nobody") == nil)
        #expect(try store.person(withLinkedInID: "") == nil)
    }
}

/// The calendar entries offered after a capture: what is on right now, then the most recent ones.
@Suite struct CalendarChoiceTests {
    let now = day(2026, 11, 19, 12)
    func entry(_ title: String, _ startHour: Int, _ endHour: Int, day d: Int = 19, allDay: Bool = false) -> CalendarEntry {
        CalendarEntry(title: title, start: day(2026, 11, d, startHour), end: day(2026, 11, d, endHour), place: "", isAllDay: allDay)
    }

    @Test func currentEntriesComeFirstThenTheLatestPastOnes() {
        let entries = [entry("Breakfast", 8, 9), entry("Dialogue", 11, 14), entry("Dinner", 19, 21), entry("Yesterday", 10, 11, day: 18)]
        #expect(CalendarEntry.relevant(entries, now: now).map(\.title) == ["Dialogue", "Breakfast", "Yesterday"])
    }

    @Test func futureAndUntitledEntriesAreLeftOutAndTheListIsLimited() {
        var entries = (0..<12).map { entry("Past \($0)", 1, 2, day: 18) }
        entries.append(entry("", 11, 13))
        #expect(CalendarEntry.relevant(entries, now: now, limit: 6).count == 6)
        #expect(CalendarEntry.relevant([entry("", 11, 13), entry("Later", 15, 16)], now: now).isEmpty)
    }
}
