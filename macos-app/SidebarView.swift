import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @EnvironmentObject private var backlinksStore: BacklinksStore
    @Binding var selectedNoteId: String?

    @State private var expandedFolders: Set<String> = []
    @State private var showingErrorAlert: Bool = false
    @State private var renamingNoteId: String? = nil
    @State private var newNoteName: String = ""
    @State private var folderToDelete: String? = nil
    @State private var showingDeleteConfirmation: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if noteStore.backendStatus != .online {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("Offline mode")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Spacer()
                    Button("Retry") {
                        Task {
                            await noteStore.bootstrap()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.1))
                .border(Color.orange.opacity(0.3), width: 1)
            }

            if noteStore.tree.isEmpty {
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
                        Task { await noteStore.createNote(parentId: nil) }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $selectedNoteId) {
                    ForEach(noteStore.tree, id: \.id) { noteInfo in
                        NoteRow(
                            noteInfo: noteInfo,
                            expandedFolders: $expandedFolders,
                            selectedNoteId: $selectedNoteId,
                            renamingNoteId: $renamingNoteId,
                            newNoteName: $newNoteName,
                            folderToDelete: $folderToDelete,
                            showingDeleteConfirmation: $showingDeleteConfirmation,
                            onDeleteNote: deleteItem
                        )
                    }
                }
                .listStyle(SidebarListStyle())
            }
        }
        .contextMenu {
            Button("New Note") {
                Task { await noteStore.createNote(parentId: nil) }
            }

            Button("New Folder") {
                Task { await noteStore.createFolder(parentId: nil) }
            }

            Button("New Child Note") {
                if let selectedId = selectedNoteId {
                    Task { await noteStore.createNote(parentId: selectedId) }
                }
            }
            .disabled(selectedNoteId == nil)

            Button("New Child Folder") {
                if let selectedId = selectedNoteId {
                    Task { await noteStore.createFolder(parentId: selectedId) }
                }
            }
            .disabled(selectedNoteId == nil)

            Divider()

            Button("Rename") {
                if let selectedId = selectedNoteId,
                    let title = noteStore.title(for: selectedId)
                {
                    renamingNoteId = selectedId
                    newNoteName = title
                }
            }
            .disabled(selectedNoteId == nil)

            Divider()

            Button("Delete", role: .destructive) {
                if let selectedId = selectedNoteId {
                    confirmDeletion(for: selectedId)
                }
            }
            .disabled(selectedNoteId == nil)
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("New Note") {
                        Task { await noteStore.createNote(parentId: nil) }
                    }
                    Button("New Folder") {
                        Task { await noteStore.createFolder(parentId: nil) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Create New")
            }

            ToolbarItem {
                Button(action: {
                    Task { await noteStore.refreshTree() }
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
        .alert("Error", isPresented: $showingErrorAlert) {
            Button("OK") {}
        } message: {
            if let error = noteStore.lastError {
                Text(error)
            } else {
                Text("An error occurred")
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
                    Task { await noteStore.rename(noteId: oldNoteId, newName: newNoteName) }
                }
                renamingNoteId = nil
                newNoteName = ""
            }
        } message: {
            Text("Enter new name for the item:")
        }
        .alert(
            "Delete Item",
            isPresented: $showingDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {
                folderToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let noteId = folderToDelete {
                    deleteItem(noteId: noteId)
                }
                folderToDelete = nil
            }
        } message: {
            Text(
                "Deleting will also remove any nested content. This action cannot be undone."
            )
        }
        .onChange(of: noteStore.lastError) { newValue in
            showingErrorAlert = newValue != nil
        }
    }

    private func confirmDeletion(for noteId: String) {
        if isFolderWithContent(noteId: noteId) {
            folderToDelete = noteId
            showingDeleteConfirmation = true
        } else {
            deleteItem(noteId: noteId)
        }
    }

    private func isFolderWithContent(noteId: String) -> Bool {
        guard let node = findNode(in: noteStore.tree, id: noteId) else { return false }
        return node.isFolder && !node.children.isEmpty
    }

    private func findNode(in nodes: [NoteNode], id: String) -> NoteNode? {
        for node in nodes {
            if node.id == id { return node }
            if let match = findNode(in: node.children, id: id) {
                return match
            }
        }
        return nil
    }

    private func deleteItem(noteId: String) {
        Task {
            await noteStore.delete(noteId: noteId)
            backlinksStore.dropResults(for: noteId)
            if selectedNoteId == noteId {
                selectedNoteId = nil
            }
        }
    }
}

struct NoteRow: View {
    let noteInfo: NoteNode
    @Binding var expandedFolders: Set<String>
    @Binding var selectedNoteId: String?
    @Binding var renamingNoteId: String?
    @Binding var newNoteName: String
    @Binding var folderToDelete: String?
    @Binding var showingDeleteConfirmation: Bool
    var onDeleteNote: (String) -> Void
    @EnvironmentObject private var noteStore: NoteStore

    var body: some View {
        if noteInfo.isFolder {
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
                ForEach(noteInfo.children, id: \.id) { childNoteInfo in
                    NoteRow(
                        noteInfo: childNoteInfo,
                        expandedFolders: $expandedFolders,
                        selectedNoteId: $selectedNoteId,
                        renamingNoteId: $renamingNoteId,
                        newNoteName: $newNoteName,
                        folderToDelete: $folderToDelete,
                        showingDeleteConfirmation: $showingDeleteConfirmation,
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
                    Task { await noteStore.createNote(parentId: noteInfo.id) }
                }

                Button("New Child Folder") {
                    Task { await noteStore.createFolder(parentId: noteInfo.id) }
                }

                Divider()

                Button("Rename") {
                    renamingNoteId = noteInfo.id
                    newNoteName = noteInfo.title
                }

                Divider()

                Button("Delete", role: .destructive) {
                    folderToDelete = noteInfo.id
                    showingDeleteConfirmation = true
                }
            }
        } else {
            Label {
                Text(noteInfo.title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "note.text")
                    .foregroundColor(.blue)
            }
            .tag(noteInfo.id)
            .contextMenu {
                Button("Rename") {
                    renamingNoteId = noteInfo.id
                    newNoteName = noteInfo.title
                }

                Divider()

                Button("Delete", role: .destructive) {
                    onDeleteNote(noteInfo.id)
                }
            }
        }
    }
}
