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

    @Test func editScriptReturnsAnErrorInsteadOfFailingHalfWay() {
        let (body, _) = ContactsApp.editScript(for: [.text(.nickname, from: "", to: "Anni")], identifier: "C-1")
        let try0 = body.firstIndex(of: "try")!, error = body.firstIndex { $0.hasPrefix("on error") }!
        #expect(body.firstIndex { $0.hasPrefix("set nickname") }! > try0)
        #expect(body.firstIndex(of: "save")! < error)
        #expect(body.contains { $0.hasPrefix("return \"error ") })
        // the lookups stay outside the try: a missing row stops the script before anything is changed
        #expect(body.firstIndex { $0.contains("set p to person id") }! < try0)
    }

    @Test func theAnswerOfTheScriptBecomesTheMessageToTheUser() throws {
        try ContactsApp.check(answer: "ok")
        func message(_ answer: String) -> String {
            do { try ContactsApp.check(answer: answer); return "" } catch { return (error as? LocalizedError)?.errorDescription ?? "\(error)" }
        }
        let missing = message("missing phone +49 170 0000000")
        #expect(missing.contains("phone +49 170 0000000") && missing.contains("Nothing was saved"))
        let halfway = message("error Contacts got an error: boom")
        #expect(halfway.contains("boom") && halfway.contains("may already be applied") && !halfway.contains("Nothing was saved"))
    }

    /// Contacts hands out rows by position ("email 5 of person …"). Once a row is deleted the later positions move,
    /// so every row is looked up again by its id right before it is changed or deleted.
    @Test func rowsAreLookedUpAgainByIdAfterEarlierRowsWereDeleted() {
        let (body, _) = ContactsApp.editScript(for: [
            .removeItem(.email, ContactEdit.Item(id: "E2", label: "work", value: "old@example.com")),
            .removeItem(.email, ContactEdit.Item(id: "E5", label: "home", value: "double@example.com")),
            .removeAddress(ContactEdit.Address(id: "A1", label: "home", street: "Beispielweg 1")),
        ], identifier: "C-1")
        let try0 = body.firstIndex(of: "try")!
        for n in 1...3 {
            // before anything changes, the row's id is noted …
            #expect(body.firstIndex { $0.hasPrefix("set i\(n) to id of item 1 of m\(n)") }! < try0)
            // … and the row is fetched again by it directly before its deletion
            let delete = body.firstIndex(of: "delete item 1 of m\(n)")!
            #expect(body[delete - 1].hasPrefix("set m\(n) to (every ") && body[delete - 1].hasSuffix("whose id is i\(n))"))
            #expect(delete > try0)
        }
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
