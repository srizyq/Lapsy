import CoreLocation
import CoreMotion
import MediaPlayer
import UIKit
import Observation

/// One run from "ready" to "finished": GPS tracking, the clock, pace, route following
/// and rerouting. Background location is enabled while a run is active.
@MainActor @Observable
final class RunSession: NSObject, CLLocationManagerDelegate {
    enum Phase { case ready, running, paused, finished }

    let activity: Activity
    let startName: String
    let profile: RoutingProfile?

    private(set) var route: GeneratedRoute?
    private(set) var phase: Phase = .ready
    private(set) var current: CLLocation?
    private(set) var breadcrumb: [CLLocationCoordinate2D] = []
    private(set) var distanceM = 0.0
    private(set) var nav = NavigationState()
    private(set) var statusNote: String?
    private(set) var denied = false
    private(set) var rerouteCount = 0
    private(set) var startedAt: Date?
    /// Metres climbed so far, from the phone's altitude readings.
    private(set) var ascentM = 0.0
    /// Steps per minute right now (on foot only), or nil if the phone can't tell.
    private(set) var cadenceSPM: Int?

    @ObservationIgnored private var locations: [CLLocation] = []
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var engine: NavigationEngine?
    @ObservationIgnored private var elapsedBase: TimeInterval = 0
    @ObservationIgnored private var resumedAt: Date?
    @ObservationIgnored private var lastAccepted: CLLocation?
    @ObservationIgnored private var recent: [(time: Date, distance: Double)] = []
    @ObservationIgnored private var offRouteCount = 0
    @ObservationIgnored private var lastRerouteAt = Date.distantPast
    @ObservationIgnored private var rerouting = false
    @ObservationIgnored private var hapticStep: Int?
    @ObservationIgnored private var kmMarks: [Double] = []
    @ObservationIgnored private var altitudeBase: Double?
    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private let voice = VoiceGuide()
    @ObservationIgnored private let live = LiveActivityManager()
    @ObservationIgnored private var spokenFar: Set<Int> = []
    @ObservationIgnored private var spokenNear: Set<Int> = []
    @ObservationIgnored private var spokeArrival = false
    /// Whether spoken directions are on. Remembered between runs.
    var voiceOn = VoiceGuide.enabled {
        didSet {
            VoiceGuide.enabled = voiceOn
            if !voiceOn { voice.stop() }
        }
    }

    init(planned: PlannedRoute) {
        activity = planned.activity
        startName = planned.startName
        profile = planned.profile
        route = planned.route
        super.init()
        if let route = planned.route { engine = NavigationEngine(route: route) }
        live.onToggle = { [weak self] in
            guard let self else { return }
            if self.phase == .running { self.pause() } else if self.phase == .paused { self.resume() }
        }
        live.onFinish = { [weak self] in self?.finish() }

        manager.delegate = self
        manager.activityType = activity.group == .wheels ? .otherNavigation : .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false

        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: denied = true
        default: manager.startUpdatingLocation()
        }
    }

    // MARK: - Derived values

    func elapsed(at date: Date = Date()) -> TimeInterval {
        elapsedBase + (resumedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    /// Recent pace in seconds per km, from the last ~30 seconds of movement.
    var paceSecPerKm: Double? {
        guard let first = recent.first, let last = recent.last, last.time > first.time else { return nil }
        let meters = last.distance - first.distance
        guard meters > 5 else { return nil }
        return last.time.timeIntervalSince(first.time) / (meters / 1000)
    }

    var speedKmh: Double? { paceSecPerKm.map { 3600 / $0 } }

    var energyKcal: Double { activity.kcalPerKmPerKg * 70 * distanceM / 1000 }

    var routeTotalM: Double { engine?.totalM ?? 0 }

    /// Straight-line distance from the runner to where the route begins.
    var distanceToStartM: Double? {
        guard let here = current, let first = route?.coordinates.first else { return nil }
        return here.distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude))
    }

    var averagePaceSecPerKm: Double? {
        let t = elapsed()
        return distanceM > 50 && t > 0 ? t / (distanceM / 1000) : nil
    }

    /// The finished outing as a record to keep, or nil if it was too short to be worth saving.
    func makeSavedRun() -> SavedRun? {
        guard let startedAt, distanceM >= 50 else { return nil }
        return SavedRun(
            activityId: activity.id,
            startedAt: startedAt,
            durationS: elapsedBase,
            distanceM: distanceM,
            energyKcal: energyKcal,
            startName: startName,
            track: Polyline.encode(breadcrumb),
            plannedPolyline: route.map { Polyline.encode($0.coordinates) },
            plannedDistanceM: route?.distanceM,
            avgHeartRate: HealthService.shared.averageHeartRate,
            ascentM: ascentM,
            splits: splits,
            surface: route?.surface
        )
    }

    /// Seconds taken for each completed kilometre.
    var splits: [Double] {
        zip([0] + kmMarks, kmMarks).map { $1 - $0 }
    }

    // MARK: - Along the planned route

    /// Height gained (negative = lost) over the next `meters` of the planned route.
    func climbAhead(_ meters: Double) -> Double? {
        guard let (here, there) = ahead(meters) else { return nil }
        return there.elevation - here.elevation
    }

    /// Slope of the next ~100 m of the planned route, in percent.
    var gradePercent: Double? {
        guard let (here, there) = ahead(100), there.distance - here.distance > 20 else { return nil }
        return (there.elevation - here.elevation) / (there.distance - here.distance) * 100
    }

    private func ahead(_ meters: Double) -> ((distance: Double, elevation: Double), (distance: Double, elevation: Double))? {
        guard let engine, let route, route.elevations.count == engine.cumulative.count,
              engine.cumulative.indices.contains(nav.routeIndex) else { return nil }
        let i = nav.routeIndex
        let target = engine.cumulative[i] + meters
        let j = engine.cumulative.firstIndex(where: { $0 >= target }) ?? (engine.cumulative.count - 1)
        guard j > i else { return nil }
        return ((engine.cumulative[i], route.elevations[i]), (engine.cumulative[j], route.elevations[j]))
    }

    /// The song playing in the Music app, if there is one and access was allowed.
    func nowPlaying() -> (title: String, artist: String)? {
        guard MPMediaLibrary.authorizationStatus() == .authorized,
              let item = MPMusicPlayerController.systemMusicPlayer.nowPlayingItem,
              let title = item.title else { return nil }
        return (title, item.artist ?? "")
    }

    // MARK: - Controls

    func begin() {
        guard phase == .ready else { return }
        phase = .running
        distanceM = 0
        breadcrumb = []
        recent = []
        locations = []
        kmMarks = []
        ascentM = 0
        altitudeBase = nil
        lastAccepted = nil
        elapsedBase = 0
        resumedAt = Date()
        startedAt = Date()
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = true

        if let first = route?.steps.first {
            voice.speak("Starting your \(activity.noun). \(first.instruction)")
        } else {
            voice.speak("Starting your \(activity.noun).")
        }

        let started = startedAt ?? Date()
        if activity.group != .wheels, CMPedometer.isCadenceAvailable() {
            pedometer.startUpdates(from: started) { [weak self] data, _ in
                let perSecond = data?.currentCadence?.doubleValue
                Task { @MainActor in self?.cadenceSPM = perSecond.map { Int(($0 * 60).rounded()) } }
            }
        }
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            MPMediaLibrary.requestAuthorization { _ in }
        }
        live.start(name: activity.name, state: liveState())
        Task {
            await HealthService.shared.requestAccess()
            HealthService.shared.startHeartRate(since: started)
        }
    }

    func pause() {
        guard phase == .running else { return }
        elapsedBase = elapsed()
        resumedAt = nil
        lastAccepted = nil
        phase = .paused
        live.update(liveState(), force: true)
    }

    func resume() {
        guard phase == .paused else { return }
        resumedAt = Date()
        phase = .running
        live.update(liveState(), force: true)
    }

    func finish() {
        guard phase == .running || phase == .paused else { return }
        elapsedBase = elapsed()
        resumedAt = nil
        phase = .finished
        teardown()
        HealthService.shared.stopHeartRate()

        if let startedAt, distanceM >= 50 {
            let (activity, distance, energy, track, end) = (activity, distanceM, energyKcal, locations, Date())
            Task {
                await HealthService.shared.saveWorkout(
                    activity: activity, start: startedAt, end: end,
                    distanceM: distance, energyKcal: energy, locations: track
                )
            }
        }
    }

    /// Leave without saving (from the ready screen, or after the summary).
    func close() {
        teardown()
    }

    private func teardown() {
        live.end()
        voice.stop()
        pedometer.stopUpdates()
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - Location updates

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                denied = false
                self.manager.startUpdatingLocation()
            case .denied, .restricted:
                denied = true
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in handle(locations) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    private func handle(_ locations: [CLLocation]) {
        for location in locations {
            // Ignore fixes that are invalid or too imprecise to trust.
            guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { continue }
            current = location
            guard phase == .running else { continue }

            if let last = lastAccepted {
                let step = location.distance(from: last)
                // Below ~2 m is GPS jitter while standing still.
                if step >= 2 {
                    distanceM += step
                    markKilometres()
                    countClimb(location)
                    lastAccepted = location
                    breadcrumb.append(location.coordinate)
                    self.locations.append(location)
                    recent.append((location.timestamp, distanceM))
                    recent.removeAll { location.timestamp.timeIntervalSince($0.time) > 30 }
                }
            } else {
                lastAccepted = location
                breadcrumb.append(location.coordinate)
                self.locations.append(location)
                recent.append((location.timestamp, distanceM))
            }
            follow(location)
        }
        if phase == .running { live.update(liveState()) }
    }

    private func markKilometres() {
        while distanceM >= Double(kmMarks.count + 1) * 1000 {
            kmMarks.append(elapsed())
        }
    }

    /// Adds to the climb only when the altitude has really moved by a few metres,
    /// so GPS and barometer wobble doesn't pile up.
    private func countClimb(_ location: CLLocation) {
        guard location.verticalAccuracy >= 0, location.verticalAccuracy <= 15 else { return }
        let altitude = location.altitude
        guard let base = altitudeBase else { altitudeBase = altitude; return }
        if altitude - base >= 3 {
            ascentM += altitude - base
            altitudeBase = altitude
        } else if base - altitude >= 3 {
            altitudeBase = altitude
        }
    }

    // MARK: - Lock screen card

    private func liveState() -> LapsyRunAttributes.ContentState {
        let step = nav.nextStep
        let arrived = nav.arrived
        return LapsyRunAttributes.ContentState(
            arrow: arrived ? "flag.fill" : (step?.symbol ?? "arrow.up"),
            turnDistanceM: arrived ? nil : nav.distanceToNextM,
            instruction: arrived ? "You've arrived" : (statusNote ?? step?.instruction ?? "Follow your \(activity.noun)"),
            distanceM: distanceM,
            clockStart: resumedAt.map { $0.addingTimeInterval(-elapsedBase) },
            elapsedS: elapsed(),
            paceText: livePace(),
            heartRate: HealthService.shared.heartRate,
            paused: phase == .paused,
            offRoute: statusNote != nil && !arrived
        )
    }

    private func livePace() -> String {
        if activity.group == .wheels { return speedKmh.map { String(format: "%.1f km/h", $0) } ?? "--" }
        guard let sec = paceSecPerKm, sec < 3600 else { return "--:--" }
        return String(format: "%d:%02d /km", Int(sec) / 60, Int(sec) % 60)
    }

    // MARK: - Following and rerouting


    private func follow(_ location: CLLocation) {
        guard var engine else { return }
        let state = engine.update(location.coordinate)
        self.engine = engine
        nav = state

        if state.arrived {
            statusNote = "You've arrived"
            if !spokeArrival {
                spokeArrival = true
                voice.speak("You've arrived.")
            }
            return
        }

        // One tap of feedback as each turn gets close, and a spoken heads-up twice:
        // about 150 m before and again right at the turn.
        if let index = state.nextStepIndex, let step = state.nextStep, let toNext = state.distanceToNextM {
            if toNext < 40, hapticStep != index {
                hapticStep = index
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
            if step.type != 10 {
                if toNext <= 160, toNext > 70, !spokenFar.contains(index) {
                    spokenFar.insert(index)
                    voice.speak(VoiceGuide.phrase(step, in: toNext))
                } else if toNext <= 45, !spokenNear.contains(index) {
                    spokenNear.insert(index)
                    spokenFar.insert(index)
                    voice.speak(step.instruction)
                }
            }
        }

        // Off the route for several fixes in a row means a real detour, not GPS noise.
        offRouteCount = state.offRouteM > 35 ? offRouteCount + 1 : 0
        if offRouteCount >= 3, !rerouting, Date().timeIntervalSince(lastRerouteAt) > 20 {
            Task { await reroute(from: location.coordinate, state: state) }
        }
    }

    private func reroute(from here: CLLocationCoordinate2D, state: NavigationState) async {
        guard let route, let engine, let profile else { return }
        rerouting = true
        lastRerouteAt = Date()
        statusNote = "Off route. Finding a way back..."
        voice.speak("You're off route. Finding a way back.")
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        defer { rerouting = false }

        // Rejoin the original route about 200 m ahead of the nearest point.
        let target = state.distanceAlongM + 200
        let rejoin = engine.cumulative.firstIndex(where: { $0 >= target }) ?? (route.coordinates.count - 1)
        do {
            let detour = try await RouteService().route(
                through: [here, route.coordinates[rejoin]],
                profile: profile
            )
            let merged = RouteReroute.merge(detour: detour, original: route, rejoin: rejoin)
            self.route = merged
            self.engine = NavigationEngine(route: merged)
            offRouteCount = 0
            hapticStep = nil
            spokenFar = []
            spokenNear = []
            rerouteCount += 1
            statusNote = nil
            voice.speak("New route found.")
        } catch {
            statusNote = "Can't reroute right now"
        }
    }
}
