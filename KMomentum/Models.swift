import Foundation
import SwiftData

@Model final class UserCycleState {
    var lastPeriodStartDate: Date
    var cycleLengthDays: Int
    var isSickModeActive: Bool
    var sickModeStartDay: Date?
    var manualOverrideDate: Date?
    var hasPeriodDate: Bool
    var selectedMode: String
    var sessionStartedAt: Date?
    var sessionDay: Date?
    var commitment: Date?
    var remindersEnabled: Bool
    var activePlanID: UUID?
    var didSeedPlans: Bool = false
    var restingPulseBaseline: Int?
    var reviewedMVRStart: Date?
    var confettiEnabled: Bool = true
    var hapticsEnabled: Bool = true
    var preferredWeightUnit: String = "lb"
    var customReminderEnabled: Bool = false
    var customReminderTime: Date? = nil
    var commitmentRenegotiatedDay: Date? = nil
    var reminderAcknowledgedAt: Date? = nil
    // Notification schedule – weekday vs weekend
    var weekdayReminderHour: Int = 17
    var weekdayReminderMinute: Int = 0
    var weekendReminderHour: Int = 10
    var weekendReminderMinute: Int = 0
    // Extra notifications
    var morningNudgeEnabled: Bool = false
    var morningNudgeHour: Int = 8
    var morningNudgeMinute: Int = 0
    var streakAlertEnabled: Bool = false
    var followUpEnabled: Bool = false
    // Optional silence window (off by default)
    var silenceWindowEnabled: Bool = false
    var silenceStartHour: Int = 8
    var silenceEndHour: Int = 17
    init() {
        lastPeriodStartDate = Date(); cycleLengthDays = 30; isSickModeActive = false
        hasPeriodDate = false; selectedMode = SessionMode.standard.rawValue; remindersEnabled = false
    }
}
@Model final class DailyLog {
    @Attribute(.unique) var dayKey: String
    var id: UUID
    var date: Date
    var completed: Bool
    var isMVR: Bool
    var isSickProtocol: Bool
    var notes: String?
    var intensityRaw: String?
    var compassionateChoiceRaw: String? = nil
    var recoveryStreakDay: Int? = nil
    init(date: Date, mode: SessionMode) {
        let start = Calendar.current.startOfDay(for: date)
        self.date = start; id = UUID()
        dayKey = String(start.timeIntervalSince1970)
        completed = true; isMVR = mode == .mvr; isSickProtocol = mode == .recovery
        intensityRaw = mode.rawValue
    }
}

extension DailyLog {
    var isSessionCompleted: Bool { HabitRules.isSessionCompleted(completed: completed, choice: compassionateChoice) }
    var compassionateChoice: CompassionateChoice? { compassionateChoiceRaw.flatMap(CompassionateChoice.init(rawValue:)) }
    var intensity: SessionMode { intensityRaw.flatMap(SessionMode.init(rawValue:)) ?? (isSickProtocol ? .recovery : isMVR ? .mvr : .standard) }
}
struct PlanRevision: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var text: String
}
@Model final class SavedPlan {
    var id: UUID
    var name: String
    var text: String
    var revisionsData: Data
    var documentData: Data?
    var updatedAt: Date
    init(document: PlanDocument) {
        id = UUID(); name = document.name; text = PlanText.export(document)
        revisionsData = Data(); updatedAt = Date(); documentData = try? JSONEncoder().encode(document)
    }
    var document: PlanDocument? {
        if let documentData, let value = try? JSONDecoder().decode(PlanDocument.self, from: documentData) { return value }
        return try? PlanText.parse(text)
    }
    var revisions: [PlanRevision] { (try? JSONDecoder().decode([PlanRevision].self, from: revisionsData)) ?? [] }
    func replace(document: PlanDocument, text: String) throws {
        var history = revisions
        history.insert(.init(date: updatedAt, text: self.text), at: 0)
        revisionsData = try JSONEncoder().encode(history)
        documentData = try JSONEncoder().encode(document)
        self.text = text; name = document.name; updatedAt = Date()
    }
}
@Model final class WorkoutSession {
    var id: UUID
    var date: Date
    var planID: UUID?
    var planName: String
    var modeRaw: String
    var routineData: Data
    var resultsData: Data
    var accumulatedSeconds: Double
    var runningSince: Date?
    var status: String // running, paused, completed, cancelled
    init(date: Date, planID: UUID?, planName: String, mode: SessionMode, routine: WorkoutRoutine) throws {
        id = UUID(); self.date = date; self.planID = planID; self.planName = planName; modeRaw = mode.rawValue
        routineData = try JSONEncoder().encode(routine); resultsData = Data()
        accumulatedSeconds = 0; runningSince = date; status = "running"
    }
    var routine: WorkoutRoutine? { try? JSONDecoder().decode(WorkoutRoutine.self, from: routineData) }
    var results: [SetResult] { (try? JSONDecoder().decode([SetResult].self, from: resultsData)) ?? [] }
    var mode: SessionMode { SessionMode(rawValue: modeRaw) ?? .standard }
    var isOpen: Bool { status == "running" || status == "paused" }
    func elapsed(at now: Date) -> Double { SessionRules.elapsed(accumulated: accumulatedSeconds, runningSince: runningSince, now: now) }
    func pause(at now: Date) { accumulatedSeconds = elapsed(at: now); runningSince = nil; status = "paused" }
    func resume(at now: Date) { guard status == "paused" else { return }; runningSince = now; status = "running" }
    func record(_ result: SetResult) throws {
        var values = results
        values.removeAll { $0.exercise == result.exercise && $0.set == result.set }
        values.append(result)
        resultsData = try JSONEncoder().encode(values)
    }
}
@Model final class MVRReview {
    var date: Date
    var episodeStart: Date
    var pulse: Int?
    var baseline: Int?
    var reason: String
    var choice: String
    init(episodeStart: Date, pulse: Int?, baseline: Int?, reason: String, choice: SessionMode) {
        date = Date(); self.episodeStart = episodeStart; self.pulse = pulse; self.baseline = baseline
        self.reason = reason; self.choice = choice.rawValue
    }
}

// The app and App Intents use the same default store and schema.
@MainActor enum MomentumStore {
    private static var cachedContainer: ModelContainer?
    static func container() throws -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        let container = try ModelContainer(for: UserCycleState.self, DailyLog.self, SavedPlan.self, WorkoutSession.self, MVRReview.self)
        cachedContainer = container
        return container
    }
    static func logs(from start: Date, until end: Date) throws -> [DailyLog] {
        let context = ModelContext(try container())
        let descriptor = FetchDescriptor<DailyLog>(predicate: #Predicate { $0.date >= start && $0.date < end })
        return try context.fetch(descriptor)
    }
}
