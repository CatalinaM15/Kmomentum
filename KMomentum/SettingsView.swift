import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var state: UserCycleState
    @Bindable var health: HealthService
    let onCommitment: () -> Void
    let onRemindersChanged: () -> Void
    @State private var baseline = ""
    @State private var editingBaseline = false
    @State private var confirmBaseline = false
    @FocusState private var baselineFocused: Bool
    @State private var message: String?
    @AppStorage("healthConnected") private var healthConnected = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Entrenamiento") {
                    Picker("Unidad de peso", selection: $state.preferredWeightUnit) {
                        Text("Kilogramos (kg)").tag("kg")
                        Text("Libras (lb)").tag("lb")
                    }.onChange(of: state.preferredWeightUnit) { _, _ in persist() }
                }
                Section("Apple Health") {
                    Text(health.status)
                    Button("Conectar Apple Health") { Task { await health.connect() } }
                        .disabled(healthConnected)
                    Text("Solo consultamos el periodo y los pasos. El pulso se introduce manualmente y no se lee de Salud. Si no hay datos o permiso de lectura, mostramos «Sin datos».").font(.caption)
                }
                Section("Pulso habitual en reposo") {
                    if editingBaseline {
                        TextField("PPM · opcional", text: $baseline).keyboardType(.numberPad)
                            .focused($baselineFocused).accessibilityLabel("Pulso habitual en reposo, PPM")
                        HStack {
                            Button("Guardar") {
                                let trimmed = baseline.trimmingCharacters(in: .whitespaces)
                                guard trimmed.isEmpty || Int(trimmed).map({ (25...250).contains($0) }) == true else { message = "Introduce un número entre 25 y 250, o deja vacío para quitar la referencia."; return }
                                baselineFocused = false
                                confirmBaseline = true
                            }
                            Spacer()
                            Button("Cancelar") { editingBaseline = false; baselineFocused = false; message = nil }
                        }.buttonStyle(.borderless)
                    } else {
                        HStack {
                            Text(state.restingPulseBaseline.map { "\($0) PPM" } ?? "Sin referencia")
                                .font(.headline).monospacedDigit()
                            Spacer()
                            Button {
                                baseline = state.restingPulseBaseline.map(String.init) ?? ""
                                message = nil; editingBaseline = true; baselineFocused = true
                            } label: {
                                Image(systemName: "pencil").frame(width: 44, height: 44)
                            }.buttonStyle(.borderless).accessibilityLabel("Modificar pulso habitual en reposo")
                        }
                    }
                    Text("Tras tres días de MVR puedes comparar el pulso que ingreses con esta referencia. No determina por sí solo qué sesión debes hacer.").font(.caption)
                }
                Section("Celebración") {
                    Toggle("Confeti al completar", isOn: $state.confettiEnabled).onChange(of: state.confettiEnabled) { _, _ in persist() }
                    Toggle("Pulso háptico", isOn: $state.hapticsEnabled).onChange(of: state.hapticsEnabled) { _, _ in persist() }
                    Text("Todos los modos celebran igual. El confeti respeta Reducir movimiento del iPhone.").font(.caption)
                }
                Section("Recordatorio diario fijo") {
                    Toggle("Activar recordatorio diario", isOn: Binding(get: { state.customReminderEnabled }, set: { enabled in
                        Task {
                            let allowed = enabled ? await NotificationScheduler.shared.authorize() : false
                            state.customReminderEnabled = allowed
                            if allowed, state.customReminderTime == nil { state.customReminderTime = defaultReminderTime }
                            if persist() { onRemindersChanged() }
                            if enabled && !allowed { message = "Permite las notificaciones en Ajustes de iOS." }
                        }
                    }))
                    if state.customReminderEnabled {
                        DatePicker("Hora diaria", selection: Binding(get: { state.customReminderTime ?? defaultReminderTime }, set: { time in
                            state.customReminderTime = time
                            if persist() { onRemindersChanged() }
                        }), displayedComponents: .hourAndMinute)
                        Text("Discipline is how you respect the life God trusted you with: Do Kmomentum -just 5 min").font(.caption)
                    }
                }
                Section("Tu recordatorio") {
                    Toggle("Recordatorio diario según tu ciclo", isOn: Binding(get: { state.remindersEnabled }, set: { enabled in Task {
                        let allowed = enabled ? await NotificationScheduler.shared.authorize() : false
                        state.remindersEnabled = allowed
                        if persist() { onRemindersChanged() }
                        if enabled && !allowed { message = "Permite las notificaciones en Ajustes de iOS." }
                    } }))
                    Button("Elegir hora para hoy", action: onCommitment)
                    if let date = state.commitment, Calendar.current.isDateInToday(date) { Text("Hoy: \(date.formatted(date: .omitted, time: .shortened))").font(.caption) }
                    if let status = NotificationScheduler.shared.status { Text(status).font(.caption) }
                    Text("Menstrual: 11:00 · Folicular: 16:00 · Ovulatoria: 18:00 · Lútea: 19:00. Registra el inicio de tu periodo para recibirlos. Se programan siete días y se renuevan al abrir la app.").font(.caption)
                }
                Section {
                    NavigationLink("Administrar planes") { PlanLibraryView(state: state) }
                    NavigationLink("Historial de sesiones") { SessionHistoryView() }
                } footer: { Text("Los planes y registros se guardan en este dispositivo. Las adaptaciones son referencias editables; ajusta el ejercicio a tus síntomas y recomendaciones clínicas.") }
                if let message { Section { Text(message).font(.subheadline) } }
            }.navigationTitle("A tu manera").toolbar { Button("Listo") { dismiss() } }
                .alert("¿Guardar referencia?", isPresented: $confirmBaseline) {
                    Button("Guardar") {
                        state.restingPulseBaseline = Int(baseline.trimmingCharacters(in: .whitespaces))
                        if persist() { editingBaseline = false; message = nil }
                    }
                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text(baseline.trimmingCharacters(in: .whitespaces).isEmpty ? "Se quitará la referencia actual." : "Nuevo pulso habitual: \(baseline.trimmingCharacters(in: .whitespaces)) PPM.")
                }
        }
    }
    private var defaultReminderTime: Date { Calendar.current.date(bySettingHour: 20, minute: 0, second: 0, of: Date()) ?? Date() }
    @discardableResult private func persist() -> Bool { do { try context.save(); return true } catch { context.rollback(); message = error.localizedDescription; return false } }
}
