import SwiftUI
import WidgetKit
struct MomentumEntry: TimelineEntry { let date: Date; let snapshot: WidgetSnapshot }
struct MomentumProvider: TimelineProvider {
    func placeholder(in context: Context) -> MomentumEntry { .init(date: Date(), snapshot: .init(date: Date(), completed: false, title: "Tu sesión de hoy", minutes: 40, exercises: 3, mvrMinutes: 6, hasPlan: true)) }
    func getSnapshot(in context: Context, completion: @escaping (MomentumEntry) -> Void) { completion(.init(date: Date(), snapshot: .current())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MomentumEntry>) -> Void) {
        let now = Date()
        var entries = [MomentumEntry(date: now, snapshot: .current())]
        entries += WidgetSnapshot.timeline.filter { $0.date > now }.map { MomentumEntry(date: $0.date, snapshot: $0) }
        let last = entries.last?.date ?? now
        let expiration = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: last))!
        entries.append(.init(date: expiration, snapshot: .init(date: expiration, completed: false, title: "Abre la app para actualizar")))
        completion(Timeline(entries: entries, policy: .after(expiration)))
    }
}
struct MomentumWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: MomentumEntry
    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var link: URL { URL(string: snapshot.hasPlan || snapshot.completed ? "kmomentum://session" : "kmomentum://plans")! }
    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                WeeklyProgressView(completedDays: snapshot.weeklyCompletedDays, cyclePhase: snapshot.cyclePhase ?? .menstrual, animate: false)
            case .accessoryCircular:
                LockProgressView(snapshot: snapshot)
            case .accessoryRectangular:
                LockCommitmentView(snapshot: snapshot)
            default:
                home
            }
        }.widgetURL(family == .accessoryRectangular && !snapshot.completed && !snapshot.paused && snapshot.recoveryActive != true ? URL(string: "kmomentum://commitment") : link)
            .containerBackground(for: .widget) {
                if family == .systemSmall || family == .systemMedium { Color(red: 0.96, green: 0.95, blue: 0.92) }
                else { Color.clear }
            }
    }
    private var home: some View {
        VStack(spacing: 12) {
            if snapshot.completed || snapshot.paused {
                if snapshot.paused {
                    Text(snapshot.mediumMessage).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(snapshot.mediumMessage).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }
                HStack(spacing: 0) {
                    ForEach(0..<7) { index in
                        let done = snapshot.week.indices.contains(index) && snapshot.week[index]
                        let paused = snapshot.pausedWeek?.indices.contains(index) == true && snapshot.pausedWeek![index]
                        VStack(spacing: 2) {
                            Text(["L", "M", "M", "J", "V", "S", "D"][index]).font(.caption)
                            Image(systemName: paused ? "circle.fill" : done ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(paused ? Color.purple : done ? Color.green : Color(red: 0.32, green: 0.39, blue: 0.30).opacity(0.5))
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"][index]): \(paused ? "descanso o recuperación" : done ? "completado" : "sin completar")")
                    }
                }
            } else {
                Text(snapshot.mediumMessage).font(.headline).fixedSize(horizontal: false, vertical: true)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .foregroundStyle(Color(red: 0.32, green: 0.39, blue: 0.30))
    }
}
struct KMomentumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KMomentum", provider: MomentumProvider()) { MomentumWidgetView(entry: $0) }
            .configurationDisplayName("Tu sesión de hoy").description("En inicio, tu constancia semanal. En bloqueo, tu porcentaje o tu compromiso de hoy.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

private struct LockProgressView: View {
    let snapshot: WidgetSnapshot
    private var phaseColor: Color {
        switch snapshot.cyclePhase {
        case .menstrual: Color(red: 150/255, green: 113/255, blue: 74/255)
        case .follicular: Color(red: 57/255, green: 1, blue: 20/255)
        case .ovulatory: Color.cyan
        case .luteal: Color(red: 165/255, green: 90/255, blue: 42/255)
        case nil: Color.primary
        }
    }
    var body: some View {
        Gauge(value: HabitRules.weeklyProgress(completedDays: snapshot.weeklyCompletedDays)) {
            Image(systemName: "heart.fill")
        } currentValueLabel: {
            Text("\(snapshot.weeklyPercentage)%").font(.caption.weight(.semibold)).minimumScaleFactor(0.7)
        }.gaugeStyle(.accessoryCircularCapacity).tint(phaseColor).widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progreso semanal: \(snapshot.weeklyPercentage) por ciento, \(snapshot.weeklyCompletedDays) de 7 días. \(snapshot.cyclePhase.map { "Fase \($0.rawValue)." } ?? "")")
    }
}
private struct LockCommitmentView: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        Text(snapshot.commitmentMessage)
            .font(.headline).multilineTextAlignment(.center).lineLimit(3).minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
private struct LockWeekView: View {
    let snapshot: WidgetSnapshot
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7) { index in
                let state = snapshot.weekState(at: index)
                Image(systemName: state == .paused ? "circle.inset.filled" : state == .completed ? "circle.fill" : "circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(state == .paused ? Color.purple : state == .completed ? Color.green : Color.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"][index]): \(state == .paused ? "descanso o recuperación" : state == .completed ? "completado" : "pendiente")")
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .widgetURL(URL(string: "kmomentum://session"))
            .containerBackground(Color.clear, for: .widget)
    }
}
struct MomentumLockWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KMomentumLockWeek", provider: MomentumProvider()) { entry in
            LockWeekView(snapshot: entry.snapshot)
        }.configurationDisplayName("Tu semana en bolitas")
            .description("Siete días de constancia y autocuidado, sin presión.")
            .supportedFamilies([.accessoryRectangular])
    }
}
@main struct MomentumWidgets: WidgetBundle {
    var body: some Widget {
        KMomentumWidget()
        MomentumLockWeekWidget()
    }
}
