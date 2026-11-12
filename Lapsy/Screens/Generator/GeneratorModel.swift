import SwiftUI
import MapKit
import Observation

@MainActor @Observable
final class GeneratorModel {
    var activity: Activity = Activity.all[0]
    var pathType: PathType = .mixed
    var avoidSteps = false
    var avoidBusyRoads = false
    var preferGreen = false
    var elevationBias: ElevationBias = .any
    var shape: RouteKind = .loop
    /// Where a point-to-point route ends.
    var destination: StartPoint?
    var lengthKm = 5.0
    var start = StartPoint.fallback
    var usingCurrentLocation = true

    var result: GenerationResult?
    var selected = 0
    var loading = false
    var errorText: String?
    /// Something worth knowing about the result that is not an error.
    var noteText: String?
    var round = 0
    /// Index into `profilePoints` while the user drags on the elevation chart.
    var scrubIndex: Int?
    /// Set by "Regenerate" elsewhere: make a route as soon as the Generator opens.
    var autoGenerate = false

    init() {
        #if DEBUG
        // Test hooks: SIMCTL_CHILD_LAPSY_LAT / _LON / _ACTIVITY / _PATH / _KM
        let env = ProcessInfo.processInfo.environment
        if let lat = env["LAPSY_LAT"].flatMap(Double.init), let lon = env["LAPSY_LON"].flatMap(Double.init) {
            start = StartPoint(name: "Test start", coordinate: .init(latitude: lat, longitude: lon))
            usingCurrentLocation = false
        }
        if let id = env["LAPSY_ACTIVITY"], let a = Activity.all.first(where: { $0.id == id }) { activity = a }
        if let raw = env["LAPSY_PATH"], let p = PathType(rawValue: raw) { pathType = p }
        if let km = env["LAPSY_KM"].flatMap(Double.init) { lengthKm = km }
        #endif
    }

    // MARK: - Derived

    var lengthRange: ClosedRange<Double> { activity.group == .wheels ? 5...80 : 1...30 }
    var profile: RoutingProfile? { activity.profile(for: pathType) }

    /// The best loop plus up to three others that are not obviously bad.
    var candidates: [GeneratedRoute] {
        guard let ranked = result?.ranked, let first = ranked.first else { return [] }
        let rest = ranked.dropFirst().filter {
            $0.score.overlap < 0.15 && $0.score.roundness > 0.25 && $0.score.distanceError < 0.3
        }
        return [first] + Array(rest.prefix(3))
    }

    var route: GeneratedRoute? {
        let c = candidates
        return c.indices.contains(selected) ? c[selected] : c.first
    }

    var profilePoints: [ProfilePoint] { route?.profilePoints ?? [] }

    // MARK: - Actions

    func setActivity(_ new: Activity) {
        activity = new
        lengthKm = min(max(lengthKm, lengthRange.lowerBound), lengthRange.upperBound)
    }

    func reset() {
        result = nil
        errorText = nil
        noteText = nil
        selected = 0
        round = 0
        scrubIndex = nil
    }

    func nextCandidate() {
        guard candidates.count > 1 else { return }
        selected = (selected + 1) % candidates.count
        scrubIndex = nil
    }

    var options: RouteOptions {
        var o = RouteOptions(pathType: pathType, avoidSteps: avoidSteps)
        o.avoidBusyRoads = avoidBusyRoads
        o.preferGreen = preferGreen
        o.elevationBias = elevationBias
        o.shape = shape
        o.destination = destination?.coordinate
        return o
    }

    func generate() async {
        guard let profile else { return }
        loading = true
        errorText = nil
        noteText = nil
        if result != nil { round += 1 }
        defer { loading = false }
        do {
            let generated = try await RouteGenerator().bestRoute(
                start: start.coordinate,
                lengthM: lengthKm * 1000,
                profile: profile,
                round: round,
                options: options
            )
            result = generated
            noteText = generated.note
            selected = 0
            scrubIndex = nil
        } catch {
            errorText = error.localizedDescription
        }
    }
}
