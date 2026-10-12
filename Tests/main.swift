import Foundation
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) { checks += 1; if !condition() { fatalError(message) } }
var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/Bogota")!
func date(_ year: Int = 2026, _ month: Int = 10, _ day: Int, _ hour: Int = 0) -> Date { calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))! }
for (day, phase) in [(1,CyclePhase.menstrual),(7,.menstrual),(8,.follicular),(13,.follicular),(14,.ovulatory),(17,.ovulatory),(18,.luteal),(30,.luteal)] { check(HabitRules.phase(day: day) == phase, "Phase boundary \(day)") }
check(HabitRules.cycleDay(start: date(2026,10,1,23), now: date(2026,10,2), calendar: calendar) == 2, "Midnight day transition")
check(HabitRules.cycleDay(start: date(2026,10,1), now: date(2026,10,31), calendar: calendar) == 1, "Cycle wrap")
check(HabitRules.cycleDay(start: date(2026,10,11), now: date(2026,10,10), calendar: calendar) == 1, "Future date clamps")
check(HabitRules.weekIndex(date(2026,10,5), calendar: calendar) == 0, "Monday first")
check(HabitRules.weekIndex(date(2026,10,11), calendar: calendar) == 6, "Sunday last")
check(HabitRules.completedDaysInWeek([], now: date(2026,10,11), calendar: calendar) == 0, "Empty week has no progress")
let fullWeek = (5...11).map { date(2026,10,$0) }
check(HabitRules.completedDaysInWeek(fullWeek, now: date(2026,10,11), calendar: calendar) == 7, "Full Monday–Sunday week reaches 100 percent")
check(HabitRules.completedDaysInWeek([date(2026,10,4), date(2026,10,5), date(2026,10,5,18), date(2026,10,7), date(2026,10,8)], now: date(2026,10,7,19), calendar: calendar) == 2, "Weekly progress counts unique completed days and excludes previous week and future days")
check(HabitRules.completedDaysInWeek(fullWeek, now: date(2026,10,12), calendar: calendar) == 0, "Weekly progress resets on Monday")
for phase in CyclePhase.allCases {
    for weekday in 0..<7 {
        let plan = HabitRules.plan(phase: phase, weekday: weekday, mode: .mvr, recoveryDay: 1)
        check((5...10).contains(plan.minutes), "MVR length")
        check(!plan.exercises.isEmpty, "MVR content")
        let full = HabitRules.plan(phase: phase, weekday: weekday, mode: .standard, recoveryDay: 1)
        check((40...45).contains(full.minutes), "Standard duration")
        if phase == .menstrual { check(!full.strength, "Menstrual no external load") }
    }
}
for (day,minutes) in [(1,5),(3,5),(4,10),(7,10),(8,15),(20,15)] {
    check(HabitRules.plan(phase: .ovulatory, weekday: 1, mode: .recovery, recoveryDay: day).minutes == minutes, "Recovery boundary")
}
check(HabitRules.recoveryDay(start: date(2026,10,1,23), now: date(2026,10,4), calendar: calendar) == 4, "Recovery calendar days")

let original = DefaultWorkouts.document
let exported = PlanText.export(original)
let parsed = try PlanText.parse(exported)
check(original == parsed, "Default plan round trip")
check(parsed.blocks.count == 39, "Every baseline phase and adaptation exported")
func rejects(_ text: String, _ description: String) {
    do { _ = try PlanText.parse(text); check(false, description) }
    catch { check(true, description) }
}
let simple = """
PLAN: Mi plan
DÍA: Todos
FASE: Todas
MODO: Estándar
TÍTULO: Fuerza personalizada
MINUTOS: 25
EJERCICIO: Sentadilla
SERIES: 3
REPETICIONES: 10
DESCANSO: 60
"""
let custom = try PlanText.parse(simple)
check(custom.routine(phase: .follicular, weekday: 2, mode: .standard, recoveryDay: 1).minutes == 25, "Custom all-day block selected")
check(custom.routine(phase: .follicular, weekday: 2, mode: .mvr, recoveryDay: 1).minutes == 10, "Missing adaptations preserve base MVR")
check(custom.routine(phase: .follicular, weekday: 2, mode: .intermediate, recoveryDay: 1).minutes == 20, "Intermediate fallback")
rejects(simple.replacingOccurrences(of: "SERIES: 3", with: "SERIES: 0"), "Invalid set count")
rejects(simple.replacingOccurrences(of: "SERIES: 3\n", with: ""), "Missing sets")
rejects(simple + "\nDURACIÓN: 20", "Ambiguous reps and duration")
rejects(simple + "\nINVENTADO: 1", "Unknown field")
rejects(simple + "\nSERIES: 4", "Duplicate field")
rejects(simple.replacingOccurrences(of: "MINUTOS: 25", with: "MINUTOS: cinco"), "Non-numeric duration")
rejects(simple + "\n" + simple.components(separatedBy: "\n").dropFirst().joined(separator: "\n"), "Duplicate block")
rejects("PLAN: Incompleto", "Empty plan")
let customSpecific = try PlanText.parse(simple + """

DÍA: Miércoles
FASE: Folicular
MODO: Estándar
TÍTULO: Miércoles adaptado
MINUTOS: 15
EJERCICIO: Movilidad
SERIES: 1
DURACIÓN: 900
""")
check(customSpecific.routine(phase: .follicular, weekday: 2, mode: .standard, recoveryDay: 1).minutes == 15, "Specific block overrides wildcard")
for phase in CyclePhase.allCases { for day in 0..<7 { for mode in SessionMode.allCases {
    let routine = parsed.routine(phase: phase, weekday: day, mode: mode, recoveryDay: 1)
    check(!routine.exercises.isEmpty, "Every mode resolves")
    for e in routine.exercises { check((e.reps != nil) != (e.seconds != nil), "Exactly one exercise target") }
} } }
let start = date(2026,10,10,18)
check(SessionRules.elapsed(accumulated: 0, runningSince: start, now: start.addingTimeInterval(120)) == 120, "Running clock")
check(SessionRules.elapsed(accumulated: 120, runningSince: nil, now: start.addingTimeInterval(900)) == 120, "Pause excludes wall time")
check(SessionRules.elapsed(accumulated: 120, runningSince: start.addingTimeInterval(900), now: start.addingTimeInterval(960)) == 180, "Resume accumulates")
check(SessionRules.elapsed(accumulated: 120, runningSince: start, now: start.addingTimeInterval(-100)) == 120, "Clock rollback does not subtract")
let mvr = (7...9).map { CompletionDay(date: date(2026,10,$0), mode: .mvr) }
check(SessionRules.mvrEpisode(logs: mvr, now: date(2026,10,9,18), calendar: calendar)?.count == 3, "Third day triggers")
check(SessionRules.mvrEpisode(logs: mvr, now: date(2026,10,10,18), calendar: calendar)?.count == 3, "Previous three days retained today")
check(SessionRules.mvrEpisode(logs: mvr, now: date(2026,10,11), calendar: calendar) == nil, "Missing day breaks streak")
check(SessionRules.mvrEpisode(logs: mvr + [mvr[2]], now: date(2026,10,9,18), calendar: calendar)?.count == 3, "Duplicate entries count once")
check(SessionRules.mvrEpisode(logs: mvr + [.init(date: date(2026,10,10), mode: .intermediate)], now: date(2026,10,10,18), calendar: calendar) == nil, "Intermediate breaks MVR streak")
check(SessionRules.mvrEpisode(logs: mvr + [.init(date: date(2026,10,10), mode: .recovery)], now: date(2026,10,10,18), calendar: calendar) == nil, "Recovery excluded")
let continued = SessionRules.mvrEpisode(logs: mvr + [.init(date: date(2026,10,10), mode: .mvr)], now: date(2026,10,10,18), calendar: calendar)
check(continued?.start == date(2026,10,7) && continued?.count == 4, "Same episode stable start suppresses repeated review")
var dst = Calendar(identifier: .gregorian); dst.timeZone = TimeZone(identifier: "America/New_York")!
let dstDays = [7,8,9].map { CompletionDay(date: dst.date(from: DateComponents(year: 2026, month: 3, day: $0))!, mode: .mvr) }
check(SessionRules.mvrEpisode(logs: dstDays, now: dst.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 18))!, calendar: dst)?.count == 3, "Calendar streak across daylight savings")
check(!SessionRules.shortSessionFinished(mode: .mvr, minutes: 5, elapsed: 299), "MVR prompt waits until timer ends")
check(SessionRules.shortSessionFinished(mode: .mvr, minutes: 5, elapsed: 300), "MVR prompts at five minutes")
check(SessionRules.shortSessionFinished(mode: .recovery, minutes: 5, elapsed: 300), "Recovery prompts at its deadline")
check(!SessionRules.shortSessionFinished(mode: .recovery, minutes: 10, elapsed: 300), "Recovery respects routine duration")
check(SessionRules.shortSessionFinished(mode: .recovery, minutes: 10, elapsed: 900), "Elapsed deadline is detected after backgrounding")
check(!SessionRules.shortSessionFinished(mode: .standard, minutes: 5, elapsed: 300), "Standard never prompts for short-session upgrade")
check(!SessionRules.shortSessionFinished(mode: .intermediate, minutes: 5, elapsed: 300), "Intermediate retains its existing completion flow")
check(!SessionRules.shortSessionFinished(mode: .mvr, minutes: 0, elapsed: 300), "Invalid duration cannot trigger completion")
check(SessionRules.shortSessionFinished(mode: .mvr, minutes: 5, elapsed: 60, endedEarly: true), "Ending MVR early offers Standard")
check(SessionRules.shortSessionFinished(mode: .recovery, minutes: 10, elapsed: 60, endedEarly: true), "Ending recovery early offers Standard")
check(!SessionRules.shortSessionFinished(mode: .standard, minutes: 40, elapsed: 60, endedEarly: true), "Ending Standard early keeps normal completion")
check(!SessionRules.shortSessionFinished(mode: .intermediate, minutes: 20, elapsed: 60, endedEarly: true), "Ending intermediate early keeps normal completion")
for cycleDay in 1...28 {
    let reminder = HabitRules.cycleReminder(currentCycleDay: cycleDay)
    let expectedHour = cycleDay <= 5 ? 11 : cycleDay <= 13 ? 16 : cycleDay <= 16 ? 18 : 19
    check(reminder?.hour == expectedHour, "Cycle reminder phase and hour for day \(cycleDay)")
    check(reminder?.body.contains("[X]") == false, "Reminder replaces placeholders for day \(cycleDay)")
}
check(HabitRules.cycleReminder(currentCycleDay: 0) == nil && HabitRules.cycleReminder(currentCycleDay: 29) == nil, "Cycle reminder rejects days outside 1–28")
check(HabitRules.cycleReminder(currentCycleDay: 1)?.body == "Día 1 menstrual. Hoy tu cuerpo pide quietud. 5 min de respiración bastan para mantener la racha sin exigirte.", "Menstrual copy injects current day")
check(HabitRules.cycleReminder(currentCycleDay: 7)?.body == "Llevas 7 días encendidos. Abre Kmomentum y mantén tu barra semanal creciendo.", "Follicular copy injects current day")
check(HabitRules.cycleReminder(currentCycleDay: 2)?.body == "¿Cero energía? Entra a Kmomentum solo para registrar tu día y descansa.", "Copies alternate within each phase")
check(Set((1...28).compactMap { HabitRules.cycleReminder(currentCycleDay: $0)?.body.replacingOccurrences(of: "Día \($0)", with: "Día [X]").replacingOccurrences(of: "Llevas \($0)", with: "Llevas [X]") }).count == 8, "All eight matrix copies are used")
check(HabitRules.cycleDay(start: date(2026,10,1), now: date(2026,10,28), length: 28, calendar: calendar) == 28, "Notification cycle reaches day 28")
check(HabitRules.cycleDay(start: date(2026,10,1), now: date(2026,10,29), length: 28, calendar: calendar) == 1, "Notification cycle wraps to day 1")
check(DefaultWorkouts.timed("Respiración", 300).target == "05:00 min", "Timed target displays minutes and seconds")
check(DefaultWorkouts.timed("Plancha", 20, sets: 3).target == "3 × 00:20 min", "Timed target preserves number of sets")
check(DefaultWorkouts.strength("Sentadilla", sets: 2, reps: 10).target == "2 × 10 reps", "Strength target retains repetitions")
check(HabitRules.weeklyLiquidFill(completedDays: 0) == 0, "Empty week leaves the heart empty")
check(HabitRules.weeklyLiquidFill(completedDays: 1) == 0.40, "First day visually fills 40 percent of the heart")
check(HabitRules.weeklyLiquidFill(completedDays: 2) == 0.50, "Second day visually fills 50 percent")
for days in 2...7 {
    check(abs(HabitRules.weeklyLiquidFill(completedDays: days) - HabitRules.weeklyLiquidFill(completedDays: days - 1) - 0.10) < 0.000001, "Each remaining day adds ten percent visually")
}
check(HabitRules.weeklyLiquidFill(completedDays: 7) == 1, "Seven days fill the heart completely")
check(HabitRules.weeklyLiquidFill(completedDays: -1) == 0 && HabitRules.weeklyLiquidFill(completedDays: 8) == 1, "Liquid fill stays inside the heart bounds")
for days in 0...7 {
    check(HabitRules.weeklyProgress(completedDays: days) == Double(days) / 7, "Displayed percentage always matches the completed fraction")
}
let widgetSample = WidgetSnapshot(date: date(2026,10,11), completed: true, title: "Sesión", week: [true, false, true, false, false, false, true], cyclePhase: .luteal)
let widgetData = try JSONEncoder().encode(widgetSample)
let restoredWidget = try JSONDecoder().decode(WidgetSnapshot.self, from: widgetData)
check(restoredWidget.cyclePhase == .luteal && restoredWidget.week.filter { $0 }.count == 3, "Widget receives the same phase and weekly completion as the app")
check(restoredWidget.mediumMessage == "Buen trabajo!", "Completed medium widget celebrates")
var pendingWidget = widgetSample
pendingWidget.completed = false
let phaseMessages: [(CyclePhase, String)] = [
    (.menstrual, "Hoy, moverte con suavidad también cuenta."),
    (.follicular, "Aprovecha tu impulso. Tu sesión te espera."),
    (.ovulatory, "¿Vamos con Estándar hoy?"),
    (.luteal, "Una sesión corta basta para mantener el momentum.")
]
for (phase, message) in phaseMessages {
    pendingWidget.cyclePhase = phase
    check(pendingWidget.mediumMessage == message, "Pending medium widget uses the short phase message")
}
pendingWidget.cyclePhase = nil
check(pendingWidget.mediumMessage == "Un pequeño paso hoy también cuenta.", "Unknown phase gets a neutral message")
var legacyWidget = try JSONSerialization.jsonObject(with: widgetData) as! [String: Any]
legacyWidget.removeValue(forKey: "cyclePhase")
let legacyData = try JSONSerialization.data(withJSONObject: legacyWidget)
let restoredLegacy = try JSONDecoder().decode(WidgetSnapshot.self, from: legacyData)
check(restoredLegacy.cyclePhase == nil && restoredLegacy.week == widgetSample.week, "Existing widget snapshots remain readable before app refresh")
let reminderNow = date(2026,10,11,10)
let promise = date(2026,10,11,20)
func reminderPlan(closed: Bool = false, promise: Date? = nil, negotiated: Date? = nil, ack: Date? = nil, now: Date = reminderNow) -> [LocalReminderPlan] {
    ReminderRules.plan(currentCycleDay: 1, closed: closed, commitment: promise, renegotiatedDay: negotiated, acknowledgedAt: ack, enabled: true, customTime: date(2026,10,11,18), now: now, calendar: calendar)
}
check(ReminderRules.commitmentDate(time: date(2026,10,11,4), now: date(2026,10,11,3), calendar: calendar) == date(2026,10,11,4), "4am included")
check(ReminderRules.commitmentDate(time: date(2026,10,11,3), now: date(2026,10,11,2), calendar: calendar) == nil, "Before4am rejected")
check(ReminderRules.commitmentDate(time: promise, now: promise, calendar: calendar) == nil, "Past time rejected")
check(!ReminderRules.compassionAvailable(commitment: promise, renegotiatedDay: reminderNow, now: reminderNow, calendar: calendar), "B unavailable before promise")
check(!ReminderRules.compassionAvailable(commitment: promise, renegotiatedDay: nil, now: promise, calendar: calendar), "B requires A")
check(ReminderRules.compassionAvailable(commitment: promise, renegotiatedDay: reminderNow, now: promise, calendar: calendar), "B starts at promise")
check(!ReminderRules.compassionAvailable(commitment: promise, renegotiatedDay: reminderNow, now: date(2026,10,12), calendar: calendar), "Yesterday promise expired")
let initialReminders = reminderPlan()
check(initialReminders.count <= 64, "Queue stays within local limit")
check(Set(initialReminders.map(\.identifier)).count == initialReminders.count, "Unique reminder ids")
let loops = initialReminders.filter { $0.identifier.hasPrefix("persistent-") }
check(!loops.isEmpty && loops.allSatisfy { $0.category == ReminderRules.firstCategory }, "Initial loop uses A")
check(loops.first!.date == date(2026,10,11,18).addingTimeInterval(300), "Loop follows fixed reminder five minutes later")
for pair in zip(loops, loops.dropFirst()) { check(pair.1.date.timeIntervalSince(pair.0.date) == 300, "Five minute cadence") }
check(loops.allSatisfy { $0.date <= date(2026,10,12) }, "Loops end by midnight")
let renegotiated = reminderPlan(promise: promise, negotiated: reminderNow)
check(renegotiated.filter { calendar.isDate($0.date, inSameDayAs: reminderNow) }.allSatisfy { $0.date >= promise }, "Promise silences all earlier alerts")
check(renegotiated.contains { $0.identifier == "commitment" && $0.date == promise && $0.category == ReminderRules.secondCategory }, "Exact promise time triggers B")
check(!renegotiated.contains { $0.repeatsDaily }, "No recurring fixed alert overrides promise")
let acknowledged = reminderPlan(promise: promise, negotiated: reminderNow, ack: promise, now: promise)
check(!acknowledged.contains { $0.identifier.hasPrefix("persistent-") }, "Starting or completing a session stops loop")
let closedReminders = reminderPlan(closed: true)
check(closedReminders.allSatisfy { !calendar.isDate($0.date, inSameDayAs: reminderNow) && !$0.repeatsDaily }, "Completed or compassion day silences today")
let lateReminders = reminderPlan(promise: date(2026,10,11,23).addingTimeInterval(1800), negotiated: reminderNow, now: date(2026,10,11,23).addingTimeInterval(1800))
check(lateReminders.filter { $0.identifier.hasPrefix("persistent-") }.count == 6, "23:30 preserves six reminders through midnight")
check(ReminderRules.recoveryDay(previousDates: [], now: reminderNow, calendar: calendar) == 1, "First recovery day")
check(ReminderRules.recoveryDay(previousDates: [date(2026,10,9),date(2026,10,10),date(2026,10,10,18),reminderNow], now: reminderNow, calendar: calendar) == 3, "Consecutive recovery deduplicates dates")
check(ReminderRules.recoveryDay(previousDates: [date(2026,10,9)], now: reminderNow, calendar: calendar) == 1, "Recovery gap resets count")
check(restoredLegacy.pausedWeek == nil, "Old widget data supports new care state")
var pausedWidget = pendingWidget
pausedWidget.date = date(2026,10,11)
pausedWidget.pausedWeek = Array(repeating: true, count: 7)
check(pausedWidget.paused && pausedWidget.mediumMessage == "Descansa y respira. Mañana retomamos.", "Compassion widget message")
check(ReminderRules.commitmentDate(time: date(2026,10,11,23).addingTimeInterval(1800), now: reminderNow, calendar: calendar) != nil, "23:30 included")
check(ReminderRules.commitmentDate(time: date(2026,10,11,23).addingTimeInterval(1860), now: reminderNow, calendar: calendar) == nil, "23:31 excluded")
check(ReminderRules.plan(currentCycleDay: nil, closed: false, commitment: nil, renegotiatedDay: nil, acknowledgedAt: nil, enabled: false, customTime: nil, now: reminderNow, calendar: calendar).isEmpty, "No opt-in means no reminders")
check(reminderPlan(promise: promise, negotiated: reminderNow, ack: reminderNow).contains { $0.identifier.hasPrefix("persistent-") }, "Opening before promise keeps future loop")
let phaseOnly = ReminderRules.plan(currentCycleDay: 1, closed: false, commitment: nil, renegotiatedDay: nil, acknowledgedAt: nil, enabled: true, customTime: nil, now: reminderNow, calendar: calendar)
check(phaseOnly.contains { $0.identifier.hasPrefix("persistent-") && $0.date == date(2026,10,11,11).addingTimeInterval(300) }, "Phase reminder starts fallback loop")
let pausedData = try JSONEncoder().encode(pausedWidget)
let restoredPaused = try JSONDecoder().decode(WidgetSnapshot.self, from: pausedData)
check(restoredPaused.pausedWeek == pausedWidget.pausedWeek, "Purple care states survive snapshot encoding")
let secondStageLoop = renegotiated.filter { $0.identifier.hasPrefix("persistent-") }
for minute in stride(from: 5, through: 30, by: 5) {
    check(secondStageLoop.contains { $0.date == promise.addingTimeInterval(Double(minute * 60)) && $0.category == ReminderRules.secondCategory }, "Second stage includes every five minutes through thirty")
}
let reopened = reminderPlan(promise: promise, negotiated: reminderNow, ack: reminderNow, now: promise.addingTimeInterval(600))
check(reopened.contains { $0.identifier.hasPrefix("persistent-") && $0.date == promise.addingTimeInterval(900) }, "Reopening without a decision keeps reminders")
check(!HabitRules.isSessionCompleted(completed: false, choice: nil), "Pending day exports false")
check(HabitRules.isSessionCompleted(completed: true, choice: nil), "Completed workout exports true")
check(HabitRules.isSessionCompleted(completed: false, choice: .recovery), "Recovery exports true without counting a workout")
check(!HabitRules.isSessionCompleted(completed: false, choice: .rest), "Rest alone does not export workout or Recovery completion")
check(SessionRules.canEscalateToStandard(completed: [.init(date: reminderNow, mode: .mvr)], now: promise, calendar: calendar), "MVR can escalate later the same day")
check(!SessionRules.canEscalateToStandard(completed: [.init(date: reminderNow, mode: .mvr), .init(date: promise, mode: .standard)], now: promise, calendar: calendar), "Completed Standard removes mini escalation")
check(!SessionRules.canEscalateToStandard(completed: [.init(date: reminderNow, mode: .mvr)], now: date(2026,10,12), calendar: calendar), "MVR mini escalation expires next day")
check(!SessionRules.canEscalateToStandard(completed: [.init(date: reminderNow, mode: .recovery)], now: promise, calendar: calendar), "Recovery does not trigger post-MVR link")
print("Passed \(checks) domain checks")
