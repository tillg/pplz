/// The version text in the app's About area: "V. 0.2.693 - 2026-11-20 14:07" (issue #12).
/// The build number is the commit count, and the build date is the build machine's local time.
/// Both are set at build time by `scripts/build-app.sh` and `scripts/ui.sh`; an Xcode build has neither.
public enum AppVersion {
    /// The text for an Info.plist dictionary, normally `Bundle.main.infoDictionary`.
    /// A value that is missing or empty is left out.
    public static func text(info: [String: Any]?) -> String {
        func value(_ key: String) -> String? {
            guard let text = info?[key] as? String, !text.isEmpty else { return nil }
            return text
        }
        let version = [value("CFBundleShortVersionString") ?? "?", value("CFBundleVersion")].compactMap { $0 }.joined(separator: ".")
        return ["V. " + version, value("CXBuildDate")].compactMap { $0 }.joined(separator: " - ")
    }
}
