import MapKit
import Testing
@testable import CXUI

/// The map's drawing order (issue #14).
@MainActor
@Suite struct PersonMapTests {
    @Test func ownPositionIsDrawnAbovePinsAndGroups() {
        let coordinator = PersonMap.Coordinator()
        let map = coordinator.makeMap()
        let own = MKAnnotationView(annotation: map.userLocation, reuseIdentifier: nil)
        let pin = MKMarkerAnnotationView(annotation: MKPointAnnotation(), reuseIdentifier: nil)

        coordinator.mapView(map, didAdd: [own, pin])

        #expect(own.zPriority == .max)
        #expect(pin.zPriority.rawValue < own.zPriority.rawValue)
    }
}
