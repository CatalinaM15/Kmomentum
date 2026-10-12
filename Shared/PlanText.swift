import Foundation

struct PlanTextError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}
enum PlanText {
    static let blankTemplate = """
    PLAN:

    # Completa el nombre del plan, el título y los campos de tu primer ejercicio.
    # Puedes repetir el bloque DÍA para añadir días, fases o modos diferentes.
    DÍA: Todos
    FASE: Todas
    MODO: Estándar
    TÍTULO:
    MINUTOS:
    NOTA:

    EJERCICIO:
    SERIES: 1
    # Para fuerza, sustituye DURACIÓN por REPETICIONES.
    DURACIÓN:
    DESCANSO: 0
    TÉCNICA:
    """
    static let days = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"]
    private static func normalized(_ text: String) -> String { text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es")).uppercased() }
    static func export(_ plan: PlanDocument) -> String {
        var lines = ["PLAN: \(plan.name)", "# Cada DÍA inicia un bloque. Usa Todos/Todas para cualquier día/fase.", "# DURACIÓN y DESCANSO se expresan en segundos. Campos omitidos de adaptación usan el plan base."]
        for b in plan.blocks {
            lines += ["", "DÍA: \(b.day.map { days[$0] } ?? "Todos")", "FASE: \(b.phase?.rawValue ?? "Todas")", "MODO: \(b.mode.rawValue)"]
            if let stage = b.stage { lines.append("ETAPA: \(stage)") }
            lines += ["TÍTULO: \(b.routine.title)", "MINUTOS: \(b.routine.minutes)", "NOTA: \(b.routine.note)"]
            for e in b.routine.exercises {
                lines += ["", "EJERCICIO: \(e.name)", "SERIES: \(e.sets)"]
                if let reps = e.reps { lines.append("REPETICIONES: \(reps)") }
                if let seconds = e.seconds { lines.append("DURACIÓN: \(seconds)") }
                lines.append("DESCANSO: \(e.rest)")
                if !e.technique.isEmpty { lines.append("TÉCNICA: \(e.technique)") }
            }
        }
        return lines.joined(separator: "\n")
    }
    static func parse(_ text: String) throws -> PlanDocument {
        guard text.utf8.count <= 250_000 else { throw PlanTextError(message: "El plan es demasiado largo (máximo 250 KB).") }
        var name: String?
        var blocks: [PlanBlock] = []
        var fields: [String:String] = [:]
        var exerciseFields: [String:String] = [:]
        var exercises: [ExercisePrescription] = []
        var blockLine = 0
        func fail(_ message: String) -> PlanTextError { .init(message: "Bloque de la línea \(blockLine): \(message)") }
        func integer(_ value: String?, field: String, range: ClosedRange<Int>) throws -> Int {
            guard let value, let n = Int(value), range.contains(n) else { throw fail("\(field) debe ser un número entre \(range.lowerBound) y \(range.upperBound).") }
            return n
        }
        func flushExercise() throws {
            guard !exerciseFields.isEmpty else { return }
            guard let title = exerciseFields["EJERCICIO"], !title.isEmpty else { throw fail("Falta el nombre del ejercicio.") }
            let sets = try integer(exerciseFields["SERIES"], field: "SERIES de \(title)", range: 1...20)
            guard (exerciseFields["REPETICIONES"] != nil) != (exerciseFields["DURACION"] != nil) else { throw fail("\(title): incluye REPETICIONES o DURACIÓN, solo uno de los dos.") }
            let reps = try exerciseFields["REPETICIONES"].map { try integer($0, field: "REPETICIONES", range: 1...200) }
            let seconds = try exerciseFields["DURACION"].map { try integer($0, field: "DURACIÓN", range: 1...7200) }
            let rest = try integer(exerciseFields["DESCANSO"] ?? "0", field: "DESCANSO", range: 0...900)
            exercises.append(.init(name: title, sets: sets, reps: reps, seconds: seconds, rest: rest, technique: exerciseFields["TECNICA"] ?? ""))
            guard exercises.count <= 30 else { throw fail("Máximo 30 ejercicios por bloque.") }
            exerciseFields = [:]
        }
        func flushBlock() throws {
            guard !fields.isEmpty else { return }
            try flushExercise()
            guard !exercises.isEmpty else { throw fail("Agrega al menos un EJERCICIO.") }
            let day: Int?
            let rawDay = normalized(fields["DIA"] ?? "")
            if rawDay == "TODOS" { day = nil }
            else if let index = days.firstIndex(where: { normalized($0) == rawDay }) { day = index }
            else { throw fail("DÍA debe ser Lunes…Domingo o Todos.") }
            let phase: CyclePhase?
            let rawPhase = normalized(fields["FASE"] ?? "Todas")
            if rawPhase == "TODAS" { phase = nil }
            else if let value = CyclePhase.allCases.first(where: { normalized($0.rawValue) == rawPhase }) { phase = value }
            else { throw fail("FASE no reconocida.") }
            guard let mode = SessionMode.allCases.first(where: { normalized($0.rawValue) == normalized(fields["MODO"] ?? "Estándar") }) else { throw fail("MODO debe ser Estándar, Intermedio, MVR o Recuperación.") }
            let stage = try fields["ETAPA"].map { try integer($0, field: "ETAPA", range: 1...3) }
            if stage != nil && mode != .recovery { throw fail("ETAPA solo se usa en Recuperación.") }
            let minutes = try integer(fields["MINUTOS"], field: "MINUTOS", range: 1...180)
            guard let title = fields["TITULO"], !title.isEmpty else { throw fail("Falta TÍTULO.") }
            let block = PlanBlock(day: day, phase: phase, mode: mode, stage: stage, routine: .init(title: title, minutes: minutes, note: fields["NOTA"] ?? "", exercises: exercises))
            guard !blocks.contains(where: { $0.key == block.key }) else { throw fail("Hay dos bloques para \(block.label).") }
            blocks.append(block); fields = [:]; exercises = []
        }
        let blockKeys: Set<String> = ["DIA","FASE","MODO","ETAPA","TITULO","MINUTOS","NOTA"]
        let exerciseKeys: Set<String> = ["EJERCICIO","SERIES","REPETICIONES","DURACION","DESCANSO","TECNICA"]
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let colon = line.firstIndex(of: ":") else { throw PlanTextError(message: "Línea \(index + 1): usa CAMPO: valor.") }
            let key = normalized(String(line[..<colon]).trimmingCharacters(in: .whitespaces))
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if key == "PLAN" {
                guard name == nil, fields.isEmpty, blocks.isEmpty, !value.isEmpty, value.count <= 100 else { throw PlanTextError(message: "Línea \(index + 1): PLAN debe aparecer una vez al inicio, con un nombre de hasta 100 caracteres.") }
                name = value; continue
            }
            guard name != nil else { throw PlanTextError(message: "Empieza con PLAN: nombre.") }
            if key == "DIA" { try flushBlock(); blockLine = index + 1; fields[key] = value; continue }
            guard fields["DIA"] != nil else { throw PlanTextError(message: "Línea \(index + 1): inicia el bloque con DÍA.") }
            if key == "EJERCICIO" { try flushExercise(); exerciseFields[key] = value; continue }
            if exerciseKeys.contains(key) {
                guard exerciseFields["EJERCICIO"] != nil else { throw fail("\(key) debe ir después de EJERCICIO.") }
                guard exerciseFields[key] == nil else { throw fail("Campo repetido: \(key).") }
                exerciseFields[key] = value
            } else if blockKeys.contains(key) {
                guard exerciseFields.isEmpty && exercises.isEmpty else { throw fail("\(key) debe ir antes del primer ejercicio.") }
                guard fields[key] == nil else { throw fail("Campo repetido: \(key).") }
                fields[key] = value
            } else { throw PlanTextError(message: "Línea \(index + 1): campo desconocido «\(key)».") }
        }
        try flushBlock()
        guard let name, !blocks.isEmpty else { throw PlanTextError(message: "Incluye PLAN y al menos un bloque DÍA con ejercicios.") }
        return .init(name: name, blocks: blocks)
    }
}
