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

    @Test func editScriptPassesValuesAsArgumentsAndLooksRowsUpBeforeChangingAnything() {
        let hostile = "X\" \ntell application \"Finder\" to quit"
        let work = ContactEdit.Item(id: "P2", label: "_$!<Work>!$_", value: "+49 221 0000000")
        let (body, text) = ContactsApp.editScript(for: [
            .text(.givenName, from: "Anna", to: hostile),
            .updateItem(.phone, from: work, to: ContactEdit.Item(id: "P2", label: "_$!<Home>!$_", value: "+49 221 1111111")),
            .removeItem(.email, ContactEdit.Item(id: "E1", label: "", value: "anna@example.com")),
            .birthday(from: .init(day: 17, month: 5), to: nil),
        ], identifier: "C-1")
        let script = body.joined(separator: "\n")
        #expect(text.first == "C-1")
        #expect(text.contains(hostile))
        #expect(!script.contains("Finder") && !script.contains("+49") && !script.contains("anna@"))
        #expect(!script.contains("every phone of p)") && !script.contains("delete every"))
        // lookups (which stop the script when a row is missing) come before the first change
        let firstChange = body.firstIndex { $0.hasPrefix("set first name") }!
        #expect(body.firstIndex { $0.contains("return \"missing") }! < firstChange)
        #expect(body.filter { $0 == "save" }.count == 1)
        #expect(script.contains("set birth date of p to missing value"))
    }

    @Test func removingASocialProfileIsRefusedBeforeAnythingIsChanged() {
        let profile = ContactEdit.Item(id: "S1", label: "LinkedIn", value: "https://www.linkedin.com/in/anna-example")
        #expect(ContactsApp.unsupported([.text(.nickname, from: "", to: "Anni"), .removeItem(.socialProfile, profile)])?.contains("anna-example") == true)
        #expect(ContactsApp.unsupported([.updateItem(.socialProfile, from: profile, to: profile), .addItem(.socialProfile, profile)]) == nil)
        #expect(throws: (any Error).self) { try ContactsApp.apply([.removeItem(.socialProfile, profile)], identifier: "C-1") }
    }

    @Test func editScriptOnlySetsWhatChangedOnAnItem() {
        let work = ContactEdit.Item(id: "P2", label: "_$!<Work>!$_", value: "+49 221 0000000")
        var relabelled = work
        relabelled.label = "_$!<Home>!$_"
        let (body, _) = ContactsApp.editScript(for: [.updateItem(.phone, from: work, to: relabelled)], identifier: "C-1")
        #expect(body.contains { $0.hasPrefix("set label of item 1 of m1") })
        #expect(!body.contains { $0.hasPrefix("set value of") })
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
