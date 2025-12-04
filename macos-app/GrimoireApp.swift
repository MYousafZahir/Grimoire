import SwiftUI

@main
struct GrimoireApp: App {
    @StateObject private var noteManager = NoteManager()
    @StateObject private var searchManager = SearchManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(noteManager)
                .environmentObject(searchManager)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(noteManager)
        }
        #endif
    }
}
