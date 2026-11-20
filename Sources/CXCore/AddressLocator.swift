#if canImport(CoreLocation)
import CoreLocation
import Foundation

/// The thin shell around Apple's geocoder: asks for one address within the hourly budget (`GeocodeBudget`,
/// counted in `GeocodeStore`). Everything it decides is decided by the tested parts; this only makes the call.
/// The caller keeps the answer (`CXStore.recordLocations`).
public enum AddressLocator {
    public enum Outcome: Equatable, Sendable {
        case done
        /// The hour's budget is spent (or the service said so itself); nothing is sent before this time.
        case paused(until: Date)
        /// The service could not be reached; nothing was spent. Try again at this time.
        case unreachable(until: Date)

        /// When to carry on, if the run stopped early.
        public var resumesAt: Date? {
            switch self {
            case .done: nil
            case .paused(let until), .unreachable(let until): until
            }
        }
    }

    /// At least this long between two requests.
    public static let spacing: Duration = .seconds(1)

    public enum Answer: Equatable, Sendable {
        /// The service answered; `nil` = it does not know the address.
        case located(Coordinate?)
        /// Nothing was learned about the address; the run should stop.
        case stopped(Outcome)
    }

    /// Asks the geocoder for one address, if the hour's budget (counted in `budget`) allows it.
    /// Wait `spacing` before the next one.
    public static func lookUp(_ address: PostalAddress, budget: GeocodeStore) async throws -> Answer {
        try Task.checkCancellation()
        if case .wait(let until) = try budget.reserve() { return .stopped(.paused(until: until)) }
        do {
            // deprecated from macOS / iOS 26 in favour of MKGeocodingRequest; works on the 15 / 18 we run on
            let marks = try await CLGeocoder().geocodeAddressString(address.query)
            try budget.noteAnswer()
            return .located(marks.first?.location.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) })
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // what to do about the failure is decided by `GeocodeErrorPolicy`; this only carries it out
            let code = (error as? CLError)?.code
            let failure: GeocodeFailure = code == .geocodeFoundNoResult ? .noResult : code == .network ? .network : .other
            let count = failure == .network ? try budget.recordNetworkFailure() : 0
            switch GeocodeErrorPolicy.reaction(to: failure, consecutiveNetworkFailures: count) {
            case .recordNotFound:
                try budget.noteAnswer()
                return .located(nil)
            case .retryLater(let seconds): return .stopped(.unreachable(until: Date().addingTimeInterval(seconds)))
            case .markThrottled: return .stopped(.paused(until: try budget.markThrottled()))
            }
        }
    }
}
#endif
