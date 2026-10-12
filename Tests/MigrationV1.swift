import Foundation
import SwiftData
@main struct MigrationV1 {
    @MainActor static func main() throws {
        let schema = Schema([UserCycleState.self, DailyLog.self])
        let configuration = ModelConfiguration(schema: schema, url: URL(fileURLWithPath: CommandLine.arguments[1]), cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = container.mainContext
        let state = UserCycleState(); state.lastPeriodStartDate = Date(timeIntervalSince1970: 1_780_000_000)
        state.hasPeriodDate = true; state.remindersEnabled = true
        context.insert(state)
        let log = DailyLog(date: Date(timeIntervalSince1970: 1_780_100_000), mode: .mvr); log.notes = "Preservar mi historial"
        context.insert(log); try context.save()
        print("Legacy store created")
    }
}
