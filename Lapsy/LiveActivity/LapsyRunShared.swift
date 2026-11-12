import ActivityKit
import AppIntents
import Foundation

// This file is identical in the app and in the LapsyLiveActivity extension.
// If you change it, change both copies.

struct LapsyRunAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// SF Symbol for the next turn.
        var arrow: String
        /// Metres to the next turn, or nil when there is no route.
        var turnDistanceM: Double?
        /// What to do at the turn, e.g. "Turn left onto High Street".
        var instruction: String
        var distanceM: Double
        /// Moment the clock would have started if it never paused. nil while paused.
        var clockStart: Date?
        /// Time on the clock while paused.
        var elapsedS: Double
        var paceText: String
        var heartRate: Int?
        var paused: Bool
        var offRoute: Bool
    }

    var activityName: String
}

extension Notification.Name {
    static let lapsyLiveAction = Notification.Name("lapsyLiveAction")
}

struct PauseRunIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Pause or resume" }
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .lapsyLiveAction, object: "toggle")
        return .result()
    }
}

struct FinishRunIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Finish" }
    static var openAppWhenRun: Bool { true }
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .lapsyLiveAction, object: "finish")
        return .result()
    }
}
