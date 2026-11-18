#if os(macOS)
import Foundation

/// Shows a contact's card in the Contacts app on the Mac.
public enum ContactsApp {
    /// `osascript` arguments that select a contact and bring Contacts to the front.
    /// The identifier travels as a script argument, never as script text.
    static func selectScriptArguments(identifier: String) -> [String] {
        [
            "-e", "on run argv",
            "-e", "tell application \"Contacts\"",
            "-e", "set selection to {person id (item 1 of argv)}",
            "-e", "activate",
            "-e", "end tell",
            "-e", "end run",
            identifier,
        ]
    }

    /// Selects the contact by scripting Contacts (macOS asks once for permission to control it).
    /// If that fails, falls back to the `addressbook://` link, which may not select the card
    /// when Contacts is already running (SPEC §8.1 S7).
    public static func open(identifier: String) throws {
        if run("/usr/bin/osascript", selectScriptArguments(identifier: identifier)) { return }
        if run("/usr/bin/open", ["addressbook://\(identifier)"]) { return }
        throw PplzError.invalid("Could not open the contact in Contacts.")
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
#endif
