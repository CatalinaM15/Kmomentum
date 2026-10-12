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
                WeeklyProgressView(completedDays: snapshot.week.filter { $0 }.count, cyclePhase: snapshot.cyclePhase ?? .menstrual, animate: false)
            case .accessoryCircular:
                VStack(spacing: 2) { Image(systemName: snapshot.completed ? "checkmark.circle.fill" : "figure.walk"); if !snapshot.completed { Text(snapshot.hasPlan ? "\(snapshot.minutes)m" : "Abrir").font(.caption2) } }.accessibilityLabel(snapshot.completed ? "Día completado" : "\(snapshot.title), \(snapshot.minutes) minutos")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.completed ? "Día completado ✓" : "Hoy · \(snapshot.title)").font(.headline).lineLimit(2)
                    if !snapshot.completed && snapshot.hasPlan { Text("\(snapshot.minutes) min · toca para ver sesión").font(.caption) }
                }
            default:
                home
            }
        }.widgetURL(link).containerBackground(Color(red: 0.96, green: 0.95, blue: 0.92), for: .widget)
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
@main struct KMomentumWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KMomentum", provider: MomentumProvider()) { MomentumWidgetView(entry: $0) }
            .configurationDisplayName("Tu sesión de hoy").description("Tu constancia semanal y un impulso para moverte hoy.")
            .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}
