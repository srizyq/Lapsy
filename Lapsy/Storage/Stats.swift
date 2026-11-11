import CoreLocation
import Foundation

/// How far back the Activity screen looks.
enum StatsPeriod: String, CaseIterable, Identifiable {
    case week, month, year, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "This week"
        case .month: "Month"
        case .year: "Year"
        case .all: "All-time"
        }
    }

    /// Days covered, or nil for everything.
    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 365
        case .all: nil
        }
    }

    var comparison: String {
        switch self {
        case .week: "last week"
        case .month: "last month"
        case .year: "last year"
        case .all: ""
        }
    }
}

struct StatsBucket: Identifiable {
    let id: Int
    let label: String
    let km: Double
}

/// Everything shown on the Activity screen, worked out from the saved outings.
struct PeriodStats {
    var runs: [SavedRun]
    var distanceM: Double
    var durationS: Double
    var ascentM: Double
    var maxAscentM: Double
    var avgPaceSecPerKm: Double?
    /// Change against the period just before this one (nil when there is nothing to compare).
    var distanceChange: Double?
    var paceChangeSec: Double?
    var buckets: [StatsBucket]
    var bestBucket: Int?
    /// Share of the ground covered in this period that no earlier outing had been on.
    var newGroundShare: Double?
    /// Paved / path / unknown share, over the outings that followed a planned route.
    var terrain: SurfaceMix?

    static func make(_ all: [SavedRun], period: StatsPeriod, now: Date = Date()) -> PeriodStats {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var start: Date?
        var prevStart: Date?
        if let days = period.days {
            start = calendar.date(byAdding: .day, value: -(days - 1), to: today)
            prevStart = start.flatMap { calendar.date(byAdding: .day, value: -days, to: $0) }
        }
        let runs = all.filter { start == nil || $0.startedAt >= start! }
        let prev = all.filter { run in
            guard let start, let prevStart else { return false }
            return run.startedAt >= prevStart && run.startedAt < start
        }

        func pace(_ list: [SavedRun]) -> Double? {
            let d = list.reduce(0) { $0 + $1.distanceM }
            let t = list.reduce(0) { $0 + $1.durationS }
            return d > 50 && t > 0 ? t / (d / 1000) : nil
        }

        let distance = runs.reduce(0) { $0 + $1.distanceM }
        let prevDistance = prev.reduce(0) { $0 + $1.distanceM }
        let avgPace = pace(runs)
        let prevPace = pace(prev)

        var stats = PeriodStats(
            runs: runs,
            distanceM: distance,
            durationS: runs.reduce(0) { $0 + $1.durationS },
            ascentM: runs.reduce(0) { $0 + ($1.ascentM ?? 0) },
            maxAscentM: runs.map { $0.ascentM ?? 0 }.max() ?? 0,
            avgPaceSecPerKm: avgPace,
            distanceChange: prevDistance > 0 ? (distance - prevDistance) / prevDistance : nil,
            paceChangeSec: (avgPace != nil && prevPace != nil) ? avgPace! - prevPace! : nil,
            buckets: [],
            bestBucket: nil,
            newGroundShare: nil,
            terrain: nil
        )
        stats.buckets = buckets(for: runs, period: period, today: today, calendar: calendar)
        if let best = stats.buckets.max(by: { $0.km < $1.km }), best.km > 0 { stats.bestBucket = best.id }
        if period != .all, let start { stats.newGroundShare = newGround(runs: runs, before: start, all: all) }
        stats.terrain = terrain(runs)
        return stats
    }

    // MARK: - Pieces

    private static func buckets(for runs: [SavedRun], period: StatsPeriod, today: Date, calendar: Calendar) -> [StatsBucket] {
        func km(from: Date, to: Date) -> Double {
            runs.filter { $0.startedAt >= from && $0.startedAt < to }.reduce(0) { $0 + $1.distanceM } / 1000
        }
        switch period {
        case .week:
            return (0..<7).map { i in
                let day = calendar.date(byAdding: .day, value: i - 6, to: today)!
                let next = calendar.date(byAdding: .day, value: 1, to: day)!
                let letter = day.formatted(.dateTime.weekday(.narrow))
                return StatsBucket(id: i, label: letter, km: km(from: day, to: next))
            }
        case .month:
            // Six blocks of five days.
            return (0..<6).map { i in
                let from = calendar.date(byAdding: .day, value: -29 + i * 5, to: today)!
                let to = calendar.date(byAdding: .day, value: 5, to: from)!
                return StatsBucket(id: i, label: from.formatted(.dateTime.day()), km: km(from: from, to: to))
            }
        case .year, .all:
            let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: today))!
            var count = 12
            if period == .all, let first = runs.map(\.startedAt).min() {
                let firstMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: first))!
                let months = calendar.dateComponents([.month], from: firstMonth, to: thisMonth).month ?? 0
                count = min(12, max(1, months + 1))
            }
            return (0..<count).map { i in
                let from = calendar.date(byAdding: .month, value: i - (count - 1), to: thisMonth)!
                let to = calendar.date(byAdding: .month, value: 1, to: from)!
                return StatsBucket(id: i, label: from.formatted(.dateTime.month(.narrow)), km: km(from: from, to: to))
            }
        }
    }

    /// Ground is counted in squares about 100 m wide.
    static func cells(_ coordinates: [CLLocationCoordinate2D]) -> Set<Int64> {
        var set = Set<Int64>()
        for c in coordinates {
            let y = Int64((c.latitude * 1000).rounded(.down))
            let x = Int64((c.longitude * 1000).rounded(.down))
            set.insert(y &* 1_000_000 &+ x)
        }
        return set
    }

    private static func newGround(runs: [SavedRun], before start: Date, all: [SavedRun]) -> Double? {
        guard !runs.isEmpty else { return nil }
        var now = Set<Int64>()
        for run in runs { now.formUnion(cells(run.trackCoordinates)) }
        guard !now.isEmpty else { return nil }
        var earlier = Set<Int64>()
        for run in all where run.startedAt < start { earlier.formUnion(cells(run.trackCoordinates)) }
        return Double(now.subtracting(earlier).count) / Double(now.count)
    }

    private static func terrain(_ runs: [SavedRun]) -> SurfaceMix? {
        var mix = SurfaceMix()
        var total = 0.0
        for run in runs {
            guard let s = run.surface, run.distanceM > 0 else { continue }
            mix.paved += s.paved * run.distanceM
            mix.unpaved += s.unpaved * run.distanceM
            mix.unknown += s.unknown * run.distanceM
            total += run.distanceM
        }
        guard total > 0 else { return nil }
        return SurfaceMix(paved: mix.paved / total, unpaved: mix.unpaved / total, unknown: mix.unknown / total)
    }
}

/// Personal bests across everything saved, per activity.
struct Records {
    private var longest: [String: UUID] = [:]
    private var fastest: [String: UUID] = [:]
    private var mostClimb: [String: UUID] = [:]

    init(_ runs: [SavedRun]) {
        for (activity, list) in Dictionary(grouping: runs, by: \.activityId) where list.count > 1 {
            longest[activity] = list.max { $0.distanceM < $1.distanceM }?.id
            fastest[activity] = list.filter { $0.distanceM >= 1000 }
                .min { ($0.averagePaceSecPerKm ?? .infinity) < ($1.averagePaceSecPerKm ?? .infinity) }?.id
            let climbers = list.filter { ($0.ascentM ?? 0) > 0 }
            mostClimb[activity] = climbers.max { ($0.ascentM ?? 0) < ($1.ascentM ?? 0) }?.id
        }
    }

    func badges(for run: SavedRun) -> [String] {
        var out: [String] = []
        if longest[run.activityId] == run.id { out.append("Longest") }
        if fastest[run.activityId] == run.id { out.append("Fastest pace") }
        if mostClimb[run.activityId] == run.id { out.append("Most climb") }
        return out
    }
}

extension StatsPeriod {
    /// Weekly distance goal in km, kept on this phone. 0 means none set.
    static var weeklyGoalKm: Double {
        get { UserDefaults.standard.double(forKey: "weeklyGoalKm") }
        set { UserDefaults.standard.set(newValue, forKey: "weeklyGoalKm") }
    }
}
