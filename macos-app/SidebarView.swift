import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @EnvironmentObject private var backlinksStore: BacklinksStore
    @Binding var selectedNoteId: String?

	    @State private var expandedFolders: Set<String> = []
	    @State private var showingErrorAlert: Bool = false
	    @State private var isShowingRenameAlert: Bool = false
	    @State private var renameTargetId: String? = nil
	    @State private var newNoteName: String = ""
		    @State private var folderToDelete: String? = nil
		    @State private var showingDeleteConfirmation: Bool = false
	    
	    private struct VisibleNode: Identifiable {
	        let id: String
	        let node: NoteNode
	        let level: Int

	        init(node: NoteNode, level: Int) {
	            self.id = node.id
	            self.node = node
	            self.level = level
	        }
	    }

	    private var visibleNodes: [VisibleNode] {
	        flattenNodes(noteStore.tree, level: 0)
	    }

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
                        createNoteWithRename(parentId: nil)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
	            } else {
	                List {
	                    ForEach(visibleNodes) { visible in
	                        NoteRow(
	                            noteInfo: visible.node,
	                            expandedFolders: $expandedFolders,
	                            selectedNoteId: $selectedNoteId,
	                            renameTargetId: $renameTargetId,
	                            isShowingRenameAlert: $isShowingRenameAlert,
	                            newNoteName: $newNoteName,
	                            folderToDelete: $folderToDelete,
	                            showingDeleteConfirmation: $showingDeleteConfirmation,
	                            onDeleteNote: deleteItem,
	                            level: visible.level
	                        )
	                    }
	                }
	                .listStyle(SidebarListStyle())
	                .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                    loadNoteId(from: providers) { droppedId in
                        Task { @MainActor in
                            await noteStore.move(noteId: droppedId, toParentId: nil)
                        }
                    }
                }
	            }
	        }
	        .onChange(of: selectedNoteId) { newSelection in
	            guard let id = newSelection else { return }
	            let ancestors = ancestorFolders(for: id, in: noteStore.tree)
	            if !ancestors.isEmpty {
	                expandedFolders.formUnion(ancestors)
	            }
	        }
	        .contextMenu {
	            Button("New Note") {
	                createNoteWithRename(parentId: nil)
            }

            Button("New Folder") {
                createFolderWithRename(parentId: nil)
            }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("New Note") {
                        createNoteWithRename(parentId: nil)
                    }
                    Button("New Folder") {
                        createFolderWithRename(parentId: nil)
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
	            "Rename Item",
	            isPresented: $isShowingRenameAlert
	        ) {
	            TextField("New name", text: $newNoteName)
	            Button("Cancel", role: .cancel) {
	                isShowingRenameAlert = false
	                renameTargetId = nil
	                newNoteName = ""
	            }
		            Button("Rename") {
		                if let oldNoteId = renameTargetId {
		                    let nameToRename = newNoteName.trimmingCharacters(in: .whitespacesAndNewlines)
		                    if !nameToRename.isEmpty {
		                        Task { await noteStore.rename(noteId: oldNoteId, newName: nameToRename) }
		                    }
		                }
		                isShowingRenameAlert = false
		                renameTargetId = nil
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
	        .onChange(of: isShowingRenameAlert) { isPresented in
	            if !isPresented {
	                renameTargetId = nil
	                newNoteName = ""
	            }
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

	    private func flattenNodes(_ nodes: [NoteNode], level: Int) -> [VisibleNode] {
	        var result: [VisibleNode] = []
	        for node in nodes {
	            result.append(VisibleNode(node: node, level: level))
	            if node.isFolder, expandedFolders.contains(node.id) {
	                result.append(contentsOf: flattenNodes(node.children, level: level + 1))
	            }
	        }
	        return result
	    }

	    private func ancestorFolders(for targetId: String, in nodes: [NoteNode], path: [String] = []) -> [String] {
	        for node in nodes {
	            if node.id == targetId {
	                return path
	            }
	            if node.isFolder {
	                let nextPath = path + [node.id]
	                let found = ancestorFolders(for: targetId, in: node.children, path: nextPath)
	                if !found.isEmpty {
	                    return found
	                }
	            }
	        }
	        return []
	    }

	    private func createNoteWithRename(parentId: String?) {
	        Task { @MainActor in
	            if let newId = await noteStore.createNote(parentId: parentId) {
	                renameTargetId = newId
	                newNoteName = noteStore.title(for: newId) ?? ""
	                isShowingRenameAlert = true
	            }
	        }
	    }

	    private func createFolderWithRename(parentId: String?) {
	        Task { @MainActor in
	            if let newId = await noteStore.createFolder(parentId: parentId) {
	                renameTargetId = newId
	                newNoteName = noteStore.title(for: newId) ?? ""
	                isShowingRenameAlert = true
	            }
	        }
	    }
	}

	struct NoteRow: View {
		        let noteInfo: NoteNode
	        @Binding var expandedFolders: Set<String>
	        @Binding var selectedNoteId: String?
	        @Binding var renameTargetId: String?
	        @Binding var isShowingRenameAlert: Bool
	        @Binding var newNoteName: String
	        @Binding var folderToDelete: String?
	        @Binding var showingDeleteConfirmation: Bool
        var onDeleteNote: (String) -> Void
        let level: Int
        @EnvironmentObject private var noteStore: NoteStore

        private func createChildNote() {
            Task { @MainActor in
                if let newId = await noteStore.createNote(parentId: noteInfo.id) {
                    renameTargetId = newId
                    newNoteName = noteStore.title(for: newId) ?? ""
                    isShowingRenameAlert = true
                }
            }
        }

        private func createChildFolder() {
            Task { @MainActor in
                if let newId = await noteStore.createFolder(parentId: noteInfo.id) {
                    renameTargetId = newId
                    newNoteName = noteStore.title(for: newId) ?? ""
                    isShowingRenameAlert = true
                }
            }
        }

	    var body: some View {
	        if noteInfo.isFolder {
	            let isExpanded = expandedFolders.contains(noteInfo.id)
	            HStack(spacing: 6) {
	                BranchGuide(level: level)
	                Button {
	                    if isExpanded {
	                        expandedFolders.remove(noteInfo.id)
	                    } else {
	                        expandedFolders.insert(noteInfo.id)
	                    }
	                } label: {
	                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
	                        .font(.caption)
	                        .foregroundColor(.secondary)
	                        .frame(width: 10)
	                }
	                .buttonStyle(.plain)

	                Image(systemName: "folder")
	                    .foregroundColor(.yellow)
	                Text(noteInfo.title)
	                    .lineLimit(1)
	                Spacer()
	            }
	            .contentShape(Rectangle())
	            .onTapGesture {
	                selectedNoteId = noteInfo.id
	            }
		            .contextMenu {
		                Button("New Child Note") {
		                    createChildNote()
		                }

	                Button("New Child Folder") {
	                    createChildFolder()
	                }

		                Divider()

		                Button("Rename") {
		                    renameTargetId = noteInfo.id
		                    newNoteName = noteInfo.title
		                    isShowingRenameAlert = true
		                }

		                Divider()

	                Button("Delete", role: .destructive) {
	                    folderToDelete = noteInfo.id
	                    showingDeleteConfirmation = true
	                }
	            }
	            .onDrag {
	                NSItemProvider(object: noteInfo.id as NSString)
	            }
	            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
	                expandedFolders.insert(noteInfo.id)
	                return loadNoteId(from: providers) { droppedId in
	                    Task { @MainActor in
	                        await noteStore.move(noteId: droppedId, toParentId: noteInfo.id)
	                    }
	                }
	            }
	            .listRowBackground(
	                selectedNoteId == noteInfo.id
	                    ? Color.accentColor.opacity(0.15)
	                    : Color.clear
	            )
		        } else {
		            HStack(spacing: 6) {
		                BranchGuide(level: level)
		                Color.clear.frame(width: 10)
		                Image(systemName: "note.text")
	                    .foregroundColor(.blue)
	                Text(noteInfo.title)
                    .lineLimit(1)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selectedNoteId = noteInfo.id
            }
	            .listRowBackground(
	                selectedNoteId == noteInfo.id
	                    ? Color.accentColor.opacity(0.15)
	                    : Color.clear
	            )
		            .contextMenu {
		                Button("Rename") {
		                    renameTargetId = noteInfo.id
		                    newNoteName = noteInfo.title
		                    isShowingRenameAlert = true
	                }

                Divider()

                Button("Delete", role: .destructive) {
                    onDeleteNote(noteInfo.id)
                }
            }
	            .onDrag {
	                NSItemProvider(object: noteInfo.id as NSString)
	            }
	            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
	                let targetParent = noteStore.parentId(for: noteInfo.id)
	                return loadNoteId(from: providers) { droppedId in
	                    Task { @MainActor in
	                        if droppedId == noteInfo.id { return }
	                        await noteStore.move(noteId: droppedId, toParentId: targetParent)
	                    }
	                }
	            }
	        }
	    }
	}

private struct BranchGuide: View {
    let level: Int
    private let step: CGFloat = 18
    private let chevronSlotWidth: CGFloat = 10
    private let elementSpacing: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            guard level > 0 else { return }
            let width = CGFloat(level) * step
            let parentIconColumn = chevronSlotWidth + elementSpacing
            let x = width - step + parentIconColumn
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            path.move(to: CGPoint(x: x, y: size.height / 2))
            path.addLine(to: CGPoint(x: width, y: size.height / 2))
            context.stroke(path, with: .color(.secondary.opacity(0.25)), lineWidth: 1)
        }
        .frame(width: CGFloat(level) * step, height: 18)
    }
}

private func loadNoteId(from providers: [NSItemProvider], completion: @escaping (String) -> Void) -> Bool {
    guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
        return false
    }
    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
        guard let droppedNSString = object as? NSString else { return }
        completion(droppedNSString as String)
    }
    return true
}
