import SwiftUI

#if os(macOS)
import AppKit
#endif

@main
struct GrimoireApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(GrimoireAppDelegate.self) private var appDelegate
    #endif

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

#if os(macOS)
private final class GrimoireAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            ProjectMenuInstaller.installOnce()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Defensive: SwiftUI sometimes rebuilds menus; ensure our items are present.
        ProjectMenuInstaller.ensureInstalled()
    }
}

enum ProjectMenuInstaller {
    private static let target = ProjectMenuTarget()
    private static let delegate = ProjectFileMenuDelegate()
    static let recentProjectsKey = "grimoire.recentProjectPaths"

    static func installOnce() {
        // SwiftUI can rebuild the menu after launch; schedule a few retries.
        for delay in [0.0, 0.25, 0.75, 1.5, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ensureInstalled()
            }
        }
    }

    static func ensureInstalled() {
        _ = installIfPossible()
        hookFileMenuDelegate()
    }

    private static func installIfPossible() -> Bool {
        guard let mainMenu = NSApp.mainMenu else { return false }

        func looksLikeFileMenu(_ item: NSMenuItem) -> Bool {
            guard let submenu = item.submenu else { return false }
            let hasClose = submenu.items.contains(where: { $0.action == #selector(NSWindow.performClose(_:)) })
            let hasNewWindow = submenu.items.contains(where: { $0.title.lowercased().contains("new window") })
            return hasClose && hasNewWindow
        }

        let fileMenuItem =
            mainMenu.items.first(where: { $0.title.caseInsensitiveCompare("File") == .orderedSame })
            ?? mainMenu.items.first(where: looksLikeFileMenu(_:))

        guard let fileMenuItem, let fileMenu = fileMenuItem.submenu else { return false }

        ensureItems(in: fileMenu)
        return true
    }

    private static func hookFileMenuDelegate() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard let fileItem = mainMenu.items.first(where: { $0.title.caseInsensitiveCompare("File") == .orderedSame })
                ?? mainMenu.items.first(where: { ($0.submenu?.items.contains(where: { $0.title.lowercased().contains("new window") }) ?? false) })
        else { return }
        guard let fileMenu = fileItem.submenu else { return }
        if fileMenu.delegate == nil || fileMenu.delegate !== delegate {
            delegate.installer = { menu in
                // Always ensure the items exist right before the menu opens.
                _ = installIfPossible()
                // Also ensure the target menu itself has the items (covers rebuilds).
                ensureItems(in: menu)
            }
            fileMenu.delegate = delegate
        }
    }

	    private static func ensureItems(in menu: NSMenu) {
	        // Remove any previously-inserted items (including older builds that used a shared marker tag).
	        let legacyTag = 901_337
	        let sepTag = legacyTag + 10
	        let newTag = legacyTag + 11
	        let openTag = legacyTag + 12
	        let recentsTag = legacyTag + 13
	        let rebuildSepTag = legacyTag + 14
	        let rebuildGlossaryTag = legacyTag + 15
	        let tagsToRemove: Set<Int> = [
	            legacyTag,
	            sepTag,
	            newTag,
	            openTag,
	            recentsTag,
	            rebuildSepTag,
	            rebuildGlossaryTag,
	        ]
	        for item in menu.items where tagsToRemove.contains(item.tag) {
	            menu.removeItem(item)
	        }

        let insertionIndex: Int
        if let idx = menu.items.firstIndex(where: { $0.title.lowercased().contains("new window") }) {
            insertionIndex = idx + 1
        } else {
            insertionIndex = 0
        }

        let separator = NSMenuItem.separator()
        separator.tag = sepTag

        let newItem = NSMenuItem(
            title: "New Project…",
            action: #selector(ProjectMenuTarget.newProject(_:)),
            keyEquivalent: "N"
        )
        newItem.keyEquivalentModifierMask = [.command, .shift]
        newItem.target = target
        newItem.tag = newTag

        let openItem = NSMenuItem(
            title: "Open Project…",
            action: #selector(ProjectMenuTarget.openProject(_:)),
            keyEquivalent: "O"
        )
        openItem.keyEquivalentModifierMask = [.command, .shift]
        openItem.target = target
        openItem.tag = openTag

	        let recentsMenuItem = NSMenuItem(title: "Open Recents…", action: nil, keyEquivalent: "")
	        recentsMenuItem.tag = recentsTag
	        recentsMenuItem.submenu = buildRecentsMenu()

	        let rebuildSeparator = NSMenuItem.separator()
	        rebuildSeparator.tag = rebuildSepTag
	        let rebuildGlossary = NSMenuItem(
	            title: "Rebuild Glossary",
	            action: #selector(ProjectMenuTarget.rebuildGlossary(_:)),
	            keyEquivalent: ""
	        )
	        rebuildGlossary.target = target
	        rebuildGlossary.tag = rebuildGlossaryTag

	        let insertAt = min(insertionIndex, menu.items.count)
	        let itemsToInsert = [separator, newItem, openItem, recentsMenuItem, rebuildSeparator, rebuildGlossary]
	        for (offset, item) in itemsToInsert.enumerated() {
	            menu.insertItem(item, at: min(insertAt + offset, menu.items.count))
	        }
	    }

    private static func buildRecentsMenu() -> NSMenu {
        let recentsMenu = NSMenu(title: "Open Recents")

        let paths = (UserDefaults.standard.array(forKey: recentProjectsKey) as? [String]) ?? []
        let trimmed = paths
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if trimmed.isEmpty {
            let none = NSMenuItem(title: "No Recent Projects", action: nil, keyEquivalent: "")
            none.isEnabled = false
            recentsMenu.addItem(none)
            return recentsMenu
        }

        for path in trimmed.prefix(10) {
            let title = (path as NSString).lastPathComponent
            let item = NSMenuItem(title: title, action: #selector(ProjectMenuTarget.openRecent(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = path
            item.toolTip = path
            recentsMenu.addItem(item)
        }

        recentsMenu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Recents", action: #selector(ProjectMenuTarget.clearRecents(_:)), keyEquivalent: "")
        clear.target = target
        recentsMenu.addItem(clear)
        return recentsMenu
    }
}

private final class ProjectMenuTarget: NSObject {
    @objc func newProject(_ sender: Any?) {
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

        NotificationCenter.default.post(
            name: .grimoireCreateProjectRequested,
            object: nil,
            userInfo: ["name": name],
        )
    }

    @objc func openProject(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Open"
        panel.message = "Select a `.grim` project folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension.lowercased() == "grim" else { return }

        NotificationCenter.default.post(
            name: .grimoireOpenProjectRequested,
            object: nil,
            userInfo: ["path": url.path],
        )
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NotificationCenter.default.post(
            name: .grimoireOpenProjectRequested,
            object: nil,
            userInfo: ["path": path],
        )
    }

	    @objc func clearRecents(_ sender: Any?) {
	        UserDefaults.standard.removeObject(forKey: ProjectMenuInstaller.recentProjectsKey)
	        ProjectMenuInstaller.ensureInstalled()
	    }

	    @objc func rebuildGlossary(_ sender: Any?) {
	        NotificationCenter.default.post(
	            name: .grimoireRebuildGlossaryRequested,
	            object: nil
	        )
	    }
	}

	extension Notification.Name {
	    static let grimoireCreateProjectRequested = Notification.Name("Grimoire.CreateProjectRequested")
	    static let grimoireOpenProjectRequested = Notification.Name("Grimoire.OpenProjectRequested")
	    static let grimoireRebuildGlossaryRequested = Notification.Name("Grimoire.RebuildGlossaryRequested")
	}

private final class ProjectFileMenuDelegate: NSObject, NSMenuDelegate {
    var installer: ((NSMenu) -> Void)?

    func menuWillOpen(_ menu: NSMenu) {
        installer?(menu)
    }
}
#endif
