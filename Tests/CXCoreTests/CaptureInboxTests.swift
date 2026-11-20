import Foundation
import Testing
@testable import CXCore

/// What is shared to cardXchange from another app waits in a folder until cardXchange picks it up.
@Suite struct CaptureInboxTests {
    func makeInbox() throws -> CaptureInbox {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cx-inbox-\(UUID().uuidString)")
        return CaptureInbox(directory: dir)
    }

    @Test func anEmptyOrMissingInboxHasNothing() throws {
        #expect(try makeInbox().takeAll().isEmpty)
    }

    @Test func sharedThingsArePickedUpOnceInTheOrderTheyCame() throws {
        let inbox = try makeInbox()
        try inbox.add(.image(Data([1, 2, 3])), at: day(2026, 11, 19, 10))
        try inbox.add(.link("https://www.linkedin.com/in/anna-example"), at: day(2026, 11, 19, 11))
        try inbox.add(.image(Data([4])), at: day(2026, 11, 19, 12))

        #expect(try inbox.takeAll() == [.image(Data([1, 2, 3])), .link("https://www.linkedin.com/in/anna-example"), .image(Data([4]))])
        #expect(try inbox.takeAll().isEmpty)
    }

    @Test func foreignFilesAreLeftAlone() throws {
        let inbox = try makeInbox()
        try inbox.add(.link("x"), at: day(2026, 11, 19, 10))
        let stranger = inbox.directory.appendingPathComponent("notes.txt")
        try Data("mine".utf8).write(to: stranger)
        #expect(try inbox.takeAll() == [.link("x")])
        #expect(FileManager.default.fileExists(atPath: stranger.path))
    }

    @Test func everyScreenshotBecomesItsOwnCaptureAndALinkSharedRightAfterBelongsToIt() {
        #expect(CaptureInbox.requests(from: []).isEmpty)
        #expect(CaptureInbox.requests(from: [.link("l")]) == [CaptureInbox.Request(image: nil, link: "l")])
        #expect(CaptureInbox.requests(from: [.image(Data([1])), .link("l1"), .image(Data([2]))])
                == [CaptureInbox.Request(image: Data([1]), link: "l1"), CaptureInbox.Request(image: Data([2]), link: nil)])
    }

    @Test func aLinkSharedBeforeAScreenshotIsNotAttachedToIt() {
        // it may be about somebody else: better two questions than one wrong pairing
        #expect(CaptureInbox.requests(from: [.link("old"), .image(Data([1]))])
                == [CaptureInbox.Request(image: nil, link: "old"), CaptureInbox.Request(image: Data([1]), link: nil)])
        #expect(CaptureInbox.requests(from: [.image(Data([1])), .link("a"), .link("b")])
                == [CaptureInbox.Request(image: Data([1]), link: "a"), CaptureInbox.Request(image: nil, link: "b")])
    }

    @Test func anUnreadableFileDoesNotCostTheOthers() throws {
        let inbox = try makeInbox()
        try inbox.add(.link("first"), at: day(2026, 11, 19, 10))
        try inbox.add(.link("third"), at: day(2026, 11, 19, 12))
        // a folder where a file is expected cannot be read as one
        try FileManager.default.createDirectory(at: inbox.directory.appendingPathComponent("0001800000000.000000-BROKEN.link"), withIntermediateDirectories: true)
        #expect(try inbox.takeAll() == [.link("first"), .link("third")])
    }
}
