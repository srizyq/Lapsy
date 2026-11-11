import CoreLocation

enum RouteReroute {
    /// Joins a detour (from where the runner is now to a point on the route) onto
    /// the rest of the original route after `rejoin`.
    static func merge(detour: GeneratedRoute, original: GeneratedRoute, rejoin: Int) -> GeneratedRoute {
        let tailStart = min(rejoin + 1, original.coordinates.count)
        let tailCoords = Array(original.coordinates[tailStart...])
        let tailElevations = original.elevations.count >= original.coordinates.count
            ? Array(original.elevations[tailStart...]) : []

        // Original vertex k (k > rejoin) lands at k + offset in the merged route.
        let offset = detour.coordinates.count - (rejoin + 1)

        // Drop the detour's own "arrive" step: the route carries on past it.
        var steps = detour.steps.filter { $0.type != 10 }
        for step in original.steps where step.startIndex > rejoin {
            var moved = step
            moved.startIndex += offset
            moved.endIndex += offset
            steps.append(moved)
        }

        let tailDistance = max(0, original.distanceM - distanceUpTo(rejoin, in: original))
        var merged = original
        merged.coordinates = detour.coordinates + tailCoords
        merged.elevations = detour.elevations + tailElevations
        merged.surfaceCodes = []   // no longer lines up with the new geometry
        merged.steps = steps
        merged.distanceM = detour.distanceM + tailDistance
        merged.durationS = detour.durationS + original.durationS * (tailDistance / max(1, original.distanceM))
        return merged
    }

    private static func distanceUpTo(_ index: Int, in route: GeneratedRoute) -> Double {
        var total = 0.0
        for i in 1..<max(1, min(index + 1, route.coordinates.count)) {
            total += NavigationEngine.meters(route.coordinates[i - 1], route.coordinates[i])
        }
        return total
    }
}
