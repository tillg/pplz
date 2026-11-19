import Foundation
import Testing
@testable import PplzCore

/// What is shared to pplz from another app waits in a folder until pplz picks it up.
@Suite struct CaptureInboxTests {
    func makeInbox() throws -> CaptureInbox {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pplz-inbox-\(UUID().uuidString)")
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
}
