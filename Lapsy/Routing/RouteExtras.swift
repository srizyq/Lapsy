import CoreLocation
import Foundation
import Observation

// MARK: - GPX

enum GPX {
    /// A GPX file (opens in Garmin, Strava, Komoot and most others) for the route.
    static func file(name: String, route: StoredRoute) throws -> URL {
        let coordinates = Polyline.decode(route.polyline)
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Lapsy" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><name>\(escape(name))</name><trkseg>

        """
        for (i, c) in coordinates.enumerated() {
            xml += "    <trkpt lat=\"\(c.latitude)\" lon=\"\(c.longitude)\">"
            if route.elevations.indices.contains(i) { xml += "<ele>\(route.elevations[i])</ele>" }
            xml += "</trkpt>\n"
        }
        xml += "  </trkseg></trk>\n</gpx>\n"

        let safe = name.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(safe.isEmpty ? "Lapsy route" : safe)
            .appendingPathExtension("gpx")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Things along the way

/// Drinking water and toilets close to a route, from OpenStreetMap.
struct Amenities: Equatable {
    var water = 0
    var toilets = 0
}

@MainActor @Observable
final class AmenityFinder {
    static let shared = AmenityFinder()

    private(set) var results: [String: Amenities] = [:]
    @ObservationIgnored private var loading: Set<String> = []

    func amenities(for polyline: String) -> Amenities? { results[polyline] }

    func load(polyline: String) async {
        guard results[polyline] == nil, !loading.contains(polyline) else { return }
        let coordinates = Polyline.decode(polyline)
        guard coordinates.count > 1 else { return }
        loading.insert(polyline)
        defer { loading.remove(polyline) }

        let lats = coordinates.map(\.latitude), lons = coordinates.map(\.longitude)
        let pad = 0.001
        let bbox = "\(lats.min()! - pad),\(lons.min()! - pad),\(lats.max()! + pad),\(lons.max()! + pad)"
        let query = "[out:json][timeout:15];(node[\"amenity\"=\"drinking_water\"](\(bbox));node[\"amenity\"=\"toilets\"](\(bbox)););out;"

        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Lapsy/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = ("data=" + (query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")).data(using: .utf8)

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = json["elements"] as? [[String: Any]] else { return }

        let path = coordinates.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        var found = Amenities()
        for element in elements {
            guard let lat = element["lat"] as? Double, let lon = element["lon"] as? Double,
                  let kind = (element["tags"] as? [String: Any])?["amenity"] as? String else { continue }
            let point = CLLocation(latitude: lat, longitude: lon)
            // Only count what is within about 100 m of the line.
            guard path.contains(where: { $0.distance(from: point) < 100 }) else { continue }
            if kind == "drinking_water" { found.water += 1 } else { found.toilets += 1 }
        }
        results[polyline] = found
    }
}
