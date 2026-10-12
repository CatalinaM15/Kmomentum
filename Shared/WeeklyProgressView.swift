import SwiftUI

private struct LiquidSurface: Shape {
    var progress: Double
    let phase: Double
    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let level = rect.height * (1 - progress)
        let amplitude = rect.height * min(0.035, progress, 1 - progress)
        let wave = amplitude * sin(phase)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: level))
        path.addCurve(to: CGPoint(x: rect.midX, y: level),
                      control1: CGPoint(x: rect.width / 6, y: level - wave),
                      control2: CGPoint(x: rect.width / 3, y: level + wave))
        path.addCurve(to: CGPoint(x: rect.maxX, y: level),
                      control1: CGPoint(x: rect.width * 2 / 3, y: level - wave),
                      control2: CGPoint(x: rect.width * 5 / 6, y: level + wave))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct WeeklyProgressView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let completedDays: Int
    let cyclePhase: CyclePhase
    var animate = true
    private var progress: Double { HabitRules.weeklyProgress(completedDays: completedDays) }
    private var liquidFill: Double { HabitRules.weeklyLiquidFill(completedDays: completedDays) }
    private var percentage: String { progress.formatted(.percent.precision(.fractionLength(0))) }
    private var palette: (base: Color, highlight: Color) {
        switch cyclePhase {
        case .menstrual: (Color(red: 150/255, green: 113/255, blue: 74/255), Color(red: 191/255, green: 164/255, blue: 133/255))
        case .follicular: (Color(red: 57/255, green: 1, blue: 20/255), Color(red: 127/255, green: 1, blue: 127/255))
        case .ovulatory: (Color(red: 0, green: 1, blue: 1), Color(red: 77/255, green: 1, blue: 1))
        case .luteal: (Color(red: 165/255, green: 90/255, blue: 42/255), Color(red: 210/255, green: 140/255, blue: 93/255))
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.animation(minimumInterval: 1 / 20, paused: !animate || reduceMotion || progress == 0 || progress == 1)) { timeline in
                ZStack {
                    Image(systemName: "heart.fill").resizable().scaledToFit().foregroundStyle(palette.base.opacity(0.12))
                    ZStack {
                        Rectangle().fill(.linearGradient(colors: [palette.highlight, palette.base], startPoint: .top, endPoint: .bottom))
                        if cyclePhase == .menstrual {
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: 0))
                                path.addQuadCurve(to: CGPoint(x: 12, y: 0), control: CGPoint(x: 6, y: 5))
                            }
                            .stroke(Color(red: 0.20, green: 0.14, blue: 0.10), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .frame(width: 12, height: 5).offset(y: 16)
                        }
                    }
                        .mask { LiquidSurface(progress: liquidFill, phase: reduceMotion ? 0 : animate ? timeline.date.timeIntervalSinceReferenceDate * .pi / 2 : .pi / 2) }
                        .mask { Image(systemName: "heart.fill").resizable().scaledToFit() }
                    Image(systemName: "heart").resizable().scaledToFit()
                        .foregroundStyle(cyclePhase == .menstrual ? palette.base : palette.highlight)
                        .shadow(color: palette.base.opacity(0.8), radius: 4)
                        .shadow(color: palette.highlight.opacity(cyclePhase == .menstrual ? 0.25 : 0.6), radius: 9)
                }
            }.frame(width: 76, height: 68).accessibilityHidden(true)
            Text(percentage)
                .font(.title2.bold()).monospacedDigit()
            Text("\(completedDays)/7").font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(Color(red: 0.18, green: 0.20, blue: 0.18))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: completedDays)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progreso semanal")
        .accessibilityValue("\(completedDays) de 7 días completados, \(percentage)")
    }
}

