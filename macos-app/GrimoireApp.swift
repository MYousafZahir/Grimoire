import SwiftUI

@main
struct GrimoireApp: App {
    @StateObject private var noteStore = NoteStore()
    @StateObject private var backlinksStore = BacklinksStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(noteStore)
                .environmentObject(backlinksStore)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(noteStore)
        }
        #endif
    }
}
