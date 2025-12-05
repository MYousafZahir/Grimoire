import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var noteManager: NoteManager
    @Binding var selectedNoteId: String?

    @State private var expandedFolders: Set<String> = []
    @State private var showingErrorAlert: Bool = false
    @State private var renamingNoteId: String? = nil
    @State private var newNoteName: String = ""
    @State private var folderToDelete: String? = nil
    @State private var showingDeleteConfirmation: Bool = false
    @State private var folderHasContent: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Status bar
            if !noteManager.isBackendAvailable {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Using sample data")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Button("Retry") {
                        noteManager.checkBackendConnection()
                        noteManager.loadNotes()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .border(Color.orange.opacity(0.3), width: 1)
            }

            // Notes list
            if noteManager.noteTree.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No Notes Yet")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    Text("Create your first note to get started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Create New Note") {
                        noteManager.createNewNote(parentId: nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $selectedNoteId) {
                    ForEach(noteManager.noteTree) { noteInfo in
                        NoteRow(
                            noteInfo: noteInfo, expandedFolders: $expandedFolders,
                            selectedNoteId: $selectedNoteId,
                            renamingNoteId: $renamingNoteId,
                            newNoteName: $newNoteName,
                            folderToDelete: $folderToDelete,
                            showingDeleteConfirmation: $showingDeleteConfirmation,
                            folderHasContent: $folderHasContent,
                            onDeleteNote: deleteItemImmediately)
                    }
                }
                .listStyle(SidebarListStyle())
            }
        }
        .contextMenu {
            Button("New Note") {
                noteManager.createNewNote(parentId: nil)
            }

            Button("New Folder") {
                noteManager.createFolder(parentId: nil) { success in
                    if success {
                        // Expand the new folder
                        if let newFolderId = noteManager.noteTree.last?.id {
                            expandedFolders.insert(newFolderId)
                        }
                    }
                }
            }

            Button("New Child Note") {
                if let selectedId = selectedNoteId {
                    noteManager.createNewNote(parentId: selectedId)
                }
            }
            .disabled(selectedNoteId == nil)

            Button("New Child Folder") {
                if let selectedId = selectedNoteId {
                    noteManager.createFolder(parentId: selectedId) { success in
                        if success {
                            // Expand the parent folder
                            expandedFolders.insert(selectedId)
                        }
                    }
                }
            }
            .disabled(selectedNoteId == nil)

            Divider()

            Button("Rename") {
                if let selectedId = selectedNoteId {
                    renamingNoteId = selectedId
                    newNoteName =
                        noteManager.noteTree.first(where: { $0.id == selectedId })?.title ?? ""
                }
            }
            .disabled(selectedNoteId == nil)

            Divider()

            Button("Delete", role: .destructive) {
                if let selectedId = selectedNoteId {
                    print("DEBUG: Delete button clicked in main context menu for: \(selectedId)")
                    // Check if this is a folder with content
                    if isFolderWithContent(noteId: selectedId) {
                        folderToDelete = selectedId
                        folderHasContent = true
                        showingDeleteConfirmation = true
                    } else {
                        // For notes or empty folders, delete immediately
                        deleteItem(noteId: selectedId)
                    }
                }
            }
            .disabled(selectedNoteId == nil)
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("New Note") {
                        noteManager.createNewNote(parentId: nil)
                    }
                    Button("New Folder") {
                        noteManager.createFolder(parentId: nil) { success in
                            if success {
                                // Expand the new folder
                                if let newFolderId = noteManager.noteTree.last?.id {
                                    expandedFolders.insert(newFolderId)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create New")
                .disabled(!noteManager.isBackendAvailable && noteManager.noteTree.isEmpty)
            }

            ToolbarItem {
                Button(action: {
                    noteManager.loadNotes()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") {}
        } message: {
            if let error = noteManager.lastError {
                Text(error)
            } else {
                Text("An error occurred")
            }
        }
        .onChange(of: noteManager.lastError) { newValue in
            if newValue != nil {
                showingErrorAlert = true
            }
        }
        .alert(
            "Rename Note",
            isPresented: Binding(
                get: { renamingNoteId != nil },
                set: { if !$0 { renamingNoteId = nil } }
            )
        ) {
            TextField("New name", text: $newNoteName)
            Button("Cancel", role: .cancel) {
                renamingNoteId = nil
                newNoteName = ""
            }
            Button("Rename") {
                if let oldNoteId = renamingNoteId, !newNoteName.isEmpty {
                    // Generate new note ID based on parent path
                    let parentPath =
                        oldNoteId.contains("/")
                        ? String(oldNoteId.split(separator: "/").dropLast().joined(separator: "/"))
                        : ""
                    let newNoteId =
                        parentPath.isEmpty ? newNoteName : "\(parentPath)/\(newNoteName)"

                    noteManager.renameNote(oldNoteId: oldNoteId, newNoteId: newNoteId) { success in
                        if !success {
                            showingErrorAlert = true
                        }
                    }
                }
                renamingNoteId = nil
                newNoteName = ""
            }
        } message: {
            Text("Enter new name for the note:")
        }
        .alert(
            "Delete Folder",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                folderToDelete = nil
                folderHasContent = false
            }
            Button("Delete", role: .destructive) {
                if let noteId = folderToDelete {
                    deleteItem(noteId: noteId)
                }
                folderToDelete = nil
                folderHasContent = false
            }
        } message: {
            if folderHasContent {
                Text(
                    "This folder contains notes. Deleting it will also delete all notes inside. This action cannot be undone."
                )
            } else {
                Text("Are you sure you want to delete this folder? This action cannot be undone.")
            }
        }
    }

    private func isFolderWithContent(noteId: String) -> Bool {
        // Check if the selected item is a folder with content
        func checkFolder(noteInfo: NoteInfo, targetId: String) -> Bool {
            if noteInfo.id == targetId {
                return noteInfo.type == "folder" && !noteInfo.children.isEmpty
            }
            // Check children recursively
            for child in noteInfo.children {
                if checkFolder(noteInfo: child, targetId: targetId) {
                    return true
                }
            }
            return false
        }

        for noteInfo in noteManager.noteTree {
            if checkFolder(noteInfo: noteInfo, targetId: noteId) {
                return true
            }
        }
        return false
    }

    private func deleteItem(noteId: String) {
        deleteItemWithCompletion(noteId: noteId)
    }

    private func deleteItemWithCompletion(noteId: String, completion: @escaping () -> Void = {}) {
        noteManager.deleteNote(noteId: noteId) { success in
            print("DEBUG: deleteNote completion called with success: \(success)")
            if !success {
                print("DEBUG: deleteNote failed, showing error alert")
                showingErrorAlert = true
            } else {
                print("DEBUG: deleteNote succeeded")
                // Clear selection if this item was selected
                if selectedNoteId == noteId {
                    selectedNoteId = nil
                }
            }
            completion()
        }
    }

    private func deleteItemImmediately(noteId: String) {
        noteManager.deleteNote(noteId: noteId) { success in
            print("DEBUG: deleteNote completion called with success: \(success)")
            if !success {
                print("DEBUG: deleteNote failed, showing error alert")
                showingErrorAlert = true
            } else {
                print("DEBUG: deleteNote succeeded")
                // Clear selection if this item was selected
                if selectedNoteId == noteId {
                    selectedNoteId = nil
                }
            }
        }
    }
}

struct NoteRow: View {
    let noteInfo: NoteInfo
    @Binding var expandedFolders: Set<String>
    @Binding var selectedNoteId: String?
    @Binding var renamingNoteId: String?
    @Binding var newNoteName: String
    @Binding var folderToDelete: String?
    @Binding var showingDeleteConfirmation: Bool
    @Binding var folderHasContent: Bool
    var onDeleteNote: (String) -> Void
    @State private var showingErrorAlert: Bool = false
    @EnvironmentObject private var noteManager: NoteManager

    var body: some View {
        // Debug logging removed - print() returns () which doesn't conform to View

        // Check if this is a folder (has type "folder" or has children)

        // BUG FIX: Handle nil type field for new folders
        // When type is nil and folder is empty, we can't determine if it's a folder yet
        let canDetermineFolderType = noteInfo.type != nil || !noteInfo.children.isEmpty

        if !canDetermineFolderType {
            // This is a newly created folder with nil type - show loading state
            Label {
                Text(noteInfo.title)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            } icon: {
                ProgressView()
                    .scaleEffect(0.5)
                    .foregroundColor(.gray)
            }
            .tag(noteInfo.id)
            .onAppear {
                // Debug logging removed for build
            }

        } else {
            // We have enough information to determine folder type
            let isFolder = noteInfo.type == "folder" || !noteInfo.children.isEmpty

            if !isFolder {
                // This is a note (leaf node)
                Label {
                    Text(noteInfo.title)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "note.text")
                        .foregroundColor(.blue)
                }
                .tag(noteInfo.id)
                .contextMenu {
                    Button("New Child Note") {
                        noteManager.createNewNote(parentId: noteInfo.id)
                    }
                    .disabled(!noteManager.isBackendAvailable)

                    Button("New Child Folder") {
                        noteManager.createFolder(parentId: noteInfo.id) { success in
                            if success {
                                // Expand this folder
                                expandedFolders.insert(noteInfo.id)
                            }
                        }
                    }
                    .disabled(!noteManager.isBackendAvailable)

                    Divider()

                    Button("Rename") {
                        renamingNoteId = noteInfo.id
                        newNoteName = noteInfo.title
                    }
                    .disabled(!noteManager.isBackendAvailable)

                    Divider()

                    Button("Delete", role: .destructive) {
                        print("Delete button clicked for note: \(noteInfo.id)")
                        // Notes don't need confirmation (they have no children)
                        onDeleteNote(noteInfo.id)
                    }
                    .disabled(!noteManager.isBackendAvailable)
                }
                .alert("Error", isPresented: $showingErrorAlert) {
                    Button("OK") {}
                } message: {
                    if let error = noteManager.lastError {
                        Text(error)
                    } else {
                        Text("An error occurred")
                    }
                }
            } else {
                // This is a folder
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedFolders.contains(noteInfo.id) },
                        set: { isExpanded in
                            if isExpanded {
                                expandedFolders.insert(noteInfo.id)
                            } else {
                                expandedFolders.remove(noteInfo.id)
                            }
                        }
                    )
                ) {
                    ForEach(noteInfo.children) { childNoteInfo in
                        NoteRow(
                            noteInfo: childNoteInfo,
                            expandedFolders: $expandedFolders,
                            selectedNoteId: $selectedNoteId,
                            renamingNoteId: $renamingNoteId,
                            newNoteName: $newNoteName,
                            folderToDelete: $folderToDelete,
                            showingDeleteConfirmation: $showingDeleteConfirmation,
                            folderHasContent: $folderHasContent,
                            onDeleteNote: onDeleteNote
                        )
                    }
                } label: {
                    Label {
                        Text(noteInfo.title)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: "folder")
                            .foregroundColor(.yellow)
                    }
                }
                .tag(noteInfo.id)
                .contextMenu {
                    Button("New Child Note") {
                        noteManager.createNewNote(parentId: noteInfo.id)
                    }
                    .disabled(!noteManager.isBackendAvailable)

                    Button("New Child Folder") {
                        noteManager.createFolder(parentId: noteInfo.id) { success in
                            if success {
                                // Expand this folder
                                expandedFolders.insert(noteInfo.id)
                            }
                        }
                    }
                    .disabled(!noteManager.isBackendAvailable)

                    Divider()

                    Button("Rename") {
                        renamingNoteId = noteInfo.id
                        newNoteName = noteInfo.title
                    }
                    .disabled(!noteManager.isBackendAvailable)

                    Divider()

                    Button("Delete", role: .destructive) {
                        print("Delete button clicked for folder: \(noteInfo.id)")
                        // Check if folder has content
                        folderToDelete = noteInfo.id
                        folderHasContent = !noteInfo.children.isEmpty
                        showingDeleteConfirmation = true
                    }
                    .disabled(!noteManager.isBackendAvailable)
                }
                .alert("Error", isPresented: $showingErrorAlert) {
                    Button("OK") {}
                } message: {
                    if let error = noteManager.lastError {
                        Text(error)
                    } else {
                        Text("An error occurred")
                    }
                }
            }
        }
    }
}

struct NoteInfo: Identifiable, Codable {
    let id: String
    let title: String
    let path: String
    let children: [NoteInfo]
    let type: String?

    // For preview purposes
    static func sample() -> [NoteInfo] {
        return [
            NoteInfo(
                id: "welcome",
                title: "Welcome",
                path: "welcome",
                children: [],
                type: "note"
            ),
            NoteInfo(
                id: "projects",
                title: "Projects",
                path: "projects",
                children: [
                    NoteInfo(
                        id: "projects/grimoire",
                        title: "Grimoire",
                        path: "projects/grimoire",
                        children: [
                            NoteInfo(
                                id: "projects/grimoire/backend",
                                title: "Backend",
                                path: "projects/grimoire/backend",
                                children: [],
                                type: "note"
                            ),
                            NoteInfo(
                                id: "projects/grimoire/frontend",
                                title: "Frontend",
                                path: "projects/grimoire/frontend",
                                children: [],
                                type: "note"
                            ),
                        ],
                        type: "folder"
                    )
                ],
                type: "folder"
            ),
            NoteInfo(
                id: "ideas",
                title: "Ideas",
                path: "ideas",
                children: [],
                type: "note"
            ),
        ]
    }
}

// Debug extension to print NoteInfo
extension NoteInfo {
    func debugDescription() -> String {
        return
            "NoteInfo(id: \(id), title: \(title), type: \(type ?? "nil"), children: \(children.count))"
    }
}

#Preview {
    SidebarView(selectedNoteId: .constant("welcome"))
        .environmentObject(NoteManager())
        .frame(width: 250)
}
