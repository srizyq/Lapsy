import CoreLocation
import HealthKit
import Observation

/// Apple Health: reads heart rate during an outing and saves the finished outing as a
/// workout. Health data stays on the phone; Lapsy never uploads it.
@MainActor @Observable
final class HealthService {
    static let shared = HealthService()

    private(set) var heartRate: Int?
    private(set) var averageHeartRate: Int?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var query: HKAnchoredObjectQuery?
    @ObservationIgnored private var readings: [Int] = []

    private init() {}

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: - Permission

    /// Asks once; iOS only shows the sheet the first time.
    func requestAccess() async {
        guard isAvailable else { return }
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate)]
        let write: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType(.distanceWalkingRunning),
            HKQuantityType(.distanceCycling),
            HKQuantityType(.distanceSwimming),
            HKQuantityType(.distanceWheelchair),
            HKQuantityType(.activeEnergyBurned),
            HKSeriesType.workoutRoute(),
        ]
        try? await store.requestAuthorization(toShare: write, read: read)
    }

    // MARK: - Heart rate

    func startHeartRate(since start: Date) {
        guard isAvailable else { return }
        stopHeartRate()
        heartRate = nil
        averageHeartRate = nil
        readings = []

        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = {
            [weak self] _, samples, _, _, _ in
            let unit = HKUnit.count().unitDivided(by: .minute())
            let values = (samples as? [HKQuantitySample] ?? []).map { Int($0.quantity.doubleValue(for: unit).rounded()) }
            guard !values.isEmpty else { return }
            Task { @MainActor in self?.record(values) }
        }
        let q = HKAnchoredObjectQuery(type: HKQuantityType(.heartRate), predicate: predicate,
                                      anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
        q.updateHandler = handler
        store.execute(q)
        query = q
    }

    func stopHeartRate() {
        if let query { store.stop(query) }
        query = nil
    }

    private func record(_ values: [Int]) {
        readings.append(contentsOf: values)
        heartRate = values.last
        averageHeartRate = readings.isEmpty ? nil : readings.reduce(0, +) / readings.count
    }

    // MARK: - Workout

    func saveWorkout(
        activity: Activity, start: Date, end: Date,
        distanceM: Double, energyKcal: Double, locations: [CLLocation]
    ) async {
        guard isAvailable,
              store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = Self.workoutType(for: activity)
        config.locationType = activity.id == "swim" ? .unknown : .outdoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        do {
            try await builder.beginCollection(at: start)

            var samples: [HKSample] = []
            if let type = Self.distanceType(for: activity), distanceM > 0 {
                samples.append(HKQuantitySample(
                    type: type, quantity: HKQuantity(unit: .meter(), doubleValue: distanceM), start: start, end: end))
            }
            if energyKcal > 0 {
                samples.append(HKQuantitySample(
                    type: HKQuantityType(.activeEnergyBurned),
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energyKcal), start: start, end: end))
            }
            if !samples.isEmpty { try await builder.addSamples(samples) }

            try await builder.endCollection(at: end)
            guard let workout = try await builder.finishWorkout() else { return }

            if locations.count > 1 {
                let route = HKWorkoutRouteBuilder(healthStore: store, device: .local())
                try await route.insertRouteData(locations)
                try await route.finishRoute(with: workout, metadata: nil)
            }
        } catch {
            // Health is a nice-to-have; a failed save never blocks the run.
        }
    }

    private static func workoutType(for activity: Activity) -> HKWorkoutActivityType {
        switch activity.id {
        case "walk": .walking
        case "run", "trailrun": .running
        case "hike": .hiking
        case "roadbike", "bike", "mtb", "ebike": .cycling
        case "wheelchair": .wheelchairWalkPace
        case "kayak": .paddleSports
        case "ski": .downhillSkiing
        case "skate": .skatingSports
        case "row": .rowing
        case "swim": .swimming
        default: .other
        }
    }

    private static func distanceType(for activity: Activity) -> HKQuantityType? {
        switch activity.id {
        case "walk", "run", "trailrun", "hike": HKQuantityType(.distanceWalkingRunning)
        case "roadbike", "bike", "mtb", "ebike": HKQuantityType(.distanceCycling)
        case "wheelchair": HKQuantityType(.distanceWheelchair)
        case "swim": HKQuantityType(.distanceSwimming)
        default: nil
        }
    }
}
