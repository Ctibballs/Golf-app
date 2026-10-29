import SwiftUI
import CoreLocation
import MapKit
import Observation
import GolfKit

/// Wraps CLLocationManager for SwiftUI. High accuracy only while a round is being played.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var location: CLLocation?
    /// Whether continuous updates are wanted (they begin once permission is granted).
    private(set) var isUpdating = false
    private(set) var lastError: String?
    private var wantsOneShot = false

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2
        manager.activityType = .fitness
    }

    var point: GeoPoint? { location.map { GeoPoint($0.coordinate) } }

    /// Horizontal accuracy in metres, when known.
    var accuracy: Double? {
        guard let location, location.horizontalAccuracy >= 0 else { return nil }
        return location.horizontalAccuracy
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func requestAccess() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
        isUpdating = true
        requestAccess()
        if isAuthorized { manager.startUpdatingLocation() }
    }

    func stop() {
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    /// One-off fix for things like nearby course search.
    func requestOneShot() {
        requestAccess()
        if isAuthorized {
            manager.requestLocation()
        } else {
            wantsOneShot = true
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.authorization = status
            guard self.isAuthorized else { return }
            // Resume whatever was asked for before permission arrived.
            if self.isUpdating { self.manager.startUpdatingLocation() }
            if self.wantsOneShot {
                self.wantsOneShot = false
                self.manager.requestLocation()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor [weak self] in
            // Ignore stale or very poor fixes.
            guard latest.horizontalAccuracy >= 0, latest.horizontalAccuracy < 100,
                  abs(latest.timestamp.timeIntervalSinceNow) < 30 else { return }
            self?.location = latest
            self?.lastError = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.lastError = message }
    }
}

// MARK: - Coordinate bridging

extension GeoPoint {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension Array where Element == GeoPoint {
    var coordinates: [CLLocationCoordinate2D] { map(\.coordinate) }
}

extension GeoBounds {
    /// A map region around the bounds with some breathing room.
    func region(padding: Double = 1.25) -> MKCoordinateRegion {
        MKCoordinateRegion(
            center: center.coordinate,
            span: MKCoordinateSpan(
                latitudeDelta: max(0.002, latitudeSpan * padding),
                longitudeDelta: max(0.002, longitudeSpan * padding)
            )
        )
    }
}

extension HoleLayout {
    /// Camera looking down the hole from behind the tee, green at the top of the screen.
    func camera(pitch: Double = 0, zoom: Double = 1) -> MapCamera? {
        guard let tee = teePoint, let green = greenCenter, let bearing else { return nil }
        let middle = GeoMath.interpolate(tee, green, fraction: 0.5)
        let length = max(80, GeoMath.distance(tee, green))
        return MapCamera(centerCoordinate: middle.coordinate, distance: length * 2.6 / zoom, heading: bearing, pitch: pitch)
    }
}
