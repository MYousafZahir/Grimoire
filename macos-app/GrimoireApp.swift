import SwiftUI

#if os(macOS)
import AppKit
#endif

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
                .task {
                    #if os(macOS)
                    ProjectMenuInstaller.installOnce(noteStore: noteStore, backlinksStore: backlinksStore)
                    #endif
                }
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

#if os(macOS)
private enum ProjectMenuInstaller {
    private static var isInstalled: Bool = false
    private static let target = ProjectMenuTarget()

    static func installOnce(noteStore: NoteStore, backlinksStore: BacklinksStore) {
        guard !isInstalled else { return }
        isInstalled = true

        target.noteStore = noteStore
        target.backlinksStore = backlinksStore

        guard let mainMenu = NSApp.mainMenu else { return }
        guard let fileMenuItem = mainMenu.items.first(where: { $0.title == "File" }) else { return }
        guard let fileMenu = fileMenuItem.submenu else { return }

        let markerTag = 901_337
        if fileMenu.items.contains(where: { $0.tag == markerTag }) { return }

        let newItem = NSMenuItem(title: "New Project…", action: #selector(ProjectMenuTarget.newProject(_:)), keyEquivalent: "N")
        newItem.keyEquivalentModifierMask = [.command, .shift]
        newItem.target = target
        newItem.tag = markerTag

        let openItem = NSMenuItem(title: "Open Project…", action: #selector(ProjectMenuTarget.openProject(_:)), keyEquivalent: "O")
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = target
        openItem.tag = markerTag

        // Insert near the top of File menu, after "New" items if they exist.
        let insertionIndex: Int
        if let idx = fileMenu.items.firstIndex(where: { $0.action == #selector(NSDocumentController.newDocument(_:)) }) {
            insertionIndex = idx + 1
        } else {
            insertionIndex = min(1, fileMenu.items.count)
        }

        fileMenu.insertItem(NSMenuItem.separator(), at: insertionIndex)
        fileMenu.insertItem(openItem, at: insertionIndex + 1)
        fileMenu.insertItem(newItem, at: insertionIndex + 1)
    }
}

private final class ProjectMenuTarget: NSObject {
    weak var noteStore: NoteStore?
    weak var backlinksStore: BacklinksStore?

    @objc func newProject(_ sender: Any?) {
        guard let noteStore, let backlinksStore else { return }

        let alert = NSAlert()
        alert.messageText = "New Project"
        alert.informativeText = "Creates a new `.grim` project with its own notes and folders."
        alert.alertStyle = .informational

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        input.placeholderString = "Project name"
        alert.accessoryView = input

        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        Task { @MainActor in
            backlinksStore.clear()
            await noteStore.createProject(name: name)
        }
    }

    @objc func openProject(_ sender: Any?) {
        guard let noteStore, let backlinksStore else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Open"
        panel.message = "Select a `.grim` project folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension.lowercased() == "grim" else { return }

        Task { @MainActor in
            backlinksStore.clear()
            await noteStore.openProject(path: url.path)
        }
    }
}
#endif
