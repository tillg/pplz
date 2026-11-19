import Foundation

/// The logic behind the tag field of the edit sheets. The chosen tags are kept as comma-separated
/// text; existing tags are offered so that they get reused instead of re-invented in new spellings.
public enum TagInput {
    /// The chosen tags: trimmed, without empty entries, each once (case does not matter).
    public static func names(in text: String) -> [String] {
        var seen = Set<String>()
        return text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// Adds a tag, in the spelling of an existing tag if there is one.
    public static func adding(_ name: String, to text: String, known: [String]) -> String {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        let chosen = names(in: text)
        guard !key.isEmpty, !chosen.contains(where: { $0.lowercased() == key }) else { return chosen.joined(separator: ", ") }
        let spelling = known.first { $0.lowercased() == key } ?? name.trimmingCharacters(in: .whitespaces)
        return (chosen + [spelling]).joined(separator: ", ")
    }

    public static func removing(_ name: String, from text: String) -> String {
        names(in: text).filter { $0.lowercased() != name.lowercased() }.joined(separator: ", ")
    }

    /// Existing tags that are not chosen yet and contain what was typed so far.
    public static func suggestions(known: [String], chosen text: String, query: String) -> [String] {
        let chosen = Set(names(in: text).map { $0.lowercased() })
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        return known.filter { !chosen.contains($0.lowercased()) && (query.isEmpty || $0.lowercased().contains(query)) }
    }

    /// Whether what was typed would be a new tag.
    public static func canCreate(_ query: String, known: [String], chosen text: String) -> Bool {
        let key = query.trimmingCharacters(in: .whitespaces).lowercased()
        return !key.isEmpty && !(known + names(in: text)).contains { $0.lowercased() == key }
    }
}
