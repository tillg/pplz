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
