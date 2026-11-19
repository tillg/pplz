import Foundation

/// A place on the globe.
public struct Coordinate: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Great-circle distance in kilometres (haversine, earth radius 6371 km).
    public func distanceKm(to other: Coordinate) -> Double {
        let toRadians = Double.pi / 180
        let dLat = (other.latitude - latitude) * toRadians
        let dLon = (other.longitude - longitude) * toRadians
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * toRadians) * cos(other.latitude * toRadians) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * asin(min(1, sqrt(a)))
    }
}

public enum Distance {
    /// "50km", "50 km", "50", "2,5 km" or "800m" in kilometres; a number alone is kilometres.
    public static func parseKm(_ text: String) throws -> Double {
        var rest = text.trimmed.lowercased().replacingOccurrences(of: ",", with: ".")
        var factor = 1.0
        if rest.hasSuffix("km") {
            rest = String(rest.dropLast(2))
        } else if rest.hasSuffix("m") {
            rest = String(rest.dropLast())
            factor = 0.001
        }
        guard let value = Double(rest.trimmed), value > 0, value.isFinite else {
            throw PplzError.invalid("\"\(text)\" is not a distance. Write it like 50km, 50 or 800m.")
        }
        return value * factor
    }
}

/// One postal address of a contact.
public struct PostalAddress: Codable, Equatable, Sendable {
    /// "home", "work", … as the contact labels it; may be empty.
    public var label: String
    public var street: String
    public var postalCode: String
    public var city: String
    public var country: String

    public init(label: String = "", street: String = "", postalCode: String = "", city: String = "", country: String = "") {
        self.label = label
        self.street = street
        self.postalCode = postalCode
        self.city = city
        self.country = country
    }

    /// What is sent to the geocoder: "Street, 12345 City, Country", with whatever parts there are —
    /// so someone with only a city is found at the city centre. Empty if there is nothing to locate.
    public var query: String {
        let town = [postalCode, city].map(\.trimmed).filter { !$0.isEmpty }.joined(separator: " ")
        return [street.trimmed, town, country.trimmed].filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The key in the geocode cache: the query without case, accents and extra spaces.
    public var key: String { Self.normalised(query) }

    /// The key of a place typed on the command line, e.g. "Köln".
    public static func key(forPlace place: String) -> String { normalised(place) }

    private static func normalised(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// The hourly budget for the geocoding service: at most `hourlyLimit` requests per clock hour; when it is
/// used up, nothing is sent until ten minutes into the next hour.
public enum GeocodeBudget {
    public static let hourlyLimit = 300
    /// How far into the new hour the pause runs.
    public static let pauseIntoNextHour: TimeInterval = 10 * 60

    public enum Decision: Equatable, Sendable {
        case send
        case wait(until: Date)
    }

    public static func slotStart(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .hour, for: date)?.start ?? date
    }

    /// When a spent slot ends its pause.
    static func resume(after slotStart: Date, calendar: Calendar) -> Date {
        (calendar.date(byAdding: .hour, value: 1, to: slotStart) ?? slotStart.addingTimeInterval(3600)).addingTimeInterval(pauseIntoNextHour)
    }

    /// What was sent in the hour `now` is in; a count from an earlier hour is void.
    public static func sent(now: Date, slotStart: Date?, sent: Int, calendar: Calendar = .current) -> Int {
        slotStart == self.slotStart(of: now, calendar: calendar) ? sent : 0
    }

    /// May a request go out now? `slotStart` and `sent` are what was stored by the last request.
    /// The pause of a spent hour runs past the hour's end, so it is judged by the stored slot, not by the new hour.
    public static func decide(now: Date, slotStart: Date?, sent: Int, limit: Int = hourlyLimit, calendar: Calendar = .current) -> Decision {
        guard let slotStart, sent >= limit else { return .send }
        let resume = resume(after: slotStart, calendar: calendar)
        return now < resume ? .wait(until: resume) : .send
    }
}

/// What has been geocoded so far, and how much of this hour's budget is used. One file per device,
/// shared by the app and the command line.
public struct GeocodeState: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        /// `nil` = the service does not know the address.
        public var coordinate: Coordinate?
        public var checkedAt: Date
    }

    /// Addresses not found are asked again after this long.
    public static let retryNotFoundAfter: TimeInterval = 30 * 86_400

    public var entries: [String: Entry] = [:]
    public var slotStart: Date?
    public var sent = 0

    public init() {}

    public func coordinate(for key: String) -> Coordinate? { entries[key]?.coordinate }

    /// Located, or not found recently enough not to ask again.
    public func isKnown(_ key: String, now: Date = Date()) -> Bool {
        guard let entry = entries[key] else { return false }
        return entry.coordinate != nil || now.timeIntervalSince(entry.checkedAt) < Self.retryNotFoundAfter
    }

    public func budget(now: Date = Date(), calendar: Calendar = .current) -> GeocodeBudget.Decision {
        GeocodeBudget.decide(now: now, slotStart: slotStart, sent: sent, calendar: calendar)
    }
}

/// The geocode cache file. Every change is read, changed and written back under a lock on a second
/// file, so the app and the command line can work at the same time without losing each other's entries.
public final class GeocodeStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// `geocache.json` next to the default store. Deliberately not tied to `PPLZ_STORE` or `--store`:
    /// the cache belongs to this device, whichever store is open.
    public static func defaultURL() -> URL {
        URL.applicationSupportDirectory.appendingPathComponent("pplz/geocache.json")
    }

    public func load() throws -> GeocodeState {
        guard let data = try? Data(contentsOf: url) else { return GeocodeState() }
        return try Self.decoder.decode(GeocodeState.self, from: data)
    }

    /// Notes the answer for an address; `nil` = not found.
    public func record(_ key: String, _ coordinate: Coordinate?, now: Date = Date()) throws {
        try update { $0.entries[key] = .init(coordinate: coordinate, checkedAt: now) }
    }

    /// Counts a request against the hour's budget if there is any left. Called before every request,
    /// so a request that is lost on the way still counts.
    public func reserve(now: Date = Date(), limit: Int = GeocodeBudget.hourlyLimit, calendar: Calendar = .current) throws -> GeocodeBudget.Decision {
        try update { state in
            let decision = GeocodeBudget.decide(now: now, slotStart: state.slotStart, sent: state.sent, limit: limit, calendar: calendar)
            if decision == .send {
                state.sent = GeocodeBudget.sent(now: now, slotStart: state.slotStart, sent: state.sent, calendar: calendar) + 1
                state.slotStart = GeocodeBudget.slotStart(of: now, calendar: calendar)
            }
            return decision
        }
    }

    /// The service answered with its throttle error: this hour's budget is spent. Returns when to continue.
    @discardableResult
    public func markThrottled(now: Date = Date(), limit: Int = GeocodeBudget.hourlyLimit, calendar: Calendar = .current) throws -> Date {
        let slot = GeocodeBudget.slotStart(of: now, calendar: calendar)
        try update { state in
            state.sent = max(limit, GeocodeBudget.sent(now: now, slotStart: state.slotStart, sent: state.sent, calendar: calendar))
            state.slotStart = slot
        }
        return GeocodeBudget.resume(after: slot, calendar: calendar)
    }

    private func update<T>(_ change: (inout GeocodeState) throws -> T) throws -> T {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lock = open(url.path + ".lock", O_CREAT | O_RDWR, 0o644)
        guard lock >= 0, flock(lock, LOCK_EX) == 0 else { throw PplzError.invalid("Cannot lock the geocode cache at \(url.path).") }
        defer { flock(lock, LOCK_UN); close(lock) }
        var state = try load()
        let result = try change(&state)
        try Self.encoder.encode(state).write(to: url, options: .atomic)
        return result
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

/// One address on the map.
public struct LocatedPin: Identifiable, Equatable, Sendable {
    public var id: String
    /// The `PersonEntry.key` of the person.
    public var personKey: String
    public var name: String
    public var label: String
    public var coordinate: Coordinate
}

/// A person with an address near a place.
public struct NearbyPerson: Equatable, Sendable {
    public var entry: PersonEntry
    /// The nearest of their addresses.
    public var label: String
    public var distanceKm: Double
}

/// Matches people's addresses with the geocode cache.
public enum LocatedPeople {
    /// Every located address is its own pin.
    public static func pins(for entries: [PersonEntry], in state: GeocodeState) -> [LocatedPin] {
        entries.flatMap { entry in
            entry.addresses.enumerated().compactMap { index, address in
                state.coordinate(for: address.key).map {
                    LocatedPin(id: "\(entry.key)#\(index)", personKey: entry.key, name: entry.name, label: address.label, coordinate: $0)
                }
            }
        }
    }

    /// People with a located address within `km` of `center`, nearest first, each once with the nearest address.
    public static func near(_ center: Coordinate, within km: Double, entries: [PersonEntry], in state: GeocodeState) -> [NearbyPerson] {
        entries.compactMap { entry in
            entry.addresses.compactMap { address in
                state.coordinate(for: address.key).map { (address.label, center.distanceKm(to: $0)) }
            }.min { $0.1 < $1.1 }
                .flatMap { $0.1 <= km ? NearbyPerson(entry: entry, label: $0.0, distanceKm: $0.1) : nil }
        }.sorted { $0.distanceKm != $1.distanceKm ? $0.distanceKm < $1.distanceKm : $0.entry.name < $1.entry.name }
    }

    /// The distinct addresses still to be geocoded.
    public static func outstanding(in entries: [PersonEntry], state: GeocodeState, now: Date = Date()) -> [PostalAddress] {
        var seen: Set<String> = []
        return entries.flatMap(\.addresses).filter { !$0.query.isEmpty && !state.isKnown($0.key, now: now) && seen.insert($0.key).inserted }
    }

    public struct Counts: Equatable, Sendable {
        public var located: Int
        public var notFound: Int
        public var outstanding: Int
        public var total: Int { located + notFound + outstanding }
    }

    /// Distinct addresses by what became of them.
    public static func counts(in entries: [PersonEntry], state: GeocodeState, now: Date = Date()) -> Counts {
        var counts = Counts(located: 0, notFound: 0, outstanding: 0)
        var seen: Set<String> = []
        for address in entries.flatMap(\.addresses) where !address.query.isEmpty && seen.insert(address.key).inserted {
            if state.coordinate(for: address.key) != nil {
                counts.located += 1
            } else if state.isKnown(address.key, now: now) {
                counts.notFound += 1
            } else {
                counts.outstanding += 1
            }
        }
        return counts
    }

    /// "1 234 of 2 000 addresses located · 12 not found · continues at 14:10"; `nil` without addresses.
    public static func statusLine(_ counts: Counts, resumesAt: Date?) -> String? {
        guard counts.total > 0 else { return nil }
        let numbers = NumberFormatter()
        numbers.groupingSeparator = " "
        numbers.usesGroupingSeparator = true
        func n(_ value: Int) -> String { numbers.string(from: NSNumber(value: value)) ?? "\(value)" }
        var parts = ["\(n(counts.located)) of \(n(counts.total)) addresses located"]
        if counts.notFound > 0 { parts.append("\(n(counts.notFound)) not found") }
        if let resumesAt, counts.outstanding > 0 {
            let time = DateFormatter()
            time.locale = Locale(identifier: "en_US_POSIX")
            time.dateFormat = "HH:mm"
            parts.append("continues at \(time.string(from: resumesAt))")
        }
        return parts.joined(separator: " · ")
    }
}
