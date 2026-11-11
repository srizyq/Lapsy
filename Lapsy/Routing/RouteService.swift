import Foundation
import CoreLocation

enum RoutingProfile: String, CaseIterable {
    case footWalking = "foot-walking"
    case footHiking = "foot-hiking"
    case cyclingRegular = "cycling-regular"
    case cyclingRoad = "cycling-road"
    case cyclingMountain = "cycling-mountain"
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

struct GeneratedRoute {
    var coordinates: [CLLocationCoordinate2D]
    var elevations: [Double]
    var distanceM: Double
    var durationS: Double
    var ascentM: Double
    var surface: SurfaceMix
    var stepCount: Int
    var score: RouteScore = .zero
    var seed: Int = 0
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
/// with the same request shape, so the key stays on the server.
struct RouteService {
    func generateLoop(
        start: CLLocationCoordinate2D,
        lengthM: Double,
        profile: RoutingProfile,
        seed: Int,
        points: Int = 3
    ) async throws -> GeneratedRoute {
        let key = Secrets.openRouteServiceKey
        guard !key.isEmpty else { throw RouteError.missingKey }

        let url = URL(string: "https://api.openrouteservice.org/v2/directions/\(profile.rawValue)/geojson")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "coordinates": [[start.longitude, start.latitude]],
            "options": ["round_trip": ["length": lengthM, "points": points, "seed": seed]],
            "elevation": true,
            "extra_info": ["surface"],
            "instructions": true,
        ]
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

        return GeneratedRoute(
            coordinates: coords,
            elevations: elevations,
            distanceM: feature.properties.summary.distance,
            durationS: feature.properties.summary.duration,
            ascentM: feature.properties.ascent ?? 0,
            surface: mix,
            stepCount: feature.properties.segments?.first?.steps?.count ?? 0
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

    struct Step: Decodable {}

    struct Extras: Decodable {
        let surface: Surface?
    }

    struct Surface: Decodable {
        let summary: [SurfaceEntry]
    }

    struct SurfaceEntry: Decodable {
        let value: Double
        let distance: Double
    }
}
