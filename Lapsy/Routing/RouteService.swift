import Foundation
import CoreLocation

enum RoutingProfile: String, CaseIterable {
    case footWalking = "foot-walking"
    case footHiking = "foot-hiking"
    case cyclingRegular = "cycling-regular"
    case cyclingRoad = "cycling-road"
    case cyclingMountain = "cycling-mountain"
    case cyclingElectric = "cycling-electric"
    case wheelchair = "wheelchair"
}

struct SurfaceMix {
    var paved: Double = 0
    var unpaved: Double = 0
    var unknown: Double = 0

    /// ORS surface codes. 0 and 13 are treated as unknown.
    static func category(for code: Int) -> WritableKeyPath<SurfaceMix, Double> {
        switch code {
        case 1, 3, 4, 5, 6, 7, 14: return \.paved
        case 2, 8, 9, 10, 11, 12, 15, 16, 17, 18: return \.unpaved
        default: return \.unknown
        }
    }
}

/// One turn instruction. The maneuver happens at `startIndex`, then the route
/// continues along `name` until `endIndex`.
struct RouteStep {
    var instruction: String
    var name: String
    var distanceM: Double
    /// ORS maneuver code: 0 left, 1 right, 2 sharp left, 3 sharp right, 4 slight left,
    /// 5 slight right, 6 straight, 7 roundabout, 8 exit roundabout, 9 u-turn,
    /// 10 arrive, 11 depart, 12 keep left, 13 keep right.
    var type: Int
    var startIndex: Int
    var endIndex: Int
}

struct GeneratedRoute {
    var coordinates: [CLLocationCoordinate2D]
    var elevations: [Double]
    var distanceM: Double
    var durationS: Double
    var ascentM: Double
    var surface: SurfaceMix
    /// ORS surface code for each coordinate (same length as `coordinates`), or empty.
    var surfaceCodes: [Int] = []
    var steps: [RouteStep] = []
    var score: RouteScore = .zero
    var seed: Int = 0

    var stepCount: Int { steps.count }
}

enum RouteError: LocalizedError {
    case missingKey
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "No routing key set in Secrets.swift."
        case .badResponse(let message): message
        }
    }
}

/// Dev-only direct client. The shipped app will call a Supabase edge function
/// with the same request shapes, so the key stays on the server.
struct RouteService {
    func generateLoop(
        start: CLLocationCoordinate2D,
        lengthM: Double,
        profile: RoutingProfile,
        seed: Int,
        points: Int = 3,
        options: RouteOptions = RouteOptions()
    ) async throws -> GeneratedRoute {
        var apiOptions: [String: Any] = [
            "round_trip": ["length": lengthM, "points": points, "seed": seed]
        ]
        if options.avoidSteps {
            apiOptions["avoid_features"] = ["steps"]
        }
        return try await send(
            body: [
                "coordinates": [[start.longitude, start.latitude]],
                "options": apiOptions,
                "elevation": true,
                "extra_info": ["surface"],
                "instructions": true,
            ],
            profile: profile
        )
    }

    /// Directions through two or more points, used to reroute back onto a route.
    func route(
        through points: [CLLocationCoordinate2D],
        profile: RoutingProfile
    ) async throws -> GeneratedRoute {
        try await send(
            body: [
                "coordinates": points.map { [$0.longitude, $0.latitude] },
                "elevation": true,
                "extra_info": ["surface"],
                "instructions": true,
            ],
            profile: profile
        )
    }

    private func send(body: [String: Any], profile: RoutingProfile) async throws -> GeneratedRoute {
        let key = Secrets.openRouteServiceKey
        guard !key.isEmpty else { throw RouteError.missingKey }

        let url = URL(string: "https://api.openrouteservice.org/v2/directions/\(profile.rawValue)/geojson")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw RouteError.badResponse(Self.errorMessage(from: data, status: status))
        }
        return try Self.parse(data)
    }

    private static func errorMessage(from data: Data, status: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return "Routing error \(status): \(message)"
        }
        return "Routing error \(status)"
    }

    private static func parse(_ data: Data) throws -> GeneratedRoute {
        let decoded = try JSONDecoder().decode(ORSResponse.self, from: data)
        guard let feature = decoded.features.first else {
            throw RouteError.badResponse("No route returned.")
        }
        let points = feature.geometry.coordinates
        let coords = points.compactMap { p -> CLLocationCoordinate2D? in
            p.count >= 2 ? CLLocationCoordinate2D(latitude: p[1], longitude: p[0]) : nil
        }
        let elevations = points.map { $0.count >= 3 ? $0[2] : 0 }

        var mix = SurfaceMix()
        let total = feature.properties.summary.distance
        for entry in feature.properties.extras?.surface?.summary ?? [] {
            let share = total > 0 ? entry.distance / total : 0
            mix[keyPath: SurfaceMix.category(for: Int(entry.value))] += share
        }

        // Per-point surface: ORS gives [startIndex, endIndex, code] ranges.
        var codes = [Int](repeating: 0, count: coords.count)
        for range in feature.properties.extras?.surface?.values ?? [] where range.count == 3 {
            let (start, end, code) = (range[0], range[1], range[2])
            guard start >= 0, start < coords.count else { continue }
            for i in start...min(end, coords.count - 1) { codes[i] = code }
        }

        let steps = (feature.properties.segments ?? [])
            .flatMap { $0.steps ?? [] }
            .map {
                RouteStep(
                    instruction: $0.instruction ?? "",
                    name: $0.name ?? "",
                    distanceM: $0.distance ?? 0,
                    type: $0.type ?? 6,
                    startIndex: $0.way_points?.first ?? 0,
                    endIndex: $0.way_points?.last ?? 0
                )
            }

        return GeneratedRoute(
            coordinates: coords,
            elevations: elevations,
            distanceM: feature.properties.summary.distance,
            durationS: feature.properties.summary.duration,
            ascentM: feature.properties.ascent ?? 0,
            surface: mix,
            surfaceCodes: codes,
            steps: steps
        )
    }
}

// MARK: - Response shape

private struct ORSResponse: Decodable {
    let features: [Feature]

    struct Feature: Decodable {
        let geometry: Geometry
        let properties: Properties
    }

    struct Geometry: Decodable {
        let coordinates: [[Double]]
    }

    struct Properties: Decodable {
        let summary: Summary
        let ascent: Double?
        let segments: [Segment]?
        let extras: Extras?
    }

    struct Summary: Decodable {
        let distance: Double
        let duration: Double
    }

    struct Segment: Decodable {
        let steps: [Step]?
    }

    struct Step: Decodable {
        let distance: Double?
        let type: Int?
        let instruction: String?
        let name: String?
        let way_points: [Int]?
    }

    struct Extras: Decodable {
        let surface: Surface?
    }

    struct Surface: Decodable {
        let summary: [SurfaceEntry]
        let values: [[Int]]?
    }

    struct SurfaceEntry: Decodable {
        let value: Double
        let distance: Double
    }
}
