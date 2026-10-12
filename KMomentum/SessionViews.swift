import SwiftUI
import SwiftData

struct SessionOptionButtonStyle: ButtonStyle {
    let accent: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 52)
            .foregroundStyle(configuration.role == .destructive ? Color.red : accent)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct ExerciseLogView: View {
    @Environment(\.modelContext) private var context
    let exercise: ExercisePrescription
    let index: Int
    let session: WorkoutSession?
    let previous: [SetResult]
    let preferredWeightUnit: String
    let onError: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(exercise.name).font(.headline)
            if exercise.reps != nil {
                Text("\(exercise.target) · Descanso \(exercise.rest) s").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Label(exercise.target, systemImage: "timer").font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            if !exercise.technique.isEmpty { Label(exercise.technique, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
            if exercise.reps != nil { Label("0° Bloqueo · Mantén micro-flexión activa", systemImage: "exclamationmark.shield").font(.caption2).foregroundStyle(.brown) }
            if exercise.reps != nil, let session {
                ForEach(0..<exercise.sets, id: \.self) { set in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(set + 1)").font(.caption.monospaced()).frame(width: 18)
                            TextField("Reps", text: binding(session, set, \.reps)).keyboardType(.numberPad).textFieldStyle(.roundedBorder).accessibilityLabel("\(exercise.name), serie \(set + 1), repeticiones")
                            TextField("Peso", text: binding(session, set, \.weight)).keyboardType(.decimalPad).textFieldStyle(.roundedBorder).accessibilityLabel("\(exercise.name), serie \(set + 1), peso")
                            Picker("Unidad", selection: binding(session, set, \.unit)) { Text("lb").tag("lb"); Text("kg").tag("kg") }.labelsHidden().pickerStyle(.menu).accessibilityLabel("Unidad de peso, serie \(set + 1)")
                        }
                        if let last = previous.first(where: { $0.set == set }), !last.weight.isEmpty || !last.reps.isEmpty {
                            Text("Anterior: \(last.reps.isEmpty ? "—" : last.reps) reps · \(last.weight.isEmpty ? "—" : last.weight) \(last.unit)").font(.caption2).foregroundStyle(.secondary).padding(.leading, 24)
                        }
                    }
                }
            } else if exercise.reps != nil, !previous.isEmpty {
                Text("Último registro: " + previous.sorted(by: { $0.set < $1.set }).map { "S\($0.set + 1): \($0.reps.isEmpty ? "—" : $0.reps) reps · \($0.weight.isEmpty ? "—" : $0.weight) \($0.unit)" }.joined(separator: " / ")).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
    private func binding(_ session: WorkoutSession, _ set: Int, _ key: WritableKeyPath<SetResult, String>) -> Binding<String> {
        Binding(get: { session.results.first { $0.exercise == index && $0.set == set }?[keyPath: key] ?? (key == \.unit ? preferredWeightUnit : "") }, set: { value in
            var result = session.results.first { $0.exercise == index && $0.set == set } ?? SetResult(exercise: index, set: set, unit: preferredWeightUnit)
            let clean = value.replacingOccurrences(of: ",", with: ".")
            if key == \.reps && !clean.isEmpty && (Int(clean) == nil || !(0...999).contains(Int(clean) ?? -1)) { return }
            if key == \.weight && !clean.isEmpty && (Double(clean) == nil || !(0...9999).contains(Double(clean) ?? -1)) && clean != "." { return }
            if key == \.unit && clean != "kg" && clean != "lb" { return }
            result[keyPath: key] = clean
            do { try session.record(result); try context.save() } catch { context.rollback(); onError(error.localizedDescription) }
        })
    }
}
struct SessionHistoryView: View {
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \DailyLog.date, order: .reverse) private var logs: [DailyLog]
    var body: some View {
        List {
            if sessions.isEmpty && logs.isEmpty { Text("Aquí aparecerán tus sesiones y pesos por serie.").foregroundStyle(.secondary) }
            ForEach(sessions) { session in
                DisclosureGroup {
                    Text(session.planName).font(.caption)
                    Text("Tiempo activo: \(Int(session.elapsed(at: Date())) / 60) min").font(.caption)
                    if let routine = session.routine {
                        ForEach(Array(routine.exercises.enumerated()), id: \.offset) { index, exercise in
                            VStack(alignment: .leading) {
                                Text(exercise.name).font(.headline)
                                Text(exercise.target).font(.caption)
                                ForEach(session.results.filter { $0.exercise == index }.sorted { $0.set < $1.set }, id: \.set) { result in
                                    Text("Serie \(result.set + 1): \(result.reps.isEmpty ? "—" : result.reps) reps · \(result.weight.isEmpty ? "—" : result.weight) \(result.unit)").font(.caption)
                                }
                            }
                        }
                    }
                } label: {
                    VStack(alignment: .leading) {
                        Text(session.routine?.title ?? "Sesión")
                        Text("\(session.date.formatted(date: .abbreviated, time: .shortened)) · \(session.mode.rawValue)").font(.caption)
                        Text(session.status == "completed" ? "Completada ✓" : session.status == "cancelled" ? (logs.contains { $0.compassionateChoice != nil && Calendar.current.isDate($0.date, inSameDayAs: session.date) } ? "Guardada · día de descanso" : "Incompleta") : session.status == "paused" ? "Pausada" : "En curso").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            let legacy = logs.filter { log in !sessions.contains { $0.status == "completed" && Calendar.current.isDate($0.date, inSameDayAs: log.date) } }
            if !legacy.isEmpty { Section("Registros diarios") { ForEach(legacy) { log in
                if let choice = log.compassionateChoice {
                    Label("\(log.date.formatted(date: .abbreviated, time: .omitted)) · \(choice == .recovery ? "Día \(log.recoveryStreakDay ?? 1) de recovery" : "Descanso")", systemImage: "bed.double.fill").foregroundStyle(.purple)
                } else {
                    Text("\(log.date.formatted(date: .abbreviated, time: .omitted)) · \(log.intensity.rawValue) ✓")
                }
            } } }
        }.navigationTitle("Tu historial").toolbar(.visible, for: .navigationBar)
    }
}
struct MVR3DayAlertView: View {
    let count: Int
    let cycleDay: Int?
    let baseline: Int?
    let onChoose: (Int?, String, SessionMode) -> Void
    @State private var pulse = ""
    @State private var reason = ""
    @State private var step = 0
    private var validPulse: Bool { pulse.isEmpty || Int(pulse).map { (25...250).contains($0) } == true }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Has mantenido el momentum durante \(count) días con tu mínimo.").font(.title2).fontDesign(.serif); Text("Revisemos qué necesitas para continuar. No hay una respuesta incorrecta.") }
                if step == 0 {
                    Section("1 · ¿Cómo está tu cuerpo?") {
                        if let day = cycleDay, (22...30).contains(day) { Text("En los días previos al periodo puedes notar cambios de energía. Ajustemos según cómo te sientes.") }
                        Text("Si notas malestar, fiebre o síntomas respiratorios, puedes elegir recuperación. Esta revisión no detecta infecciones.")
                        TextField("Pulso en reposo de hoy · PPM (opcional)", text: $pulse).keyboardType(.numberPad)
                        if !validPulse { Text("Introduce un número entre 25 y 250, o déjalo vacío.").foregroundStyle(.red) }
                        if let baseline, let value = Int(pulse), validPulse { Text("Habitual: \(baseline) PPM · diferencia: \(value - baseline >= 0 ? "+" : "")\(value - baseline) PPM. Es una referencia, no un diagnóstico.").font(.caption) }
                        else if baseline == nil { Text("Puedes registrar tu pulso habitual en Ajustes. No lo leemos de Apple Health.").font(.caption) }
                        Button("Continuar") { step = 1 }.disabled(!validPulse)
                        Button("No lo sé / Omitir") { pulse = ""; step = 1 }
                    }
                } else if step == 1 {
                    Section("2 · ¿Qué dificulta entrenar?") {
                        ForEach(["Tengo poca energía o malestar", "Me cuesta empezar", "Tengo poco tiempo"], id: \.self) { option in Button { reason = option; step = 2 } label: { Text(option) } }
                    }
                    Button("Volver") { step = 0 }
                } else {
                    Section("3 · Tú eliges el siguiente paso") {
                        Text(reason == "Tengo poca energía o malestar" ? "Puedes priorizar recuperación o mantener tu mínimo. No necesitas aumentar la carga." : "Si te sientes bien, prueba el puente de 20 minutos. También puedes mantener MVR o elegir recuperación.")
                        ForEach([SessionMode.intermediate, .mvr, .recovery], id: \.self) { mode in
                            Button(mode == .intermediate ? "Elegir escalón intermedio · 20 min" : mode == .mvr ? "Seguir en MVR" : "Activar recuperación") { onChoose(Int(pulse), reason, mode) }
                        }
                        Text("Puedes probar dos días intermedios antes de volver al completo, sin obligación ni bloqueos.").font(.caption)
                    }
                    Button("Volver") { step = 1 }
                }
            }.navigationTitle("Tu próximo paso").navigationBarTitleDisplayMode(.inline)
        }.interactiveDismissDisabled()
    }
}
struct CelebrationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let confetti: Bool
    var compassionate = false
    var onContinueStandard: (() -> Void)? = nil
    let onClose: () -> Void
    @State private var animate = false
    var body: some View {
        ZStack {
            Color(red: 0.96, green: 0.95, blue: 0.92).ignoresSafeArea()
            if confetti && !compassionate && !reduceMotion {
                GeometryReader { geometry in
                    ForEach(0..<35) { i in
                        ConfettiPiece(index: i, size: geometry.size, animate: animate)
                    }
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
            GeometryReader { geometry in
            ScrollView {
            VStack(spacing: 24) {
                Image(systemName: compassionate ? "bed.double.fill" : "checkmark.seal.fill").font(.system(size: 70)).foregroundStyle(compassionate ? Color.purple : Color.green)
                Text(compassionate ? "Descansa y respira. Mañana retomamos." : "¡Muy bien, mantuviste el momentum!").font(.system(size: 34, design: .serif)).multilineTextAlignment(.center)
                if !compassionate { Text("Tu compromiso de hoy está completo.").foregroundStyle(.secondary) }
                if let onContinueStandard {
                    Text("¿Cómo se siente tu cuerpo ahora?").font(.title3)
                    Button(action: onClose) {
                        Text("Suficiente por hoy, me voy a descansar").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.borderedProminent).tint(.brown)
                    Button(action: onContinueStandard) {
                        Text("¡Renové energías! Quiero hacer el Estándar").frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(.bordered).tint(.brown)
                } else {
                    Button("Continuar", action: onClose).buttonStyle(.borderedProminent).tint(.brown)
                }
            }.multilineTextAlignment(.center).frame(maxWidth: 500).padding(32)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            }
        }.onAppear { animate = true }
    }
}

private struct ConfettiPiece: View {
    let index: Int
    let size: CGSize
    let animate: Bool
    private var color: Color { [Color.orange, .green, .pink, .yellow][index % 4] }
    private var x: CGFloat { size.width * CGFloat((index * 37) % 100) / 100 }
    private var y: CGFloat { animate ? size.height + 30 : -CGFloat(index * 13) }
    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 12)
            .rotationEffect(.degrees(animate ? Double(index * 57) : 0))
            .position(x: x, y: y).opacity(animate ? 0 : 1)
            .animation(.easeOut(duration: 2.8).delay(Double(index % 7) * 0.06), value: animate)
    }
}
