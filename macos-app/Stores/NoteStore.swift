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
    @Published var currentContent: String = ""
    @Published var currentNoteKind: NoteKind? = nil
    @Published var saveState: SaveState = .idle
    @Published var isLoadingTree: Bool = false
    @Published var isLoadingNote: Bool = false
    @Published var backendStatus: BackendStatus = .unknown
    @Published var lastError: String? = nil

    private let repository: NoteRepository
    private var lastSavedContent: String = ""
    private var loadTask: Task<Void, Never>?
    private let cancelledCode = URLError.Code.cancelled

    init(repository: NoteRepository = HTTPNoteRepository()) {
        self.repository = repository
    }

    func bootstrap() async {
        await checkBackend()
        await refreshTree()
    }

    func checkBackend() async {
        backendStatus = await repository.healthCheck() ? .online : .offline
    }

    func refreshTree() async {
        isLoadingTree = true
        defer { isLoadingTree = false }

        do {
            tree = try await repository.fetchTree()
            backendStatus = .online
            lastError = nil
        } catch {
            backendStatus = .offline
            lastError = error.localizedDescription
            if tree.isEmpty {
                tree = NoteNode.sampleTree()
            }
        }
    }

    func select(_ noteId: String?) {
        selection = noteId
        loadTask?.cancel()

        guard let noteId else {
            currentContent = ""
            lastSavedContent = ""
            currentNoteKind = nil
            saveState = .idle
            lastError = nil
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
        guard currentContent != lastSavedContent else {
            saveState = .idle
            return
        }

        saveState = .saving
        lastError = nil

        do {
            try await repository.saveContent(
                noteId: noteId,
                content: currentContent,
                parentId: parentId(for: noteId)
            )
            lastSavedContent = currentContent
            saveState = .idle
            lastError = nil
        } catch {
            // Treat any failure during in-flight edits as non-fatal; stay in editing state
            saveState = .editing
            lastError = nil
            #if DEBUG
            print("SaveDraft suppressed error: \(error.localizedDescription)")
            #endif
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
            lastError = error.localizedDescription
            return nil
        }
    }

    func rename(noteId: String, newName: String) async {
        guard !newName.isEmpty else { return }

        do {
            try await repository.rename(noteId: noteId, newId: newName)
            await refreshTree()
            if selection == noteId {
                select(newName)
            }
        } catch {
            lastError = error.localizedDescription
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
}
