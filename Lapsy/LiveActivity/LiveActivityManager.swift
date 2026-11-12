import ActivityKit
import CoreLocation
import Foundation

/// Keeps the lock screen / Dynamic Island card in step with the run.
@MainActor
final class LiveActivityManager {
    private var activity: ActivityKit.Activity<LapsyRunAttributes>?
    private var lastPush = Date.distantPast
    private var lastState: LapsyRunAttributes.ContentState?
    private var observer: NSObjectProtocol?
    var onToggle: () -> Void = {}
    var onFinish: () -> Void = {}

    init() {
        observer = NotificationCenter.default.addObserver(forName: .lapsyLiveAction, object: nil, queue: .main) { [weak self] note in
            let action = note.object as? String
            Task { @MainActor in
                if action == "toggle" { self?.onToggle() } else if action == "finish" { self?.onFinish() }
            }
        }
    }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func start(name: String, state: LapsyRunAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        activity = try? ActivityKit.Activity.request(
            attributes: LapsyRunAttributes(activityName: name),
            content: .init(state: state, staleDate: nil)
        )
        lastState = state
        lastPush = Date()
    }

    /// Sends a new state. Frequent updates are skipped unless `force` is set.
    func update(_ state: LapsyRunAttributes.ContentState, force: Bool = false) {
        guard let activity, state != lastState else { return }
        if !force, Date().timeIntervalSince(lastPush) < 3 { return }
        lastState = state
        lastPush = Date()
        Task { await activity.update(.init(state: state, staleDate: nil)) }
    }

    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
