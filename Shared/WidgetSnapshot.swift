import Foundation
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
    var paused: Bool {
        let index = HabitRules.weekIndex(date)
        return pausedWeek?.indices.contains(index) == true ? pausedWeek![index] : false
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
