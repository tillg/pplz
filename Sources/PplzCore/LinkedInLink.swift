import Foundation

/// LinkedIn profile addresses come in many shapes (country sub-domains, mobile paths, tracking
/// parameters, encoded letters). What identifies the profile is the part after "/in/".
public enum LinkedInLink {
    /// The profile ID in an address or in any text containing one (e.g. recognised from a browser
    /// screenshot); lower-cased, with encoded letters decoded. `nil` if there is no profile address.
    public static func profileID(in text: String) -> String? {
        guard let match = text.firstMatch(of: /(?i)linkedin\.com\/(?:mwlite\/)?in\/([^\/?#\s]+)/) else { return nil }
        let raw = String(match.1)
        let id = (raw.removingPercentEncoding ?? raw).lowercased()
        return id.isEmpty ? nil : id
    }

    /// The one address pplz stores for a profile.
    public static func url(forProfileID id: String) -> String {
        "https://www.linkedin.com/in/" + (id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)
    }
}
