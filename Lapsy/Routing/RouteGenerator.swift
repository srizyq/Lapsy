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
}

/// Asks the routing API for several loops in parallel, scores them, and keeps the best.
/// If the best loop is far from the target distance (common on trails, where the API
/// overshoots), it rescales the request by the observed ratio and tries again once.
struct RouteGenerator {
    var service = RouteService()
    var candidatesPerBatch = 6
    var acceptableError = 0.10

    func bestLoop(
        start: CLLocationCoordinate2D,
        lengthM: Double,
        profile: RoutingProfile,
        round: Int,
        options: RouteOptions = RouteOptions()
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

        all.sort { $0.score.total < $1.score.total }
        return GenerationResult(best: all[0], ranked: all, requested: requests, corrected: corrected)
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
                        // Varying the waypoint count gives differently shaped loops.
                        var route = try await service.generateLoop(
                            start: start,
                            lengthM: requestM,
                            profile: profile,
                            seed: seedBase + i,
                            points: 3 + i % 3,
                            options: options
                        )
                        route.seed = seedBase + i
                        route.score = RouteScorer.score(route, requestedM: targetM, preferPaved: options.preferPaved)
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
}
