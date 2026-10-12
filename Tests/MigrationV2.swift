import Foundation
import SwiftData
@main struct MigrationV2 {
    @MainActor static func main() throws {
        let schema = Schema([UserCycleState.self, DailyLog.self, SavedPlan.self, WorkoutSession.self, MVRReview.self])
        let configuration = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: CommandLine.arguments[1]), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        let states = try context.fetch(FetchDescriptor<UserCycleState>())
        let logs = try context.fetch(FetchDescriptor<DailyLog>())
        precondition(states.count == 1 && logs.count == 1)
        precondition(states[0].lastPeriodStartDate == Date(timeIntervalSince1970: 1_780_000_000))
        precondition(states[0].hasPeriodDate && states[0].remindersEnabled)
        precondition(states[0].confettiEnabled && states[0].hapticsEnabled && !states[0].didSeedPlans)
        precondition(states[0].preferredWeightUnit == "lb")
        precondition(!states[0].customReminderEnabled && states[0].customReminderTime == nil)
        precondition(states[0].commitmentRenegotiatedDay == nil && states[0].reminderAcknowledgedAt == nil)
        precondition(logs[0].compassionateChoice == nil && logs[0].recoveryStreakDay == nil)
        states[0].commitmentRenegotiatedDay = Date(timeIntervalSince1970: 1_780_200_000)
        states[0].reminderAcknowledgedAt = Date(timeIntervalSince1970: 1_780_200_100)
        let care = DailyLog(date: Date(timeIntervalSince1970: 1_780_200_000), mode: .recovery)
        care.completed = false; care.compassionateChoiceRaw = CompassionateChoice.recovery.rawValue; care.recoveryStreakDay = 2
        context.insert(care)
        let reminderTime = Date(timeIntervalSince1970: 1_780_200_000)
        states[0].customReminderEnabled = true; states[0].customReminderTime = reminderTime
        states[0].preferredWeightUnit = "kg"
        precondition(logs[0].notes == "Preservar mi historial" && logs[0].intensity == .mvr && logs[0].isSessionCompleted)
        let plan = SavedPlan(document: DefaultWorkouts.document); context.insert(plan)
        states[0].activePlanID = plan.id; states[0].didSeedPlans = true
        let start = Date(timeIntervalSince1970: 1_780_200_000)
        let routine = plan.document!.routine(phase: .follicular, weekday: 1, mode: .standard, recoveryDay: 1)
        let session = try WorkoutSession(date: start, planID: plan.id, planName: plan.name, mode: .standard, routine: routine)
        context.insert(session)
        try session.record(.init(exercise: 0, set: 0, reps: "10", weight: "15", unit: "lb"))
        session.pause(at: start.addingTimeInterval(120))
        precondition(session.elapsed(at: start.addingTimeInterval(900)) == 120)
        session.resume(at: start.addingTimeInterval(900))
        session.pause(at: start.addingTimeInterval(960))
        precondition(session.accumulatedSeconds == 180)
        var updated = DefaultWorkouts.document; updated.name = "Plan nuevo"
        updated.blocks[0].routine.exercises[0].name = "Ejercicio editado"
        try plan.replace(document: updated, text: PlanText.export(updated))
        precondition(session.routine == routine && session.planName != plan.name)
        precondition(plan.revisions.count == 1)
        session.status = "cancelled"
        try context.save()
        let reloaded = ModelContext(container)
        let persisted = try reloaded.fetch(FetchDescriptor<WorkoutSession>())
        let persistedStates = try reloaded.fetch(FetchDescriptor<UserCycleState>())
        precondition(persistedStates.first?.preferredWeightUnit == "kg")
        precondition(persistedStates.first?.customReminderEnabled == true && persistedStates.first?.customReminderTime == reminderTime)
        precondition(persisted.count == 1 && persisted[0].status == "cancelled")
        precondition(persisted[0].results.first?.weight == "15")
        precondition(persisted[0].results.first?.unit == "lb")
        precondition(persisted[0].accumulatedSeconds == 180)
        let logCount = try reloaded.fetchCount(FetchDescriptor<DailyLog>())
        precondition(logCount == 2)
        let careLogs = try reloaded.fetch(FetchDescriptor<DailyLog>())
        precondition(careLogs.contains { !$0.completed && $0.compassionateChoice == .recovery && $0.recoveryStreakDay == 2 && $0.isSessionCompleted })
        precondition(persistedStates.first?.commitmentRenegotiatedDay == reminderTime)
        precondition(persistedStates.first?.reminderAcknowledgedAt != nil)
        print("PASS: migration retains cycle and MVR history; defaults, plan versions, frozen session, pause/resume and cancelled set records persist")
    }
}
