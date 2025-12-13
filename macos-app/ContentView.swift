import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @EnvironmentObject private var backlinksStore: BacklinksStore

    @State private var sidebarWidth: CGFloat = 250
    @State private var backlinksWidth: CGFloat = 300
    @State private var showingBackendAlert: Bool = false
    @State private var bootPhase: BootPhase = .booting("Booting...")
    private let bootOverlayMinDurationNs: UInt64 = 450_000_000
    private let semanticIndexRequiredVersion = 2

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { noteStore.selection },
            set: { noteStore.select($0) }
        )
    }

    var body: some View {
        ZStack {
            if bootPhase == .ready {
                NavigationSplitView {
                    SidebarView(selectedNoteId: selectionBinding)
                        .frame(minWidth: 200, idealWidth: sidebarWidth, maxWidth: 400)
                } detail: {
                    HStack(spacing: 0) {
                        EditorView(selectedNoteId: selectionBinding)
                            .frame(minWidth: 400)

                        BacklinksView(selectedNoteId: selectionBinding)
                            .frame(minWidth: 250, idealWidth: backlinksWidth, maxWidth: 500)
                            .background(Color(NSColor.controlBackgroundColor))
                            .border(Color(NSColor.separatorColor), width: 1)
                    }
                }
                .navigationSplitViewStyle(.balanced)
                .overlay(alignment: .topTrailing) {
                    BackendStatusIndicator()
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            } else if bootPhase == .selectProject {
                ProjectSelectionView(
                    currentProject: noteStore.currentProject,
                    recentPaths: noteStore.recentProjectPaths(),
                    availableProjects: noteStore.availableProjects,
                    onCreateProject: { name in
                        Task { await createProjectAndEnterApp(name: name) }
                    },
                    onOpenProject: { path in
                        Task { await openProjectAndEnterApp(path: path) }
                    },
                    onContinue: {
                        Task { await continueWithCurrentProject() }
                    },
                    onRefresh: {
                        Task { await noteStore.refreshProjects() }
                    }
                )
            }

            BootOverlay(phase: bootPhase) {
                Task { await boot() }
            }
        }
        .task {
            await boot()
        }
        .onChange(of: noteStore.currentProject?.path) { newPath in
            guard let newPath else { return }
            if bootPhase == .selectProject || bootPhase == .ready {
                Task { await warmupProjectIndexAndEnter(projectPath: newPath) }
            }
        }
        .onChange(of: noteStore.backendStatus) { status in
            if bootPhase == .ready {
                showingBackendAlert = status == .offline
            }
        }
        .alert("Backend Connection Issue", isPresented: $showingBackendAlert) {
            Button("OK") {
                showingBackendAlert = false
            }
            Button("Retry") {
                Task {
                    await boot()
                }
            }
        } message: {
            if let error = noteStore.lastError {
                Text(
                    "Unable to connect to backend server: \(error)\n\nMake sure the backend is running at http://127.0.0.1:8000"
                )
            } else {
                Text(
                    "Unable to connect to backend server.\n\nMake sure the backend is running at http://127.0.0.1:8000"
                )
            }
        }
    }

    private func boot() async {
        if bootPhase == .ready || bootPhase == .selectProject { return }
        let startNs = DispatchTime.now().uptimeNanoseconds
        bootPhase = .booting("Connecting to backend...")
        await noteStore.bootstrap()
        guard noteStore.backendStatus == .online else {
            showingBackendAlert = false
            bootPhase = .failed(noteStore.lastError ?? "Backend is offline.")
            return
        }
        // Show project picker after initial boot.
        let elapsed = DispatchTime.now().uptimeNanoseconds &- startNs
        if elapsed < bootOverlayMinDurationNs {
            try? await Task.sleep(nanoseconds: bootOverlayMinDurationNs - elapsed)
        }
        bootPhase = .selectProject
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let ns = error as NSError
        return ns.code == NSURLErrorCancelled || (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled)
    }

    @ViewBuilder
    private func BackendStatusIndicator() -> some View {
        let isOnline = noteStore.backendStatus == .online
        HStack(spacing: 6) {
            Circle()
                .fill(isOnline ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(isOnline ? "Backend Connected" : "Backend Offline")
                .font(.caption)
                .foregroundColor(isOnline ? .green : .red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onTapGesture {
            showingBackendAlert = noteStore.backendStatus == .offline
        }
        .help(
            isOnline
                ? "Backend server is running" : "Tap to see backend connection details")
    }

    private func semanticIndexVersionKey(for projectPath: String) -> String {
        let normalized = projectPath.replacingOccurrences(of: "/", with: "_")
        return "grimoire.semanticContextIndexVersion.\(normalized)"
    }

    private func continueWithCurrentProject() async {
        guard let path = noteStore.currentProject?.path else { return }
        await openProjectAndEnterApp(path: path)
    }

    private func createProjectAndEnterApp(name: String) async {
        bootPhase = .booting("Creating project...")
        await noteStore.createProject(name: name)
        guard let path = noteStore.currentProject?.path else {
            bootPhase = .selectProject
            return
        }
        await warmupProjectIndexAndEnter(projectPath: path)
    }

    private func openProjectAndEnterApp(path: String) async {
        bootPhase = .booting("Opening project...")
        await noteStore.openProject(path: path)
        guard let currentPath = noteStore.currentProject?.path else {
            bootPhase = .selectProject
            return
        }
        await warmupProjectIndexAndEnter(projectPath: currentPath)
    }

    private func warmupProjectIndexAndEnter(projectPath: String) async {
        bootPhase = .booting("Warming up semantic index...")
        do {
            let key = semanticIndexVersionKey(for: projectPath)
            let current = UserDefaults.standard.integer(forKey: key)
            let forceRebuild = current < semanticIndexRequiredVersion
            try await backlinksStore.warmup(forceRebuild: forceRebuild)
            if forceRebuild {
                UserDefaults.standard.set(semanticIndexRequiredVersion, forKey: key)
            }
            bootPhase = .ready
        } catch {
            if isCancellation(error) { return }
            bootPhase = .failed((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
    }
}

private enum BootPhase: Equatable {
    case booting(String)
    case failed(String)
    case selectProject
    case ready
}

private struct BootOverlay: View {
    let phase: BootPhase
    let onRetry: () -> Void

    var body: some View {
        switch phase {
        case .ready:
            EmptyView()
        case .selectProject:
            EmptyView()
        case .booting(let step):
            overlay {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(step)
                        .font(.headline)
                    Text("Please wait until Grimoire finishes starting up.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: 420)
            }
        case .failed(let message):
            overlay {
                VStack(spacing: 12) {
                    Text("Startup Failed")
                        .font(.headline)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") { onRetry() }
                        .keyboardShortcut(.defaultAction)
                }
                .frame(maxWidth: 520)
            }
        }
    }

    private func overlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color(NSColor.windowBackgroundColor)
                .opacity(0.97)
                .ignoresSafeArea()
            content()
                .padding(24)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 6)
        }
        .allowsHitTesting(true)
    }
}

private struct ProjectSelectionView: View {
    let currentProject: ProjectInfo?
    let recentPaths: [String]
    let availableProjects: [ProjectInfo]
    let onCreateProject: (String) -> Void
    let onOpenProject: (String) -> Void
    let onContinue: () -> Void
    let onRefresh: () -> Void

    @State private var isShowingNewProjectAlert: Bool = false
    @State private var newProjectName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .alert("New Project", isPresented: $isShowingNewProjectAlert) {
            TextField("Project name", text: $newProjectName)
            Button("Cancel", role: .cancel) { newProjectName = "" }
            Button("Create") {
                let name = newProjectName.trimmingCharacters(in: .whitespacesAndNewlines)
                newProjectName = ""
                guard !name.isEmpty else { return }
                onCreateProject(name)
            }
        } message: {
            Text("Creates a new `.grim` project with its own notes and folders.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Choose a Project")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Projects are stored locally as `.grim` folders.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Refresh") { onRefresh() }
            Button("Open…") { presentOpenProjectPanel() }
            Button("New…") { isShowingNewProjectAlert = true }
        }
        .padding(16)
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let currentProject {
                    SectionCard(title: "Current Project") {
                        ProjectRow(
                            title: currentProject.name,
                            subtitle: currentProject.path,
                            buttonTitle: "Continue",
                            onSelect: onContinue
                        )
                    }
                }

                SectionCard(title: "Recent Projects") {
                    if recentPaths.isEmpty {
                        Text("No recent projects yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(recentPaths, id: \.self) { path in
                                ProjectRow(
                                    title: (path as NSString).lastPathComponent,
                                    subtitle: path,
                                    buttonTitle: "Open",
                                    onSelect: { onOpenProject(path) }
                                )
                            }
                        }
                    }
                }

                SectionCard(title: "All Projects") {
                    if availableProjects.isEmpty {
                        Text("No projects found.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(availableProjects) { project in
                                ProjectRow(
                                    title: project.name,
                                    subtitle: project.path,
                                    buttonTitle: project.isActive ? "Current" : "Open",
                                    onSelect: {
                                        if !project.isActive { onOpenProject(project.path) }
                                    }
                                )
                                .opacity(project.isActive ? 0.8 : 1.0)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func presentOpenProjectPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        panel.prompt = "Open"
        panel.message = "Select a `.grim` project folder"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.pathExtension.lowercased() == "grim" else { return }
        onOpenProject(url.path)
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

private struct ProjectRow: View {
    let title: String
    let subtitle: String
    let buttonTitle: String
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(buttonTitle) { onSelect() }
                .buttonStyle(.bordered)
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}
