import Foundation
import CoreLocation

/// Lower `total` is better.
struct RouteScore {
    /// |actual - requested| / requested.
    var distanceError: Double
    /// Share of the route that retraces ground it already covered (0 = never doubles back).
    var overlap: Double
    /// Isoperimetric quotient, 1 for a circle and near 0 for an out-and-back line.
    var roundness: Double

    var total: Double {
        2.0 * distanceError + 1.5 * overlap + 0.6 * (1 - roundness)
    }

    static let zero = RouteScore(distanceError: 0, overlap: 0, roundness: 0)
}

enum RouteScorer {
    static func score(_ route: GeneratedRoute, requestedM: Double) -> RouteScore {
        let error = requestedM > 0 ? abs(route.distanceM - requestedM) / requestedM : 0
        let points = resample(route.coordinates, every: 20)
        guard points.count > 8 else {
            return RouteScore(distanceError: error, overlap: 1, roundness: 0)
        }
        return RouteScore(
            distanceError: error,
            overlap: overlap(of: points),
            roundness: roundness(of: points)
        )
    }

    // MARK: - Geometry in local meters

    private struct P { var x: Double; var y: Double }

    private static func project(_ coords: [CLLocationCoordinate2D]) -> [P] {
        guard let first = coords.first else { return [] }
        let cosLat = cos(first.latitude * .pi / 180)
        return coords.map {
            P(x: ($0.longitude - first.longitude) * cosLat * 111_320,
              y: ($0.latitude - first.latitude) * 110_540)
        }
    }

    /// Points spaced `spacing` meters apart along the line.
    private static func resample(_ coords: [CLLocationCoordinate2D], every spacing: Double) -> [P] {
        let pts = project(coords)
        guard var prev = pts.first else { return [] }
        var out = [prev]
        var carry = 0.0
        for p in pts.dropFirst() {
            let dx = p.x - prev.x, dy = p.y - prev.y
            let len = (dx * dx + dy * dy).squareRoot()
            if len == 0 { continue }
            var travelled = spacing - carry
            while travelled <= len {
                let t = travelled / len
                out.append(P(x: prev.x + dx * t, y: prev.y + dy * t))
                travelled += spacing
            }
            carry = len - (travelled - spacing)
            prev = p
        }
        return out
    }

    private static func overlap(of pts: [P]) -> Double {
        let cell = 20.0
        func key(_ cx: Int, _ cy: Int) -> Int64 { (Int64(cx) << 32) ^ Int64(cy & 0xFFFF_FFFF) }

        var seen: [Int64: Int] = [:]
        var retraced = 0
        for (i, p) in pts.enumerated() {
            let cx = Int((p.x / cell).rounded(.down))
            let cy = Int((p.y / cell).rounded(.down))
            var hit = false
            outer: for dx in -1...1 {
                for dy in -1...1 {
                    if let j = seen[key(cx + dx, cy + dy)], i - j > 5, j > 5 {
                        hit = true
                        break outer
                    }
                }
            }
            if hit { retraced += 1 }
            let k = key(cx, cy)
            if seen[k] == nil { seen[k] = i }
        }
        return Double(retraced) / Double(pts.count)
    }

    private static func roundness(of pts: [P]) -> Double {
        var area = 0.0
        var perimeter = 0.0
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            area += a.x * b.y - b.x * a.y
            perimeter += ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
        }
        area = abs(area) / 2
        guard perimeter > 0 else { return 0 }
        return min(1, 4 * .pi * area / (perimeter * perimeter))
    }
}
