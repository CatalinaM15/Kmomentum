import Foundation

@main struct LockScreenChecks {
    static func main() throws {
        let calendar = Calendar.current
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11))!
        let promise = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: sunday)!
        var snapshot = WidgetSnapshot(date: sunday, completed: false, title: "Sesión", week: [true, false, true, false, false, false, true], commitment: promise)
        precondition(snapshot.commitmentMessage == "Tu compromiso de hoy: \(promise.formatted(date: .omitted, time: .shortened))")
        precondition(snapshot.weeklyPercentage == 43 && snapshot.weeklyCompletedDays == 3)

        snapshot.recoveryActive = true
        precondition(snapshot.commitmentMessage == "Día de pausa y respiración")
        snapshot.recoveryActive = false
        snapshot.pausedWeek = [false, false, false, false, false, false, true]
        precondition(snapshot.commitmentMessage == "Día de pausa y respiración")
        precondition(snapshot.weekState(at: 6) == .paused && snapshot.weeklyCompletedDays == 2)
        snapshot.pausedWeek = nil
        snapshot.completed = true
        precondition(snapshot.commitmentMessage == "Buen trabajo!")

        snapshot.completed = false
        snapshot.commitment = calendar.date(byAdding: .day, value: -1, to: promise)!
        precondition(snapshot.commitmentMessage == "Un pequeño paso también cuenta.")
        snapshot.commitment = nil
        precondition(snapshot.commitmentMessage == "Un pequeño paso también cuenta.")

        snapshot.date = calendar.date(byAdding: .day, value: -6, to: sunday)!
        snapshot.week = Array(repeating: true, count: 7)
        snapshot.pausedWeek = Array(repeating: true, count: 7)
        precondition(snapshot.weekState(at: 1) == .pending && snapshot.weekState(at: 7) == .pending && snapshot.weekState(at: -1) == .pending)
        snapshot.pausedWeek = []
        precondition(snapshot.weeklyPercentage == 14)
        snapshot.week = []
        precondition(snapshot.weeklyPercentage == 0 && snapshot.weekState(at: 0) == .pending)

        snapshot.commitment = promise
        snapshot.recoveryActive = true
        let data = try JSONEncoder().encode(snapshot)
        let restored = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        precondition(restored.commitment == promise && restored.recoveryActive == true)
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "commitment")
        legacy.removeValue(forKey: "recoveryActive")
        let oldSnapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        precondition(oldSnapshot.commitment == nil && oldSnapshot.recoveryActive == nil)
        print("Passed 13 Lock Screen checks")
    }
}
