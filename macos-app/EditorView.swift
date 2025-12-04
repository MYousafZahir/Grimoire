import Combine
import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var noteManager: NoteManager
    @Binding var selectedNoteId: String?
    var onTextChange: (String) -> Void

    @State private var noteContent: String = ""
    @State private var isEditing: Bool = false
    @State private var lastSavedContent: String = ""
    @State private var saveTimer: AnyCancellable?
    @State private var showPreview: Bool = false
    @State private var saveStatus: SaveStatus = .saved
    @State private var lastSaveAttempt: Date = Date()

    enum SaveStatus {
        case saved
        case editing
        case saving
        case error(String)
        case unsaved
    }

    private var isFolderSelected: Bool {
        guard let selectedNoteId = selectedNoteId else { return false }
        // Check if the selected item is a folder by looking in the note tree
        return noteManager.noteTree.contains { noteInfo in
            isFolder(noteInfo: noteInfo, targetId: selectedNoteId)
        }
    }

    private func isFolder(noteInfo: NoteInfo, targetId: String) -> Bool {
        if noteInfo.id == targetId {
            return noteInfo.type == "folder" || !noteInfo.children.isEmpty
        }
        // Check children recursively
        for child in noteInfo.children {
            if isFolder(noteInfo: child, targetId: targetId) {
                return true
            }
        }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                if let selectedNoteId = selectedNoteId,
                    let note = noteManager.getNote(id: selectedNoteId)
                {
                    Text(note.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No Note Selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Preview toggle
                Button(action: {
                    showPreview.toggle()
                }) {
                    Image(systemName: showPreview ? "eye.slash" : "eye")
                        .foregroundColor(showPreview ? .accentColor : .secondary)
                }
                .help(showPreview ? "Hide Preview" : "Show Preview")
                .buttonStyle(.plain)

                // Save status
                switch saveStatus {
                case .saved:
                    Text("Saved")
                        .font(.caption)
                        .foregroundColor(.green)
                case .editing:
                    Text("Editing...")
                        .font(.caption)
                        .foregroundColor(.orange)
                case .saving:
                    Text("Saving...")
                        .font(.caption)
                        .foregroundColor(.blue)
                case .unsaved:
                    Text("Unsaved")
                        .font(.caption)
                        .foregroundColor(.red)
                case .error(let message):
                    Text("Error: \(message)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 1)

            // Editor/Preview area
            if showPreview {
                // Simple text preview
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !noteContent.isEmpty {
                            Text(noteContent)
                                .font(.body)
                                .padding()
                        } else {
                            Text("No content to preview")
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
            } else if let selectedNoteId = selectedNoteId, !isFolderSelected {
                // Markdown editor for notes only (not folders)
                TextEditor(text: $noteContent)
                    .font(.system(.body, design: .monospaced))
                    .lineSpacing(4)
                    .padding()
                    .onChange(of: noteContent) { newValue in
                        handleTextChange(newValue)
                    }
            } else if let selectedNoteId = selectedNoteId, isFolderSelected {
                // Folder view - cannot edit folders
                VStack(spacing: 20) {
                    Image(systemName: "folder")
                        .font(.system(size: 64))
                        .foregroundColor(.yellow)

                    Text("Folder Selected")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Text("Folders cannot be edited. Select a note to edit its content.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("Folder: \(selectedNoteId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Empty state when no note is selected
                VStack(spacing: 20) {
                    Image(systemName: "note.text")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text("No Note Selected")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Text("Select a note from the sidebar or create a new one")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    if !noteManager.isBackendAvailable {
                        Text("Backend is offline - notes will be saved locally")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.top, 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedNoteId) { newValue in
            loadNoteContent()
        }
        .onAppear {
            loadNoteContent()
        }
    }

    private func loadNoteContent() {
        guard let selectedNoteId = selectedNoteId else {
            noteContent = ""
            lastSavedContent = ""
            saveStatus = .saved
            return
        }

        // Don't load content for folders
        if isFolderSelected {
            noteContent = ""
            lastSavedContent = ""
            saveStatus = .saved
            return
        }

        noteManager.loadNoteContent(noteId: selectedNoteId) { content in
            noteContent = content
            lastSavedContent = content
            isEditing = false
            saveStatus = .saved
        }
    }

    private func handleTextChange(_ newText: String) {
        guard let selectedNoteId = selectedNoteId, !isFolderSelected else { return }

        isEditing = true
        saveStatus = .editing

        // Cancel any existing timer
        saveTimer?.cancel()

        // Start a new timer for autosave using Combine
        saveTimer = Just(())
            .delay(for: .seconds(2.0), scheduler: DispatchQueue.main)
            .sink { [self] _ in
                saveNoteContent()
            }

        // Notify parent about text change for semantic search
        onTextChange(newText)
    }

    private func saveNoteContent() {
        guard let selectedNoteId = selectedNoteId, !isFolderSelected else { return }

        // Don't save if content hasn't changed
        if noteContent == lastSavedContent {
            saveStatus = .saved
            isEditing = false
            return
        }

        // Don't save too frequently
        let now = Date()
        if now.timeIntervalSince(lastSaveAttempt) < 1.0 {
            // Too soon since last save attempt, schedule for later
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.saveNoteContent()
            }
            return
        }

        lastSaveAttempt = now
        saveStatus = .saving

        noteManager.saveNoteContent(noteId: selectedNoteId, content: noteContent) { success in
            if success {
                self.lastSavedContent = self.noteContent
                self.isEditing = false
                self.saveStatus = .saved
                print("Successfully saved note: \(selectedNoteId)")
            } else {
                if self.noteManager.isBackendAvailable {
                    self.saveStatus = .error("Save failed")
                } else {
                    // If backend is offline, mark as saved locally
                    self.lastSavedContent = self.noteContent
                    self.isEditing = false
                    self.saveStatus = .saved
                    print("Saved locally (backend offline): \(selectedNoteId)")
                }
                // Schedule retry if backend comes back online
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if self.noteContent != self.lastSavedContent
                        && self.noteManager.isBackendAvailable
                    {
                        self.saveNoteContent()
                    }
                }
            }
        }
    }
}

#Preview {
    EditorView(
        selectedNoteId: .constant("welcome"),
        onTextChange: { _ in }
    )
    .environmentObject(NoteManager())
    .frame(width: 600, height: 400)
}
