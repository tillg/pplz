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

    public enum WriteResult: String, Sendable { case added, alreadyThere, removed, notThere }

    static func relatedNameScriptArguments(add: Bool, row: ContactMirror.Row) -> [String] {
        let body = add
            ? [
                "repeat with r in (get related names of p)",
                "if ((label of r) as text) is (item 2 of argv) and ((value of r) as text) is (item 3 of argv) then return \"alreadyThere\"",
                "end repeat",
                "make new related name at end of related names of p with properties {label:(item 2 of argv), value:(item 3 of argv)}",
                "save",
                "return \"added\"",
            ]
            : [
                "set found to (every related name of p whose label is (item 2 of argv) and value is (item 3 of argv))",
                "if (count of found) is 0 then return \"notThere\"",
                "delete (every related name of p whose label is (item 2 of argv) and value is (item 3 of argv))",
                "save",
                "return \"removed\"",
            ]
        let lines = ["on run argv", "tell application \"Contacts\"", "set p to person id (item 1 of argv)"] + body + ["end tell", "end run"]
        return lines.flatMap { ["-e", $0] } + [row.contactIdentifier, row.label, row.value]
    }

    /// Adds a related-name row to a contact through the Contacts app, unless the same row is already there.
    /// Scripting is used because a direct save fails for contacts that have a note until Apple grants
    /// the notes entitlement (SPEC §8.1 S4, S6).
    public static func addRelatedName(_ row: ContactMirror.Row) throws -> WriteResult {
        try write(relatedNameScriptArguments(add: true, row: row))
    }

    /// Removes exactly this related-name row from a contact.
    public static func removeRelatedName(_ row: ContactMirror.Row) throws -> WriteResult {
        try write(relatedNameScriptArguments(add: false, row: row))
    }

    private static func write(_ arguments: [String]) throws -> WriteResult {
        let process = Process()
        let output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmed
        guard process.terminationStatus == 0, let result = WriteResult(rawValue: text) else {
            let reason = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmed
            throw PplzError.invalid("Contacts did not accept the change: \(reason.isEmpty ? text : reason)")
        }
        return result
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
