import CXCore
import Foundation

// Text that cardXchange builds from data. Each piece is a whole sentence of CXUI's string catalog, with
// placeholders and plural variations, in the language of `locale` (issue #13). CXCore stays English:
// the command line and the history block in the contact notes use its text.

extension LocalizedStringResource.BundleDescription {
    /// CXUI's own bundle with its string catalog. Without it, SwiftUI and Foundation look in the app's bundle.
    static var cxui: Self { .atURL(Bundle.module.bundleURL) }
}

/// The text of `resource` in the language of `locale`, with numbers and dates formatted for it.
func localized(_ resource: LocalizedStringResource, locale: Locale) -> String {
    var resource = resource
    resource.locale = locale
    return String(localized: resource)
}

/// What the map says over its pins.
enum MapText {
    /// "1,234 of 2,000 addresses located · 12 not found · pausing until 14:10 · done about Sat 18:40"; `nil` without addresses.
    /// The parts are phrases of their own; the expected end shows only while locating runs or is paused.
    static func status(_ counts: LocatedPeople.Counts, resumesAt: Date?, doneAt: Date? = nil, locale: Locale = .current) -> String? {
        guard counts.total > 0 else { return nil }
        var parts = [localized(LocalizedStringResource("\(counts.located) of \(counts.total) addresses located", bundle: .cxui,
                                                       comment: "Map status: how many of the addresses have a place on the map"), locale: locale)]
        if counts.notFound > 0 {
            parts.append(localized(LocalizedStringResource("\(counts.notFound) not found", bundle: .cxui,
                                                           comment: "Map status: addresses that the geocoder could not find"), locale: locale))
        }
        if let resumesAt, counts.outstanding > 0 {
            let time = resumesAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
            parts.append(localized(LocalizedStringResource("pausing until \(time)", bundle: .cxui,
                                                           comment: "Map status: locating waits for the hourly budget; the placeholder is a time"),
                                   locale: locale))
        }
        if let doneAt, counts.outstanding > 0 {
            let time = doneAt.formatted(Date.FormatStyle().weekday(.abbreviated).hour().minute().locale(locale))
            parts.append(localized(LocalizedStringResource("done about \(time)", bundle: .cxui,
                                                           comment: "Map status: when all addresses are expected to be located; the placeholder is a weekday and a time"),
                                   locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    /// What the map says when it shows no pin (issue #9).
    static func notice(_ notice: MapNotice, locale: Locale = .current) -> String {
        switch notice {
        case .nobodyLocated:
            localized(LocalizedStringResource("No one on the map yet. People with an address appear once it is located.", bundle: .cxui), locale: locale)
        case .noResults:
            localized(LocalizedStringResource("No results", bundle: .cxui), locale: locale)
        case .notLocated(let matches):
            localized(LocalizedStringResource("The \(matches) matches have no located address.", bundle: .cxui,
                                              comment: "Map: the search finds people, but none of them is on the map"), locale: locale)
        }
    }
}

extension EventFormat {
    /// The format's name for the user. `displayName` stays English for the command line and the contact notes.
    func name(locale: Locale = .current) -> String {
        switch self {
        case .liveMeeting: localized(LocalizedStringResource("Live meeting", bundle: .cxui, comment: "Event format"), locale: locale)
        case .webCall: localized(LocalizedStringResource("Web call", bundle: .cxui, comment: "Event format"), locale: locale)
        case .phoneCall: localized(LocalizedStringResource("Phone call", bundle: .cxui, comment: "Event format"), locale: locale)
        case .largerGathering: localized(LocalizedStringResource("Larger gathering", bundle: .cxui, comment: "Event format"), locale: locale)
        case .writtenExchange: localized(LocalizedStringResource("Written exchange", bundle: .cxui, comment: "Event format"), locale: locale)
        }
    }
}

/// The names of relationships. The address book stores Apple's English role names; the user sees them translated.
enum RelationshipText {
    /// A role of Apple's list (`ContactMirror.appleRoles`, "colleague") in the user's language; any other role as typed.
    static func role(_ role: String, locale: Locale = .current) -> String {
        guard ContactMirror.appleRoles.contains(role) || role == "colleague" else { return role }
        return localized(LocalizedStringResource(String.LocalizationValue(role), bundle: .cxui), locale: locale)
    }
}

extension ConnectionSnapshot {
    /// How the connection reads on this person's card. A role stored as "Ben — manager of — Anna"
    /// shows on Anna's card as in Contacts: "manager", next to Ben's name.
    func label(locale: Locale = .current) -> String {
        let isRole = kind.lowercased().hasSuffix(" of")
        switch (direction, isRole) {
        case (.incoming, true):
            return RelationshipText.role(String(kind.dropLast(3)).trimmingCharacters(in: .whitespaces), locale: locale)
        case (.incoming, false):
            return localized(LocalizedStringResource("\(kind) (from them)", bundle: .cxui,
                                                     comment: "A connection that the other person has with this one; the placeholder is its kind, e.g. introduced by"),
                             locale: locale)
        case (.outgoing, _):
            return kind
        }
    }
}

extension ContactDetails {
    /// The birthday as a date of the user's language, with the age next to it: "17 May 1980 · 46 years".
    func birthdayLine(on today: Date = .now, locale: Locale = .current) -> String? {
        guard let birthday else { return nil }
        let parts = birthday.split(separator: "-").compactMap { Int($0) }
        let calendar = Calendar(identifier: .gregorian)
        guard parts.count >= 2,
              let date = calendar.date(from: DateComponents(year: parts.count == 3 ? parts[0] : 2000, month: parts[parts.count - 2], day: parts[parts.count - 1]))
        else { return birthday }
        let style = Date.FormatStyle(calendar: calendar).locale(locale).day().month(.wide)
        guard parts.count == 3, let age = age(on: today) else { return date.formatted(style) }
        let day = date.formatted(style.year())
        return localized(LocalizedStringResource("\(day) · \(age) years", bundle: .cxui,
                                                 comment: "A birthday and the age; the first placeholder is the date"), locale: locale)
    }
}

/// A text of CXCore in the user's language. CXCore's messages are English, as the command line shows them; those without
/// data in them are keys of CXUI's string catalog as well. A message with data in it stays English.
func coreText(_ text: String) -> String {
    Bundle.module.localizedString(forKey: text, value: text, table: nil)
}

/// What the user is told when something fails.
func userMessage(_ error: Error) -> String {
    coreText((error as? LocalizedError)?.errorDescription ?? "\(error)")
}
