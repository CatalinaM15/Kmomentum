import SwiftUI
import SwiftData
import WidgetKit

struct DashboardView: View {
    private enum EndAction { case pause, finish, mvr, cancel }
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var states: [UserCycleState]
    @Query(sort: \DailyLog.date, order: .reverse) private var logs: [DailyLog]
    @Query private var plans: [SavedPlan]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @State private var health = HealthService()
    @State private var now = Date()
    @State private var showSettings = false
    @State private var showPeriod = false
    @State private var showCommitment = false
    @State private var commitmentFromSettings = false
    @State private var waitingForReminderDismissal = false
    @State private var commitmentConfirmation: String?
    @State private var showCommitmentConfirmation = false
    @State private var showCompassionOptions = false
    @State private var compassionPresentedFor: Date?
    @State private var pendingCompassion: CompassionateChoice?
    @State private var startFromCompassion: SessionMode?
    @State private var showCompassionCelebration = false
    @State private var selectedDate = Date()
    @State private var commitmentDate = Date()
    @State private var error: String?
    @State private var endOptions = false
    @State private var cancelConfirmation = false
    @State private var pendingEndAction: EndAction?
    @State private var showCelebration = false
    @State private var reviewEpisode: MVREpisode?
    @State private var ready = false
    @State private var pendingURL: URL?
    @State private var showSessionDetails = false
    @State private var showShortSessionCompletion = false
    @State private var shortSessionChoice: SessionMode?
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var state: UserCycleState? { states.first }
    private var selectedPlan: SavedPlan? { plans.first { $0.id == state?.activePlanID } }
    private var currentSession: WorkoutSession? { sessions.first { $0.isOpen && Calendar.current.isDate($0.date, inSameDayAs: now) } }
    private var mode: SessionMode { currentSession?.mode ?? (state?.isSickModeActive == true ? .recovery : SessionMode(rawValue: state?.selectedMode ?? "") ?? .standard) }
    private var day: Int { HabitRules.cycleDay(start: state?.lastPeriodStartDate ?? now, now: now, length: state?.cycleLengthDays ?? 30) }
    private var phase: CyclePhase { state?.hasPeriodDate == true ? HabitRules.phase(day: day) : .menstrual }
    private var recoveryDay: Int { HabitRules.recoveryDay(start: state?.sickModeStartDay ?? now, now: now) }
    private var routine: WorkoutRoutine? { currentSession?.routine ?? selectedPlan?.document?.routine(phase: phase, weekday: HabitRules.weekIndex(now), mode: mode, recoveryDay: recoveryDay) }
    private var completed: Bool { logs.contains { $0.completed && Calendar.current.isDate($0.date, inSameDayAs: now) } }
    private var compassionateLog: DailyLog? { logs.first { $0.compassionateChoice != nil && Calendar.current.isDate($0.date, inSameDayAs: now) } }
    private var completedMVRSession: WorkoutSession? {
        let history = sessions.filter { $0.status == "completed" }.map { CompletionDay(date: $0.date, mode: $0.mode) }
        guard SessionRules.canEscalateToStandard(completed: history, now: now) else { return nil }
        return sessions.first { $0.status == "completed" && $0.mode == .mvr && Calendar.current.isDate($0.date, inSameDayAs: now) }
    }
    private var dayClosed: Bool { completed || compassionateLog != nil }
    private var compassionAvailable: Bool { ReminderRules.compassionAvailable(commitment: state?.commitment, renegotiatedDay: state?.commitmentRenegotiatedDay, now: now) }
    private var accent: Color { switch phase { case .menstrual: Color(red: 0.65, green: 0.35, blue: 0.28); case .follicular: Color(red: 0.27, green: 0.44, blue: 0.34); case .ovulatory: Color(red: 0.64, green: 0.43, blue: 0.14); case .luteal: Color(red: 0.48, green: 0.40, blue: 0.29) } }
    var body: some View {
        NavigationStack {
            ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    VStack(alignment: .leading, spacing: 12) {
                        cycleCard
                        if !dayClosed, currentSession == nil, routine != nil {
                            Button { startSession() } label: {
                                Label("Iniciar sesión", systemImage: "play.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 52)
                            }.buttonStyle(.borderedProminent).tint(accent).disabled(!ready)
                        }
                    }
                    if (!dayClosed || currentSession != nil), selectedPlan != nil { adaptationCard }
                    if compassionateLog != nil { compassionateCard }
                    else if completed && currentSession == nil { completedCard }
                    else if let routine {
                        if currentSession != nil {
                            sessionCard(routine)
                        } else {
                            DisclosureGroup(isExpanded: $showSessionDetails.animation(reduceMotion ? nil : .easeInOut(duration: 0.25))) {
                                sessionCard(routine).padding(.top, 12)
                            } label: {
                                Text("Ver detalles de la sesión")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minHeight: 44)
                            }.tint(accent)
                        }
                    }
                    else { Button("Selecciona un plan en Ajustes") { showSettings = true }.buttonStyle(.borderedProminent).tint(accent) }
                    metricsCard
                    if currentSession == nil, compassionateLog == nil, let source = completedMVRSession {
                        Button("¿Más energía? Iniciar Estándar") { continueWithStandard(from: source) }
                            .font(.footnote).buttonStyle(.plain).foregroundStyle(accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    NavigationLink("Ver historial de sesiones") { SessionHistoryView() }.font(.subheadline).tint(accent)
                    Text("La fase es una estimación de calendario. Ajusta el movimiento a cómo te sientes; descansar también es válido.").font(.caption).foregroundStyle(.secondary).padding(.bottom, 20)
                }.padding(24).frame(maxWidth: 650)
            }.background(Color(red: 0.96, green: 0.95, blue: 0.92)).toolbar(.hidden, for: .navigationBar)
            .onChange(of: currentSession?.id) { _, value in
                if value != nil {
                    DispatchQueue.main.async {
                        guard currentSession?.id == value else { return }
                        withAnimation(reduceMotion ? nil : .easeInOut) { scroll.scrollTo("session-details", anchor: .center) }
                    }
                }
            }
            }
        }
        .task { await initialize() }
        .onReceive(ticker) { date in
            let changed = !Calendar.current.isDate(date, inSameDayAs: now)
            now = date
            if changed { Task { await refreshDay(); await health.refresh() } }
            else { handleStartShortcut(); handleReminderAction(); presentCompassionIfDue(); checkShortSessionCompletion() }
        }
        .onChange(of: scenePhase) { _, value in if value == .active && ready { Task { await refreshDay(); await health.refresh() } } }
        .onChange(of: health.periodStart) { _, value in
            guard let date = value, let state, state.manualOverrideDate == nil || date > state.lastPeriodStartDate else { return }
            state.lastPeriodStartDate = date; state.hasPeriodDate = true
            if save() { publish(); Task { await reschedule() } }
        }
        .onChange(of: NotificationScheduler.shared.startSessionRequest) { _, _ in handleStartShortcut() }
        .onChange(of: NotificationScheduler.shared.requestedMode) { _, value in
            guard ready, let value else { return }; setMode(value); NotificationScheduler.shared.requestedMode = nil
        }
        .onChange(of: NotificationScheduler.shared.pendingReminderAction?.id) { _, _ in handleReminderAction() }
        .onChange(of: NotificationScheduler.shared.showCommitment) { _, value in if value && ready { presentCommitment(); NotificationScheduler.shared.showCommitment = false } }
        .onOpenURL { url in if ready { openURL(url) } else { pendingURL = url } }
        .sheet(isPresented: $showPeriod, onDismiss: { waitingForReminderDismissal = false; handleReminderAction(); checkReview() }) { periodSheet }
        .sheet(isPresented: $showSettings, onDismiss: { waitingForReminderDismissal = false; if commitmentFromSettings { commitmentFromSettings = false; presentCommitment() }; handleReminderAction(); Task { await refreshDay() } }) {
            if let state { SettingsView(state: state, health: health, onCommitment: { commitmentFromSettings = true; showSettings = false }, onRemindersChanged: { Task { await reschedule() } }) }
        }
        .sheet(isPresented: $showCommitment, onDismiss: { if commitmentConfirmation != nil { showCommitmentConfirmation = true } else { checkReview() } }) { commitmentSheet }
        .alert("Perfecto, creaste un compromiso. Recuerda tu palabra y la hora \(commitmentConfirmation ?? "").", isPresented: $showCommitmentConfirmation) { Button("Aceptar") { commitmentConfirmation = nil } }
        .fullScreenCover(isPresented: $showCompassionOptions, onDismiss: {
            waitingForReminderDismissal = false
            if let target = startFromCompassion {
                startFromCompassion = nil
                if let session = currentSession, session.mode == target {
                    session.resume(at: Date()); state?.reminderAcknowledgedAt = Date()
                    if save() { Task { await reschedule() } }
                } else {
                    if currentSession != nil { cancelSession() }
                    setMode(target)
                    startSession()
                }
            }
            else if let choice = pendingCompassion { pendingCompassion = nil; closeCompassionDay(choice) }
            else { handleReminderAction() }
        }) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 20) {
                        Text("¿Cómo quieres cerrar hoy?").font(.system(size: 34, design: .serif)).accessibilityAddTraits(.isHeader)
                        Button("Iniciar sesión") { startFromCompassion = .standard; showCompassionOptions = false }
                            .disabled(selectedPlan == nil && currentSession?.mode != .standard)
                        Button("MVR") { startFromCompassion = .mvr; showCompassionOptions = false }
                            .disabled(selectedPlan == nil && currentSession?.mode != .mvr)
                        Button("Recovery") { pendingCompassion = .recovery; showCompassionOptions = false }
                        Button("A descansar") { pendingCompassion = .rest; showCompassionOptions = false }
                    }.multilineTextAlignment(.center).padding(24).frame(maxWidth: 500)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
            }.background(Color(red: 0.96, green: 0.95, blue: 0.92))
                .buttonStyle(SessionOptionButtonStyle(accent: .purple))
        }
        .fullScreenCover(isPresented: $showCompassionCelebration) {
            CelebrationView(confetti: false, compassionate: true) { showCompassionCelebration = false }
        }
        .fullScreenCover(isPresented: $showShortSessionCompletion, onDismiss: {
            guard let choice = shortSessionChoice else { return }
            shortSessionChoice = nil
            if choice == .standard { continueWithStandard() }
            else { finish(as: choice, celebrate: false) }
        }) {
            CelebrationView(confetti: state?.confettiEnabled ?? true, onContinueStandard: {
                shortSessionChoice = .standard
                showShortSessionCompletion = false
            }) {
                shortSessionChoice = mode
                showShortSessionCompletion = false
            }.interactiveDismissDisabled()
                .onAppear { if state?.hapticsEnabled != false { Haptics.shared.complete() } }
        }
        .fullScreenCover(isPresented: $showCelebration, onDismiss: { checkReview() }) { CelebrationView(confetti: state?.confettiEnabled ?? true) { showCelebration = false } }
        .fullScreenCover(isPresented: Binding(get: { reviewEpisode != nil }, set: { if !$0 { reviewEpisode = nil } })) {
            if let episode = reviewEpisode {
                MVR3DayAlertView(count: episode.count, cycleDay: state?.hasPeriodDate == true ? day : nil, baseline: state?.restingPulseBaseline) { pulse, reason, choice in completeReview(episode, pulse: pulse, reason: reason, choice: choice) }
            }
        }
        .sheet(isPresented: $endOptions, onDismiss: {
            let action = pendingEndAction
            pendingEndAction = nil
            switch action {
            case .pause: pause()
            case .finish: requestFinish()
            case .mvr: finish(as: .mvr)
            case .cancel: cancelConfirmation = true
            case nil: break
            }
        }) { endSessionSheet }
        .sheet(isPresented: $cancelConfirmation) {
            ScrollView {
                VStack(spacing: 20) {
                    Text("¿Cancelar esta sesión?").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                    Button("Cancelar", role: .destructive) { cancelConfirmation = false; cancelSession() }
                    Button("Conservar esta sesión") { cancelConfirmation = false }
                }.multilineTextAlignment(.center).padding(24).frame(maxWidth: .infinity)
            }.buttonStyle(SessionOptionButtonStyle(accent: accent))
                .presentationBackground(Color(red: 0.96, green: 0.95, blue: 0.92))
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .alert("No se pudo completar la acción", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("Aceptar") { error = nil } } message: { Text(error ?? "") }
    }
    private func chooseEndAction(_ action: EndAction) {
        pendingEndAction = action
        endOptions = false
    }
    private var endSessionSheet: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(earlyEndTitle).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                if currentSession?.status == "running" { Button("Pausar") { chooseEndAction(.pause) } }
                Button("Terminar") { chooseEndAction(.finish) }
                if let session = currentSession, session.elapsed(at: now) >= 300, session.mode != .mvr {
                    Button("Completar como MVR") { chooseEndAction(.mvr) }
                }
                Button("Cancelar sesión", role: .destructive) { chooseEndAction(.cancel) }
            }.multilineTextAlignment(.center).padding(24).frame(maxWidth: .infinity)
        }.buttonStyle(SessionOptionButtonStyle(accent: accent))
            .presentationBackground(Color(red: 0.96, green: 0.95, blue: 0.92))
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
    private var earlyEndTitle: String {
        guard let session = currentSession, let routine = session.routine else { return "Tu sesión" }
        return session.elapsed(at: now) < Double(routine.minutes * 60) ? "Todavía queda tiempo de tu sesión.\n¿Quieres pausar o terminar?" : "¿Cómo quieres cerrar tu sesión?"
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("KMomentum").font(.system(size: 27, weight: .medium, design: .serif))
                Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "es_CO"))).uppercased()).font(.caption2).tracking(1).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").padding(12).background(.white.opacity(0.7), in: Circle()) }.tint(accent).accessibilityLabel("Ajustes")
        }
    }
    private var cycleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(state?.hasPeriodDate == true ? "Día \(day) · Fase \(phase.rawValue)" : "Tu ciclo, a tu ritmo", systemImage: "circle.lefthalf.filled").font(.subheadline.weight(.medium))
            Text(state?.hasPeriodDate == true ? phase.message : "Registra el inicio de tu periodo para adaptar tu sesión.").font(.system(size: 23, design: .serif))
            HStack { Button("Hoy es mi día 1") { registerPeriod(now) }; Spacer(); Button("Ajustar fecha") { selectedDate = state?.lastPeriodStartDate ?? now; showPeriod = true } }.font(.caption.weight(.semibold))
        }.padding(20).background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 20)).foregroundStyle(accent).tint(accent)
    }
    private var completedCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("HOY YA CUMPLISTE", systemImage: "checkmark.seal.fill").font(.caption.weight(.semibold)).foregroundStyle(.green)
            Text("¡Muy bien, mantuviste el momentum!").font(.system(size: 30, design: .serif))
            Text("Tu compromiso de hoy está completo.").foregroundStyle(.secondary)
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 24))
    }
    private func sessionCard(_ routine: WorkoutRoutine) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 18) {
            HStack { Text("TU SESIÓN DE HOY").tracking(1); Spacer(); Text(mode.rawValue) }.font(.caption.weight(.semibold)).foregroundStyle(accent)
            Text(routine.title).font(.system(size: 32, design: .serif))
            Text("\(routine.minutes) min estimados · \(routine.exercises.count) ejercicios").font(.subheadline).foregroundStyle(.secondary)
            Text(currentSession?.planName ?? selectedPlan?.name ?? "").font(.caption).foregroundStyle(.secondary)
            if let session = currentSession {
                HStack {
                    Image(systemName: session.status == "paused" ? "pause.circle" : "timer")
                    Text(clockText(session.elapsed(at: now))).monospacedDigit().font(.title2)
                    Text(session.status == "paused" ? "En pausa" : "Tiempo activo").font(.caption)
                }.foregroundStyle(accent)
            }
            }.id("session-details")
            ForEach(Array(routine.exercises.enumerated()), id: \.offset) { index, exercise in
                Divider()
                ExerciseLogView(exercise: exercise, index: index, session: currentSession, previous: previousResults(for: exercise), preferredWeightUnit: state?.preferredWeightUnit ?? "lb") { error = $0 }
            }
            Text(routine.note).font(.caption).foregroundStyle(.secondary)
            if let session = currentSession {
                if session.mode == .intermediate, session.elapsed(at: now) >= 300 {
                    Button("Mis 5 minutos cuentan · completar como MVR") { finish(as: .mvr) }.font(.subheadline).buttonStyle(.bordered).tint(accent)
                }
                HStack {
                    Button(session.status == "paused" ? "Reanudar" : "Pausar") { if session.status == "paused" { session.resume(at: Date()); save() } else { pause() } }.buttonStyle(.bordered)
                    Button("Terminar") { now = Date(); endOptions = true }.buttonStyle(.borderedProminent)
                }.tint(accent)
            }
        }.padding(22).background(.white, in: RoundedRectangle(cornerRadius: 24))
    }
    private var adaptationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADAPTA, NO ABANDONES").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.secondary)
            if currentSession != nil { Text("Termina o cancela esta sesión antes de cambiar de modo.").font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(SessionMode.allCases, id: \.self) { target in
                    Button { setMode(target) } label: { Text(target.rawValue).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading).padding(15).background(accent.opacity(mode == target ? 0.17 : 0.06), in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain).foregroundStyle(accent).disabled(currentSession != nil)
                }
            }
            if currentSession == nil, state?.hasPeriodDate == true, (26...30).contains(day), mode == .standard {
                Text("Si hoy necesitas menos carga, puedes probar el escalón intermedio de 20 minutos.").font(.caption).foregroundStyle(.secondary)
            }
            if mode == .recovery { Text("Recuperación · día \(recoveryDay)").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var metricsCard: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                weekMetric
                    .padding(14)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
                stepsMetric
                    .padding(14)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 22))
            }
            Text("Tu mínimo vale tanto como tu máximo.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }
    private var weekMetric: some View {
        WeeklyProgressView(completedDays: HabitRules.completedDaysInWeek(logs.filter(\.completed).map(\.date), now: now), cyclePhase: phase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var stepsMetric: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Pasos de hoy", systemImage: "figure.walk").font(.subheadline.weight(.semibold))
            if let steps = health.steps, let day = health.stepsDay, Calendar.current.isDateInToday(day) {
                Text(steps.formatted(.number.locale(Locale(identifier: "es_CO")))).font(.title2.bold()).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else if UserDefaults.standard.bool(forKey: "healthConnected") { Text("Sin datos disponibles").font(.caption).foregroundStyle(.secondary) }
            else { Button("Conectar Apple Health") { Task { await health.connect() } }.font(.caption).frame(minHeight: 44).tint(accent) }
            Label("Apple Health", systemImage: "heart.fill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if health.steps != nil, let day = health.stepsDay, Calendar.current.isDateInToday(day), let update = health.stepsUpdatedAt {
                Text("Actualizado a las \(update.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var periodSheet: some View {
        NavigationStack { Form { DatePicker("Primer día del periodo", selection: $selectedDate, in: ...Date(), displayedComponents: .date); Button("Guardar fecha") { registerPeriod(selectedDate); showPeriod = false } }.navigationTitle("Ajustar periodo").toolbar { Button("Cerrar") { showPeriod = false } } }.presentationDetents([.medium])
    }
    private var commitmentSheet: some View {
        NavigationStack { Form {
            DatePicker("Hoy a las", selection: $commitmentDate, displayedComponents: .hourAndMinute)
            Text("Elige una hora futura entre 4:00 a. m. y 11:30 p. m. Los recordatorios esperarán hasta esa hora.").font(.caption)
            Button("Guardar compromiso") {
                guard let date = ReminderRules.commitmentDate(time: commitmentDate, now: Date()) else { error = "Elige una hora futura de hoy entre 4:00 a. m. y 11:30 p. m."; return }
                Task {
                    guard await NotificationScheduler.shared.authorize() else { error = "Permite notificaciones en Ajustes de iOS."; return }
                    state?.commitment = date
                    state?.commitmentRenegotiatedDay = Calendar.current.startOfDay(for: Date())
                    state?.reminderAcknowledgedAt = Date()
                    state?.remindersEnabled = true
                    guard save() else { return }
                    publish()
                    await NotificationScheduler.shared.stopPersistence()
                    await reschedule()
                    let formatter = DateFormatter(); formatter.dateFormat = "HH:mm"
                    commitmentConfirmation = formatter.string(from: date)
                    showCommitment = false
                }
            }
        }.navigationTitle("Elegir hora para hoy").toolbar { Button("Cerrar") { showCommitment = false } } }.presentationDetents([.medium])
    }
    private var compassionateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "bed.double.fill").accessibilityHidden(true)
                Text("Descansa y respira. Mañana retomamos.")
            }.font(.title2).foregroundStyle(.purple)
            if let number = compassionateLog?.recoveryStreakDay { Text("Día \(number) de recovery").font(.subheadline).foregroundStyle(.secondary) }
        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.white, in: RoundedRectangle(cornerRadius: 24))
    }
    private func presentCommitment() {
        commitmentDate = state?.commitment.flatMap { $0 > Date() ? $0 : nil } ?? Date().addingTimeInterval(3600)
        showCommitment = true
    }
    private func handleReminderAction() {
        guard ready, state != nil, scenePhase == .active, !waitingForReminderDismissal,
              let action = NotificationScheduler.shared.pendingReminderAction else { return }
        guard Calendar.current.isDateInToday(action.day), !dayClosed else {
            NotificationScheduler.shared.pendingReminderAction = nil
            return
        }
        if action.intent == .renegotiate {
            if showCommitment {
                NotificationScheduler.shared.pendingReminderAction = nil
                return
            }
            // Wait for the existing presentation to dismiss before opening the shared picker.
            if showSettings || showPeriod || showCompassionOptions {
                waitingForReminderDismissal = true
                commitmentFromSettings = false
                showSettings = false; showPeriod = false; showCompassionOptions = false
                return
            }
        }
        guard !showSettings, !showPeriod, !showCommitment, !showCelebration, !showShortSessionCompletion, !showCompassionOptions, !showCompassionCelebration, !showCommitmentConfirmation, reviewEpisode == nil, !endOptions, !cancelConfirmation else { return }
        NotificationScheduler.shared.pendingReminderAction = nil
        switch action.intent {
        case .renegotiate: presentCommitment()
        case .rest: if compassionAvailable { closeCompassionDay(.rest) }
        case .recovery: if compassionAvailable { closeCompassionDay(.recovery) }
        case .chooseCompassion: if compassionAvailable { compassionPresentedFor = state?.commitment; showCompassionOptions = true }
        }
        assert(action.intent != .renegotiate || showCommitment, "Renegotiating must open the shared time picker.")
    }
    private func presentCompassionIfDue() {
        guard ready, scenePhase == .active, NotificationScheduler.shared.pendingReminderAction == nil, !dayClosed, compassionAvailable,
              !showSettings, !showPeriod, !showCommitment, !showCommitmentConfirmation,
              !showCelebration, !showCompassionCelebration, !showCompassionOptions,
              !showShortSessionCompletion, reviewEpisode == nil, !endOptions, !cancelConfirmation,
              currentSession == nil, error == nil else { return }
        // Remember the presentation without silencing the reminders.
        guard compassionPresentedFor != state?.commitment else { return }
        compassionPresentedFor = state?.commitment
        showCompassionOptions = true
    }
    private func closeCompassionDay(_ choice: CompassionateChoice) {
        now = Date()
        guard !dayClosed, compassionAvailable else { return }
        let record = logs.first { Calendar.current.isDate($0.date, inSameDayAs: now) } ?? DailyLog(date: now, mode: .recovery)
        if record.modelContext == nil { context.insert(record) }
        record.completed = false; record.compassionateChoiceRaw = choice.rawValue
        record.isSickProtocol = choice == .recovery
        record.recoveryStreakDay = choice == .recovery ? ReminderRules.recoveryDay(previousDates: logs.filter { $0.compassionateChoice == .recovery }.map(\.date), now: now) : nil
        if let session = currentSession { session.pause(at: now); session.status = "cancelled" }
        if choice == .recovery {
            applyMode(.recovery)
            state?.sickModeStartDay = Calendar.current.date(byAdding: .day, value: 1 - (record.recoveryStreakDay ?? 1), to: now)
        }
        state?.reminderAcknowledgedAt = now
        guard save() else { return }
        showCompassionCelebration = true
        publish(); Task { await reschedule() }
    }
    private func clockText(_ seconds: Double) -> String { let total = Int(seconds); return String(format: "%02d:%02d", total / 60, total % 60) }
    private func previousResults(for exercise: ExercisePrescription) -> [SetResult] {
        for session in sessions where !session.isOpen {
            if let index = session.routine?.exercises.firstIndex(where: { $0.historyKey == exercise.historyKey }) {
                let values = session.results.filter { $0.exercise == index && (!$0.reps.isEmpty || !$0.weight.isEmpty) }
                if !values.isEmpty { return values }
            }
        }
        return []
    }
    private func initialize() async {
        guard !ready else { return }
        let stored = states.first ?? UserCycleState()
        if states.isEmpty { context.insert(stored) }
        if !stored.didSeedPlans {
            let plan = SavedPlan(document: DefaultWorkouts.document); context.insert(plan)
            stored.activePlanID = plan.id; stored.didSeedPlans = true
        }
        // Preserve an in-flight timer from the previous app version during migration.
        if let start = stored.sessionStartedAt, !sessions.contains(where: { $0.isOpen }) {
            do {
                let mode = SessionMode(rawValue: stored.selectedMode) ?? .standard
                let day = HabitRules.cycleDay(start: stored.lastPeriodStartDate, now: start)
                let routine = DefaultWorkouts.routine(phase: HabitRules.phase(day: day), weekday: HabitRules.weekIndex(start), mode: mode, recoveryDay: 1)
                context.insert(try WorkoutSession(date: start, planID: stored.activePlanID, planName: "Plan anterior", mode: mode, routine: routine))
                stored.sessionStartedAt = nil; stored.sessionDay = nil
            } catch { self.error = error.localizedDescription; return }
        }
        guard save() else { return }
        ready = true
        await refreshDay()
        if UserDefaults.standard.bool(forKey: "healthConnected") { await health.connect() }
        if let pendingURL { openURL(pendingURL); self.pendingURL = nil }
    }
    private func handleStartShortcut() {
        guard ready, scenePhase == .active, NotificationScheduler.shared.startSessionRequest != nil,
              state != nil, currentSession != nil || dayClosed || selectedPlan != nil else { return }
        if showSettings || showPeriod || showCommitment || showCompassionOptions {
            commitmentFromSettings = false
            showSettings = false; showPeriod = false; showCommitment = false; showCompassionOptions = false
            return
        }
        guard !showCommitmentConfirmation, !showCompassionCelebration, !showCelebration,
              !showShortSessionCompletion, !endOptions, !cancelConfirmation, reviewEpisode == nil,
              error == nil else { return }
        NotificationScheduler.shared.startSessionRequest = nil
        now = Date()
        if let session = currentSession {
            session.resume(at: now); state?.reminderAcknowledgedAt = now
            if save() { showSessionDetails = true; publish(); Task { await reschedule() } }
        } else if compassionateLog == nil, let source = completedMVRSession {
            continueWithStandard(from: source)
        } else if !dayClosed {
            startSession()
        }
    }
    private func registerPeriod(_ date: Date) { state?.lastPeriodStartDate = Calendar.current.startOfDay(for: date); state?.manualOverrideDate = now; state?.hasPeriodDate = true; if save() { publish(); Task { await reschedule() } } }
    private func setMode(_ value: SessionMode) {
        guard currentSession == nil else { error = "Tienes una sesión en curso. Termínala o cancélala antes de elegir otro modo."; return }
        applyMode(value)
        if save() { publish() }
    }
    private func applyMode(_ value: SessionMode) {
        guard let state else { return }
        if value == .recovery && !state.isSickModeActive { state.sickModeStartDay = now }
        state.isSickModeActive = value == .recovery; state.selectedMode = value.rawValue
    }
    private func startSession() {
        now = Date()
        guard !dayClosed, currentSession == nil, let routine, let plan = selectedPlan else { return }
        checkReview(); guard reviewEpisode == nil else { return }
        do {
            context.insert(try WorkoutSession(date: now, planID: plan.id, planName: plan.name, mode: mode, routine: routine))
            state?.reminderAcknowledgedAt = now
            if save() { publish(); Task { await reschedule() } }
        }
        catch { self.error = error.localizedDescription }
    }
    private func pause() { guard let session = currentSession else { return }; session.pause(at: Date()); save() }
    private func requestFinish() {
        let date = Date()
        guard let session = currentSession, let routine = session.routine else { return }
        guard Calendar.current.isDate(session.date, inSameDayAs: date) else { Task { await refreshDay() }; return }
        if SessionRules.shortSessionFinished(mode: session.mode, minutes: routine.minutes, elapsed: session.elapsed(at: date), endedEarly: true) {
            session.pause(at: date)
            if save() { showShortSessionCompletion = true }
        } else {
            finish(as: session.mode)
        }
    }
    private func checkShortSessionCompletion() {
        guard ready, NotificationScheduler.shared.pendingReminderAction == nil, !dayClosed, !showCompassionOptions, !showCompassionCelebration, scenePhase == .active, !showShortSessionCompletion, shortSessionChoice == nil,
              !showSettings, !showPeriod, !showCommitment, !showCelebration, reviewEpisode == nil,
              !endOptions, pendingEndAction == nil, !cancelConfirmation, error == nil,
              let session = currentSession, let routine = session.routine,
              SessionRules.shortSessionFinished(mode: session.mode, minutes: routine.minutes, elapsed: session.elapsed(at: now)) else { return }
        if session.status == "running" {
            let deadline = (session.runningSince ?? now).addingTimeInterval(max(0, Double(routine.minutes) * 60 - session.accumulatedSeconds))
            session.pause(at: min(now, deadline))
            session.accumulatedSeconds = max(session.accumulatedSeconds, Double(routine.minutes) * 60)
            guard save() else { return }
        }
        showShortSessionCompletion = true
    }
    private func markCompleted(_ session: WorkoutSession, as value: SessionMode, at date: Date) {
        state?.reminderAcknowledgedAt = date
        session.pause(at: date); session.status = "completed"; session.modeRaw = value.rawValue
        let today = logs.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
        if let today { today.completed = true; today.isMVR = value == .mvr; today.isSickProtocol = value == .recovery; today.intensityRaw = value.rawValue }
        else { context.insert(DailyLog(date: date, mode: value)) }
    }
    private func continueWithStandard(from source: WorkoutSession? = nil) {
        let date = Date()
        guard let session = source ?? currentSession, currentSession == nil || currentSession?.id == session.id,
              Calendar.current.isDate(session.date, inSameDayAs: date),
              session.mode == .mvr || session.mode == .recovery else { return }
        guard let document = plans.first(where: { $0.id == session.planID })?.document else {
            error = "No se pudo cargar el plan de esta sesión. Tus registros se conservan; puedes descansar y completar el día."
            return
        }
        let standard = document.routine(phase: phase, weekday: HabitRules.weekIndex(date), mode: .standard, recoveryDay: recoveryDay)
        do {
            let next = try WorkoutSession(date: date, planID: session.planID, planName: session.planName, mode: .standard, routine: standard)
            if session.isOpen { markCompleted(session, as: session.mode, at: date) }
            context.insert(next)
            applyMode(.standard)
            guard save() else { return }
            now = date; showSessionDetails = true
            publish(); Task { await reschedule() }
        } catch { self.error = error.localizedDescription }
    }
    private func finish(as value: SessionMode, celebrate: Bool = true) {
        guard let session = currentSession else { return }
        let finishDate = Date()
        guard Calendar.current.isDate(session.date, inSameDayAs: finishDate) else { Task { await refreshDay() }; return }
        markCompleted(session, as: value, at: finishDate)
        guard save() else { return }
        now = finishDate
        if celebrate && state?.hapticsEnabled != false { Haptics.shared.complete() }
        showCelebration = celebrate
        publish(); Task { await reschedule() }
    }
    private func cancelSession() { guard let session = currentSession else { return }; session.pause(at: Date()); session.status = "cancelled"; if save() { publish() } }
    @discardableResult private func save() -> Bool { do { try context.save(); return true } catch { context.rollback(); self.error = error.localizedDescription; return false } }
    private func refreshDay() async {
        now = Date()
        for session in sessions where session.isOpen && !Calendar.current.isDateInToday(session.date) {
            let boundary = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: session.date))!
            session.pause(at: min(now, boundary)); session.status = "cancelled"
        }
        guard save() else { return }
        if currentSession == nil { shortSessionChoice = nil; showShortSessionCompletion = false }
        if let requested = NotificationScheduler.shared.requestedMode { setMode(requested); NotificationScheduler.shared.requestedMode = nil }
        if NotificationScheduler.shared.showCommitment { presentCommitment(); NotificationScheduler.shared.showCommitment = false }
        handleStartShortcut(); handleReminderAction(); publish(); await reschedule(); presentCompassionIfDue(); checkReview(); checkShortSessionCompletion()
    }
    private func checkReview() {
        guard ready, NotificationScheduler.shared.pendingReminderAction == nil, !dayClosed, !showCompassionOptions, !showCompassionCelebration, !showCommitmentConfirmation, !showCelebration, !showSettings, !showPeriod, !showCommitment, currentSession == nil else { return }
        let history = logs.filter(\.completed).map { CompletionDay(date: $0.date, mode: $0.intensity) }
        if let episode = SessionRules.mvrEpisode(logs: history, now: Date()), state?.reviewedMVRStart.map({ Calendar.current.isDate($0, inSameDayAs: episode.start) }) != true { reviewEpisode = episode }
    }
    private func completeReview(_ episode: MVREpisode, pulse: Int?, reason: String, choice: SessionMode) {
        context.insert(MVRReview(episodeStart: episode.start, pulse: pulse, baseline: state?.restingPulseBaseline, reason: reason, choice: choice))
        state?.reviewedMVRStart = episode.start; applyMode(choice)
        if save() { reviewEpisode = nil; publish() }
    }
    private func reschedule() async {
        let currentCycleDay = state?.hasPeriodDate == true ? HabitRules.cycleDay(start: state?.lastPeriodStartDate ?? now, now: now, length: 28) : nil
        let savedLogs = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? logs
        let closed = savedLogs.contains { Calendar.current.isDateInToday($0.date) && ($0.completed || $0.compassionateChoice != nil) }
        await NotificationScheduler.shared.schedule(currentCycleDay: currentCycleDay, completed: closed, commitment: state?.commitment, enabled: state?.remindersEnabled ?? false, customReminderTime: state?.customReminderEnabled == true ? state?.customReminderTime : nil, renegotiatedDay: state?.commitmentRenegotiatedDay, acknowledgedAt: state?.reminderAcknowledgedAt)
    }
    private func openURL(_ url: URL) {
        guard url.scheme == "kmomentum" else { return }
        if url.host == "plans" { showSettings = true }
        if url.host == "commitment" {
            NotificationScheduler.shared.pendingReminderAction = .init(intent: .renegotiate, day: Date())
            handleReminderAction()
        }
        if url.host == "mvr", !completed, currentSession == nil { setMode(.mvr) }
    }
    private func publish() {
        guard ready else { return }
        let calendar = Calendar.current
        let storedLogs = (try? context.fetch(FetchDescriptor<DailyLog>())) ?? logs
        let storedPlans = (try? context.fetch(FetchDescriptor<SavedPlan>())) ?? plans
        let activePlan = storedPlans.first { $0.id == state?.activePlanID }
        let entries = (0..<8).map { offset -> WidgetSnapshot in
            let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            let phase = state?.hasPeriodDate == true ? HabitRules.phase(day: HabitRules.cycleDay(start: state?.lastPeriodStartDate ?? date, now: date)) : .menstrual
            let recoveryDay = HabitRules.recoveryDay(start: state?.sickModeStartDay ?? date, now: date)
            let planned = activePlan?.document?.routine(phase: phase, weekday: HabitRules.weekIndex(date), mode: mode, recoveryDay: recoveryDay)
            let workout = offset == 0 ? (currentSession?.routine ?? planned) : planned
            let mvr = activePlan?.document?.routine(phase: phase, weekday: HabitRules.weekIndex(date), mode: .mvr, recoveryDay: recoveryDay)
            let done = storedLogs.contains { $0.completed && calendar.isDate($0.date, inSameDayAs: date) }
            let week = (0..<7).map { index in
                let target = calendar.date(byAdding: .day, value: index - HabitRules.weekIndex(date), to: date)!
                return storedLogs.contains { $0.completed && calendar.isDate($0.date, inSameDayAs: target) }
            }
            let pausedWeek = (0..<7).map { index in
                let target = calendar.date(byAdding: .day, value: index - HabitRules.weekIndex(date), to: date)!
                return storedLogs.contains { $0.compassionateChoice != nil && calendar.isDate($0.date, inSameDayAs: target) }
            }
            let commitment = state?.commitment.flatMap { calendar.isDate($0, inSameDayAs: date) ? $0 : nil }
            return .init(date: date, completed: done, title: workout?.title ?? "Selecciona un plan", minutes: workout?.minutes ?? 0, exercises: workout?.exercises.count ?? 0, mvrMinutes: mvr?.minutes ?? 0, hasPlan: workout != nil, week: week, cyclePhase: phase, pausedWeek: pausedWeek, commitment: commitment, recoveryActive: state?.isSickModeActive == true)
        }
        do { try WidgetSnapshot.save(entries); WidgetCenter.shared.reloadAllTimelines() } catch { self.error = error.localizedDescription }
    }
}
