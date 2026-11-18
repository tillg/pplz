#if os(macOS)
import Foundation
import Testing
@testable import PplzCore

@Suite struct ContactsAppTests {
    @Test func identifierIsPassedAsArgumentNotAsScriptText() {
        let hostile = "X\" \ntell application \"Finder\" to quit"
        let arguments = ContactsApp.selectScriptArguments(identifier: hostile)
        #expect(arguments.last == hostile)
        #expect(arguments.dropLast().allSatisfy { !$0.contains("Finder") })
        #expect(arguments.contains { $0.contains("item 1 of argv") })
    }
}
#endif

#if os(macOS)
@Suite struct ScriptTextTransportTests {
    /// Text handed to a script must arrive byte for byte: accented letters must not be re-encoded
    /// (a note or name would otherwise be changed just by passing through pplz).
    @Test func textArgumentsArriveUnchanged() throws {
        let composed = "Tëst Köln — Jörg Müller \"quoted\"\n  second line\n\nlast"   // precomposed (NFC) letters
        let output = try ContactsApp.runScript(["return a1 & \"|\" & a2 & \"|\" & a3"], text: [composed, "", "x"])
        #expect(Array(output.utf8) == Array((composed + "||x\n").utf8))
    }
}
#endif
