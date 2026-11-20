import Foundation

/// LinkedIn profile addresses come in many shapes (country sub-domains, mobile paths, tracking
/// parameters, encoded letters). What identifies the profile is the part after "/in/".
public enum LinkedInLink {
    /// The profile ID in an address or in any text containing one (e.g. recognised from a browser
    /// screenshot); lower-cased, with encoded letters decoded. `nil` if there is no profile address.
    public static func profileID(in text: String) -> String? {
        guard let match = text.firstMatch(of: /(?i)linkedin\.com\/(?:mwlite\/)?in\/([^\/?#\s)\],;]+)/) else { return nil }
        var raw = String(match.1)
        // an address cut off on screen ("…/in/dr-oliver-mass…") gives half an ID, which would be a wrong one
        if raw.hasSuffix("…") || raw.hasSuffix("...") { return nil }
        while let last = raw.last, ".:!'\"".contains(last) { raw.removeLast() }
        let id = (raw.removingPercentEncoding ?? raw).lowercased()
        return id.isEmpty ? nil : id
    }

    /// What the user typed into a LinkedIn field: an address, or just the ID itself.
    public static func profileID(typed text: String) -> String? {
        let text = text.trimmed
        if let id = profileID(in: text) { return id }
        let isBareID = !text.isEmpty && !text.contains(where: { $0.isWhitespace || $0 == "/" || $0 == ":" }) && !text.contains(".")
        return isBareID ? text.lowercased() : nil
    }

    /// The one address cardXchange stores for a profile.
    public static func url(forProfileID id: String) -> String {
        "https://www.linkedin.com/in/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)
    }
}
