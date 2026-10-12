import Foundation
enum WidgetDayState { case pending, completed, paused }
struct WidgetSnapshot: Codable {
    var date: Date
    var completed: Bool
    var title: String
    var minutes: Int = 0
    var exercises: Int = 0
    var mvrMinutes: Int = 0
    var hasPlan: Bool = false
    var week: [Bool] = Array(repeating: false, count: 7)
    var cyclePhase: CyclePhase? = nil
    var pausedWeek: [Bool]? = nil
    var commitment: Date? = nil
    var recoveryActive: Bool? = nil
    func weekState(at index: Int) -> WidgetDayState {
        guard (0..<7).contains(index), index <= HabitRules.weekIndex(date) else { return .pending }
        if let pausedWeek, pausedWeek.indices.contains(index), pausedWeek[index] { return .paused }
        return week.indices.contains(index) && week[index] ? .completed : .pending
    }
    var weeklyCompletedDays: Int { (0..<7).filter { weekState(at: $0) == .completed }.count }
    var weeklyPercentage: Int { Int((HabitRules.weeklyProgress(completedDays: weeklyCompletedDays) * 100).rounded()) }
    var commitmentMessage: String {
        if paused || recoveryActive == true { return "Día de pausa y respiración" }
        if completed { return "Buen trabajo!" }
        if let commitment, Calendar.current.isDate(commitment, inSameDayAs: date) {
            return "Tu compromiso de hoy: \(commitment.formatted(date: .omitted, time: .shortened))"
        }
        return "Un pequeño paso también cuenta."
    }
    var paused: Bool {
        weekState(at: HabitRules.weekIndex(date)) == .paused
    }
    var mediumMessage: String {
        if paused { return "Descansa y respira. Mañana retomamos." }
        if completed { return "Buen trabajo!" }
        switch cyclePhase {
        case .menstrual: return "Hoy, moverte con suavidad también cuenta."
        case .follicular: return "Aprovecha tu impulso. Tu sesión te espera."
        case .ovulatory: return "¿Vamos con Estándar hoy?"
        case .luteal: return "Una sesión corta basta para mantener el momentum."
        case nil: return "Un pequeño paso hoy también cuenta."
        }
    }
    static let group = "group.com.kmomentum.app"
    static var timeline: [WidgetSnapshot] {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: "timeline-v2"), let values = try? JSONDecoder().decode([WidgetSnapshot].self, from: data) else { return [] }
        return values
    }
    static func current(at now: Date = Date()) -> WidgetSnapshot {
        timeline.first { Calendar.current.isDate($0.date, inSameDayAs: now) } ?? .init(date: now, completed: false, title: "Abre la app para actualizar")
    }
    static func save(_ entries: [WidgetSnapshot]) throws {
        let data = try JSONEncoder().encode(entries)
        UserDefaults(suiteName: group)?.set(data, forKey: "timeline-v2")
    }
}
