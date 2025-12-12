import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @EnvironmentObject private var backlinksStore: BacklinksStore

    @State private var sidebarWidth: CGFloat = 250
    @State private var backlinksWidth: CGFloat = 300
    @State private var showingBackendAlert: Bool = false
    @State private var bootPhase: BootPhase = .booting("Booting...")
    private let bootOverlayMinDurationNs: UInt64 = 450_000_000
    private let semanticIndexVersionKey = "grimoire.semanticContextIndexVersion"
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
            }

            BootOverlay(phase: bootPhase) {
                Task { await boot() }
            }
        }
        .task {
            await boot()
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
        if bootPhase == .ready { return }
        let startNs = DispatchTime.now().uptimeNanoseconds
        bootPhase = .booting("Connecting to backend...")
        await noteStore.bootstrap()
        guard noteStore.backendStatus == .online else {
            showingBackendAlert = false
            bootPhase = .failed(noteStore.lastError ?? "Backend is offline.")
            return
        }

        bootPhase = .booting("Warming up semantic index...")
        do {
            let current = UserDefaults.standard.integer(forKey: semanticIndexVersionKey)
            let forceRebuild = current < semanticIndexRequiredVersion
            try await backlinksStore.warmup(forceRebuild: forceRebuild)
            if forceRebuild {
                UserDefaults.standard.set(semanticIndexRequiredVersion, forKey: semanticIndexVersionKey)
            }
            let elapsed = DispatchTime.now().uptimeNanoseconds &- startNs
            if elapsed < bootOverlayMinDurationNs {
                try? await Task.sleep(nanoseconds: bootOverlayMinDurationNs - elapsed)
            }
            bootPhase = .ready
        } catch {
            if isCancellation(error) { return }
            showingBackendAlert = false
            bootPhase = .failed((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
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
}

private enum BootPhase: Equatable {
    case booting(String)
    case failed(String)
    case ready
}

private struct BootOverlay: View {
    let phase: BootPhase
    let onRetry: () -> Void

    var body: some View {
        switch phase {
        case .ready:
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
