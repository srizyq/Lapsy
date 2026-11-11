import Foundation
import Observation

/// A route the user has chosen and is about to run.
struct PlannedRoute {
    var activity: Activity
    /// nil for tracking-only activities.
    var route: GeneratedRoute?
    var startName: String
}

@MainActor @Observable
final class AppState {
    var tab: AppTab = .generator
    var planned: PlannedRoute?
    let location = LocationProvider()
}
