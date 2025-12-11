import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @EnvironmentObject private var backlinksStore: BacklinksStore

    @State private var sidebarWidth: CGFloat = 250
    @State private var backlinksWidth: CGFloat = 300
    @State private var showingBackendAlert: Bool = false

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { noteStore.selection },
            set: { noteStore.select($0) }
        )
    }

    var body: some View {
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
        .task {
            await noteStore.bootstrap()
        }
        .onChange(of: noteStore.backendStatus) { status in
            showingBackendAlert = status == .offline
        }
        .overlay(alignment: .topTrailing) {
            BackendStatusIndicator()
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
        .alert("Backend Connection Issue", isPresented: $showingBackendAlert) {
            Button("OK") {
                showingBackendAlert = false
            }
            Button("Retry") {
                Task {
                    await noteStore.bootstrap()
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
