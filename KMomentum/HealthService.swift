import Foundation
import HealthKit
import Observation

@MainActor @Observable final class HealthService {
    var steps: Int?
    var stepsUpdatedAt: Date?
    var stepsDay: Date?
    var periodStart: Date?
    var status = "Apple Health sin conectar"
    private let store = HKHealthStore()
    private var observers: [HKObserverQuery] = []
    func connect() async {
        guard HKHealthStore.isHealthDataAvailable() else { status = "Salud no está disponible en este dispositivo"; return }
        let types: Set<HKObjectType> = [HKQuantityType(.stepCount), HKCategoryType(.menstrualFlow)]
        do {
            try await store.requestAuthorization(toShare: [], read: types)
            UserDefaults.standard.set(true, forKey: "healthConnected")
            status = "Lecturas de Apple Health · según disponibilidad"
            await refresh()
            guard observers.isEmpty else { return }
            for type in [HKQuantityType(.stepCount) as HKSampleType, HKCategoryType(.menstrualFlow)] {
                let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, error in
                    Task { @MainActor in
                        if error == nil { await self?.refresh() }
                        completion()
                    }
                }
                observers.append(query); store.execute(query)
            }
        } catch { status = "No se pudo conectar: \(error.localizedDescription)" }
    }
    func refresh() async {
        guard UserDefaults.standard.bool(forKey: "healthConnected") else { return }
        await refreshSteps()
        let flow = await samples(type: HKCategoryType(.menstrualFlow), days: 120)
        let bleeding = flow.compactMap { $0 as? HKCategorySample }.filter { $0.value != HKCategoryValueMenstrualFlow.none.rawValue }
        if let explicit = bleeding.first(where: { ($0.metadata?[HKMetadataKeyMenstrualCycleStart] as? Bool) == true }) { periodStart = explicit.startDate }
        else if let latest = bleeding.first {
            var start = latest.startDate
            for sample in bleeding.dropFirst() {
                let gap = Calendar.current.dateComponents([.day], from: sample.startDate, to: start).day ?? 0
                if gap > 3 { break }; start = sample.startDate
            }
            periodStart = start
        }
    }
    private func refreshSteps() async {
        let day = Calendar.current.startOfDay(for: Date())
        let result: (Int?, Date?) = await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: day, end: Date(), options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: HKQuantityType(.stepCount), quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, _ in
                let value = statistics?.sumQuantity().map { Int($0.doubleValue(for: .count())) }
                continuation.resume(returning: (value, value == nil ? nil : Date()))
            }
            store.execute(query)
        }
        // Do not let a query crossing midnight show yesterday's steps as today's.
        guard Calendar.current.isDateInToday(day) else { steps = nil; stepsUpdatedAt = nil; stepsDay = nil; return }
        steps = result.0; stepsUpdatedAt = result.1; stepsDay = day
    }
    private func samples(type: HKSampleType, days: Int) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.date(byAdding: .day, value: -days, to: Date()), end: Date())
            store.execute(HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, _ in continuation.resume(returning: samples ?? []) })
        }
    }
}
