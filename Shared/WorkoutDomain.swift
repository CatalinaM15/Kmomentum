import Foundation

struct ExercisePrescription: Codable, Equatable {
    var name: String
    var sets: Int
    var reps: Int?
    var seconds: Int?
    var rest: Int
    var technique: String
    var target: String {
        if let reps { return "\(sets) × \(reps) reps" }
        let time = seconds ?? 0
        let duration = String(format: "%02d:%02d min", time / 60, time % 60)
        return sets == 1 ? duration : "\(sets) × \(duration)"
    }
    var historyKey: String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es")) }
}
struct WorkoutRoutine: Codable, Equatable {
    var title: String
    var minutes: Int
    var note: String
    var exercises: [ExercisePrescription]
}
struct PlanBlock: Codable, Equatable {
    var day: Int? // Monday = 0; nil means every day
    var phase: CyclePhase?
    var mode: SessionMode
    var stage: Int? // Recovery stages: 1 acute, 2 remission, 3 return
    var routine: WorkoutRoutine
    var key: String { "\(day ?? -1)|\(phase?.rawValue ?? "Todas")|\(mode.rawValue)|\(stage ?? 0)" }
    var label: String { "\(day.map { PlanText.days[$0] } ?? "Todos") · \(phase?.rawValue ?? "Todas") · \(mode.rawValue)\(stage.map { " · Etapa \($0)" } ?? "")" }
}
struct PlanDocument: Codable, Equatable {
    var name: String
    var blocks: [PlanBlock]
    func routine(phase: CyclePhase, weekday: Int, mode: SessionMode, recoveryDay: Int) -> WorkoutRoutine {
        let stage = recoveryDay <= 3 ? 1 : recoveryDay <= 7 ? 2 : 3
        let matches = blocks.filter { $0.mode == mode && ($0.phase == nil || $0.phase == phase) && ($0.day == nil || $0.day == weekday) && ($0.stage == nil || $0.stage == stage) }
        func priority(_ b: PlanBlock) -> Int { (b.phase == nil ? 0 : 4) + (b.day == nil ? 0 : 2) + (b.stage == nil ? 0 : 1) }
        return matches.max(by: { priority($0) < priority($1) })?.routine ?? DefaultWorkouts.routine(phase: phase, weekday: weekday, mode: mode, recoveryDay: recoveryDay)
    }
}
enum DefaultWorkouts {
    static func timed(_ name: String, _ seconds: Int, sets: Int = 1, rest: Int = 0, technique: String = "") -> ExercisePrescription {
        .init(name: name, sets: sets, reps: nil, seconds: seconds, rest: rest, technique: technique)
    }
    static func strength(_ name: String, sets: Int = 3, reps: Int = 10, rest: Int = 60, technique: String = "Mantén micro-flexión activa; evita bloquear articulaciones.") -> ExercisePrescription {
        .init(name: name, sets: sets, reps: reps, seconds: nil, rest: rest, technique: technique)
    }
    static func routine(phase: CyclePhase, weekday: Int, mode: SessionMode, recoveryDay: Int) -> WorkoutRoutine {
        if mode == .intermediate {
            return .init(title: "Reconecta en 20 minutos", minutes: 20, note: "Solo cumple los primeros 5 minutos. Si quieres parar, completas el día con MVR; si no, terminas los 20 min. Duración orientativa: no apresures las series.", exercises: [
                timed("Caminata en caminadora", 720, technique: "Referencia ajustable: 4,8–5,2 km/h · inclinación 1,5 %. Respira cómodamente. Ante síntomas respiratorios, detente y sigue tu plan de manejo del asma."),
                strength("Sentadilla goblet a banco", sets: 2, rest: 45, technique: "Referencia: 10–12 lb. Toca suavemente el banco y sube sin bloquear rodillas."),
                strength("Press Pallof en polea", sets: 2, rest: 30, technique: "10 repeticiones por lado. Mantén 2 segundos al frente resistiendo la rotación; micro-flexión activa.")])
        }
        let old = HabitRules.plan(phase: phase, weekday: weekday, mode: mode, recoveryDay: recoveryDay)
        let exercises: [ExercisePrescription]
        if mode == .recovery {
            exercises = recoveryDay <= 3 ? [timed("Respiración diafragmática cómoda", 300)] : recoveryDay <= 7 ? [timed("Movilidad articular suave", 600)] : [timed("Caminata suave", 600), timed("Movilidad activa · RPE 5", 300)]
        } else if mode == .mvr {
            exercises = weekday == 6 ? [timed("Movilidad y respiración", 300)] : [1,3,5].contains(weekday) ? [strength("Sentadilla sin peso", sets: 2, reps: 8, rest: 30), strength("Empuje suave contra pared", sets: 2, reps: 8, rest: 30), timed("Marcha en el sitio", 120)] : [timed("Caminata suave", 600)]
        } else if weekday == 6 || phase == .menstrual {
            exercises = [timed("Caminata plana suave", 1800), timed("Movilidad activa · gato-vaca", 300), timed("Respiración diafragmática", 300)]
        } else if phase == .luteal {
            exercises = [timed("Caminata inclinada · 3–4 %", 1800), strength("Deadbug controlado", sets: 2, reps: 8, rest: 45), timed("Plancha cómoda", 20, sets: 3, rest: 40, technique: "Evita bloquear los codos; mantén una posición cómoda.")]
        } else if [1,3,5].contains(weekday) {
            exercises = [strength("Jalón en polea"), strength("Sentadilla con mancuerna"), strength("Press Pallof en polea", technique: "10 repeticiones por lado. Mantén micro-flexión activa.")]
        } else {
            exercises = [timed("Calentamiento caminando", 300), timed("Caco · 2 min trote / 1 min caminata", 2100), timed("Vuelta a la calma", 300)]
        }
        return .init(title: old.title, minutes: old.minutes, note: old.note, exercises: exercises)
    }
    static var document: PlanDocument {
        var blocks: [PlanBlock] = []
        for phase in CyclePhase.allCases { for day in 0..<7 { blocks.append(.init(day: day, phase: phase, mode: .standard, stage: nil, routine: routine(phase: phase, weekday: day, mode: .standard, recoveryDay: 1))) } }
        for day in 0..<7 { blocks.append(.init(day: day, phase: nil, mode: .mvr, stage: nil, routine: routine(phase: .menstrual, weekday: day, mode: .mvr, recoveryDay: 1))) }
        blocks.append(.init(day: nil, phase: nil, mode: .intermediate, stage: nil, routine: routine(phase: .luteal, weekday: 0, mode: .intermediate, recoveryDay: 1)))
        for (stage, day) in [(1,1),(2,4),(3,8)] { blocks.append(.init(day: nil, phase: nil, mode: .recovery, stage: stage, routine: routine(phase: .menstrual, weekday: 0, mode: .recovery, recoveryDay: day))) }
        return .init(name: "Mi plan KMomentum", blocks: blocks)
    }
}
struct SetResult: Codable, Equatable {
    var exercise: Int
    var set: Int
    var reps: String = ""
    var weight: String = ""
    var unit: String = "lb"
}
struct CompletionDay { var date: Date; var mode: SessionMode }
struct MVREpisode: Equatable { var start: Date; var count: Int }
enum SessionRules {
    static func canEscalateToStandard(completed: [CompletionDay], now: Date, calendar: Calendar = .current) -> Bool {
        let today = completed.filter { calendar.isDate($0.date, inSameDayAs: now) }
        return today.contains { $0.mode == .mvr } && !today.contains { $0.mode == .standard }
    }
    static func shortSessionFinished(mode: SessionMode, minutes: Int, elapsed: TimeInterval, endedEarly: Bool = false) -> Bool {
        (mode == .mvr || mode == .recovery) && (endedEarly || (minutes > 0 && elapsed >= Double(minutes) * 60))
    }
    static func elapsed(accumulated: TimeInterval, runningSince: Date?, now: Date) -> TimeInterval {
        max(0, accumulated) + max(0, runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }
    static func mvrEpisode(logs: [CompletionDay], now: Date, calendar: Calendar = .current) -> MVREpisode? {
        // A calendar day is counted once. A missing day or any other mode breaks the streak.
        let today = calendar.startOfDay(for: now)
        let grouped = Dictionary(grouping: logs.filter { $0.date <= now }, by: { calendar.startOfDay(for: $0.date) })
        var cursor = grouped[today] == nil ? calendar.date(byAdding: .day, value: -1, to: today)! : today
        var start = cursor; var count = 0
        while let entries = grouped[cursor], entries.allSatisfy({ $0.mode == .mvr }) {
            count += 1; start = cursor
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor)!
        }
        return count >= 3 ? MVREpisode(start: start, count: count) : nil
    }
}
