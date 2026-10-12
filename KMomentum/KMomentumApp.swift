import SwiftUI
import SwiftData
@main struct KMomentumApp: App {
    @UIApplicationDelegateAdaptor(MomentumAppDelegate.self) private var appDelegate
    private let container: ModelContainer
    init() {
        do { container = try MomentumStore.container() }
        catch { fatalError("No se pudo abrir el historial de KMomentum: \(error.localizedDescription)") }
        MomentumShortcuts.updateAppShortcutParameters()
    }
    var body: some Scene {
        WindowGroup { DashboardView().preferredColorScheme(.light) }
            .modelContainer(container)
    }
}
