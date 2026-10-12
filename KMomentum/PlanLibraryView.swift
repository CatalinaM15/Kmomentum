import SwiftUI
import SwiftData

struct PlanLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedPlan.updatedAt, order: .reverse) private var plans: [SavedPlan]
    @Bindable var state: UserCycleState
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Text("Guardar conserva el plan. Activar lo elige para tus próximas sesiones. Tu entrenamiento en curso y tu historial no cambian.").font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("Crear desde una copia del plan base") { PlanEditorView(plan: nil) }
            }
            ForEach(plans) { plan in
                Section {
                    NavigationLink { PlanEditorView(plan: plan) } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(plan.name).font(.headline)
                            Text(state.activePlanID == plan.id ? "Activo" : "Guardado · sin activar").font(.caption).foregroundStyle(state.activePlanID == plan.id ? .green : .secondary)
                        }
                    }
                    HStack {
                        Button(state.activePlanID == plan.id ? "Dejar sin seleccionar" : "Activar") {
                            guard plan.document != nil else { error = "Valida el plan antes de activarlo."; return }
                            state.activePlanID = state.activePlanID == plan.id ? nil : plan.id
                            persist()
                        }.buttonStyle(.bordered)
                        Spacer()
                        Button("Duplicar") {
                            guard var document = plan.document else { error = "No se pudo leer este plan."; return }
                            document.name += " · copia"
                            context.insert(SavedPlan(document: document)); persist()
                        }.buttonStyle(.bordered)
                    }
                }
            }
        }.navigationTitle("Administrar planes")
            .alert("No se pudo guardar", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
    }
    private func persist() { do { try context.save() } catch { context.rollback(); self.error = error.localizedDescription } }
}
struct PlanEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let plan: SavedPlan?
    @State private var text: String
    @State private var validated: PlanDocument?
    @State private var message: String?
    @State private var preview = false
    @State private var copied = false
    @State private var discard = false
    private let original: String
    init(plan: SavedPlan?) {
        self.plan = plan
        let value = plan?.text ?? PlanText.export(DefaultWorkouts.document)
        original = value; _text = State(initialValue: value)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edita esta plantilla o pega un plan. DURACIÓN y DESCANSO: segundos. Sin IA. Los bloques no definidos conservan las adaptaciones del plan base.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(copied ? "Copiado ✓" : "Copiar texto") { UIPasteboard.general.string = text; copied = true }
                PasteButton(payloadType: String.self) { values in if let first = values.first { text = first; validated = nil } }
                Spacer()
                if let plan, !plan.revisions.isEmpty {
                    Menu("Versiones") { ForEach(plan.revisions) { version in Button(version.date.formatted(date: .abbreviated, time: .shortened)) { text = version.text; validated = nil; message = "Versión recuperada en el editor. Valida y guarda para aplicarla." } } }
                }
            }.font(.caption)
            TextEditor(text: $text).font(.system(.caption, design: .monospaced)).autocorrectionDisabled().textInputAutocapitalization(.never).accessibilityLabel("Texto del plan")
                .onChange(of: text) { _, _ in validated = nil; copied = false }
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.2)))
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            Button("Validar y ver cambios") {
                do { validated = try PlanText.parse(text); message = nil; preview = true }
                catch { message = error.localizedDescription }
            }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
        }.padding().navigationTitle(plan == nil ? "Nuevo plan" : "Editar plan").navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Volver") { if text != original { discard = true } else { dismiss() } } } }
            .confirmationDialog("¿Salir sin guardar estos cambios?", isPresented: $discard, titleVisibility: .visible) { Button("Descartar cambios", role: .destructive) { dismiss() }; Button("Seguir editando", role: .cancel) {} }
            .sheet(isPresented: $preview) {
                if let document = validated {
                    NavigationStack {
                        List {
                            Section("\(document.name) · \(document.blocks.count) bloques") {
                                Text("Guardar no activa un plan nuevo. Si editas el activo, los cambios se aplican a la próxima sesión.")
                                Text(changeSummary(document)).font(.subheadline)
                            }
                            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                                DisclosureGroup(block.label) {
                                    Text("\(block.routine.title) · \(block.routine.minutes) min").font(.headline)
                                    ForEach(Array(block.routine.exercises.enumerated()), id: \.offset) { _, exercise in
                                        VStack(alignment: .leading) { Text(exercise.name); Text("\(exercise.target) · Descanso \(exercise.rest) s").font(.caption); if !exercise.technique.isEmpty { Text(exercise.technique).font(.caption).foregroundStyle(.secondary) } }
                                    }
                                    if let old = plan?.document?.blocks.first(where: { $0.key == block.key }), old != block {
                                        Text("Antes: \(old.routine.title) · \(old.routine.minutes) min").font(.caption).foregroundStyle(.secondary)
                                        ForEach(Array(old.routine.exercises.enumerated()), id: \.offset) { _, e in Text("\(e.name): \(e.target), descanso \(e.rest) s").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }.navigationTitle("Revisar cambios").toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Editar") { preview = false } }
                            ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save(document) } }
                        }
                    }
                }
            }
    }
    private func changeSummary(_ document: PlanDocument) -> String {
        guard let previous = plan?.document else { return "Se guardará un plan nuevo sin seleccionar." }
        let added = document.blocks.filter { b in !previous.blocks.contains { $0.key == b.key } }.count
        let removed = previous.blocks.filter { b in !document.blocks.contains { $0.key == b.key } }.count
        let changed = document.blocks.filter { b in previous.blocks.contains { $0.key == b.key && $0 != b } }.count
        return "\(changed) bloques modificados · \(added) nuevos · \(removed) eliminados. Los eliminados usarán la adaptación base."
    }
    private func save(_ document: PlanDocument) {
        do {
            if let plan { try plan.replace(document: document, text: text) }
            else { let added = SavedPlan(document: document); added.text = text; context.insert(added) }
            try context.save(); preview = false; dismiss()
        } catch { context.rollback(); message = error.localizedDescription; preview = false }
    }
}
