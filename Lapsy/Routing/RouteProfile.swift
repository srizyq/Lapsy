import CoreLocation

/// One point on the route with its distance along the route and elevation.
struct ProfilePoint: Identifiable {
    let id: Int
    let km: Double
    let elevation: Double
    let coordinate: CLLocationCoordinate2D
}

extension GeneratedRoute {
    /// Route points with cumulative distance, thinned to about 120 for charting.
    var profilePoints: [ProfilePoint] {
        var all: [ProfilePoint] = []
        var total = 0.0
        var previous: CLLocation?
        for (i, c) in coordinates.enumerated() {
            let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
            if let previous { total += here.distance(from: previous) }
            previous = here
            all.append(ProfilePoint(
                id: i,
                km: total / 1000,
                elevation: i < elevations.count ? elevations[i] : 0,
                coordinate: c
            ))
        }
        let step = max(1, all.count / 120)
        return all.enumerated()
            .filter { $0.offset % step == 0 || $0.offset == all.count - 1 }
            .map(\.element)
    }
}
