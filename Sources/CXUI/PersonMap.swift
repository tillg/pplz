import MapKit
import CXCore
import SwiftUI

#if os(macOS)
private typealias MapRepresentable = NSViewRepresentable
private typealias PlatformColor = NSColor
#else
private typealias MapRepresentable = UIViewRepresentable
private typealias PlatformColor = UIColor
#endif

/// Every located address as a pink pin; pins close together become one with a count. A pin's callout
/// opens the person. The same MKMapView on Mac, iPhone and iPad.
struct PersonMap: MapRepresentable {
    var pins: [LocatedPin]
    /// The person whose pins to bring into view, e.g. the one chosen in the list.
    var focus: String?
    /// Changes whenever the map should fit its pins again, e.g. when the search text changes.
    var fitID: String
    var onOpen: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    #if os(macOS)
    func makeNSView(context: Context) -> MKMapView { context.coordinator.makeMap() }
    func updateNSView(_ map: MKMapView, context: Context) { context.coordinator.update(map, with: self) }
    #else
    func makeUIView(context: Context) -> MKMapView { context.coordinator.makeMap() }
    func updateUIView(_ map: MKMapView, context: Context) { context.coordinator.update(map, with: self) }
    #endif

    final class PinAnnotation: NSObject, MKAnnotation {
        let pin: LocatedPin
        init(_ pin: LocatedPin) { self.pin = pin }
        var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: pin.coordinate.latitude, longitude: pin.coordinate.longitude) }
        var title: String? { pin.name }
        var subtitle: String? { pin.label.isEmpty ? nil : pin.label }
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        private var parent: PersonMap?
        private var shown: [String: PinAnnotation] = [:]
        private var fitID: String?
        private var focus: String?
        /// Set once the user has moved the map: pins that arrive later then no longer move it.
        private var userMoved = false
        /// A region change we asked for is under way; the map reports it afterwards like the user's own.
        private var movingByCode = false
        private var hasFitted = false
        /// Asks for the user's location the first time the map is shown, not at launch.
        private let location = CLLocationManager()

        func makeMap() -> MKMapView {
            let map = MKMapView()
            map.delegate = self
            // the user's own position and a button that moves the map to it, like Maps (issue #10)
            location.requestWhenInUseAuthorization()       // does nothing once the user has answered
            map.showsUserLocation = true
            map.showsUserTrackingButton = true
            #if os(iOS)
            map.tintColor = .systemBlue     // else the pink tint of the app makes the own position look like a pin (issue #14)
            #endif
            return map
        }

        func update(_ map: MKMapView, with parent: PersonMap) {
            self.parent = parent
            let wanted = Dictionary(parent.pins.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            // only what changed is touched, so that pins arriving one by one do not make the map flicker
            let gone = shown.filter { wanted[$0.key] == nil }
            map.removeAnnotations(Array(gone.values))
            gone.keys.forEach { shown[$0] = nil }
            let added = wanted.filter { shown[$0.key] == nil }.map { PinAnnotation($0.value) }
            added.forEach { shown[$0.pin.id] = $0 }
            map.addAnnotations(added)

            if fitID != parent.fitID {
                fitID = parent.fitID
                userMoved = false
                show(Array(shown.values), in: map)
            } else if !userMoved, let newest = added.last, !map.visibleMapRect.contains(MKMapPoint(newest.coordinate)) {
                show(Array(shown.values), in: map)
            }
            if focus != parent.focus {
                // a person whose pins are not located yet is tried again with every update
                let theirs = shown.values.filter { $0.pin.personKey == parent.focus }
                if !theirs.isEmpty || parent.focus == nil { focus = parent.focus }
                show(theirs, in: map)
                if !theirs.isEmpty { userMoved = true }      // placed on purpose: later pins must not undo it
            }
        }

        private func show(_ annotations: [PinAnnotation], in map: MKMapView) {
            guard !annotations.isEmpty else { return }
            movingByCode = true
            hasFitted = true
            map.showAnnotations(annotations, animated: false)
        }

        func mapView(_ map: MKMapView, regionDidChangeAnimated animated: Bool) {
            // the map reports its own first placement too, before there was anything to fit
            if movingByCode { movingByCode = false } else if hasFitted { userMoved = true }
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                let view = (map.dequeueReusableAnnotationView(withIdentifier: "cluster") as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: cluster, reuseIdentifier: "cluster")
                view.annotation = cluster
                view.markerTintColor = PlatformColor.systemPink
                return view
            }
            guard annotation is PinAnnotation else { return nil }
            let view = (map.dequeueReusableAnnotationView(withIdentifier: "pin") as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "pin")
            view.annotation = annotation
            view.markerTintColor = PlatformColor.systemPink
            view.clusteringIdentifier = "person"
            view.canShowCallout = true
            #if os(macOS)
            view.rightCalloutAccessoryView = NSButton(title: "Open", target: nil, action: nil)
            #else
            view.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            #endif
            return view
        }

        /// The own position is drawn above all pins and groups, so that they never hide it (issue #14).
        func mapView(_ map: MKMapView, didAdd views: [MKAnnotationView]) {
            for view in views where view.annotation is MKUserLocation { view.zPriority = .max }
        }

        /// A cluster zooms in to its people instead of opening a callout.
        func mapView(_ map: MKMapView, didSelect view: MKAnnotationView) {
            guard let cluster = view.annotation as? MKClusterAnnotation else { return }
            map.deselectAnnotation(cluster, animated: false)
            map.showAnnotations(cluster.memberAnnotations, animated: true)
        }

        #if os(macOS)
        func mapView(_ map: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: NSControl) { open(view) }
        #else
        func mapView(_ map: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) { open(view) }
        #endif

        private func open(_ view: MKAnnotationView) {
            guard let pin = view.annotation as? PinAnnotation else { return }
            parent?.onOpen(pin.pin.personKey)
        }
    }
}
