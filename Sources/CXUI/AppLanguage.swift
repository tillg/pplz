import Foundation

/// The language of the app, chosen in Settings (issue #13). "System" follows the device's language list;
/// a language the app does not have falls back to English, the development language of the string catalogs.
/// The choice is the `AppleLanguages` value in the app's own defaults, which takes effect at the next launch.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, english, german, french

    public var id: Self { self }

    /// The value for `AppleLanguages`; `nil` removes the key.
    var appleLanguages: [String]? {
        switch self {
        case .system: nil
        case .english: ["en"]
        case .german: ["de"]
        case .french: ["fr"]
        }
    }

    /// The choice that a stored `AppleLanguages` value stands for: its first language, if the app has it.
    init(appleLanguages: Any?) {
        let first = (appleLanguages as? [String])?.first.map { Locale.Language(identifier: $0).languageCode?.identifier }
        self = Self.allCases.first { $0 != .system && $0.appleLanguages?.first == first } ?? .system
    }
}

extension AppLanguage {
    /// The name in the language picker: each language in its own name, as in the system's settings.
    var title: String {
        switch self {
        case .system: String(localized: "System", bundle: .module, comment: "Language setting: the language of the device")
        case .english: "English"
        case .german: "Deutsch"
        case .french: "Français"
        }
    }
}
