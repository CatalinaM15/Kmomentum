import CoreHaptics
import UIKit
@MainActor final class Haptics {
    static let shared = Haptics()
    private var engine: CHHapticEngine?
    func complete() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { UINotificationFeedbackGenerator().notificationOccurred(.success); return }
        do {
            if engine == nil { engine = try CHHapticEngine() }
            try engine?.start()
            let count = 2
            let events = (0..<count).map { index in CHHapticEvent(eventType: .hapticTransient, parameters: [CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6), CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)], relativeTime: Double(index) * 0.15) }
            let player = try engine?.makePlayer(with: CHHapticPattern(events: events, parameters: [])); try player?.start(atTime: 0)
        } catch { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }
}
