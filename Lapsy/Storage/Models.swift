import CoreLocation
import Foundation

extension Activity {
    static func byId(_ id: String) -> Activity {
        all.first { $0.id == id } ?? all[all.count - 1]
    }
}

/// A route that can be written to disk and the database, and turned back into a
/// `GeneratedRoute` that Live Run can follow.
struct StoredRoute: Codable {
    var polyline: String
    var elevations: [Double]
    var surfaceCodes: [Int]
    var steps: [RouteStep]
    var surface: SurfaceMix
    var distanceM: Double
    var durationS: Double
    var ascentM: Double
    var profile: RoutingProfile?

    init(_ route: GeneratedRoute, profile: RoutingProfile?) {
        polyline = Polyline.encode(route.coordinates)
        elevations = route.elevations.map { ($0 * 10).rounded() / 10 }
        surfaceCodes = route.surfaceCodes
        steps = route.steps
        surface = route.surface
        distanceM = route.distanceM
        durationS = route.durationS
        ascentM = route.ascentM
        self.profile = profile
    }

    func route() -> GeneratedRoute {
        GeneratedRoute(
            coordinates: Polyline.decode(polyline),
            elevations: elevations,
            distanceM: distanceM,
            durationS: durationS,
            ascentM: ascentM,
            surface: surface,
            surfaceCodes: surfaceCodes,
            steps: steps
        )
    }
}

/// A finished outing.
struct SavedRun: Codable, Identifiable {
    var id = UUID()
    var activityId: String
    var startedAt: Date
    var durationS: Double
    var distanceM: Double
    var energyKcal: Double
    var startName: String
    /// Where the person actually went (encoded polyline).
    var track: String
    /// The route they were following, if any (encoded polyline).
    var plannedPolyline: String?
    var plannedDistanceM: Double?
    var rating: Int?
    var synced = false

    var activity: Activity { Activity.byId(activityId) }
    var trackCoordinates: [CLLocationCoordinate2D] { Polyline.decode(track) }
    var plannedCoordinates: [CLLocationCoordinate2D] { plannedPolyline.map(Polyline.decode) ?? [] }

    var averagePaceSecPerKm: Double? {
        distanceM > 50 && durationS > 0 ? durationS / (distanceM / 1000) : nil
    }
    var averageSpeedKmh: Double? { averagePaceSecPerKm.map { 3600 / $0 } }
}

/// A route the person kept to run again.
struct SavedRoute: Codable, Identifiable {
    var id = UUID()
    var name: String
    var activityId: String
    var startName: String
    var createdAt: Date
    var route: StoredRoute
    var synced = false

    var activity: Activity { Activity.byId(activityId) }
}

/// Number formatting shared by the history screens.
enum Fmt {
    static func km(_ meters: Double) -> String { String(format: "%.2f", meters / 1000) }

    static func clock(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func pace(_ secPerKm: Double?) -> String {
        guard let sec = secPerKm, sec < 3600 else { return "--:--" }
        return String(format: "%d:%02d", Int(sec) / 60, Int(sec) % 60)
    }

    static func when(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}
