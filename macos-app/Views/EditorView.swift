import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var noteManager: NoteManager
    @Binding var selectedNoteId: String?
    var onTextChange: (String) -> Void

    @State private var noteContent: String = ""
    @State private var isEditing: Bool = false
    @State private var lastSavedContent: String = ""
    @State private var saveTimer: Timer?
    @State private var showPreview: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                if let selectedNoteId = selectedNoteId,
                   let note = noteManager.getNote(id: selectedNoteId) {
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
                if isEditing {
                    Text("Editing...")
                        .font(.caption)
                        .foregroundColor(.orange)
                } else if noteContent != lastSavedContent {
                    Text("Unsaved")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("Saved")
                        .font(.caption)
                        .foregroundColor(.green)
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
            } else {
                // Markdown editor
                TextEditor(text: $noteContent)
                    .font(.system(.body, design: .monospaced))
                    .lineSpacing(4)
                    .padding()
                    .onChange(of: noteContent) { newValue in
                        handleTextChange(newValue)
                    }
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
            return
        }

        noteManager.loadNoteContent(noteId: selectedNoteId) { content in
            noteContent = content
            lastSavedContent = content
            isEditing = false
        }
    }

    private func handleTextChange(_ newText: String) {
        isEditing = true

        // Cancel any existing timer
        saveTimer?.invalidate()

        // Start a new timer for autosave
        saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
            saveNoteContent()
        }

        // Notify parent about text change for semantic search
        onTextChange(newText)
    }

    private func saveNoteContent() {
        guard let selectedNoteId = selectedNoteId else { return }

        noteManager.saveNoteContent(noteId: selectedNoteId, content: noteContent) { success in
            if success {
                lastSavedContent = noteContent
                isEditing = false
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
