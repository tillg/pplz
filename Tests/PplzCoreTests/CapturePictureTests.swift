import CoreGraphics
import Foundation
import Testing
@testable import PplzCore

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
