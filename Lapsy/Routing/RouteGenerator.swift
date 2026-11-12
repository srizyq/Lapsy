import Foundation
import CoreLocation

struct GenerationResult {
    var best: GeneratedRoute
    /// Every candidate that came back, best first.
    var ranked: [GeneratedRoute]
    /// How many API requests were made in total.
    var requested: Int
    /// True when a second, length-corrected batch was needed.
    var corrected: Bool
    /// Set when a preference could not be applied, in plain words.
    var note: String? = nil
}

/// Asks the routing API for several routes in parallel, scores them, and keeps the best.
/// If the best one is far from the target distance (common on trails, where the API
/// overshoots), it rescales the request by the observed ratio and tries again once.
struct RouteGenerator {
    var service = RouteService()
    var candidatesPerBatch = 6
    var acceptableError = 0.10

    func bestRoute(
        start: CLLocationCoordinate2D,
        lengthM: Double,
        profile: RoutingProfile,
        round: Int,
        options: RouteOptions
    ) async throws -> GenerationResult {
        switch options.shape {
        case .loop, .outAndBack:
            return try await lengthTargeted(start: start, lengthM: lengthM, profile: profile, round: round, options: options)
        case .pointToPoint:
            guard let end = options.destination else {
                throw RouteError.badResponse("Choose where you want to go first.")
            }
            var route = try await service.route(through: [start, end], profile: profile, avoidSteps: options.avoidSteps)
            route.score = RouteScorer.score(route, requestedM: route.distanceM, options: options)
            return GenerationResult(best: route, ranked: [route], requested: 1, corrected: false)
        }
    }

    private func lengthTargeted(
        start: CLLocationCoordinate2D,
        lengthM: Double,
        profile: RoutingProfile,
        round: Int,
        options: RouteOptions
    ) async throws -> GenerationResult {
        var all = try await batch(
            start: start, targetM: lengthM, requestM: lengthM,
            profile: profile, seedBase: round * 1000, options: options
        )
        var requests = candidatesPerBatch
        var corrected = false

        let first = all.min { $0.score.total < $1.score.total }
        if let first, first.score.distanceError > acceptableError {
            // Median ratio of what we got to what we asked for.
            let ratios = all.map { $0.distanceM / lengthM }.sorted()
            let median = ratios[ratios.count / 2]
            if median > 0 {
                let adjusted = lengthM / median
                if let more = try? await batch(
                    start: start, targetM: lengthM, requestM: adjusted,
                    profile: profile, seedBase: round * 1000 + 500, options: options
                ) {
                    all += more
                    requests += candidatesPerBatch
                    corrected = true
                }
            }
        }

        var note: String?
        if options.preferGreen {
            if let shares = await GreenFinder.shares(for: all) {
                for i in all.indices { all[i].score.preferencePenalty += 1.5 * (1 - shares[i]) }
            } else {
                note = "Couldn't check for green areas just now, so this route may not be the greenest."
            }
        }

        all.sort { $0.score.total < $1.score.total }
        return GenerationResult(best: all[0], ranked: all, requested: requests, corrected: corrected, note: note)
    }

    /// One parallel batch. Throws only if every request failed.
    private func batch(
        start: CLLocationCoordinate2D,
        targetM: Double,
        requestM: Double,
        profile: RoutingProfile,
        seedBase: Int,
        options: RouteOptions
    ) async throws -> [GeneratedRoute] {
        let outcomes = await withTaskGroup(of: Result<GeneratedRoute, Error>.self) { group in
            for i in 0..<candidatesPerBatch {
                group.addTask {
                    do {
                        var route: GeneratedRoute
                        if options.shape == .outAndBack {
                            // Walk out to a point about half the length away, then come back.
                            // Different bearings give different out-and-back routes.
                            let bearing = Double((seedBase / 500) * 37 + i * 60 + (seedBase % 500) * 7)
                            let straight = (requestM / 2) / 1.35
                            let far = Self.point(from: start, bearingDegrees: bearing, meters: straight)
                            route = try await service.route(
                                through: [start, far, start], profile: profile, avoidSteps: options.avoidSteps
                            )
                        } else {
                            // Varying the waypoint count gives differently shaped loops.
                            route = try await service.generateLoop(
                                start: start,
                                lengthM: requestM,
                                profile: profile,
                                seed: seedBase + i,
                                points: 3 + i % 3,
                                options: options
                            )
                        }
                        route.seed = seedBase + i
                        route.score = RouteScorer.score(route, requestedM: targetM, options: options)
                        return .success(route)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var collected: [Result<GeneratedRoute, Error>] = []
            for await outcome in group { collected.append(outcome) }
            return collected
        }

        var routes: [GeneratedRoute] = []
        var firstError: Error?
        for outcome in outcomes {
            switch outcome {
            case .success(let route): routes.append(route)
            case .failure(let error): firstError = firstError ?? error
            }
        }
        guard !routes.isEmpty else {
            throw firstError ?? RouteError.badResponse("No route returned.")
        }
        return routes
    }

    private static func point(from c: CLLocationCoordinate2D, bearingDegrees: Double, meters: Double) -> CLLocationCoordinate2D {
        let r = 6_371_000.0
        let d = meters / r
        let b = bearingDegrees * .pi / 180
        let lat1 = c.latitude * .pi / 180, lon1 = c.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(b))
        let lon2 = lon1 + atan2(sin(b) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}
