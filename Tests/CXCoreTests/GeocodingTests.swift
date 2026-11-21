import Foundation
import SwiftData
import Testing
@testable import CXCore

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

    func finish(_ outstanding: Int, now: Date, slot: Date?, sent: Int) -> Date? {
        GeocodeBudget.finish(outstanding: outstanding, now: now, slotStart: slot, sent: sent, calendar: calendar)
    }

    @Test func nothingOutstandingHasNoFinish() {
        #expect(finish(0, now: at(13, 20), slot: at(13), sent: 50) == nil)
    }

    /// One request per second, while the hour's budget lasts.
    @Test func whatFitsIntoThisHoursBudgetIsDoneInOneSecondEach() {
        #expect(finish(100, now: at(13, 20), slot: at(13), sent: 50) == at(13, 20).addingTimeInterval(100))
        #expect(finish(250, now: at(13, 20), slot: at(13), sent: 50) == at(13, 20).addingTimeInterval(250))
    }

    /// The rest waits for the next hours, each starting ten minutes after the hour with a full budget.
    @Test func theRestGoesOnTenMinutesIntoEachNextHour() {
        #expect(finish(400, now: at(13, 20), slot: at(13), sent: 100) == at(14, 10).addingTimeInterval(200))
        #expect(finish(900, now: at(13, 20), slot: nil, sent: 0) == at(15, 10).addingTimeInterval(300))
        #expect(finish(100, now: at(13, 20), slot: at(11), sent: 300) == at(13, 20).addingTimeInterval(100))   // an old hour's count is void
    }

    @Test func aSpentBudgetStartsWhenThePauseEnds() {
        #expect(finish(650, now: at(13, 20), slot: at(13), sent: 300) == at(16, 10).addingTimeInterval(50))
        #expect(finish(10, now: at(14, 5), slot: at(13), sent: 300) == at(14, 10).addingTimeInterval(10))
    }

    /// Near the end of an hour only some requests fit before it ends. The rest count against the next hour,
    /// which is then spent after 300 and pauses until ten minutes into the hour after it.
    @Test func requestsThatDoNotFitIntoTheHourCountAgainstTheNextHour() {
        // 10 before 14:00, 300 from 14:00:00 to 14:04:59, the pause until 15:10, 290 from 15:10:00 to 15:14:49
        #expect(finish(600, now: at(13, 59).addingTimeInterval(50), slot: nil, sent: 0) == at(15, 14).addingTimeInterval(50))
        // 120 before 14:00, 280 from 14:00:00 to 14:04:39; the hour from 14:00 is not spent, so no pause
        #expect(finish(400, now: at(13, 58), slot: nil, sent: 0) == at(14, 4).addingTimeInterval(40))
    }
}

@Suite struct GeocodeStoreTests {
    func makeStore() -> GeocodeStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cx-geo-tests-\(UUID().uuidString)")
        return GeocodeStore(url: dir.appendingPathComponent("geocache.json"))
    }
    let cologne = Coordinate(latitude: 50.9375, longitude: 6.9603)

    @Test func aMissingFileIsAnEmptyCache() throws {
        let state = try makeStore().load()
        #expect(state.entries.isEmpty)
        #expect(state.sent == 0)
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

    @Test func aFileThatExistsButCannotBeReadIsAnErrorNotAnEmptyCache() throws {
        let store = makeStore()
        _ = try store.reserve()
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: store.url.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.url.path) }
        #expect(throws: (any Error).self) { try store.load() }
        #expect(throws: (any Error).self) { try store.reserve() }   // and nothing is written over it
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.url.path)
        #expect(try store.load().sent == 1)
    }

    @Test func aFileThatDoesNotDecodeIsMovedAsideAndTheCacheStartsEmpty() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("this is not json".utf8).write(to: store.url)
        let broken = store.url.appendingPathExtension("broken")
        #expect(try store.load().entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: store.url.path))
        #expect(try String(contentsOf: broken, encoding: .utf8) == "this is not json")
        // writing works again, and a second broken file replaces the first one aside
        _ = try store.reserve()
        try Data("again broken".utf8).write(to: store.url)
        #expect(try store.load().entries.isEmpty)
        #expect(try String(contentsOf: broken, encoding: .utf8) == "again broken")
    }

    @Test func networkFailuresInARowAreCountedAndAnAnswerResetsTheCount() throws {
        let store = makeStore()
        #expect(try store.recordNetworkFailure() == 1)
        #expect(try store.recordNetworkFailure() == 2)
        #expect(try GeocodeStore(url: store.url).recordNetworkFailure() == 3)   // kept across launches
        try store.noteAnswer()
        #expect(try store.recordNetworkFailure() == 1)
        try store.markThrottled()
        #expect(try store.recordNetworkFailure() == 1)
    }

    @Test func aFileWrittenBeforeTheCounterExistedStillLoads() throws {
        let store = makeStore()
        try FileManager.default.createDirectory(at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"entries":{},"sent":5}"#.utf8).write(to: store.url)
        #expect(try store.load().sent == 5)
    }

    /// The app and the CLI count in the same file: no request one of them counted may get lost.
    @Test func concurrentWritersLoseNothing() throws {
        let store = makeStore()
        let other = GeocodeStore(url: store.url)
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            let target = index.isMultiple(of: 2) ? store : other
            _ = try? target.reserve(now: Date(), limit: 1000)
        }
        #expect(try store.load().sent == 40)
    }

    @Test func theDefaultFileSitsNextToTheDefaultStore() {
        #expect(GeocodeStore.defaultURL().deletingLastPathComponent() == CXStore.defaultURL(environment: [:]).deletingLastPathComponent())
        #expect(GeocodeStore.defaultURL().lastPathComponent == "geocache.json")
    }
}

/// What to do when the geocoder fails for one address.
@Suite struct GeocodeErrorPolicyTests {
    @Test func noResultAndAnyOtherErrorMarkTheAddressNotFoundAndGoOn() {
        #expect(GeocodeErrorPolicy.reaction(to: .noResult, consecutiveNetworkFailures: 0) == .recordNotFound)
        #expect(GeocodeErrorPolicy.reaction(to: .other, consecutiveNetworkFailures: 0) == .recordNotFound)
        #expect(GeocodeErrorPolicy.reaction(to: .other, consecutiveNetworkFailures: 5) == .recordNotFound)
    }

    @Test func aNetworkErrorStopsTheRunAndTriesAgainInFiveMinutes() {
        #expect(GeocodeErrorPolicy.reaction(to: .network, consecutiveNetworkFailures: 1) == .retryLater(after: 300))
        #expect(GeocodeErrorPolicy.reaction(to: .network, consecutiveNetworkFailures: 2) == .retryLater(after: 300))
    }

    @Test func threeNetworkErrorsInARowCountAsThrottling() {
        #expect(GeocodeErrorPolicy.reaction(to: .network, consecutiveNetworkFailures: 3) == .markThrottled)
        #expect(GeocodeErrorPolicy.reaction(to: .network, consecutiveNetworkFailures: 4) == .markThrottled)
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
            #expect(throws: CXError.self) { try Distance.parseKm(text) }
        }
    }
}

/// The located addresses are part of the cardXchange data that syncs through iCloud.
@Suite struct LocationStoreTests {
    let cologne = Coordinate(latitude: 50.9375, longitude: 6.9603)
    let bonn = Coordinate(latitude: 50.7374, longitude: 7.0982)

    func cache() -> GeocodeStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cx-geo-tests-\(UUID().uuidString)")
        return GeocodeStore(url: dir.appendingPathComponent("geocache.json"))
    }

    @Test func resultsAndNotFoundSurviveARelaunch() throws {
        let (store, url) = try makeStore()
        try store.recordLocations(["köln, germany": .init(coordinate: cologne, checkedAt: Date()),
                                   "nowhere 1, atlantis": .init(coordinate: nil, checkedAt: Date())])

        var state = GeocodeState()
        state.entries = try CXStore(url: url).locations()       // the next launch
        #expect(state.coordinate(for: "köln, germany") == cologne)
        #expect(state.isKnown("nowhere 1, atlantis"))
        #expect(state.coordinate(for: "nowhere 1, atlantis") == nil)
        #expect(!state.isKnown("bonn, germany"))
    }

    @Test func notFoundIsAskedAgainAfterThirtyDays() throws {
        let (store, _) = try makeStore()
        let then = Date(timeIntervalSince1970: 1_800_000_000)
        try store.recordLocations(["nowhere 1, atlantis": .init(coordinate: nil, checkedAt: then),
                                   "köln, germany": .init(coordinate: cologne, checkedAt: then)])
        var state = GeocodeState()
        state.entries = try store.locations()
        #expect(state.isKnown("nowhere 1, atlantis", now: then.addingTimeInterval(29 * 86_400)))
        #expect(!state.isKnown("nowhere 1, atlantis", now: then.addingTimeInterval(31 * 86_400)))
        #expect(state.isKnown("köln, germany", now: then.addingTimeInterval(400 * 86_400)))
    }

    /// Asking again after the thirty days changes the row that is there; it does not add another.
    @Test func aNewAnswerReplacesTheOldOne() throws {
        let (store, _) = try makeStore()
        let then = Date(timeIntervalSince1970: 1_800_000_000)
        try store.recordLocations(["köln, germany": .init(coordinate: nil, checkedAt: then)])
        try store.recordLocations(["köln, germany": .init(coordinate: cologne, checkedAt: then.addingTimeInterval(60))])
        #expect(try store.locations() == ["köln, germany": .init(coordinate: cologne, checkedAt: then.addingTimeInterval(60))])
        #expect(try store.context.fetch(FetchDescriptor<LocatedAddress>()).count == 1)
    }

    /// Two devices located the same address before they synced: both rows stay (deleting could remove both),
    /// and every device reads the same one — found beats not found, then the earlier answer.
    @Test func twoRowsForOneAddressAreReadTheSameEverywhere() throws {
        let (store, _) = try makeStore()
        let then = Date(timeIntervalSince1970: 1_800_000_000)
        for (coordinate, date) in [(nil, then), (bonn, then.addingTimeInterval(20)), (cologne, then.addingTimeInterval(10))] as [(Coordinate?, Date)] {
            store.context.insert(LocatedAddress(key: "köln, germany", coordinate: coordinate, checkedAt: date))
        }
        try store.context.save()
        #expect(try store.locations() == ["köln, germany": .init(coordinate: cologne, checkedAt: then.addingTimeInterval(10))])
        try store.recordLocations(["köln, germany": .init(coordinate: bonn, checkedAt: then.addingTimeInterval(99))])
        #expect(try store.context.fetch(FetchDescriptor<LocatedAddress>()).count == 3)
    }

    /// What a device located before the coordinates were synced moves into the store once.
    @Test func theOldCacheFileIsHandedOverToTheStore() throws {
        let (store, _) = try makeStore()
        let cache = cache()
        try FileManager.default.createDirectory(at: cache.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"entries":{"köln, germany":{"coordinate":{"latitude":50.9375,"longitude":6.9603},"checkedAt":"2026-11-19T22:00:00Z"},"bonn, germany":{"checkedAt":"2026-11-19T22:00:01Z"}},"sent":7,"slotStart":"2026-11-19T22:00:00Z"}"#.utf8)
            .write(to: cache.url)
        try store.recordLocations(["bonn, germany": .init(coordinate: bonn, checkedAt: Date(timeIntervalSince1970: 1_800_000_000))])

        #expect(try cache.handOver(to: store) == 1)                       // Bonn is in the store already and stays as it is
        #expect(try store.locations()["köln, germany"]?.coordinate == cologne)
        #expect(try store.locations()["bonn, germany"]?.coordinate == bonn)
        let left = try cache.load()
        #expect(left.entries.isEmpty)
        #expect(left.sent == 7)                                            // the hour's count stays on the device
        #expect(try cache.handOver(to: store) == 0)
    }

    /// Only the device's own cache goes into the device's own store: a test store must not swallow it.
    @Test func handingOverHappensOnlyBetweenTheDefaultFiles() throws {
        let (store, url) = try makeStore()
        let cache = cache()
        try FileManager.default.createDirectory(at: cache.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"entries":{"bonn, germany":{"checkedAt":"2026-11-19T22:00:01Z"}},"sent":0}"#.utf8).write(to: cache.url)
        #expect(!GeocodeStore.isDefaultPair(store: url, cache: GeocodeStore.defaultURL()))
        #expect(!GeocodeStore.isDefaultPair(store: CXStore.defaultURL(environment: [:]), cache: cache.url))
        #expect(GeocodeStore.isDefaultPair(store: CXStore.defaultURL(environment: [:]), cache: GeocodeStore.defaultURL()))
        #expect(try cache.handOverIfDefault(store: url, to: store) == 0)
        #expect(try cache.load().entries.count == 1)
        #expect(try store.locations().isEmpty)
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

    /// Every device picks a card at random, so that two devices rarely work on the same one.
    @Test func theNextCardIsARandomOneWithOpenAddresses() {
        var state = self.state
        state.entries[capital.key] = nil
        let hamburg = PostalAddress(label: "work", city: "Hamburg", country: "Germany")
        let entries = [entry("Anna Example", [home, capital]), entry("Ben Sample", [hamburg, unknown, hamburg]), entry("Cy Done", [work]),
                       entry("Di Empty", [PostalAddress(label: "x")])]
        var generator = SystemRandomNumberGenerator()
        var seen: Set<[String]> = []
        for _ in 0..<200 { seen.insert(LocatedPeople.nextCard(in: entries, state: state, using: &generator).map(\.key)) }
        #expect(seen == [[capital.key], [hamburg.key]])       // only the open addresses of one card, each once; both cards get their turn

        state.entries[capital.key] = .init(coordinate: berlin, checkedAt: Date())
        state.entries[hamburg.key] = .init(coordinate: nil, checkedAt: Date())
        #expect(LocatedPeople.nextCard(in: entries, state: state, using: &generator).isEmpty)
    }

    @Test func theStatusLineSaysHowFarLocatingIsAndWhenItContinues() {
        let resumes = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 14, minute: 10))!
        let counts = LocatedPeople.Counts(located: 1234, notFound: 0, outstanding: 766)
        #expect(LocatedPeople.statusLine(counts, resumesAt: resumes) == "1 234 of 2 000 addresses located · pausing until 14:10")
        #expect(LocatedPeople.statusLine(counts, resumesAt: nil) == "1 234 of 2 000 addresses located")
        #expect(LocatedPeople.statusLine(.init(located: 5, notFound: 2, outstanding: 0), resumesAt: resumes) == "5 of 7 addresses located · 2 not found")
        #expect(LocatedPeople.statusLine(.init(located: 0, notFound: 0, outstanding: 0), resumesAt: nil) == nil)
    }

    /// Issue #8: when the rest is expected to be located, with the day.
    @Test func theStatusLineSaysWhenLocatingIsExpectedToBeDone() {
        let calendar = Calendar.current
        let resumes = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 14, minute: 10))!
        let done = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 18, minute: 40))!
        let counts = LocatedPeople.Counts(located: 147, notFound: 5, outstanding: 1959)
        #expect(LocatedPeople.statusLine(counts, resumesAt: resumes, doneAt: done)
                == "147 of 2 111 addresses located · 5 not found · pausing until 14:10 · done about Sat 18:40")
        #expect(LocatedPeople.statusLine(counts, resumesAt: nil, doneAt: done) == "147 of 2 111 addresses located · 5 not found · done about Sat 18:40")
        #expect(LocatedPeople.statusLine(.init(located: 5, notFound: 2, outstanding: 0), resumesAt: nil, doneAt: done) == "5 of 7 addresses located · 2 not found")
    }

    /// Issue #9: what the map says when it shows no pin.
    @Test func theMapSaysWhyItShowsNoPin() {
        #expect(MapNotice.make(search: "", matches: 3, pins: 2) == nil)
        #expect(MapNotice.make(search: "ann", matches: 1, pins: 1) == nil)
        #expect(MapNotice.make(search: "", matches: 3, pins: 0) == .nobodyLocated)
        #expect(MapNotice.make(search: "", matches: 0, pins: 0) == .nobodyLocated)
        #expect(MapNotice.make(search: "zzz", matches: 0, pins: 0) == .noResults)
        #expect(MapNotice.make(search: "hama", matches: 1, pins: 0) == .notLocated(matches: 1))
        #expect(MapNotice.make(search: "an", matches: 4, pins: 0) == .notLocated(matches: 4))
    }

    /// The list ignores a search of only spaces, so the notice ignores it too.
    @Test func aSearchOfOnlySpacesIsNoSearch() {
        #expect(MapNotice.make(search: "   ", matches: 3, pins: 0) == .nobodyLocated)
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
