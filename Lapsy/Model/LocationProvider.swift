import CoreLocation
import Observation

/// One-shot current location for choosing a start point. Live tracking for runs is separate.
@MainActor @Observable
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    var coordinate: CLLocationCoordinate2D?
    var denied = false

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var attempts = 0

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            denied = true
        default:
            // Show the last known spot straight away, then refine with a fresh fix.
            if coordinate == nil, let last = manager.location?.coordinate { coordinate = last }
            attempts = 0
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                denied = false
                if coordinate == nil, let last = self.manager.location?.coordinate { coordinate = last }
                attempts = 0
                self.manager.requestLocation()
            case .denied, .restricted:
                denied = true
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in coordinate = c }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // The first fix right after "Allow" often fails with "location unknown". Try again a few times.
        guard (error as? CLError)?.code == .locationUnknown else { return }
        Task { @MainActor in
            guard attempts < 5 else { return }
            attempts += 1
            try? await Task.sleep(for: .seconds(1.5))
            self.manager.requestLocation()
        }
    }
}
