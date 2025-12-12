import SwiftUI
import UniformTypeIdentifiers
import AppKit

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
	    @State private var selectedIds: Set<String> = []
	    @State private var selectionAnchorId: String? = nil
		    @State private var showingBatchDeleteConfirmation: Bool = false
		    @State private var batchDeleteIds: [String] = []
		    @State private var isShowingBatchRenameAlert: Bool = false
		    @State private var batchRenameBaseName: String = ""
		    @State private var isShowingKeybindLegend: Bool = false
	    
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
		        applyInteractions(
		            applyAlerts(
		                applyMenus(mainContent)
		            )
		        )
		    }

			    private var mainContent: some View {
			        VStack(spacing: 0) {
			            offlineBanner
			            if noteStore.tree.isEmpty {
			                emptyState
			            } else {
			                treeList
			            }
			            keybindFooter
			        }
			    }

		    @ViewBuilder
		    private var offlineBanner: some View {
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
		    }

		    private var emptyState: some View {
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
		    }

		    private var treeList: some View {
		        List {
		            ForEach(visibleNodes) { visible in
		                NoteRow(
		                    noteInfo: visible.node,
		                    expandedFolders: $expandedFolders,
		                    selectedNoteId: $selectedNoteId,
		                    selectedIds: $selectedIds,
		                    renameTargetId: $renameTargetId,
		                    isShowingRenameAlert: $isShowingRenameAlert,
		                    newNoteName: $newNoteName,
		                    folderToDelete: $folderToDelete,
		                    showingDeleteConfirmation: $showingDeleteConfirmation,
		                    onDeleteNote: deleteItem,
		                    level: visible.level,
		                    onSelect: handleSelection,
		                    onPrepareBatchDelete: prepareBatchDelete,
		                    onShowBatchRename: {
		                        renameTargetId = nil
		                        isShowingRenameAlert = false
		                        batchRenameBaseName = ""
		                        isShowingBatchRenameAlert = true
		                    }
		                )
		            }
		        }
		        .listStyle(SidebarListStyle())
		        .frame(maxWidth: .infinity, maxHeight: .infinity)
		        .onDrop(of: [UTType.text], isTargeted: nil) { providers in
		            loadNoteIds(from: providers) { droppedIds in
		                Task { @MainActor in
		                    for droppedId in droppedIds {
		                        await noteStore.move(noteId: droppedId, toParentId: nil)
		                    }
		                }
		            }
		        }
		    }

			    private var keybindFooter: some View {
			        HStack {
			            Spacer()
			            Button(action: { isShowingKeybindLegend = true }) {
			                Image(systemName: "keyboard")
			                    .foregroundColor(.secondary)
			            }
			            .buttonStyle(.plain)
			            .help("Keybinds")
			            .padding(.horizontal, 8)
			            .padding(.vertical, 6)
			        }
			        .background(Color(NSColor.controlBackgroundColor))
			        .border(Color(NSColor.separatorColor), width: 1)
			    }

		    private func applyMenus<V: View>(_ view: V) -> some View {
		        view
		            .onChange(of: selectedNoteId) { newSelection in
		                guard let id = newSelection else { return }
		                let ancestors = ancestorFolders(for: id, in: noteStore.tree)
		                if !ancestors.isEmpty {
		                    expandedFolders.formUnion(ancestors)
		                }
		            }
		            .contextMenu { rootContextMenu }
		            .toolbar { sidebarToolbar }
		    }

		    @ViewBuilder
		    private var rootContextMenu: some View {
		        Button("New Note") {
		            createNoteWithRename(parentId: nil)
		        }
		        Button("New Folder") {
		            createFolderWithRename(parentId: nil)
		        }
		    }

		    @ToolbarContentBuilder
		    private var sidebarToolbar: some ToolbarContent {
		        ToolbarItem {
		            Menu {
		                Button("New Note") { createNoteWithRename(parentId: nil) }
		                Button("New Folder") { createFolderWithRename(parentId: nil) }
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

		    private func applyAlerts<V: View>(_ view: V) -> some View {
		        view
		            .alert("Error", isPresented: $showingErrorAlert) {
		                Button("OK") {}
		            } message: {
		                if let error = noteStore.lastError {
		                    Text(error)
		                } else {
		                    Text("An error occurred")
		                }
		            }
		            .alert("Rename Item", isPresented: $isShowingRenameAlert) {
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
		            .alert("Delete Item", isPresented: $showingDeleteConfirmation) {
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
		                Text("Deleting will also remove any nested content. This action cannot be undone.")
		            }
		            .alert("Delete Selected Items", isPresented: $showingBatchDeleteConfirmation) {
		                Button("Cancel", role: .cancel) {
		                    batchDeleteIds = []
		                }
		                Button("Delete", role: .destructive) {
		                    performBatchDelete()
		                }
		            } message: {
		                Text("Delete \(batchDeleteIds.count) selected item(s)? This will remove any nested content.")
		            }
		            .alert("Batch Rename", isPresented: $isShowingBatchRenameAlert) {
		                TextField("Base name", text: $batchRenameBaseName)
		                Button("Cancel", role: .cancel) {
		                    isShowingBatchRenameAlert = false
		                    batchRenameBaseName = ""
		                }
		                Button("Rename") {
		                    let base = batchRenameBaseName.trimmingCharacters(in: .whitespacesAndNewlines)
		                    if !base.isEmpty {
		                        performBatchRename(baseName: base)
		                    }
		                    isShowingBatchRenameAlert = false
		                    batchRenameBaseName = ""
		                }
			            } message: {
			                Text("Renames selected items to “Base name 1”, “Base name 2”, …")
			            }
			            .sheet(isPresented: $isShowingKeybindLegend) {
			                KeybindLegendView()
			            }
			    }

		    private func applyInteractions<V: View>(_ view: V) -> some View {
		        view
		            .onDeleteCommand {
		                if selectedIds.isEmpty { return }
		                if selectedIds.count == 1, let only = selectedIds.first {
		                    deleteItem(noteId: only)
		                } else {
		                    prepareBatchDelete()
		                }
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
	        Task { @MainActor in
	            await noteStore.delete(noteId: noteId)
	            backlinksStore.dropResults(for: noteId)

	            let toRemove = selectedIds.filter { id in
	                id == noteId || id.hasPrefix(noteId + "/")
	            }
	            if !toRemove.isEmpty {
	                selectedIds.subtract(toRemove)
	            }

	            if selectedNoteId == noteId || selectedIds.isEmpty {
	                selectedNoteId = selectedIds.first
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
	                selectedIds = [newId]
	                selectionAnchorId = newId
	                renameTargetId = newId
	                newNoteName = noteStore.title(for: newId) ?? ""
	                isShowingRenameAlert = true
	            }
	        }
	    }

	    private func createFolderWithRename(parentId: String?) {
	        Task { @MainActor in
	            if let newId = await noteStore.createFolder(parentId: parentId) {
	                selectedIds = [newId]
	                selectionAnchorId = newId
	                renameTargetId = newId
	                newNoteName = noteStore.title(for: newId) ?? ""
	                isShowingRenameAlert = true
	            }
	        }
	    }

	    private func handleSelection(_ id: String) {
	        let flags = NSApp.currentEvent?.modifierFlags ?? []
	        let isShift = flags.contains(.shift)
	        let isToggle = flags.contains(.command) || flags.contains(.control)

	        let orderedIds = visibleNodes.map(\.id)
	        var nextSelected = selectedIds

	        if isShift {
	            let anchor = selectionAnchorId ?? id
	            if let a = orderedIds.firstIndex(of: anchor),
	               let b = orderedIds.firstIndex(of: id) {
	                let lower = min(a, b)
	                let upper = max(a, b)
	                let rangeIds = Set(orderedIds[lower...upper])
	                if isToggle {
	                    nextSelected.formUnion(rangeIds)
	                } else {
	                    nextSelected = rangeIds
	                }
	            } else {
	                nextSelected = [id]
	            }
	        } else if isToggle {
	            if nextSelected.contains(id) {
	                nextSelected.remove(id)
	            } else {
	                nextSelected.insert(id)
	            }
	            selectionAnchorId = id
	        } else {
	            nextSelected = [id]
	            selectionAnchorId = id
	        }

	        selectedIds = nextSelected
	        if nextSelected.contains(id) {
	            selectedNoteId = id
	        } else {
	            selectedNoteId = nextSelected.first
	        }
	    }

	    private func prepareBatchDelete() {
	        let roots = filteredSelectedRoots(from: selectedIds)
	        guard !roots.isEmpty else { return }
	        batchDeleteIds = roots
	        showingBatchDeleteConfirmation = true
	    }

	    private func performBatchDelete() {
	        let idsToDelete = batchDeleteIds
	        batchDeleteIds = []
	        Task { @MainActor in
	            for id in idsToDelete {
	                await noteStore.delete(noteId: id)
	                backlinksStore.dropResults(for: id)
	            }
	            selectedIds.removeAll()
	            selectedNoteId = nil
	        }
	    }

	    private func performBatchRename(baseName: String) {
	        let ids = Array(selectedIds)
	        let sortedByDepth = ids.sorted {
	            let da = $0.split(separator: "/").count
	            let db = $1.split(separator: "/").count
	            if da != db { return da > db }
	            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
	        }
	        Task { @MainActor in
	            for (index, oldId) in sortedByDepth.enumerated() {
	                let numbered = "\(baseName) \(index + 1)"
	                await noteStore.rename(noteId: oldId, newName: numbered)
	            }
	        }
	    }

	    private func filteredSelectedRoots(from ids: Set<String>) -> [String] {
	        let list = Array(ids)
	        return list.filter { candidate in
	            !list.contains(where: { other in
	                other != candidate && candidate.hasPrefix(other + "/")
	            })
	        }
	    }
	}

	struct NoteRow: View {
		        let noteInfo: NoteNode
	        @Binding var expandedFolders: Set<String>
	        @Binding var selectedNoteId: String?
	        @Binding var selectedIds: Set<String>
	        @Binding var renameTargetId: String?
	        @Binding var isShowingRenameAlert: Bool
	        @Binding var newNoteName: String
	        @Binding var folderToDelete: String?
	        @Binding var showingDeleteConfirmation: Bool
	        var onDeleteNote: (String) -> Void
	        let level: Int
	        @EnvironmentObject private var noteStore: NoteStore
	        let onSelect: (String) -> Void
	        let onPrepareBatchDelete: () -> Void
	        let onShowBatchRename: () -> Void

	        private func createChildNote() {
	            Task { @MainActor in
	                if let newId = await noteStore.createNote(parentId: noteInfo.id) {
	                    onSelect(newId)
	                    renameTargetId = newId
	                    newNoteName = noteStore.title(for: newId) ?? ""
	                    isShowingRenameAlert = true
	                }
            }
        }

	        private func createChildFolder() {
	            Task { @MainActor in
	                if let newId = await noteStore.createFolder(parentId: noteInfo.id) {
	                    onSelect(newId)
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
		                onSelect(noteInfo.id)
		            }
			            .contextMenu {
			                if selectedIds.count > 1, selectedIds.contains(noteInfo.id) {
			                    Button("Delete Selected (\(selectedIds.count))", role: .destructive) {
			                        onPrepareBatchDelete()
			                    }
			                    Button("Batch Rename…") {
			                        onShowBatchRename()
			                    }
			                } else {
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
		            }
		            .onDrag {
		                if !selectedIds.contains(noteInfo.id) {
		                    onSelect(noteInfo.id)
		                }
		                let idsToDrag: [String]
		                if selectedIds.contains(noteInfo.id) && selectedIds.count > 1 {
		                    idsToDrag = Array(selectedIds)
		                } else {
		                    idsToDrag = [noteInfo.id]
		                }
		                let payload: String
		                if idsToDrag.count == 1 {
		                    payload = idsToDrag[0]
		                } else if let data = try? JSONEncoder().encode(idsToDrag),
		                          let string = String(data: data, encoding: .utf8) {
		                    payload = string
		                } else {
		                    payload = idsToDrag.joined(separator: "\n")
		                }
		                return NSItemProvider(object: payload as NSString)
		            }
		            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
		                expandedFolders.insert(noteInfo.id)
		                return loadNoteIds(from: providers) { droppedIds in
		                    Task { @MainActor in
		                        for droppedId in droppedIds where droppedId != noteInfo.id {
		                            await noteStore.move(noteId: droppedId, toParentId: noteInfo.id)
		                        }
		                    }
		                }
		            }
		            .listRowBackground(
		                selectedIds.contains(noteInfo.id)
		                    ? Color.accentColor.opacity(selectedNoteId == noteInfo.id ? 0.15 : 0.08)
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
	                onSelect(noteInfo.id)
	            }
		            .listRowBackground(
		                selectedIds.contains(noteInfo.id)
		                    ? Color.accentColor.opacity(selectedNoteId == noteInfo.id ? 0.15 : 0.08)
		                    : Color.clear
		            )
			            .contextMenu {
			                if selectedIds.count > 1, selectedIds.contains(noteInfo.id) {
			                    Button("Delete Selected (\(selectedIds.count))", role: .destructive) {
			                        onPrepareBatchDelete()
			                    }
			                    Button("Batch Rename…") {
			                        onShowBatchRename()
			                    }
			                } else {
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
	            }
		            .onDrag {
		                if !selectedIds.contains(noteInfo.id) {
		                    onSelect(noteInfo.id)
		                }
		                let idsToDrag: [String]
		                if selectedIds.contains(noteInfo.id) && selectedIds.count > 1 {
		                    idsToDrag = Array(selectedIds)
		                } else {
		                    idsToDrag = [noteInfo.id]
		                }
		                let payload: String
		                if idsToDrag.count == 1 {
		                    payload = idsToDrag[0]
		                } else if let data = try? JSONEncoder().encode(idsToDrag),
		                          let string = String(data: data, encoding: .utf8) {
		                    payload = string
		                } else {
		                    payload = idsToDrag.joined(separator: "\n")
		                }
		                return NSItemProvider(object: payload as NSString)
		            }
		            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
		                let targetParent = noteStore.parentId(for: noteInfo.id)
		                return loadNoteIds(from: providers) { droppedIds in
		                    Task { @MainActor in
		                        for droppedId in droppedIds where droppedId != noteInfo.id {
		                            await noteStore.move(noteId: droppedId, toParentId: targetParent)
		                        }
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

private struct KeybindLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keybinds")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("Editor") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Click — edit chunk at cursor (render mode)")
                    Text("Ctrl+Click+Drag — select text (render mode)")
                    Text("Esc — exit editing, render full note")
                    Text("Enter — insert newline")
                    Text("Shift+Enter — split into new chunk below")
                    Text("Backspace at start — merge with previous chunk")
                    Text("Cmd+Z — undo")
                    Text("Cmd+Shift+Z / Cmd+Y — redo")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Sidebar") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Click — select item")
                    Text("Shift+Click — range select")
                    Text("Cmd/Ctrl+Click — toggle select")
                    Text("Drag & drop — move notes/folders")
                    Text("Delete — delete selected items")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(20)
        .frame(minWidth: 360, minHeight: 320)
    }
}

private func loadNoteIds(from providers: [NSItemProvider], completion: @escaping ([String]) -> Void) -> Bool {
    guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
        return false
    }
    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
        guard let droppedNSString = object as? NSString else { return }
        let text = droppedNSString as String
        if let data = text.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            completion(decoded)
        } else {
            completion([text])
        }
    }
    return true
}
