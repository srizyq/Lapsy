import Foundation
import Observation

/// A route the user has chosen and is about to run.
struct PlannedRoute {
    var activity: Activity
    /// nil for tracking-only activities.
    var route: GeneratedRoute?
    /// Profile used to build the route, reused when rerouting.
    var profile: RoutingProfile?
    var startName: String
}

@MainActor @Observable
final class AppState {
    var tab: AppTab = .generator
    /// The run in progress (or about to start / just finished).
    var session: RunSession?
    let location = LocationProvider()
}
