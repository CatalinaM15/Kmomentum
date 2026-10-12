import Foundation
import SwiftData

@Model final class UserCycleState {
    var lastPeriodStartDate: Date
    var cycleLengthDays: Int
    var isSickModeActive: Bool
    var sickModeStartDay: Date?
    var manualOverrideDate: Date?
    var hasPeriodDate: Bool
    var selectedMode: String
    var sessionStartedAt: Date?
    var sessionDay: Date?
    var commitment: Date?
    var remindersEnabled: Bool
    init() {
        lastPeriodStartDate = Date(); cycleLengthDays = 30; isSickModeActive = false
        hasPeriodDate = false; selectedMode = SessionMode.standard.rawValue; remindersEnabled = false
    }
}
@Model final class DailyLog {
    @Attribute(.unique) var dayKey: String
    var id: UUID
    var date: Date
    var completed: Bool
    var isMVR: Bool
    var isSickProtocol: Bool
    var notes: String?
    init(date: Date, mode: SessionMode) {
        let start = Calendar.current.startOfDay(for: date)
        self.date = start; id = UUID()
        dayKey = String(start.timeIntervalSince1970)
        completed = true; isMVR = mode == .mvr; isSickProtocol = mode == .recovery
    }
}
