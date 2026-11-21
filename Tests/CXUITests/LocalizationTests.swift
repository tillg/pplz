import Foundation
import Testing
@testable import CXCore
@testable import CXUI

/// The language setting (issue #13): a choice in Settings becomes `AppleLanguages` in the app's own defaults.
@Suite struct AppLanguageTests {
    @Test func systemRemovesTheKeyAndALanguageWritesItsCode() {
        #expect(AppLanguage.system.appleLanguages == nil)
        #expect(AppLanguage.english.appleLanguages == ["en"])
        #expect(AppLanguage.german.appleLanguages == ["de"])
        #expect(AppLanguage.french.appleLanguages == ["fr"])
    }

    @Test func theStoredValueGivesTheChoice() {
        #expect(AppLanguage(appleLanguages: nil) == .system)
        #expect(AppLanguage(appleLanguages: ["de"]) == .german)
        #expect(AppLanguage(appleLanguages: ["fr-CA", "en"]) == .french)
        #expect(AppLanguage(appleLanguages: ["en-GB"]) == .english)
    }

    @Test func anOtherLanguageOrAnOddValueCountsAsSystem() {
        #expect(AppLanguage(appleLanguages: ["es"]) == .system)
        #expect(AppLanguage(appleLanguages: []) == .system)
        #expect(AppLanguage(appleLanguages: "de") == .system)
    }
}

@MainActor
@Suite struct LanguageSettingTests {
    private func model(settings: String) -> PeopleModel {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cx-ui-tests-\(UUID().uuidString).store")
        var configuration = PeopleModel.Configuration(storeURL: url, usesContacts: false)
        configuration.settingsSuite = settings
        return PeopleModel(configuration: configuration)
    }

    @Test func theChosenLanguageIsKeptForTheNextLaunch() {
        let suite = "cx-ui-tests-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        #expect(model(settings: suite).language == .system)

        model(settings: suite).language = .german

        #expect(UserDefaults(suiteName: suite)?.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["de"])
        #expect(model(settings: suite).language == .german)
    }

    @Test func systemRemovesTheStoredLanguage() {
        let suite = "cx-ui-tests-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        model(settings: suite).language = .french

        model(settings: suite).language = .system

        #expect(UserDefaults(suiteName: suite)?.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
        #expect(model(settings: suite).language == .system)
    }
}

/// Text that cardXchange builds from data, as whole sentences of the string catalog in each language (issue #13).
@Suite struct LocalizedTextTests {
    let english = Locale(identifier: "en_GB")
    let german = Locale(identifier: "de_DE")
    let french = Locale(identifier: "fr_FR")

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func theMapStatusSaysHowFarLocatingIsAndWhenItContinues() {
        let counts = LocatedPeople.Counts(located: 1234, notFound: 0, outstanding: 766)
        #expect(MapText.status(counts, resumesAt: date(19, 14, 10), locale: english) == "1,234 of 2,000 addresses located · pausing until 14:10")
        #expect(MapText.status(counts, resumesAt: nil, locale: english) == "1,234 of 2,000 addresses located")
        #expect(MapText.status(.init(located: 5, notFound: 2, outstanding: 0), resumesAt: date(19, 14, 10), locale: english)
                == "5 of 7 addresses located · 2 not found")
        #expect(MapText.status(.init(located: 1, notFound: 0, outstanding: 0), resumesAt: nil, locale: english) == "1 of 1 address located")
        #expect(MapText.status(.init(located: 0, notFound: 0, outstanding: 0), resumesAt: nil, locale: english) == nil)
    }

    /// Issue #8: when the rest is expected to be located, with the day.
    @Test func theMapStatusSaysWhenLocatingIsExpectedToBeDone() {
        let counts = LocatedPeople.Counts(located: 147, notFound: 5, outstanding: 1959)
        #expect(MapText.status(counts, resumesAt: date(19, 14, 10), doneAt: date(21, 18, 40), locale: english)
                == "147 of 2,111 addresses located · 5 not found · pausing until 14:10 · done about Sat 18:40")
        #expect(MapText.status(counts, resumesAt: nil, doneAt: date(21, 18, 40), locale: english)
                == "147 of 2,111 addresses located · 5 not found · done about Sat 18:40")
        #expect(MapText.status(.init(located: 5, notFound: 2, outstanding: 0), resumesAt: nil, doneAt: date(21, 18, 40), locale: english)
                == "5 of 7 addresses located · 2 not found")
    }

    @Test func theMapStatusInGermanAndFrench() {
        let counts = LocatedPeople.Counts(located: 147, notFound: 5, outstanding: 1959)
        #expect(MapText.status(counts, resumesAt: date(19, 14, 10), doneAt: date(21, 18, 40), locale: german)
                == "147 von 2.111 Adressen gefunden · 5 nicht gefunden · Pause bis 14:10 · fertig etwa Sa. 18:40")
        #expect(MapText.status(.init(located: 1, notFound: 0, outstanding: 0), resumesAt: nil, locale: german) == "1 von 1 Adresse gefunden")
        #expect(MapText.status(counts, resumesAt: date(19, 14, 10), doneAt: date(21, 18, 40), locale: french)
                == "Adresses localisées : 147 sur 2\u{202F}111 · 5 introuvables · en pause jusqu’à 14:10 · fin vers sam. 18:40")
        #expect(MapText.status(.init(located: 1, notFound: 1, outstanding: 0), resumesAt: nil, locale: french)
                == "Adresses localisées : 1 sur 2 · 1 introuvable")
    }

    @Test func theMapNoticeCountsTheMatches() {
        #expect(MapText.notice(.notLocated(matches: 1), locale: english) == "The match has no located address.")
        #expect(MapText.notice(.notLocated(matches: 3), locale: english) == "The 3 matches have no located address.")
        #expect(MapText.notice(.notLocated(matches: 3), locale: german) == "Die 3 Treffer haben keine gefundene Adresse.")
        #expect(MapText.notice(.noResults, locale: french) == "Aucun résultat")
    }

    @Test func eventFormatsHaveANameInEachLanguage() {
        #expect(EventFormat.liveMeeting.name(locale: english) == "Live meeting")
        #expect(EventFormat.webCall.name(locale: german) == "Videoanruf")
        #expect(EventFormat.phoneCall.name(locale: french) == "Appel téléphonique")
    }

    /// As in Contacts: a role stored as "Ben — manager of — Anna" shows on Anna's card as "manager", next to Ben's name.
    @Test func aConnectionReadsLikeARelationshipInContacts() {
        let ben = PersonRef(id: UUID(), name: "Ben Sample")
        func label(_ kind: String, _ direction: ConnectionSnapshot.Direction, _ locale: Locale) -> String {
            ConnectionSnapshot(id: UUID(), kind: kind, other: ben, direction: direction).label(locale: locale)
        }
        #expect(label("manager of", .incoming, english) == "manager")
        #expect(label("manager of", .outgoing, english) == "manager of")
        #expect(label("introduced by", .outgoing, english) == "introduced by")
        #expect(label("introduced by", .incoming, english) == "introduced by (from them)")
        #expect(label("manager of", .incoming, german) == "Vorgesetzte(r)")
        #expect(label("friend of", .incoming, french) == "ami(e)")
        #expect(label("introduced by", .incoming, german) == "introduced by (aus deren Sicht)")
    }

    @Test func aRoleOfAppleIsTranslatedAndAnOwnRoleIsShownAsTyped() {
        #expect(RelationshipText.role("sister", locale: german) == "Schwester")
        #expect(RelationshipText.role("colleague", locale: french) == "collègue")
        #expect(RelationshipText.role("mentor", locale: german) == "mentor")
    }

    @Test func theBirthdayShowsTheDateAndTheAge() {
        let today = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 21))!
        func line(_ birthday: String?, _ locale: Locale) -> String? {
            ContactDetails(identifier: "C-1", birthday: birthday).birthdayLine(on: today, locale: locale)
        }
        #expect(line("1980-05-17", english) == "17 May 1980 · 46 years")
        #expect(line("2025-05-17", english) == "17 May 2025 · 1 year")
        #expect(line("--05-17", english) == "17 May")
        #expect(line(nil, english) == nil)
        #expect(line("1980-05-17", german) == "17. Mai 1980 · 46 Jahre")
        #expect(line("2025-05-17", french) == "17 mai 2025 · 1 an")
    }
}

/// The string catalogs of the apps (issue #13): every text has a German and a French translation, with the
/// same placeholders as the English text.
@Suite struct StringCatalogTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let catalogs = ["Sources/CXUI/Localizable.xcstrings", "App/Shared/Localizable.xcstrings",
                           "App/Shared/InfoPlist.xcstrings", "App/ShareCommon/Localizable.xcstrings"]

    /// The placeholders of a text, without their position: "%1$@ von %2$lld" gives ["@", "lld"].
    static func placeholders(_ text: String) -> [String] {
        let pattern = /%(?:\d+\$)?(@|lld|ld|d|f)/
        return text.matches(of: pattern).map { String($0.output.1) }.sorted()
    }

    /// Every text of a localization: the plain one, and each plural form.
    static func texts(_ localization: [String: Any]) -> [String] {
        var texts: [String] = []
        if let unit = localization["stringUnit"] as? [String: Any], let value = unit["value"] as? String { texts.append(value) }
        if let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] {
            texts += plural.values.flatMap { Self.texts($0) }
        }
        return texts
    }

    @Test(arguments: catalogs)
    func everyTextIsTranslatedWithTheSamePlaceholders(_ path: String) throws {
        let data = try Data(contentsOf: Self.root.appendingPathComponent(path))
        let strings = try #require((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["strings"] as? [String: [String: Any]])
        #expect(!strings.isEmpty)
        for (key, entry) in strings where entry["shouldTranslate"] as? Bool != false {
            let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
            for language in ["de", "fr"] {
                let localization = try #require(localizations[language], "\(key) has no \(language)")
                #expect((localization["stringUnit"] as? [String: Any])?["state"] as? String ?? "translated" == "translated", "\(key) [\(language)]")
                // a text with substitutions has its plural forms there; Info.plist keys have no placeholders
                guard localization["substitutions"] == nil, !path.hasSuffix("InfoPlist.xcstrings") else { continue }
                for text in Self.texts(localization) where Self.placeholders(text).count > 0 || Self.placeholders(key).count > 0 {
                    // a plural form for one may leave out the number
                    let expected = Self.placeholders(key)
                    let found = Self.placeholders(text)
                    #expect(found == expected || (localization["variations"] != nil && found == expected.filter { $0 != "lld" }),
                            "\(key) [\(language)]: \(text)")
                }
            }
        }
    }

    /// The trap of a Swift package: text that is looked up in the app's bundle instead of CXUI's stays English.
    @Test func cxuiTextIsFoundInItsOwnBundle() {
        #expect(localized(LocalizedStringResource("Recently Deleted", bundle: .cxui), locale: Locale(identifier: "de")) == "Zuletzt gelöscht")
        #expect(localized(LocalizedStringResource("Recently Deleted", bundle: .cxui), locale: Locale(identifier: "fr")) == "Suppressions récentes")
        #expect(Bundle.module.localizations.contains("de") && Bundle.module.localizations.contains("fr"))
    }
}
