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

    public enum WriteResult: String, Sendable { case added, alreadyThere, removed, notThere, written, conflict }

    /// Runs an AppleScript with text arguments available as `a1`, `a2`, ….
    ///
    /// Text travels through UTF-8 files, not through the command line: command-line arguments get
    /// re-encoded on the way (accented letters are decomposed), which would silently alter notes and names.
    static func runScript(_ body: [String], text: [String]) throws -> String {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pplz-script-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        var paths: [String] = []
        for (index, value) in text.enumerated() {
            guard !value.isEmpty else { paths.append(""); continue }   // an empty file cannot be read back
            let file = folder.appendingPathComponent("a\(index + 1).txt")
            try Data(value.utf8).write(to: file)
            paths.append(file.path)
        }
        let prelude = ["on txt(p)", "if p is \"\" then return \"\"", "return read (POSIX file p) as «class utf8»", "end txt", "on run argv"]
            + text.indices.map { "set a\($0 + 1) to my txt(item \($0 + 1) of argv)" }
        let lines = prelude + body + ["end run"]

        let process = Process()
        let output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = lines.flatMap { ["-e", $0] } + paths
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let reason = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).trimmed
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw PplzError.invalid("Contacts did not accept the request: \(reason)")
        }
        return result
    }

    private static func write(_ body: [String], text: [String]) throws -> WriteResult {
        let answer = try runScript(body, text: text).trimmed
        guard let result = WriteResult(rawValue: answer) else {
            throw PplzError.invalid("Contacts did not accept the change: \(answer)")
        }
        return result
    }

    /// Adds a related-name row to a contact through the Contacts app, unless the same row is already there.
    /// Scripting is used because a direct save fails for contacts that have a note until Apple grants
    /// the notes entitlement (SPEC §8.1 S4, S6).
    public static func addRelatedName(_ row: ContactMirror.Row) throws -> WriteResult {
        try write([
            "tell application \"Contacts\"",
            "set p to person id a1",
            "repeat with r in (get related names of p)",
            "if ((label of r) as text) is a2 and ((value of r) as text) is a3 then return \"alreadyThere\"",
            "end repeat",
            "make new related name at end of related names of p with properties {label:a2, value:a3}",
            "save",
            "return \"added\"",
            "end tell",
        ], text: [row.contactIdentifier, row.label, row.value])
    }

    /// Removes exactly this related-name row from a contact.
    public static func removeRelatedName(_ row: ContactMirror.Row) throws -> WriteResult {
        try write([
            "tell application \"Contacts\"",
            "set p to person id a1",
            "if (count of (every related name of p whose label is a2 and value is a3)) is 0 then return \"notThere\"",
            "delete (every related name of p whose label is a2 and value is a3)",
            "save",
            "return \"removed\"",
            "end tell",
        ], text: [row.contactIdentifier, row.label, row.value])
    }

    /// Adds a labelled URL row to a contact, unless a row with the same address is already there.
    public static func addURL(_ row: ContactMirror.Row) throws -> WriteResult {
        try write([
            "tell application \"Contacts\"",
            "set p to person id a1",
            "repeat with u in (get urls of p)",
            "if ((value of u) as text) is a3 then return \"alreadyThere\"",
            "end repeat",
            "make new url at end of urls of p with properties {label:a2, value:a3}",
            "save",
            "return \"added\"",
            "end tell",
        ], text: [row.contactIdentifier, row.label, row.value])
    }

    /// The contact's note, read through the Contacts app ("" if empty).
    public static func readNote(identifier: String) throws -> String {
        var text = try runScript([
            "tell application \"Contacts\"",
            "set n to note of person id a1",
            "if n is missing value then return \"\"",
            "return n",
            "end tell",
        ], text: [identifier])
        if text.hasSuffix("\n") { text.removeLast() }   // osascript ends its output with one newline
        return text
    }

    /// Replaces the note with `new`, but only if it still reads `expected` — so a change made in
    /// the meantime is never overwritten.
    public static func writeNote(identifier: String, expected: String, new: String) throws -> WriteResult {
        try write([
            "tell application \"Contacts\"",
            "set p to person id a1",
            "set n to note of p",
            "if n is missing value then set n to \"\"",
            "considering case, diacriticals and white space",
            "if (n as text) is not a2 then return \"conflict\"",
            "end considering",
            "set note of p to a3",
            "save",
            "return \"written\"",
            "end tell",
        ], text: [identifier, expected, new])
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
