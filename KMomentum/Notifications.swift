import Foundation
import UserNotifications
import AppIntents
import Observation
import UIKit

enum ReminderIntent: String { case renegotiate, rest, recovery, chooseCompassion }
struct PendingReminderAction: Identifiable {
    let id = UUID()
    let intent: ReminderIntent
    let day: Date
}

@MainActor final class MomentumAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationScheduler.shared.configure(delegate: self)
        assert(UNUserNotificationCenter.current().delegate === self, "The notification receiver must be registered before launch finishes.")
        return true
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            NotificationScheduler.shared.handle(response)
            completionHandler()
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

@MainActor @Observable final class NotificationScheduler: NSObject {
    static let shared = NotificationScheduler()
    var startSessionRequest: UUID?
    var requestedMode: SessionMode?
    var showCommitment = false
    var pendingReminderAction: PendingReminderAction?
    var status: String?
    private let center = UNUserNotificationCenter.current()
    private var schedulingTask: Task<Void, Never>?
    private var generation = 0
    private var ownedIdentifiers: [String] {
        (0..<7).flatMap { ["sunset-\($0)", "cycle-daily-\($0)", "fixed-future-\($0)"] } + ["commitment", "fixed-daily"] + (0..<64).map { "persistent-\($0)" }
    }
    func configure(delegate: UNUserNotificationCenterDelegate) {
        center.delegate = delegate
        let commit = UNNotificationAction(identifier: "COMMIT", title: "Establecer como la nueva hora de hoy", options: .foreground)
        let mvr = UNNotificationAction(identifier: "MVR", title: "Activar MVR", options: .foreground)
        let rest = UNNotificationAction(identifier: "REST", title: "A descansar", options: .foreground)
        let recovery = UNNotificationAction(identifier: "RECOVERY", title: "Recovery", options: .foreground)
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ReminderRules.firstCategory, actions: [commit, mvr], intentIdentifiers: []),
            UNNotificationCategory(identifier: ReminderRules.secondCategory, actions: [rest, recovery], intentIdentifiers: []),
            UNNotificationCategory(identifier: "HABIT", actions: [commit, mvr], intentIdentifiers: [])
        ])
    }
    func authorize() async -> Bool {
        do { return try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { status = error.localizedDescription; return false }
    }
    func schedule(currentCycleDay: Int?, completed: Bool, commitment: Date?, enabled: Bool, customReminderTime: Date?, renegotiatedDay: Date?, acknowledgedAt: Date?) async {
        generation += 1
        let currentGeneration = generation
        schedulingTask?.cancel()
        await schedulingTask?.value
        guard generation == currentGeneration else { return }
        let plans = ReminderRules.plan(currentCycleDay: currentCycleDay, closed: completed, commitment: commitment, renegotiatedDay: renegotiatedDay, acknowledgedAt: acknowledgedAt, enabled: enabled, customTime: customReminderTime, now: Date())
        let task = Task { @MainActor in
            self.center.removePendingNotificationRequests(withIdentifiers: self.ownedIdentifiers)
            for plan in plans {
                guard !Task.isCancelled else { return }
                await self.add(plan)
            }
        }
        schedulingTask = task
        await task.value
    }
    func stopPersistence() async {
        generation += 1
        let currentGeneration = generation
        schedulingTask?.cancel()
        await schedulingTask?.value
        guard generation == currentGeneration else { return }
        center.removePendingNotificationRequests(withIdentifiers: (0..<64).map { "persistent-\($0)" })
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { self.ownedIdentifiers.contains($0.request.identifier) && Calendar.current.isDateInToday($0.date) }.map { $0.request.identifier })
    }
    private func add(_ plan: LocalReminderPlan) async {
        let content = UNMutableNotificationContent()
        content.title = "Kmomentum"; content.body = plan.body
        content.sound = .default; content.categoryIdentifier = plan.category; content.interruptionLevel = .timeSensitive
        let fields: Set<Calendar.Component> = plan.repeatsDaily ? [.hour, .minute] : [.year, .month, .day, .hour, .minute]
        let trigger = UNCalendarNotificationTrigger(dateMatching: Calendar.current.dateComponents(fields, from: plan.date), repeats: plan.repeatsDaily)
        do { try await center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger)) }
        catch { status = "No se pudo programar: \(error.localizedDescription)" }
    }
    func handle(_ response: UNNotificationResponse) {
        if response.actionIdentifier == "MVR" { self.requestedMode = .mvr }
        let intent: ReminderIntent?
        switch response.actionIdentifier {
        case "COMMIT": intent = .renegotiate
        case "REST": intent = .rest
        case "RECOVERY": intent = .recovery
        default: intent = response.notification.request.content.categoryIdentifier == ReminderRules.secondCategory ? .chooseCompassion : nil
        }
        if let intent { self.pendingReminderAction = .init(intent: intent, day: response.notification.date) }
    }
}
struct TriggerMissedHabitShortcut: AppIntent {
    static var title: LocalizedStringResource = "Abrir rescate del hábito"
    static var description = IntentDescription("Abre KMomentum en modo mínimo viable. Puedes añadir esta acción a una automatización horaria de Atajos.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        NotificationScheduler.shared.requestedMode = .mvr
        return .result()
    }
}
struct StartDailySessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Empezar KMomentum"
    static var description = IntentDescription("Abre la app e inicia o reanuda tu sesión de hoy.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        NotificationScheduler.shared.startSessionRequest = UUID()
        return .result()
    }
}
struct WeeklyProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "Consultar progreso semanal"
    static var description = IntentDescription("Devuelve el porcentaje entero que muestra el corazón semanal de KMomentum.")
    static var openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let now = Date(), calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -HabitRules.weekIndex(now), to: calendar.startOfDay(for: now))!
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        let logs = try MomentumStore.logs(from: start, until: end)
        let days = HabitRules.completedDaysInWeek(logs.filter(\.completed).map(\.date), now: now)
        let percent = Int((HabitRules.weeklyProgress(completedDays: days) * 100).rounded())
        return .result(value: percent, dialog: "Tu progreso semanal es del \(percent) por ciento: \(days) de 7 días completados.")
    }
}
struct SessionCompletedIntent: AppIntent {
    static var title: LocalizedStringResource = "Consultar isSessionCompleted"
    static var description = IntentDescription("Devuelve verdadero si hoy completaste una sesión o marcaste Recovery. Úsalo como condición en tus automatizaciones.")
    static var openAppWhenRun = false
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let isSessionCompleted = try MomentumStore.logs(from: start, until: end).contains { $0.isSessionCompleted }
        let dialog: IntentDialog = isSessionCompleted ? "Hoy ya completaste tu sesión o elegiste Recovery." : "Hoy aún no hay una sesión completada ni Recovery registrado."
        return .result(value: isSessionCompleted, dialog: dialog)
    }
}
struct MomentumShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartDailySessionIntent(), phrases: ["Empezar \(.applicationName)", "Iniciar mi sesión en \(.applicationName)"], shortTitle: "Empezar sesión", systemImageName: "play.fill")
        AppShortcut(intent: WeeklyProgressIntent(), phrases: ["Cuál es mi progreso en \(.applicationName)"], shortTitle: "Progreso semanal", systemImageName: "heart.fill")
        AppShortcut(intent: SessionCompletedIntent(), phrases: ["Ya completé mi sesión de \(.applicationName)"], shortTitle: "Estado de hoy", systemImageName: "checkmark.circle")
        AppShortcut(intent: TriggerMissedHabitShortcut(), phrases: ["Activa mi mínimo en \(.applicationName)"], shortTitle: "Mi mínimo viable", systemImageName: "bolt.heart")
    }
}
