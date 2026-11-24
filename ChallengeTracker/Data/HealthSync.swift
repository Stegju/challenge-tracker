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
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.distanceWalkingRunning)]
        do {
            try await store.requestAuthorization(toShare: [], read: read)
            return true
        } catch {
            AppLog.add("Health authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Workouts that started on or after `since`. For new runs (not in `known`) long enough,
    /// also works out the fastest stretch for each distance in `stretchKm`.
    func fetchWorkouts(since: Date, known: Set<String>, stretchKm: [Double]) async -> [HealthWorkout] {
        guard isAvailable else { return [] }
        let raw: [(String, Date, Double, UInt, Double?, Bool)] = await withCheckedContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: nil, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { @Sendable _, samples, error in
                if let error {
                    NSLog("Health query failed: \(error.localizedDescription)")
                }
                let workouts = (samples ?? []).compactMap { $0 as? HKWorkout }
                let values = workouts.map { w -> (String, Date, Double, UInt, Double?, Bool) in
                    let km = w.totalDistance?.doubleValue(for: HKUnit.meterUnit(with: .kilo))
                    let indoor = (w.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue ?? false
                    return (w.uuid.uuidString, w.startDate, w.duration, w.workoutActivityType.rawValue, km, indoor)
                }
                cont.resume(returning: values)
            }
            store.execute(query)
        }
        var out: [HealthWorkout] = []
        for r in raw {
            var hw = HealthWorkout(id: r.0, start: r.1, durationSeconds: r.2, activity: Self.activityName(r.3),
                                   distanceKm: r.4, indoor: r.5)
            let wanted = stretchKm.filter { ($0 * 0.999) <= (r.4 ?? 0) }
            if hw.activity == "running", !wanted.isEmpty, !known.contains(r.0), let uuid = UUID(uuidString: r.0) {
                let points = await distancePoints(workout: uuid)
                for km in wanted {
                    if let t = HealthImport.fastestStretch(points.map { (t: $0.0, d: $0.1) }, meters: km * 1000) {
                        hw.fastestStretches[km] = t
                    }
                }
            }
            out.append(hw)
        }
        return out
    }

    /// Cumulative (seconds since 1970, metres) from the running distance samples of one workout.
    private func distancePoints(workout uuid: UUID) async -> [(Double, Double)] {
        let store = self.store
        return await withCheckedContinuation { cont in
            let find = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: HKQuery.predicateForObject(with: uuid),
                                     limit: 1, sortDescriptors: nil) { @Sendable _, samples, _ in
                guard let w = samples?.first as? HKWorkout else {
                    cont.resume(returning: [])
                    return
                }
                let start = w.startDate.timeIntervalSince1970
                let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
                let q = HKSampleQuery(sampleType: HKQuantityType(.distanceWalkingRunning),
                                      predicate: HKQuery.predicateForObjects(from: w),
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { @Sendable _, distSamples, _ in
                    var total = 0.0
                    var points: [(Double, Double)] = [(start, 0)]
                    for case let qs as HKQuantitySample in distSamples ?? [] {
                        total += qs.quantity.doubleValue(for: HKUnit.meter())
                        points.append((qs.endDate.timeIntervalSince1970, total))
                    }
                    cont.resume(returning: points)
                }
                store.execute(q)
            }
            store.execute(find)
        }
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
        case .boxing: return "boxing"
        case .kickboxing: return "kickboxing"
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
