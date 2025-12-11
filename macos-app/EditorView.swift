import SwiftUI

struct EditorView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @EnvironmentObject private var backlinksStore: BacklinksStore
    @Binding var selectedNoteId: String?

    @State private var noteContent: String = ""
    @State private var showPreview: Bool = false
    @State private var saveTask: Task<Void, Never>?

    private var isFolderSelected: Bool {
        guard let selectedNoteId else { return false }
        return noteStore.isFolder(id: selectedNoteId)
            || noteStore.currentNoteKind == .folder
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let selectedNoteId {
                    Text(noteStore.title(for: selectedNoteId) ?? selectedNoteId)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No Note Selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { showPreview.toggle() }) {
                    Image(systemName: showPreview ? "eye.slash" : "eye")
                        .foregroundColor(showPreview ? .accentColor : .secondary)
                }
                .help(showPreview ? "Hide Preview" : "Show Preview")
                .buttonStyle(.plain)

                statusLabel
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 1)

            if showPreview {
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
            } else if let selectedNoteId, !isFolderSelected {
                TextEditor(text: $noteContent)
                    .font(.system(.body, design: .monospaced))
                    .lineSpacing(4)
                    .padding()
                    .onChange(of: noteContent) { newValue in
                        handleTextChange(newValue, noteId: selectedNoteId)
                    }
            } else if let selectedNoteId, isFolderSelected {
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedNoteId) { _ in
            syncFromStore()
        }
        .onChange(of: noteStore.currentContent) { _ in
            syncFromStore()
        }
        .task {
            syncFromStore()
        }
    }

    private func syncFromStore() {
        guard selectedNoteId == noteStore.selection else { return }
        noteContent = noteStore.currentContent
    }

    private func handleTextChange(_ newText: String, noteId: String) {
        noteStore.updateDraft(newText)
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            // Run the save in a detached task so subsequent cancellations (new keystrokes)
            // don't abort an in-flight network call.
            _ = await Task.detached(priority: .userInitiated) { @MainActor in
                await noteStore.saveDraft()
            }.value
        }

        backlinksStore.search(
            noteId: noteId,
            text: newText,
            titleProvider: { noteStore.title(for: $0) }
        )
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch noteStore.saveState {
        case .idle:
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
        case .failed(let message):
            let lower = message.lowercased()
            if lower.contains("cancel") || lower.contains("canceled") {
                Text("Editing...")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Text("Error: \(message)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }
}
