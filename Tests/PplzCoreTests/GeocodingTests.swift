import Foundation
import Testing
@testable import PplzCore

/// The map: addresses become coordinates through Apple's geocoder, slowly and once. Everything around the
/// network call — the budget, the cache file, the matching, the distances — is plain code, tested here on
/// real files. The call itself is a thin shell in `AddressLocator` and is tried by hand.
@Suite struct GeocodeBudgetTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }
    func at(_ hour: Int, _ minute: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: hour, minute: minute))! }
    func decide(now: Date, slot: Date?, sent: Int, limit: Int = 300) -> GeocodeBudget.Decision {
        GeocodeBudget.decide(now: now, slotStart: slot, sent: sent, limit: limit, calendar: calendar)
    }

    @Test func underBudgetMaySend() {
        #expect(decide(now: at(13, 20), slot: at(13), sent: 299) == .send)
        #expect(decide(now: at(13, 20), slot: nil, sent: 0) == .send)
    }

    @Test func spentBudgetWaitsForTheNextHourPlusTenMinutes() {
        #expect(decide(now: at(13, 20), slot: at(13), sent: 300) == .wait(until: at(14, 10)))
        #expect(decide(now: at(13, 59), slot: at(13), sent: 450) == .wait(until: at(14, 10)))
    }

    /// The new hour has begun, but the pause runs ten minutes into it.
    @Test func thePauseRunsTenMinutesIntoTheNewHour() {
        #expect(decide(now: at(14, 5), slot: at(13), sent: 300) == .wait(until: at(14, 10)))
        #expect(decide(now: at(14, 10), slot: at(13), sent: 300) == .send)
    }

    @Test func aNewSlotStartsWithAnEmptyCount() {
        #expect(decide(now: at(15, 0), slot: at(13), sent: 120) == .send)
        #expect(GeocodeBudget.sent(now: at(15, 0), slotStart: at(13), sent: 120, calendar: calendar) == 0)
        #expect(GeocodeBudget.sent(now: at(13, 30), slotStart: at(13), sent: 120, calendar: calendar) == 120)
    }

    @Test func slotsAreClockHours() {
        #expect(GeocodeBudget.slotStart(of: at(13, 59), calendar: calendar) == at(13))
        #expect(GeocodeBudget.slotStart(of: at(14, 0), calendar: calendar) == at(14))
    }

    @Test func theHourlyLimitIs300() {
        #expect(GeocodeBudget.hourlyLimit == 300)
    }
}

@Suite struct GeocodeStoreTests {
    func makeStore() -> GeocodeStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pplz-geo-tests-\(UUID().uuidString)")
        return GeocodeStore(url: dir.appendingPathComponent("geocache.json"))
    }
    let cologne = Coordinate(latitude: 50.9375, longitude: 6.9603)

    @Test func aMissingFileIsAnEmptyCache() throws {
        let state = try makeStore().load()
        #expect(state.entries.isEmpty)
        #expect(state.sent == 0)
    }

    @Test func resultsAndNotFoundSurviveARelaunch() throws {
        let store = makeStore()
        try store.record("köln, germany", cologne)
        try store.record("nowhere 1, atlantis", nil)

        let again = GeocodeStore(url: store.url)       // the next launch
        let state = try again.load()
        #expect(state.coordinate(for: "köln, germany") == cologne)
        #expect(state.isKnown("nowhere 1, atlantis"))
        #expect(state.coordinate(for: "nowhere 1, atlantis") == nil)
        #expect(!state.isKnown("bonn, germany"))
    }

    /// A relaunch in the middle of an hour carries on counting where the last run stopped.
    @Test func theCountIsKeptAcrossLaunches() throws {
        let store = makeStore()
        let now = Date()
        for _ in 0..<3 { #expect(try store.reserve(now: now, limit: 5) == .send) }
        let again = GeocodeStore(url: store.url)
        #expect(try again.reserve(now: now, limit: 5) == .send)
        #expect(try again.reserve(now: now, limit: 5) == .send)
        guard case .wait(let until) = try again.reserve(now: now, limit: 5) else { Issue.record("sixth request must wait"); return }
        #expect(until > now)
        #expect(try again.load().sent == 5)
    }

    @Test func aNewHourStartsCountingAgain() throws {
        let store = makeStore()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let first = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 13, minute: 5))!
        let later = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 15, minute: 1))!
        for _ in 0..<2 { _ = try store.reserve(now: first, limit: 2, calendar: calendar) }
        #expect(try store.reserve(now: first, limit: 2, calendar: calendar) != .send)
        #expect(try store.reserve(now: later, limit: 2, calendar: calendar) == .send)
        #expect(try store.load().sent == 1)
    }

    /// The service answered with its throttle error: whatever was left of the hour is gone.
    @Test func throttlingSpendsTheBudget() throws {
        let store = makeStore()
        let now = Date()
        _ = try store.reserve(now: now)
        try store.markThrottled(now: now)
        guard case .wait = try store.reserve(now: now) else { Issue.record("must pause"); return }
    }

    @Test func notFoundIsAskedAgainAfterThirtyDays() throws {
        let store = makeStore()
        let then = Date(timeIntervalSince1970: 1_800_000_000)
        try store.record("nowhere 1, atlantis", nil, now: then)
        try store.record("köln, germany", cologne, now: then)
        let state = try store.load()
        #expect(state.isKnown("nowhere 1, atlantis", now: then.addingTimeInterval(29 * 86_400)))
        #expect(!state.isKnown("nowhere 1, atlantis", now: then.addingTimeInterval(31 * 86_400)))
        #expect(state.isKnown("köln, germany", now: then.addingTimeInterval(400 * 86_400)))
    }

    /// The app and the CLI write the same file: nothing one of them wrote may get lost.
    @Test func concurrentWritersLoseNothing() throws {
        let store = makeStore()
        let other = GeocodeStore(url: store.url)
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            let target = index.isMultiple(of: 2) ? store : other
            try? target.record("address \(index)", Coordinate(latitude: Double(index), longitude: 0))
            _ = try? target.reserve(now: Date(), limit: 1000)
        }
        let state = try store.load()
        #expect(state.entries.count == 40)
        #expect(state.sent == 40)
    }

    @Test func theDefaultFileSitsNextToTheDefaultStore() {
        #expect(GeocodeStore.defaultURL().deletingLastPathComponent() == PplzStore.defaultURL(environment: [:]).deletingLastPathComponent())
        #expect(GeocodeStore.defaultURL().lastPathComponent == "geocache.json")
    }
}

@Suite struct AddressTests {
    @Test func aFullAddressIsAskedForAsStreetPostalCodeCityCountry() {
        let address = PostalAddress(label: "home", street: "Domkloster 4", postalCode: "50667", city: "Köln", country: "Germany")
        #expect(address.query == "Domkloster 4, 50667 Köln, Germany")
    }

    @Test func aCityAloneIsAskedForAsCityAndCountry() {
        #expect(PostalAddress(city: "Köln", country: "Germany").query == "Köln, Germany")
        #expect(PostalAddress(city: "Köln").query == "Köln")
        #expect(PostalAddress(country: "Germany").query == "Germany")
    }

    @Test func anEmptyAddressHasNothingToLocate() {
        #expect(PostalAddress(label: "home").query.isEmpty)
        #expect(PostalAddress(label: "home", street: "  ", city: " ").query.isEmpty)
    }

    @Test func theCacheKeyIgnoresCaseAccentsAndSpacing() {
        let a = PostalAddress(street: "Domkloster  4", city: "KÖLN", country: "germany")
        let b = PostalAddress(street: "domkloster 4", city: "Koln", country: "Germany ")
        #expect(a.key == b.key)
        #expect(a.key != PostalAddress(street: "Domkloster 5", city: "Köln", country: "Germany").key)
    }

    @Test func aPlaceTypedOnTheCommandLineHasTheSameKeyAsACityAddress() {
        #expect(PostalAddress.key(forPlace: "Köln") == PostalAddress(city: "Köln").key)
    }
}

@Suite struct DistanceTests {
    let cologneCathedral = Coordinate(latitude: 50.9413, longitude: 6.9583)
    let duesseldorfTownHall = Coordinate(latitude: 51.2257, longitude: 6.7763)
    let berlinGate = Coordinate(latitude: 52.5163, longitude: 13.3777)

    @Test func haversineKnownDistances() {
        #expect(abs(cologneCathedral.distanceKm(to: duesseldorfTownHall) - 34.1) < 0.5)
        #expect(abs(cologneCathedral.distanceKm(to: berlinGate) - 476) < 5)
        #expect(cologneCathedral.distanceKm(to: cologneCathedral) == 0)
    }

    @Test func symmetricAndAcrossTheDateLine() {
        #expect(abs(cologneCathedral.distanceKm(to: berlinGate) - berlinGate.distanceKm(to: cologneCathedral)) < 1e-9)
        let east = Coordinate(latitude: 0, longitude: 179.5), west = Coordinate(latitude: 0, longitude: -179.5)
        #expect(abs(east.distanceKm(to: west) - 111.2) < 1)
    }

    @Test func distancesAreWrittenInKilometresOrMetres() throws {
        #expect(try Distance.parseKm("50km") == 50)
        #expect(try Distance.parseKm("50 km") == 50)
        #expect(try Distance.parseKm("50") == 50)
        #expect(try Distance.parseKm("2.5km") == 2.5)
        #expect(try Distance.parseKm("2,5 km") == 2.5)
        #expect(try Distance.parseKm("800m") == 0.8)
        #expect(try Distance.parseKm(" 800 M ") == 0.8)
    }

    @Test func nonsenseDistancesAreRejected() {
        for text in ["", "km", "far", "-5km", "5 miles", "0"] {
            #expect(throws: PplzError.self) { try Distance.parseKm(text) }
        }
    }
}

@Suite struct LocatedPeopleTests {
    let cologne = Coordinate(latitude: 50.9375, longitude: 6.9603)
    let bonn = Coordinate(latitude: 50.7374, longitude: 7.0982)
    let berlin = Coordinate(latitude: 52.5200, longitude: 13.4050)

    let home = PostalAddress(label: "home", city: "Bonn", country: "Germany")
    let work = PostalAddress(label: "work", street: "Domkloster 4", postalCode: "50667", city: "Köln", country: "Germany")
    let capital = PostalAddress(label: "home", city: "Berlin", country: "Germany")
    let unknown = PostalAddress(label: "home", city: "Nirgendwo", country: "Germany")

    func entry(_ name: String, _ addresses: [PostalAddress], tags: [String] = []) -> PersonEntry {
        PersonEntry(id: nil, contactIdentifier: name, name: name, eventCount: 0, lastMet: nil, tags: tags, addresses: addresses)
    }
    var state: GeocodeState {
        var state = GeocodeState()
        state.entries[home.key] = .init(coordinate: bonn, checkedAt: Date())
        state.entries[work.key] = .init(coordinate: cologne, checkedAt: Date())
        state.entries[capital.key] = .init(coordinate: berlin, checkedAt: Date())
        state.entries[unknown.key] = .init(coordinate: nil, checkedAt: Date())
        return state
    }

    @Test func everyAddressIsItsOwnLabelledPin() {
        let pins = LocatedPeople.pins(for: [entry("Anna Example", [home, work])], in: state)
        #expect(pins.map(\.label).sorted() == ["home", "work"])
        #expect(pins.allSatisfy { $0.name == "Anna Example" && $0.personKey == "Anna Example" })
        #expect(Set(pins.map(\.id)).count == 2)
    }

    @Test func peopleWithoutALocatedAddressHaveNoPin() {
        let pins = LocatedPeople.pins(for: [entry("Ben Sample", [unknown]), entry("Cy Nobody", []), entry("Di Later", [PostalAddress(city: "Hamburg")])],
                                      in: state)
        #expect(pins.isEmpty)
    }

    @Test func nearListsThePeopleWithinTheDistanceNearestFirst() {
        let entries = [entry("Anna Example", [capital, work]), entry("Ben Sample", [home]), entry("Cy Far", [capital]), entry("Di Nowhere", [unknown])]
        let hits = LocatedPeople.near(cologne, within: 50, entries: entries, in: state)
        #expect(hits.map(\.entry.name) == ["Anna Example", "Ben Sample"])     // once each, with the address that is near
        #expect(hits[0].label == "work")
        #expect(hits[0].distanceKm < 1)
        #expect(abs(hits[1].distanceKm - 25) < 3)
        #expect(LocatedPeople.near(cologne, within: 1000, entries: entries, in: state).count == 3)
    }

    @Test func outstandingAddressesAreCountedOnceAndNotFoundOnesAreNotOutstanding() {
        var state = self.state
        state.entries[capital.key] = nil
        let entries = [entry("Anna Example", [home, capital]), entry("Ben Sample", [capital, unknown]), entry("Cy Empty", [PostalAddress(label: "x")])]
        #expect(LocatedPeople.outstanding(in: entries, state: state).map(\.key) == [capital.key])
        let counts = LocatedPeople.counts(in: entries, state: state)
        #expect(counts == .init(located: 1, notFound: 1, outstanding: 1))
        #expect(counts.total == 3)
    }

    @Test func theStatusLineSaysHowFarLocatingIsAndWhenItContinues() {
        let resumes = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 14, minute: 10))!
        let counts = LocatedPeople.Counts(located: 1234, notFound: 0, outstanding: 766)
        #expect(LocatedPeople.statusLine(counts, resumesAt: resumes) == "1 234 of 2 000 addresses located · continues at 14:10")
        #expect(LocatedPeople.statusLine(counts, resumesAt: nil) == "1 234 of 2 000 addresses located")
        #expect(LocatedPeople.statusLine(.init(located: 5, notFound: 2, outstanding: 0), resumesAt: resumes) == "5 of 7 addresses located · 2 not found")
        #expect(LocatedPeople.statusLine(.init(located: 0, notFound: 0, outstanding: 0), resumesAt: nil) == nil)
    }

    @Test func peopleAreFilteredLikeTheList() {
        let entries = [entry("Anna Example", [home], tags: ["sailing"]), entry("Ben Sample", [work])]
        #expect(PeopleSections.matching(entries, search: "sail").map(\.name) == ["Anna Example"])
        #expect(PeopleSections.matching(entries, search: "").count == 2)
    }

    @Test func theDirectoryCarriesTheAddressesButTheJSONStaysAsItWas() throws {
        let contact = ContactSummary(identifier: "C1", name: "Anna Example", addresses: [home, work])
        let entries = PeopleDirectory.merge(contacts: [contact], persons: [])
        #expect(entries[0].addresses == [home, work])
        let json = String(decoding: try JSONEncoder().encode(entries[0]), as: UTF8.self)
        #expect(!json.contains("addresses"))
        #expect(!json.contains("Domkloster"))
    }
}
