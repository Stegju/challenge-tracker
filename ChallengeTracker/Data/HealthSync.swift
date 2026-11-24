import Foundation
import HealthKit

/// Read-only access to Apple Health workouts. Query callbacks are @Sendable and
/// only pass plain values back, so nothing HealthKit-owned crosses actors.
@MainActor
final class HealthSync {
    static let shared = HealthSync()

    private let store = HKHealthStore()
    private var observer: HKObserverQuery?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows the Health permission sheet (only the first time; later calls return at once).
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let read: Set<HKObjectType> = [HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: [], read: read)
            return true
        } catch {
            AppLog.add("Health authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Workouts that started on or after `since`.
    func fetchWorkouts(since: Date) async -> [HealthWorkout] {
        guard isAvailable else { return [] }
        let raw: [(String, Date, Double, UInt, Double?)] = await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { @Sendable _, samples, error in
                if let error {
                    NSLog("Health query failed: \(error.localizedDescription)")
                }
                let workouts = (samples ?? []).compactMap { $0 as? HKWorkout }
                let values = workouts.map { w -> (String, Date, Double, UInt, Double?) in
                    let km = w.totalDistance?.doubleValue(for: HKUnit.meterUnit(with: .kilo))
                    return (w.uuid.uuidString, w.startDate, w.duration, w.workoutActivityType.rawValue, km)
                }
                cont.resume(returning: values)
            }
            store.execute(query)
        }
        return raw.map { HealthWorkout(id: $0.0, start: $0.1, durationSeconds: $0.2,
                                       activity: Self.activityName($0.3), distanceKm: $0.4) }
    }

    /// Calls `onChange` whenever Health gets a new workout, also in the background.
    func startObserving(_ onChange: @escaping @MainActor () async -> Void) {
        guard isAvailable, observer == nil else { return }
        let query = HKObserverQuery(sampleType: HKObjectType.workoutType(), predicate: nil) { @Sendable _, completion, error in
            if error != nil {
                completion()
                return
            }
            Task { @MainActor in
                await onChange()
                completion()
            }
        }
        observer = query
        store.execute(query)
        store.enableBackgroundDelivery(for: HKObjectType.workoutType(), frequency: .immediate) { @Sendable ok, error in
            if let error { NSLog("Health background delivery failed: \(error.localizedDescription)") }
            _ = ok
        }
    }

    /// Plain names that match the catalogue's counted exercises ("running", "cycling", "rowing").
    static func activityName(_ raw: UInt) -> String {
        guard let t = HKWorkoutActivityType(rawValue: raw) else { return "workout" }
        switch t {
        case .running: return "running"
        case .cycling: return "cycling"
        case .rowing: return "rowing"
        case .walking: return "walking"
        case .hiking: return "hiking"
        case .swimming: return "swimming"
        case .traditionalStrengthTraining: return "strength training"
        case .functionalStrengthTraining: return "functional strength training"
        case .highIntensityIntervalTraining: return "hiit"
        case .crossTraining: return "cross training"
        case .mixedCardio: return "mixed cardio"
        case .coreTraining: return "core training"
        case .yoga: return "yoga"
        case .elliptical: return "elliptical"
        case .stairClimbing: return "stair climbing"
        default: return "workout"
        }
    }
}
