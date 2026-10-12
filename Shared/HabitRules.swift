import Foundation

enum CompassionateChoice: String, Codable { case rest, recovery }
struct LocalReminderPlan {
    var identifier: String
    var date: Date
    var body: String
    var category: String
    var repeatsDaily = false
}
enum ReminderRules {
    static let firstCategory = "HABIT_A"
    static let secondCategory = "HABIT_B"
    static let fixedBody = "Discipline is how you respect the life God trusted you with: Do Kmomentum -just 5 min"

    static func commitmentDate(time: Date, now: Date, calendar: Calendar = .current) -> Date? {
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        guard (240...1410).contains(minutes), let date = calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: now), date > now else { return nil }
        return date
    }
    static func compassionAvailable(commitment: Date?, renegotiatedDay: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let commitment, let renegotiatedDay else { return false }
        return calendar.isDate(commitment, inSameDayAs: now) && calendar.isDate(renegotiatedDay, inSameDayAs: now) && commitment <= now
    }
    static func recoveryDay(previousDates: [Date], now: Date, calendar: Calendar = .current) -> Int {
        let days = Set(previousDates.map { calendar.startOfDay(for: $0) })
        var count = 1
        var cursor = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))!
        while days.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count
    }
    static func plan(currentCycleDay: Int?, closed: Bool, commitment: Date?, renegotiatedDay: Date?, acknowledgedAt: Date?, enabled: Bool, customTime: Date?, now: Date, calendar: Calendar = .current) -> [LocalReminderPlan] {
        let promise = commitment.flatMap { calendar.isDate($0, inSameDayAs: now) ? $0 : nil }
        let negotiated = renegotiatedDay.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        func acknowledged(_ date: Date) -> Bool { acknowledgedAt.map { $0 >= date } ?? false }
        var plans: [LocalReminderPlan] = []
        var phaseDue: Date?
        var phaseBody = "Un pequeño paso todavía cuenta."
        if enabled, let currentCycleDay, (1...28).contains(currentCycleDay) {
            for offset in 0..<7 {
                let day = calendar.date(byAdding: .day, value: offset, to: now)!
                let message = HabitRules.cycleReminder(currentCycleDay: (currentCycleDay - 1 + offset) % 28 + 1)!
                let time = calendar.date(bySettingHour: message.hour, minute: 0, second: 0, of: day)!
                if offset == 0 { phaseDue = time; phaseBody = message.body }
                guard time > now, !(offset == 0 && (closed || promise != nil || acknowledged(time))) else { continue }
                plans.append(.init(identifier: "cycle-daily-\(offset)", date: time, body: message.body, category: firstCategory))
            }
        }
        var fixedDue: Date?
        if let customTime {
            let parts = calendar.dateComponents([.hour, .minute], from: customTime)
            fixedDue = calendar.date(bySettingHour: parts.hour ?? 20, minute: parts.minute ?? 0, second: 0, of: now)!
            if closed || promise != nil {
                // shortcut: replace today's recurring alert with six dated ones to silence today; restore recurrence on the next app refresh.
                for offset in 1..<7 {
                    let time = calendar.date(byAdding: .day, value: offset, to: fixedDue!)!
                    plans.append(.init(identifier: "fixed-future-\(offset)", date: time, body: fixedBody, category: firstCategory))
                }
            } else {
                plans.append(.init(identifier: "fixed-daily", date: fixedDue!, body: fixedBody, category: firstCategory, repeatsDaily: true))
            }
        }
        guard !closed, let due = promise ?? fixedDue ?? phaseDue, !acknowledged(due) else { return plans }
        let category = promise != nil && negotiated ? secondCategory : firstCategory
        let body = promise != nil ? "Tu compromiso de hoy te espera. Un pequeño paso también cuenta." : customTime != nil ? fixedBody : phaseBody
        if let promise, promise > now {
            plans.append(.init(identifier: "commitment", date: promise, body: body, category: category))
        }
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        var index = due > now ? 0 : Int(now.timeIntervalSince(due) / 300) + 1
        // shortcut: iOS limits pending local notifications to 64; replenish this bounded queue on app lifecycle changes.
        while plans.count < 64 {
            let time = due.addingTimeInterval(Double(index) * 300)
            guard time <= midnight else { break }
            index += 1
            if plans.contains(where: { $0.date == time }) { continue }
            plans.append(.init(identifier: "persistent-\(plans.count)", date: time, body: body, category: category))
        }
        return plans
    }
}

enum CyclePhase: String, CaseIterable, Codable {
    case menstrual = "Menstrual", follicular = "Folicular", ovulatory = "Ovulatoria", luteal = "Lútea"
    var ceiling: Int { switch self { case .menstrual: 135; case .follicular: 155; case .ovulatory: 158; case .luteal: 150 } }
    var message: String { switch self { case .menstrual: "Lento pero constante."; case .follicular: "Explota tu energía."; case .ovulatory: "Fuerte y continúa."; case .luteal: "La constancia también puede ser suave." } }
}
enum SessionMode: String, CaseIterable, Codable { case standard = "Estándar", intermediate = "Intermedio", mvr = "MVR", recovery = "Recuperación" }
struct SessionPlan {
    let title: String
    let minutes: Int
    let exercises: [String]
    let strength: Bool
    let note: String
}
enum HabitRules {
    static func isSessionCompleted(completed: Bool, choice: CompassionateChoice?) -> Bool {
        completed || choice == .recovery
    }
    static func weeklyProgress(completedDays: Int) -> Double {
        Double(min(7, max(0, completedDays))) / 7
    }
    static func weeklyLiquidFill(completedDays: Int) -> Double {
        let days = min(7, max(0, completedDays))
        if days == 0 { return 0 }
        if days == 7 { return 1 }
        return 0.40 + Double(days - 1) * (0.60 / 6)
    }
    static func cycleReminder(currentCycleDay: Int) -> (hour: Int, body: String)? {
        let hour: Int
        let firstDay: Int
        let copies: [String]
        switch currentCycleDay {
        case 1...5:
            hour = 11; firstDay = 1
            copies = [
                "Día [X] menstrual. Hoy tu cuerpo pide quietud. 5 min de respiración bastan para mantener la racha sin exigirte.",
                "¿Cero energía? Entra a Kmomentum solo para registrar tu día y descansa."
            ]
        case 6...13:
            hour = 16; firstDay = 6
            copies = [
                "Tu fase folicular viene con energía extra. ¿Dejamos lista tu sesión hoy?",
                "Llevas [X] días encendidos. Abre Kmomentum y mantén tu barra semanal creciendo."
            ]
        case 14...16:
            hour = 18; firstDay = 14
            copies = [
                "Pico ovulatorio detectado. Tienes energía de sobra: ¿aprovechamos el modo Estándar hoy?",
                "Rompe tu propia marca esta semana. Tu cuerpo está al 100%."
            ]
        case 17...28:
            hour = 19; firstDay = 17
            copies = [
                "Fase lútea activa. No necesitas hacer 40 minutos; prueba la sesión corta de 5 min para soltar el día.",
                "Tu barra semanal está a una sesión corta de completarse. ¡Mantén el momentum sin presión!"
            ]
        default: return nil
        }
        return (hour, copies[(currentCycleDay - firstDay) % copies.count].replacingOccurrences(of: "[X]", with: String(currentCycleDay)))
    }
    static func completedDaysInWeek(_ dates: [Date], now: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -weekIndex(now, calendar: calendar), to: today)!
        return Set(dates.map { calendar.startOfDay(for: $0) }.filter { $0 >= start && $0 <= today }).count
    }
    static func cycleDay(start: Date, now: Date, length: Int = 30, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: now)).day ?? 0
        return max(0, days) % max(1, length) + 1
    }
    static func phase(day: Int) -> CyclePhase { switch day { case ...7: .menstrual; case 8...13: .follicular; case 14...17: .ovulatory; default: .luteal } }
    static func recoveryDay(start: Date, now: Date, calendar: Calendar = .current) -> Int {
        max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: now)).day ?? 0) + 1)
    }
    static func weekIndex(_ date: Date, calendar: Calendar = .current) -> Int { (calendar.component(.weekday, from: date) + 5) % 7 }
    static func plan(phase: CyclePhase, weekday: Int, mode: SessionMode, recoveryDay: Int) -> SessionPlan {
        let strength = [1, 3, 5].contains(weekday)
        if mode == .recovery {
            if recoveryDay <= 3 { return .init(title: "Respirar también cuenta", minutes: 5, exercises: ["Respiración diafragmática cómoda en cama"], strength: false, note: "Mi cuerpo está gastando energía en el sistema inmune.") }
            if recoveryDay <= 7 { return .init(title: "Volver con suavidad", minutes: 10, exercises: ["Movilidad articular suave en casa"], strength: false, note: "Reactivando el movimiento sin forzar la respiración.") }
            return .init(title: "Reingreso progresivo", minutes: 15, exercises: ["Caminata suave", "Movilidad activa · RPE 5"], strength: false, note: "Aumenta solo si te sientes recuperada.")
        }
        if mode == .mvr {
            return .init(title: weekday == 6 ? "Una pausa para ti" : strength ? "Tu mínimo de fuerza" : "Diez minutos cuentan", minutes: weekday == 6 ? 5 : strength ? 6 : 10, exercises: weekday == 6 ? ["Movilidad y respiración"] : strength ? ["Sentadilla cómoda sin peso", "Empuje suave contra pared", "Marcha en el sitio"] : ["Caminata suave"], strength: strength, note: "Una sesión pequeña. El 100 % de tu compromiso.")
        }
        if weekday == 6 || phase == .menstrual { return .init(title: "Movimiento consciente", minutes: 40, exercises: ["Caminata plana suave", "Movilidad activa · gato-vaca", "Respiración diafragmática"], strength: false, note: "Sin peso externo. Ajusta o descansa según tus síntomas.") }
        if phase == .luteal { return .init(title: "Estabilidad y calma", minutes: 40, exercises: ["Caminata inclinada · 3–4 %", "Deadbug controlado", "Plancha cómoda"], strength: true, note: "Control antes que amplitud.") }
        return .init(title: strength ? "Fuerza con intención" : "Encuentra tu ritmo", minutes: 45, exercises: strength ? ["Jalón en polea", "Sentadilla con mancuerna", "Press Pallof"] : ["Calentamiento caminando", "Caco Z2 · 2 min trote / 1 min caminata", "Vuelta a la calma"], strength: strength, note: phase == .ovulatory ? "Referencia del plan: 15–25 lb, solo si la técnica y tolerancia lo permiten." : "Esfuerzo de referencia · RPE 7.")
    }
}
