import Foundation
import HealthKit

/// One day of recovery data for the Insights screen.
struct DailyRecovery: Identifiable {
    let id = UUID()
    let date: Date
    let sleepHours: Double?
    let hrvMs: Double?
}

/// All HealthKit access lives here. Everything degrades gracefully:
/// if HealthKit is unavailable or the user denies access, the app works
/// fully on its own data and this manager simply does nothing.
final class HealthKitManager: ObservableObject {
    static let shared = HealthKitManager()

    @Published var isAuthorized = false
    @Published var lastError: String?

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // Symptom identifiers as raw strings — avoids any doubt about which
    // Swift overlay members exist in a given SDK.
    private let symptomIDs = [
        "HKCategoryTypeIdentifierAbdominalCramps",
        "HKCategoryTypeIdentifierBloating",
        "HKCategoryTypeIdentifierFatigue",
        "HKCategoryTypeIdentifierHeadache",
        "HKCategoryTypeIdentifierLowerBackPain",
        "HKCategoryTypeIdentifierMoodChanges",
        "HKCategoryTypeIdentifierNausea",
        "HKCategoryTypeIdentifierSleepChanges",
    ]

    private func symptomType(_ raw: String) -> HKCategoryType {
        HKCategoryType(HKCategoryTypeIdentifier(rawValue: raw))
    }

    private var shareTypes: Set<HKSampleType> {
        var s = Set<HKSampleType>()
        s.insert(HKCategoryType(.menstrualFlow))
        for raw in symptomIDs { s.insert(symptomType(raw)) }
        return s
    }

    private var readTypes: Set<HKObjectType> {
        var r = Set<HKObjectType>(shareTypes)
        r.insert(HKCategoryType(.sleepAnalysis))
        r.insert(HKQuantityType(.heartRateVariabilitySDNN))
        r.insert(HKQuantityType(.restingHeartRate))
        return r
    }

    /// Asks for share + read permission. Safe to call repeatedly.
    func requestAuthorization() async {
        guard isAvailable else { return }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            // HealthKit doesn't reveal the user's choice; we optimistically mark
            // authorized — individual saves/reads simply return empty when denied.
            await MainActor.run { self.isAuthorized = true }
        } catch {
            await MainActor.run { self.lastError = error.localizedDescription }
        }
    }

    // MARK: - Writing

    /// Writes the day's flow + mood samples to HealthKit so Apple Health,
    /// the Health app's Cycle Tracking, and watchOS stay in sync.
    func saveDayLog(date: Date, flow: String?, moods: [String]) {
        guard isAvailable, isAuthorized else { return }
        let start = date.startOfNogDay
        let end = start.nogAdding(days: 1)
        var samples: [HKCategorySample] = []

        if let flow {
            let value: Int = switch flow {
            case "light": HKCategoryValueMenstrualFlow.light.rawValue
            case "medium": HKCategoryValueMenstrualFlow.medium.rawValue
            case "heavy": HKCategoryValueMenstrualFlow.heavy.rawValue
            default: HKCategoryValueMenstrualFlow.unspecified.rawValue // incl. "spotting"
            }
            samples.append(HKCategorySample(type: HKCategoryType(.menstrualFlow),
                                            value: value, start: start, end: end))
        }

        let moodToSymptoms: [String: [String]] = [
            "happy": ["HKCategoryTypeIdentifierMoodChanges"],
            "calm": ["HKCategoryTypeIdentifierMoodChanges"],
            "energetic": ["HKCategoryTypeIdentifierMoodChanges"],
            "anxious": ["HKCategoryTypeIdentifierMoodChanges"],
            "sad": ["HKCategoryTypeIdentifierMoodChanges"],
            "irritable": ["HKCategoryTypeIdentifierMoodChanges"],
            "tired": ["HKCategoryTypeIdentifierFatigue", "HKCategoryTypeIdentifierSleepChanges"],
            "cramps": ["HKCategoryTypeIdentifierAbdominalCramps"],
        ]
        let na = HKCategoryValue.notApplicable.rawValue
        for mood in moods {
            for raw in moodToSymptoms[mood] ?? [] {
                samples.append(HKCategorySample(type: symptomType(raw),
                                                value: na, start: start, end: end))
            }
        }

        guard !samples.isEmpty else { return }
        store.save(samples) { [weak self] _, error in
            if let error {
                Task { @MainActor in self?.lastError = error.localizedDescription }
            }
        }
    }

    // MARK: - Reading (for Insights)

    /// Sleep hours + average HRV per day for the last `days` days.
    func fetchRecoveryData(days: Int = 14) async -> [DailyRecovery] {
        guard isAvailable, isAuthorized else { return [] }
        async let sleep = fetchSleepHours(days: days)
        async let hrv = fetchHRV(days: days)
        let (sleepMap, hrvMap) = await (sleep, hrv)
        let today = Date().startOfNogDay
        return (0..<days).map { i in
            let d = today.nogAdding(days: -i)
            return DailyRecovery(date: d, sleepHours: sleepMap[d], hrvMs: hrvMap[d])
        }.reversed()
    }

    private func fetchSleepHours(days: Int) async -> [Date: Double] {
        let type = HKCategoryType(.sleepAnalysis)
        let start = Date().startOfNogDay.nogAdding(days: -days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let samples: [HKCategorySample] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, results, _ in
                cont.resume(returning: (results as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleep.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
        ]
        var map: [Date: Double] = [:]
        for s in samples where asleep.contains(s.value) {
            let day = s.startDate.startOfNogDay
            map[day, default: 0] += s.endDate.timeIntervalSince(s.startDate) / 3600
        }
        return map
    }

    private func fetchHRV(days: Int) async -> [Date: Double] {
        let type = HKQuantityType(.heartRateVariabilitySDNN)
        let start = Date().startOfNogDay.nogAdding(days: -days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        var map: [Date: Double] = [:]
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let q = HKStatisticsCollectionQuery(quantityType: type,
                                                quantitySamplePredicate: predicate,
                                                options: .discreteAverage,
                                                anchorDate: start,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, _ in
                results?.enumerateStatistics(from: start, to: Date()) { stats, _ in
                    if let avg = stats.averageQuantity() {
                        map[stats.startDate.startOfNogDay] = avg.doubleValue(for: .secondUnit(with: .milli))
                    }
                }
                cont.resume()
            }
            self.store.execute(q)
        }
        return map
    }
}
