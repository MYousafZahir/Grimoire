import Foundation

@MainActor
final class NoteStore: ObservableObject {
    enum SaveState: Equatable {
        case idle
        case editing
        case saving
        case failed(String)
    }

    enum BackendStatus {
        case unknown
        case online
        case offline
    }

    @Published var tree: [NoteNode] = []
    @Published var selection: String? = nil
    @Published var loadedNoteId: String? = nil
    @Published var currentContent: String = ""
    @Published var currentNoteKind: NoteKind? = nil
    @Published var saveState: SaveState = .idle
    @Published var isLoadingTree: Bool = false
    @Published var isLoadingNote: Bool = false
    @Published var backendStatus: BackendStatus = .unknown
    @Published var lastError: String? = nil
    @Published var currentProject: ProjectInfo? = nil
    @Published var availableProjects: [ProjectInfo] = []
    @Published var pendingReveal: NoteRevealRequest? = nil

    private let repository: NoteRepository
    private var lastSavedContent: String = ""
    private var loadTask: Task<Void, Never>?
    private var saveRevision: Int = 0
    private let cancelledCode = URLError.Code.cancelled
    private let recentProjectsKey = "grimoire.recentProjectPaths"
    private let maxRecentProjects = 10

    init(repository: NoteRepository = HTTPNoteRepository()) {
        self.repository = repository
    }

    func requestReveal(noteId: String, contextChunkId: String? = nil, excerpt: String? = nil) {
        pendingReveal = NoteRevealRequest(noteId: noteId, contextChunkId: contextChunkId, excerpt: excerpt)
    }

    func clearReveal(requestId: UUID) {
        if pendingReveal?.id == requestId {
            pendingReveal = nil
        }
    }

    func bootstrap() async {
        await checkBackend()
        if backendStatus == .online {
            await refreshCurrentProject()
            await refreshProjects()
        }
    }

    func checkBackend() async {
        // The backend may still be starting when the app launches (e.g. via `./grimoire`).
        // Retry briefly before declaring it offline.
        let deadline = Date().addingTimeInterval(6.0)
        while true {
            if await repository.healthCheck() {
                backendStatus = .online
                return
            }
            if Date() >= deadline { break }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        backendStatus = .offline
    }

    func refreshCurrentProject() async {
        do {
            currentProject = try await repository.fetchCurrentProject()
            lastError = nil
            if let path = currentProject?.path {
                addRecentProject(path: path)
            }
        } catch {
            if isCancellation(error) { return }
            // Non-fatal: keep app usable even if backend doesn't support projects.
            currentProject = nil
        }
    }

    func refreshProjects() async {
        do {
            availableProjects = try await repository.fetchProjects()
        } catch {
            if isCancellation(error) { return }
            availableProjects = []
        }
    }

    func recentProjectPaths() -> [String] {
        guard let list = UserDefaults.standard.array(forKey: recentProjectsKey) as? [String] else {
            return []
        }
        return list
    }

    private func addRecentProject(path: String) {
        let normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        var list = recentProjectPaths()
        list.removeAll { $0 == normalized }
        list.insert(normalized, at: 0)
        if list.count > maxRecentProjects {
            list = Array(list.prefix(maxRecentProjects))
        }
        UserDefaults.standard.set(list, forKey: recentProjectsKey)
    }

    func refreshTree() async {
        isLoadingTree = true
        defer { isLoadingTree = false }

        do {
            tree = try await repository.fetchTree()
            backendStatus = .online
            lastError = nil
        } catch {
            if isCancellation(error) { return }
            backendStatus = .offline
            lastError = error.localizedDescription
            if tree.isEmpty {
                tree = NoteNode.sampleTree()
            }
        }
    }

    func openProject(path: String) async {
        loadTask?.cancel()
        selection = nil
        currentContent = ""
        lastSavedContent = ""
        currentNoteKind = nil
        saveState = .idle

        do {
            currentProject = try await repository.openProject(path: path)
            addRecentProject(path: currentProject?.path ?? path)
            backendStatus = .online
            lastError = nil
            await refreshProjects()
            await refreshTree()
        } catch {
            if isCancellation(error) { return }
            lastError = error.localizedDescription
        }
    }

    func createProject(name: String) async {
        loadTask?.cancel()
        selection = nil
        currentContent = ""
        lastSavedContent = ""
        currentNoteKind = nil
        saveState = .idle

        do {
            currentProject = try await repository.createProject(name: name)
            if let path = currentProject?.path {
                addRecentProject(path: path)
            }
            backendStatus = .online
            lastError = nil
            await refreshProjects()
            await refreshTree()
        } catch {
            if isCancellation(error) { return }
            lastError = error.localizedDescription
        }
    }

    func select(_ noteId: String?) {
        selection = noteId
        loadTask?.cancel()

        guard let noteId else {
            currentContent = ""
            lastSavedContent = ""
            currentNoteKind = nil
            loadedNoteId = nil
            saveState = .idle
            lastError = nil
            pendingReveal = nil
            return
        }

        loadTask = Task { [weak self] in
            await self?.loadContent(for: noteId)
        }
    }

    func loadContent(for noteId: String) async {
        guard !isFolder(id: noteId) else {
            currentContent = ""
            lastSavedContent = ""
            currentNoteKind = .folder
            loadedNoteId = noteId
            saveState = .idle
            return
        }

        isLoadingNote = true
        defer { isLoadingNote = false }

        do {
            let document = try await repository.fetchContent(noteId: noteId)
            currentContent = document.content
            lastSavedContent = document.content
            currentNoteKind = document.kind
            loadedNoteId = noteId
            saveState = .idle
            lastError = nil
        } catch {
            let message = error.localizedDescription.lowercased()
            if isCancellation(error) || message.contains("cancel") || message.contains("canceled") {
                // Ignore cancellations when switching notes quickly
                saveState = .editing
                lastError = nil
                return
            }
            lastError = error.localizedDescription
            currentContent = ""
            lastSavedContent = ""
            currentNoteKind = .note
            loadedNoteId = nil
            saveState = .failed(error.localizedDescription)
        }
    }

    func updateDraft(_ text: String) {
        currentContent = text
        saveState = .editing
        lastError = nil
    }

    func saveDraft() async {
        guard let noteId = selection, currentNoteKind == .note else { return }
        let contentToSave = currentContent
        guard contentToSave != lastSavedContent else {
            saveState = .idle
            return
        }

        saveRevision += 1
        let revision = saveRevision

        saveState = .saving
        lastError = nil

        do {
            try await repository.saveContent(
                noteId: noteId,
                content: contentToSave,
                parentId: parentId(for: noteId)
            )
            if revision == saveRevision {
                lastSavedContent = contentToSave
                saveState = currentContent == contentToSave ? .idle : .editing
                lastError = nil
            }
        } catch {
            if !isCancellation(error) {
                #if DEBUG
                print("SaveDraft suppressed error: \(error.localizedDescription)")
                #endif
            }
            if revision == saveRevision {
                // Treat any failure during in-flight edits as non-fatal; stay in editing state
                saveState = .editing
                lastError = nil
            }
        }
    }

    func createNote(parentId: String?) async -> String? {
        let newId = generateId(prefix: "note")
        let defaultContent = "# New Note\n\nStart writing here..."

        do {
            try await repository.saveContent(
                noteId: newId,
                content: defaultContent,
                parentId: parentId
            )
            await refreshTree()
            select(newId)
            return newId
        } catch {
            if isCancellation(error) { return nil }
            lastError = error.localizedDescription
            return nil
        }
    }

    func createFolder(parentId: String?) async -> String? {
        let newId = generateId(prefix: "folder")
        let folderPath = parentId != nil ? "\(parentId!)/\(newId)" : newId

        do {
            let folder = try await repository.createFolder(path: folderPath)
            await refreshTree()
            select(folder.id)
            return folder.id
        } catch {
            if isCancellation(error) { return nil }
            lastError = error.localizedDescription
            return nil
        }
    }

    func rename(noteId: String, newName: String) async {
        guard !newName.isEmpty else { return }

        do {
            let targetId = computeRenamedId(oldId: noteId, newName: newName)
            try await repository.rename(noteId: noteId, newId: targetId)
            await refreshTree()
            updateSelectionAfterIdChange(oldId: noteId, newId: targetId)
        } catch {
            if isCancellation(error) { return }
            lastError = error.localizedDescription
        }
    }

    func move(noteId: String, toParentId parentId: String?) async {
        if isFolder(id: noteId) {
            let leaf = noteId.split(separator: "/").last.map(String.init) ?? noteId
            let normalizedLeaf = leaf.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let normalizedParent = parentId?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            if let normalizedParent, !normalizedParent.isEmpty {
                if normalizedParent == noteId || isDescendant(normalizedParent, of: noteId) {
                    return
                }
            }

            let targetId: String
            if let normalizedParent, !normalizedParent.isEmpty {
                targetId = "\(normalizedParent)/\(normalizedLeaf)"
            } else {
                // Force a full-path rename to root by including a leading slash.
                targetId = "/\(normalizedLeaf)"
            }

            do {
                try await repository.rename(noteId: noteId, newId: targetId)
                await refreshTree()
                updateSelectionAfterIdChange(
                    oldId: noteId,
                    newId: targetId.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                )
            } catch {
                if isCancellation(error) { return }
                lastError = error.localizedDescription
            }
        } else {
            do {
                try await repository.moveItem(noteId: noteId, parentId: parentId)
                await refreshTree()
            } catch {
                if isCancellation(error) { return }
                lastError = error.localizedDescription
            }
        }
    }

    func delete(noteId: String) async {
        do {
            try await repository.delete(noteId: noteId)
            await refreshTree()
            if selection == noteId {
                select(nil)
            }
        } catch {
            if isCancellation(error) { return }
            lastError = error.localizedDescription
        }
    }

    func title(for id: String) -> String? {
        guard let node = findNode(in: tree, id: id) else { return nil }
        return node.title
    }

    func isFolder(id: String) -> Bool {
        guard let node = findNode(in: tree, id: id) else { return false }
        return node.isFolder
    }

    func parentId(for id: String) -> String? {
        parentId(in: tree, targetId: id, parent: nil)
    }

    func clearErrors() {
        lastError = nil
        saveState = .idle
    }
}

struct NoteRevealRequest: Identifiable, Equatable {
    let id: UUID = UUID()
    let noteId: String
    let contextChunkId: String?
    let excerpt: String?
}

// MARK: - Helpers

private extension NoteStore {
    func findNode(in nodes: [NoteNode], id: String) -> NoteNode? {
        for node in nodes {
            if node.id == id { return node }
            if let match = findNode(in: node.children, id: id) {
                return match
            }
        }
        return nil
    }

    func parentId(in nodes: [NoteNode], targetId: String, parent: String?) -> String? {
        for node in nodes {
            if node.id == targetId {
                return parent
            }
            if let found = parentId(in: node.children, targetId: targetId, parent: node.id) {
                return found
            }
        }
        return nil
    }

    func generateId(prefix: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = Int.random(in: 1000...9999)
        return "\(prefix)_\(timestamp)_\(random)"
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == cancelledCode { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == cancelledCode.rawValue { return true }
        let message = error.localizedDescription.lowercased()
        if message.contains("cancelled") || message.contains("canceled") { return true }
        return false
    }

    func computeRenamedId(oldId: String, newName: String) -> String {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.contains("/") {
            return normalized
        }
        if let parent = parentId(for: oldId) {
            return "\(parent)/\(normalized)"
        }
        return normalized
    }

    func updateSelectionAfterIdChange(oldId: String, newId: String) {
        if selection == oldId {
            select(newId)
            return
        }
        if let currentSelection = selection, currentSelection.hasPrefix(oldId + "/") {
            let suffix = currentSelection.dropFirst(oldId.count)
            let updated = newId + suffix
            select(String(updated))
        }
    }

    func isDescendant(_ candidateId: String, of ancestorId: String) -> Bool {
        if candidateId == ancestorId { return true }
        return candidateId.hasPrefix(ancestorId + "/")
    }
}
