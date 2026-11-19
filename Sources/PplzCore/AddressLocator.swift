#if canImport(CoreLocation)
import CoreLocation
import Foundation

/// The thin shell around Apple's geocoder: asks for the addresses one by one within the hourly budget
/// (`GeocodeBudget`, kept in `GeocodeStore`) and writes every answer into the cache. Everything it
/// decides is decided by the tested parts; this only makes the call.
public enum AddressLocator {
    public enum Outcome: Equatable, Sendable {
        case done
        /// The hour's budget is spent (or the service said so itself); nothing is sent before this time.
        case paused(until: Date)
    }

    /// At least this long between two requests.
    static let spacing: Duration = .seconds(1)

    /// Geocodes the addresses in order until all are done or the budget is spent. `progress` is called
    /// after each answer with the number done so far. Cancelling the task stops it between two requests.
    public static func locate(_ addresses: [PostalAddress], in store: GeocodeStore,
                              progress: @Sendable (Int) -> Void = { _ in }) async throws -> Outcome {
        var done = 0
        for address in addresses {
            if done > 0 { try await Task.sleep(for: spacing) }
            try Task.checkCancellation()
            if case .wait(let until) = try store.reserve() { return .paused(until: until) }
            do {
                // deprecated from macOS / iOS 26 in favour of MKGeocodingRequest; works on the 15 / 18 we run on
                let marks = try await CLGeocoder().geocodeAddressString(address.query)
                try store.record(address.key, marks.first?.location.map { Coordinate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) })
            } catch let error as CLError where error.code == .geocodeFoundNoResult {
                try store.record(address.key, nil)
            } catch let error as CLError where error.code == .network {
                // the service's throttle error: treat the hour as spent
                return .paused(until: try store.markThrottled())
            }
            done += 1
            progress(done)
        }
        return .done
    }
}
#endif
