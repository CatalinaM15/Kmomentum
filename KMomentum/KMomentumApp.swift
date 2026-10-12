import SwiftUI
import SwiftData
@main struct KMomentumApp: App {
    private let container: ModelContainer
    init() {
        do { container = try MomentumStore.container() }
        catch { fatalError("No se pudo abrir el historial de KMomentum: \(error.localizedDescription)") }
        NotificationScheduler.shared.configure()
        MomentumShortcuts.updateAppShortcutParameters()
    }
    var body: some Scene {
        WindowGroup { DashboardView().preferredColorScheme(.light) }
            .modelContainer(container)
    }
}
