import CoreGraphics
import Foundation
import Testing
@testable import CXCore

/// Found on real profiles on 2026-11-19: a banner picture can contain something that looks like a
/// face, and a face that fills its round picture got a crop reaching into the banner.
@Suite struct ProfilePictureChoiceTests {
    let name = CGRect(x: 40, y: 820, width: 400, height: 60)

    @Test func theFaceRightAboveTheNameWinsOverALargerOneInTheBanner() {
        let banner = CGRect(x: 500, y: 350, width: 120, height: 120)
        let owner = CGRect(x: 184, y: 503, width: 56, height: 56)
        #expect(ProfileImage.face(among: [banner, owner], aboveLine: name) == owner)
    }

    @Test func twoBoxesForTheSameFaceCountAsTheLargerOne() {
        let whole = CGRect(x: 139, y: 535, width: 194, height: 194)
        let part = CGRect(x: 167, y: 592, width: 123, height: 123)
        #expect(ProfileImage.face(among: [part, whole], aboveLine: name) == whole)
    }

    @Test func facesBelowTheNameAreOtherPeople() {
        let owner = CGRect(x: 184, y: 503, width: 56, height: 56)
        let mutual = CGRect(x: 60, y: 1200, width: 200, height: 200)
        #expect(ProfileImage.face(among: [mutual, owner], aboveLine: name) == owner)
    }

    @Test func withoutANameLineTheLargestFaceIsTaken() {
        let small = CGRect(x: 0, y: 0, width: 50, height: 50), large = CGRect(x: 200, y: 900, width: 90, height: 90)
        #expect(ProfileImage.face(among: [small, large], aboveLine: nil) == large)
        #expect(ProfileImage.face(among: [], aboveLine: nil) == nil)
    }

    /// A drawn profile page: white page, blue banner, a round grey picture with a white ring that
    /// overlaps the banner's lower edge.
    func page(ring: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: 600, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: 0, y: 800); context.scaleBy(x: 1, y: -1)       // y grows downwards, as in the tests
        context.setFillColor(gray: ring, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        context.setFillColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 600, height: 200))
        context.setFillColor(gray: ring, alpha: 1); context.fillEllipse(in: CGRect(x: 40, y: 90, width: 220, height: 220))
        context.setFillColor(gray: 0.4, alpha: 1); context.fillEllipse(in: CGRect(x: 50, y: 100, width: 200, height: 200))
        return context.makeImage()!
    }

    @Test func thePictureIsTheWholeRoundPictureWhenItsRingIsFound() throws {
        // the face sits in the upper half of the round picture, as in a half-length portrait
        let crop = try #require(ProfileImage.roundPicture(aroundFace: CGRect(x: 130, y: 130, width: 40, height: 40), in: page(ring: 1)))
        #expect(abs(crop.minX - 50) <= 2 && abs(crop.minY - 100) <= 2)
        #expect(abs(crop.width - 200) <= 3 && crop.width == crop.height)
    }

    @Test func aLargeFaceDoesNotReachIntoTheBanner() throws {
        let crop = try #require(ProfileImage.roundPicture(aroundFace: CGRect(x: 90, y: 140, width: 120, height: 120), in: page(ring: 1)))
        #expect(crop.minY >= 98 && crop.maxY <= 302 && crop.minX >= 48 && crop.maxX <= 252)
    }

    @Test func withoutAWhiteRingThereIsNoRoundPicture() {
        #expect(ProfileImage.roundPicture(aroundFace: CGRect(x: 130, y: 130, width: 40, height: 40), in: page(ring: 0.1)) == nil)
    }
}

@Suite struct CapturedTitleTests {
    @Test func aConnectionDegreeIsNoTitle() {
        #expect(ProfileReader.title("2nd", nameLine: "Jonathan London • 2nd") == "")
        #expect(ProfileReader.title("1st", nameLine: "David Will · 1st") == "")
        #expect(ProfileReader.title("3rd+", nameLine: "Anna Example 3rd+") == "")
    }

    @Test func aTitleMustStandInTheNameLine() {
        #expect(ProfileReader.title("Dr.", nameLine: "Dr. Oliver Massmann ø • 2nd") == "Dr.")
        #expect(ProfileReader.title("Prof.", nameLine: "Jonathan London • 2nd") == "")
        #expect(ProfileReader.title("dr", nameLine: "Dr. Oliver Massmann") == "dr")
    }
}

/// A profile link shared alone carries no name, only the profile ID, which usually contains it.
@Suite struct LinkOnlyCandidateTests {
    let entries = PeopleDirectory.merge(contacts: [
        ContactSummary(identifier: "1", name: "Jonathan London"), ContactSummary(identifier: "2", name: "Oliver Massmann"),
        ContactSummary(identifier: "3", name: "Anna London"), ContactSummary(identifier: "4", name: "Li Wu"),
        ContactSummary(identifier: "5", name: "Jörg Müller"),
    ], persons: [])

    @Test func thePersonWhoseWholeNameIsInTheIDComesFirst() {
        #expect(PeopleDirectory.candidates(forLinkedInID: "dr-oliver-massmann-153a405", in: entries).map(\.name) == ["Oliver Massmann"])
        #expect(PeopleDirectory.candidates(forLinkedInID: "anna-london-99", in: entries).map(\.name) == ["Anna London", "Jonathan London"])
    }

    @Test func aFamilyNameInTheIDIsEnoughForAProposal() {
        #expect(PeopleDirectory.candidates(forLinkedInID: "jdlondon", in: entries).map(\.name) == ["Anna London", "Jonathan London"])
    }

    @Test func accentsAreIgnoredAndShortNamesProposeNothing() {
        #expect(PeopleDirectory.candidates(forLinkedInID: "joerg-mueller-1", in: entries).isEmpty)
        #expect(PeopleDirectory.candidates(forLinkedInID: "jorg-muller-1", in: entries).map(\.name) == ["Jörg Müller"])
        #expect(PeopleDirectory.candidates(forLinkedInID: "wuhan-trading", in: entries).isEmpty)
        #expect(PeopleDirectory.candidates(forLinkedInID: "", in: entries).isEmpty)
    }
}

/// First and last name are kept apart, as in Contacts: which word belongs where cannot be guessed
/// from a full name ("Maria del Carmen Ruiz").
@Suite struct CapturedNameTests {
    @Test func firstAndLastNameAreKeptAsGiven() {
        let profile = CapturedProfile(givenName: "Maria", familyName: "del Carmen Ruiz")
        #expect(profile.name == "Maria del Carmen Ruiz")
        #expect(profile.contactName == .init(given: "Maria", family: "del Carmen Ruiz"))
    }

    @Test func aFullNameIsSplitAtItsLastWord() {
        var profile = CapturedProfile(name: "Dr. Oliver Massmann")
        #expect(profile.givenName == "Dr. Oliver" && profile.familyName == "Massmann")
        #expect(profile.name == "Dr. Oliver Massmann")
        profile.name = "Mai"
        #expect(profile.givenName == "Mai" && profile.familyName == "")
    }

    @Test func aTitleIsNotPartOfTheContactsFirstName() {
        #expect(CapturedProfile(givenName: "Dr. Oliver", familyName: "Massmann").contactName == .init(given: "Oliver", family: "Massmann"))
        #expect(CapturedProfile(givenName: " Anna ", familyName: " Example ").contactName == .init(given: "Anna", family: "Example"))
    }
}

/// Seen on 2026-11-19: with a badge between name and "2nd", the degree is recognised as a line of its own.
@Suite struct NameLineTests {
    let lines = ["#HIRING", "Jan René Fricke", "• 2nd", "Building FMCG Brands | Unternehmer & Advisor", "Frankfurt, Hesse, Germany • Contact info",
                 "500+ connections", "Daniel, Frank and 25 other mutual connections"]

    @Test func aDegreeStandingAloneBelongsToTheLineAboveIt() {
        #expect(ProfileReader.nameLineIndex(in: lines) == 1)
        #expect(ProfileReader.header(of: lines) == ["Jan René Fricke", "• 2nd", "Building FMCG Brands | Unternehmer & Advisor",
                                                     "Frankfurt, Hesse, Germany • Contact info"])
        #expect(ProfileReader.locationLine(in: lines) == "Frankfurt, Hesse, Germany • Contact info")
    }

    @Test func aDegreeAloneInTheFirstLineStaysTheNameLine() {
        #expect(ProfileReader.nameLineIndex(in: ["2nd", "Head of Sales"]) == 0)
    }
}
