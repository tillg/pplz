import Foundation

/// The block cardXchange owns inside a contact's note (SPEC §3.3). Everything outside the block
/// belongs to the user and is never changed.
public enum NotesBlock {
    public static let startMarker = "── cardxchange ──"
    public static let endMarker = "── /cardxchange ──"
    /// The markers written before the rename. A block with them is still found, and replaced by the new form.
    static let oldStartMarker = "── pplz ──"
    static let oldEndMarker = "── /pplz ──"
    public static let maxEvents = 10

    /// Summary line plus the most recent events (history is newest first); `nil` if there is no history.
    /// Only date, format, title and place are written — never event notes.
    public static func render(history: [EventSnapshot], timeZone: TimeZone = .current) -> String? {
        guard let latest = history.first else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        var lines = [startMarker, "Met \(history.count)× · last \(formatter.string(from: latest.start))"]
        for event in history.prefix(maxEvents) {
            let parts = [event.format.displayName, event.title, event.place].filter { !$0.isEmpty }
            lines.append("\(formatter.string(from: event.start))  \(parts.joined(separator: " · "))")
        }
        lines.append(endMarker)
        return lines.joined(separator: "\n")
    }

    public static func containsBlock(_ note: String) -> Bool {
        blockRange(in: note, startMarker, endMarker) != nil || blockRange(in: note, oldStartMarker, oldEndMarker) != nil
    }

    /// Puts `block` into the note: replaces cardXchange's existing block in place, or appends it after a blank line.
    /// With `block == nil` the existing block is removed. Text outside the block is returned unchanged.
    /// A block with the old markers is replaced like a new one; next to a new block it is removed.
    public static func merge(note: String, block: String?) -> String {
        if let range = blockRange(in: note, startMarker, endMarker) {
            let merged = place(block, in: note, at: range)
            return blockRange(in: merged, oldStartMarker, oldEndMarker).map { place(nil, in: merged, at: $0) } ?? merged
        }
        if let range = blockRange(in: note, oldStartMarker, oldEndMarker) {
            return place(block, in: note, at: range)
        }
        guard let block else { return note }
        return note.isEmpty ? block : note + "\n\n" + block
    }

    private static func place(_ block: String?, in note: String, at range: Range<String.Index>) -> String {
        if let block {
            return note.replacingCharacters(in: range, with: block)
        }
        var before = String(note[..<range.lowerBound])
        if before.hasSuffix("\n\n") { before.removeLast(2) }
        return before + note[range.upperBound...]
    }

    /// The last complete block of one form: the last end marker and the nearest start marker before it.
    /// A start marker without an end marker is not a block and is left alone.
    private static func blockRange(in note: String, _ start: String, _ end: String) -> Range<String.Index>? {
        guard let endRange = note.range(of: end, options: .backwards),
              let startRange = note.range(of: start, options: .backwards, range: note.startIndex..<endRange.lowerBound) else { return nil }
        return startRange.lowerBound..<endRange.upperBound
    }
}
