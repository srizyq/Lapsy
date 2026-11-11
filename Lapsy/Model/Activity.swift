import Foundation

enum ActivityGroup: String, CaseIterable {
    case onFoot = "On foot"
    case wheels = "Wheels"
    case accessible = "Accessible"
    case tracking = "Tracking only"
}

/// Data-driven activity list. Adding an activity is one line in `Activity.all`.
struct Activity: Identifiable, Hashable {
    let id: String
    let name: String
    /// SF Symbol name.
    let icon: String
    let group: ActivityGroup
    /// Routing profile, or nil for activities that can only be tracked (no road network).
    let profile: RoutingProfile?
    /// Rough energy use, kcal per km per kg of body weight.
    let kcalPerKmPerKg: Double
    /// Multiplies the API's walking-speed time estimate (running is faster than walking).
    let paceFactor: Double

    var canRoute: Bool { profile != nil }

    /// The profile actually sent to the API once the path type is applied.
    func profile(for path: PathType) -> RoutingProfile? {
        guard let base = profile else { return nil }
        switch base {
        case .footWalking:
            return path == .trails ? .footHiking : .footWalking
        case .cyclingRegular, .cyclingRoad:
            return path == .trails ? .cyclingMountain : base
        default:
            return base
        }
    }

    static let all: [Activity] = [
        Activity(id: "walk", name: "Walk", icon: "figure.walk", group: .onFoot,
                 profile: .footWalking, kcalPerKmPerKg: 0.6, paceFactor: 1),
        Activity(id: "run", name: "Run", icon: "figure.run", group: .onFoot,
                 profile: .footWalking, kcalPerKmPerKg: 1.0, paceFactor: 0.55),
        Activity(id: "trailrun", name: "Trail run", icon: "figure.run", group: .onFoot,
                 profile: .footHiking, kcalPerKmPerKg: 1.05, paceFactor: 0.7),
        Activity(id: "hike", name: "Hike", icon: "figure.hiking", group: .onFoot,
                 profile: .footHiking, kcalPerKmPerKg: 0.75, paceFactor: 1),

        Activity(id: "roadbike", name: "Road bike", icon: "figure.outdoor.cycle", group: .wheels,
                 profile: .cyclingRoad, kcalPerKmPerKg: 0.35, paceFactor: 1),
        Activity(id: "bike", name: "Bike", icon: "bicycle", group: .wheels,
                 profile: .cyclingRegular, kcalPerKmPerKg: 0.4, paceFactor: 1),
        Activity(id: "mtb", name: "Mountain bike", icon: "figure.outdoor.cycle", group: .wheels,
                 profile: .cyclingMountain, kcalPerKmPerKg: 0.5, paceFactor: 1),
        Activity(id: "ebike", name: "E-bike", icon: "bicycle", group: .wheels,
                 profile: .cyclingElectric, kcalPerKmPerKg: 0.2, paceFactor: 1),

        Activity(id: "wheelchair", name: "Wheelchair", icon: "figure.roll", group: .accessible,
                 profile: .wheelchair, kcalPerKmPerKg: 0.3, paceFactor: 1),

        Activity(id: "kayak", name: "Kayak", icon: "oar.2.crossed", group: .tracking,
                 profile: nil, kcalPerKmPerKg: 0.5, paceFactor: 1),
        Activity(id: "ski", name: "Ski", icon: "figure.skiing.downhill", group: .tracking,
                 profile: nil, kcalPerKmPerKg: 0.3, paceFactor: 1),
        Activity(id: "skate", name: "Skate", icon: "figure.skating", group: .tracking,
                 profile: nil, kcalPerKmPerKg: 0.5, paceFactor: 1),
        Activity(id: "row", name: "Row", icon: "figure.rower", group: .tracking,
                 profile: nil, kcalPerKmPerKg: 0.7, paceFactor: 1),
        Activity(id: "swim", name: "Swim", icon: "figure.pool.swim", group: .tracking,
                 profile: nil, kcalPerKmPerKg: 2.5, paceFactor: 1),
        Activity(id: "other", name: "Other", icon: "figure.mixed.cardio", group: .tracking,
                 profile: nil, kcalPerKmPerKg: 0.6, paceFactor: 1),
    ]
}

/// "Parks" and "quiet streets" are left out on purpose: the routing API accepts those
/// preferences but ignores them, and its green/noise ratings are constants. They can
/// return when a data source supports them.
enum PathType: String, CaseIterable, Identifiable {
    case roads = "Roads"
    case mixed = "Mixed"
    case trails = "Trails"

    var id: String { rawValue }
}

/// What the routing API is asked to avoid, and how candidates are judged.
struct RouteOptions {
    var avoidSteps = false
    /// Prefer the candidate with the least known unpaved surface.
    var preferPaved = false

    init() {}

    init(pathType: PathType, avoidSteps: Bool) {
        self.avoidSteps = avoidSteps
        self.preferPaved = pathType == .roads
    }
}
