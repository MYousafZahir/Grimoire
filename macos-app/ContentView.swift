import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var noteManager: NoteManager
    @EnvironmentObject private var searchManager: SearchManager

    @State private var selectedNoteId: String? = nil
    @State private var sidebarWidth: CGFloat = 250
    @State private var backlinksWidth: CGFloat = 300
    @State private var showingBackendAlert: Bool = false

    var body: some View {
        NavigationSplitView {
            // Left sidebar - Note hierarchy
            SidebarView(selectedNoteId: $selectedNoteId)
                .frame(minWidth: 200, idealWidth: sidebarWidth, maxWidth: 400)
        } detail: {
            // Main editor area
            HStack(spacing: 0) {
                // Editor
                EditorView(
                    selectedNoteId: $selectedNoteId,
                    onTextChange: { text in
                        if let noteId = selectedNoteId {
                            searchManager.debouncedSearch(noteId: noteId, text: text)
                        }
                    }
                )
                .frame(minWidth: 400)

                // Right sidebar - Backlinks
                BacklinksView(selectedNoteId: $selectedNoteId)
                    .frame(minWidth: 250, idealWidth: backlinksWidth, maxWidth: 500)
                    .background(Color(NSColor.controlBackgroundColor))
                    .border(Color(NSColor.separatorColor), width: 1)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            // Setup notification observers first
            setupNotifications()

            // Add a small delay before checking backend connection
            // to ensure backend has time to start if it was just launched
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Check backend connection
                noteManager.checkBackendConnection()
                // Load initial data
                noteManager.loadNotes()
            }
        }
        .onDisappear {
            // Clean up notifications
            NotificationCenter.default.removeObserver(self)
        }
        .overlay(alignment: .topTrailing) {
            BackendStatusIndicator()
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
        .alert("Backend Connection Issue", isPresented: $showingBackendAlert) {
            Button("OK") {}
            Button("Retry") {
                noteManager.checkBackendConnection()
                noteManager.loadNotes()
            }
        } message: {
            if let error = noteManager.lastError {
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

    private func setupNotifications() {
        // Listen for note creation to select the new note
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NoteCreated"),
            object: nil,
            queue: .main
        ) { notification in
            if let noteId = notification.userInfo?["noteId"] as? String {
                print("Selecting newly created note: \(noteId)")
                selectedNoteId = noteId
            }
        }

        // Listen for notes loaded to handle selection after refresh
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NotesLoaded"),
            object: nil,
            queue: .main
        ) { _ in
            print("Notes loaded, current selection: \(selectedNoteId ?? "none")")
        }

        // Listen for note creation failures
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NoteCreationFailed"),
            object: nil,
            queue: .main
        ) { notification in
            if let noteId = notification.userInfo?["noteId"] as? String {
                print("Note creation failed: \(noteId)")
                showingBackendAlert = true
            }
        }
    }

    @ViewBuilder
    private func BackendStatusIndicator() -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(noteManager.isBackendAvailable ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(noteManager.isBackendAvailable ? "Backend Connected" : "Backend Offline")
                .font(.caption)
                .foregroundColor(noteManager.isBackendAvailable ? .green : .red)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .onTapGesture {
            showingBackendAlert = !noteManager.isBackendAvailable
        }
        .help(
            noteManager.isBackendAvailable
                ? "Backend server is running" : "Tap to see backend connection details")
    }
}

#Preview {
    ContentView()
        .environmentObject(NoteManager())
        .environmentObject(SearchManager())
}
