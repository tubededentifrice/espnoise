import SwiftUI

@main
struct ESPNoiseApp: App {
    @StateObject private var syncManager = NoiseSyncManager()

    var body: some Scene {
        WindowGroup {
            ContentView(syncManager: syncManager)
        }
    }
}
