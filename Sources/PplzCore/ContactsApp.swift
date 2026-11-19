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
        // a contact that was created a moment ago is not known to the Contacts app right away
        for attempt in 0..<4 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.7) }
            if run("/usr/bin/osascript", selectScriptArguments(identifier: identifier)) { return }
        }
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

    /// Applies the user's edits through the Contacts app, which accepts them for contacts with a note too.
    /// Changes only what the changes name: rows are found by their identifier (the address book's own, which
    /// scripting reports as `id`) or, failing that, by label and value. If a row to change or remove cannot be
    /// found, nothing is changed.
    public static func apply(_ changes: [ContactChange], identifier: String) throws {
        if let reason = unsupported(changes) { throw PplzError.invalid(reason) }
        let (body, text) = editScript(for: changes, identifier: identifier)
        try check(answer: try runScript(body, text: text).trimmed)
    }

    /// Turns the answer of the edit script into success or the message for the user.
    static func check(answer: String) throws {
        if answer == "ok" { return }
        if answer.hasPrefix("missing") {
            throw PplzError.invalid("This contact was changed in Contacts in the meantime (\(answer.dropFirst("missing ".count))). Nothing was saved. Close this form and open it again.")
        }
        if answer.hasPrefix("error") {
            throw PplzError.invalid("The Contacts app stopped part-way (\(answer.dropFirst("error ".count))). Some of your changes may already be applied in the Contacts app (it keeps them until it next saves); check the contact there.")
        }
        throw PplzError.invalid("Contacts did not accept the change: \(answer)")
    }

    /// Why the Contacts app cannot be asked to make these changes, `nil` if it can. Checked before anything is changed.
    /// (Contacts refuses to delete a social profile by script: AppleEvent error -10000, verified 2026-11-20.)
    static func unsupported(_ changes: [ContactChange]) -> String? {
        for case .removeItem(.socialProfile, let item) in changes {
            return "The Contacts app cannot remove the social profile \(item.value.trimmed) by script. Remove it in the Contacts app or on an iPhone or iPad. Nothing was saved."
        }
        return nil
    }

    private struct ScriptKind {
        var single: String
        var plural: String
    }

    private static func scriptKind(_ kind: ContactChange.ItemKind) -> ScriptKind {
        switch kind {
        case .phone: ScriptKind(single: "phone", plural: "phones")
        case .email: ScriptKind(single: "email", plural: "emails")
        case .url: ScriptKind(single: "url", plural: "urls")
        case .socialProfile: ScriptKind(single: "social profile", plural: "social profiles")
        }
    }

    /// The script for `apply`, and the text it reads as `a1`, `a2`, … (`a1` is the contact). Values only ever travel
    /// as arguments, never as script text. First every row to change or remove is looked up and the script stops
    /// if one is missing, then the changes are made and saved once.
    static func editScript(for changes: [ContactChange], identifier: String) -> (body: [String], text: [String]) {
        var text = [identifier]
        func arg(_ value: String) -> String {
            text.append(value)
            return "a\(text.count)"
        }
        /// `{label:a2, value:a3}`; a missing label is left out.
        func properties(_ pairs: [(String, String)]) -> String {
            "{" + pairs.map { "\($0.0):\($0.1)" }.joined(separator: ", ") + "}"
        }
        func find(_ n: Int, _ singular: String, id: String, label: String, valueProperty: String = "value", value: String,
                  description: String) -> [String] {
            let (i, l, v, d) = (arg(id), arg(label), arg(value), arg(description))
            return [
                "set m\(n) to (every \(singular) of p whose id is \(i))",
                "if (count of m\(n)) is 0 then set m\(n) to (every \(singular) of p whose label is \(l) and \(valueProperty) is \(v))",
                "if (count of m\(n)) is 0 then return \"missing \" & \(d)",
            ]
        }
        var lookups: [String] = [], edits: [String] = []
        for (index, change) in changes.enumerated() {
            let n = index + 1
            switch change {
            case .text(let field, _, let value):
                edits.append("set \(field.scriptProperty) of p to \(arg(value))")
            case .addItem(let kind, let item):
                let k = scriptKind(kind)
                if kind == .socialProfile {
                    let (url, user) = socialParts(item.value)
                    edits.append("make new social profile at end of social profiles of p with properties \(properties([("service name", arg(item.label)), ("user name", arg(user)), ("url", arg(url))]))")
                } else {
                    let label = item.label.isEmpty ? [] : [("label", arg(item.label))]
                    edits.append("make new \(k.single) at end of \(k.plural) of p with properties \(properties(label + [("value", arg(item.value))]))")
                }
            case .updateItem(let kind, let from, let to):
                let k = scriptKind(kind)
                lookups += find(n, k.single, id: from.id, label: from.label, value: from.value, description: "\(from.value)")
                if kind == .socialProfile {
                    if from.label != to.label { edits.append("set service name of item 1 of m\(n) to \(arg(to.label))") }
                    if from.value.trimmed != to.value {
                        let (url, user) = socialParts(to.value)
                        edits.append("set user name of item 1 of m\(n) to \(arg(user))")
                        edits.append("set url of item 1 of m\(n) to \(arg(url))")
                    }
                } else {
                    if from.value.trimmed != to.value { edits.append("set value of item 1 of m\(n) to \(arg(to.value))") }
                    if from.label != to.label { edits.append("set label of item 1 of m\(n) to \(arg(to.label))") }
                }
            case .removeItem(let kind, let item):
                let k = scriptKind(kind)
                lookups += find(n, k.single, id: item.id, label: item.label, value: item.value, description: item.value)
                edits.append("delete item 1 of m\(n)")
            case .addAddress(let address):
                let label = address.label.isEmpty ? [] : [("label", arg(address.label))]
                edits.append("make new address at end of addresses of p with properties \(properties(label + [("street", arg(address.street)), ("zip", arg(address.postalCode)), ("city", arg(address.city)), ("country", arg(address.country))]))")
            case .updateAddress(let from, let to):
                lookups += find(n, "address", id: from.id, label: from.label, valueProperty: "street", value: from.street, description: from.summary)
                for (property, old, new) in [("label", from.label, to.label), ("street", from.street, to.street), ("zip", from.postalCode, to.postalCode),
                                             ("city", from.city, to.city), ("country", from.country, to.country)] where old.trimmed != new {
                    edits.append("set \(property) of item 1 of m\(n) to \(arg(new))")
                }
            case .removeAddress(let address):
                lookups += find(n, "address", id: address.id, label: address.label, valueProperty: "street", value: address.street, description: address.summary)
                edits.append("delete item 1 of m\(n)")
            case .birthday(_, let new):
                if let new {
                    // Contacts takes a full date; the year 1604 is how it stores a birthday without a year
                    edits += ["set d to current date", "set day of d to 1", "set year of d to \(new.year ?? 1604)", "set month of d to \(new.month)",
                              "set day of d to \(new.day)", "set time of d to 43200", "set birth date of p to d"]
                } else {
                    edits.append("set birth date of p to missing value")
                }
            }
        }
        // the lookups stop the script before anything is changed; a failing change returns its error and does not save
        let body = ["tell application \"Contacts\"", "set p to person id a1"] + lookups
            + ["try"] + edits + ["save", "return \"ok\"", "on error errText", "return \"error \" & errText", "end try", "end tell"]
        return (body, text)
    }

    /// The address and user name a social profile gets from what was typed: an address (kept as it is, its last
    /// part is the user name), or a plain user name.
    private static func socialParts(_ value: String) -> (url: String, user: String) {
        let value = value.trimmed
        guard value.contains("/") else { return ("", value) }
        return (value, URL(string: value)?.lastPathComponent ?? "")
    }

    /// Sets the contact's picture through the Contacts app, which accepts it for contacts with a note too.
    public static func setImage(_ image: Data, identifier: String) throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("pplz-picture-\(UUID().uuidString).jpg")
        try image.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try runScript([
            "tell application \"Contacts\"",
            "set p to person id a1",
            "set image of p to (read (POSIX file a2) as JPEG picture)",
            "save",
            "end tell",
        ], text: [identifier, file.path])
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
