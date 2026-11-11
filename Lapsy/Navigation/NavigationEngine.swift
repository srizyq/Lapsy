import CoreLocation

/// Where the runner is relative to the route.
struct NavigationState {
    /// Index of the route segment the runner is on (between vertex i and i+1).
    var routeIndex = 0
    var distanceAlongM = 0.0
    var remainingM = 0.0
    /// Straight-line distance from the runner to the route line.
    var offRouteM = 0.0
    var nextStep: RouteStep?
    var nextStepIndex: Int?
    var distanceToNextM: Double?
    var arrived = false
}

/// Pure route-following logic: no GPS, no UI, so it can be tested with plain coordinates.
struct NavigationEngine {
    let coords: [CLLocationCoordinate2D]
    let steps: [RouteStep]
    /// Distance in meters from the route start to each vertex.
    let cumulative: [Double]
    private var lastIndex = 0

    var totalM: Double { cumulative.last ?? 0 }

    init(route: GeneratedRoute) {
        coords = route.coordinates
        steps = route.steps
        var running = 0.0
        var out: [Double] = [0]
        for i in 1..<max(1, route.coordinates.count) {
            running += Self.meters(route.coordinates[i - 1], route.coordinates[i])
            out.append(running)
        }
        cumulative = route.coordinates.isEmpty ? [] : out
    }

    mutating func update(_ here: CLLocationCoordinate2D) -> NavigationState {
        guard coords.count >= 2 else { return NavigationState() }
        let lastSegment = coords.count - 2

        // Search near the last known position first, so a loop that passes close to
        // itself does not make us jump to the wrong part of the route.
        var best = nearest(here, from: max(0, lastIndex - 3), to: min(lastSegment, lastIndex + 80))
        if best.distance > 60 {
            let global = nearest(here, from: 0, to: lastSegment)
            if global.distance < best.distance { best = global }
        }
        lastIndex = best.index

        let segLen = cumulative[best.index + 1] - cumulative[best.index]
        let along = cumulative[best.index] + best.t * segLen
        let remaining = max(0, totalM - along)

        var state = NavigationState(
            routeIndex: best.index,
            distanceAlongM: along,
            remainingM: remaining,
            offRouteM: best.distance,
            arrived: remaining < 30 && best.index > coords.count / 2
        )
        if let i = steps.firstIndex(where: { $0.startIndex > best.index }) {
            state.nextStepIndex = i
            state.nextStep = steps[i]
            state.distanceToNextM = max(0, cumulative[min(steps[i].startIndex, cumulative.count - 1)] - along)
        }
        return state
    }

    // MARK: - Geometry

    private func nearest(
        _ p: CLLocationCoordinate2D, from lo: Int, to hi: Int
    ) -> (index: Int, t: Double, distance: Double) {
        var best = (index: lo, t: 0.0, distance: Double.greatestFiniteMagnitude)
        guard lo <= hi else { return best }
        for i in lo...hi {
            let r = Self.project(p, onto: coords[i], coords[i + 1])
            if r.distance < best.distance { best = (i, r.t, r.distance) }
        }
        return best
    }

    /// Distance from `p` to segment a-b in meters, and where along the segment (0...1) it falls.
    static func project(
        _ p: CLLocationCoordinate2D, onto a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D
    ) -> (distance: Double, t: Double) {
        let cosLat = cos(p.latitude * .pi / 180)
        func xy(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            ((c.longitude - p.longitude) * cosLat * 111_320, (c.latitude - p.latitude) * 110_540)
        }
        let A = xy(a), B = xy(b)
        let dx = B.x - A.x, dy = B.y - A.y
        let len2 = dx * dx + dy * dy
        let t = len2 == 0 ? 0 : min(1, max(0, -(A.x * dx + A.y * dy) / len2))
        let cx = A.x + t * dx, cy = A.y + t * dy
        return ((cx * cx + cy * cy).squareRoot(), t)
    }

    static func meters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
}
