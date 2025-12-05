import Combine
import Foundation

// MARK: - API Request Models

struct BackendNoteInfo: Codable {
    let id: String
    let title: String
    let type: String?
    let children: [String]  // Backend returns array of strings

    // Convert to frontend NoteInfo
    func toNoteInfo() -> NoteInfo {
        return NoteInfo(
            id: id,
            title: title,
            path: id,  // Use id as path since backend doesn't provide path
            children: [],  // Children will be populated separately
            type: type
        )
    }
}

struct CreateFolderRequest: Codable {
    let folder_path: String
}

struct NotesResponse: Codable {
    let notes: [BackendNoteInfo]
}

struct CreateFolderResponse: Codable {
    let success: Bool?
    let status: String?
    let folder_id: String?
    let folder_path: String?
    let folder: BackendNoteInfo?

    var isSuccess: Bool {
        if let success = success {
            return success
        } else if let status = status {
            return status == "success"
        }
        return false
    }

    var folderId: String {
        if let folder_id = folder_id {
            return folder_id
        } else if let folder_path = folder_path {
            return folder_path
        }
        return ""
    }

    var folderInfo: NoteInfo? {
        guard let folder = folder else { return nil }
        return folder.toNoteInfo()
    }
}

struct RenameNoteRequest: Codable {
    let old_note_id: String
    let new_note_id: String
}

struct DeleteNoteRequest: Codable {
    let note_id: String
}

// Simple file logging for debugging
class DebugLogger {
    static let shared = DebugLogger()
    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.grimoire.debuglogger")

    init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        logFileURL = documentsPath.appendingPathComponent("GrimoireDebug.log")
        print("Debug log file: \(logFileURL.path)")
    }

    func log(_ message: String) {
        queue.async {
            let timestamp = DateFormatter.localizedString(
                from: Date(), dateStyle: .medium, timeStyle: .medium)
            let logMessage = "[\(timestamp)] \(message)\n"

            print(logMessage, terminator: "")

            if let data = logMessage.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let fileHandle = try? FileHandle(forWritingTo: self.logFileURL) {
                        fileHandle.seekToEndOfFile()
                        fileHandle.write(data)
                        fileHandle.closeFile()
                    }
                } else {
                    try? data.write(to: self.logFileURL, options: .atomic)
                }
            }
        }
    }
}

class NoteManager: ObservableObject {
    @Published var noteTree: [NoteInfo] = []
    @Published var notes: [String: Note] = [:]
    @Published var isBackendAvailable: Bool = false
    @Published var lastError: String? = nil

    // Include trailing slash so relative paths resolve correctly (e.g. "/update-note")
    private let backendURL = URL(string: "http://127.0.0.1:8000/")!
    private var cancellables = Set<AnyCancellable>()

    struct Note: Codable, Identifiable {
        let id: String
        let title: String
        let content: String
        let path: String
        let parentId: String?
        let createdAt: Date
        let updatedAt: Date

        init(id: String, title: String, content: String = "", path: String, parentId: String? = nil)
        {
            self.id = id
            self.title = title
            self.content = content
            self.path = path
            self.parentId = parentId
            self.createdAt = Date()
            self.updatedAt = Date()
        }
    }

    // MARK: - Public Methods

    func checkBackendConnection(completion: @escaping (Bool) -> Void = { _ in }) {
        // Use the backend URL directly for health check (root endpoint)
        let url = backendURL

        DebugLogger.shared.log("Checking backend connection to: \(url.absoluteString)")
        print("Checking backend connection to: \(url.absoluteString)")

        // Create a custom URLSession with explicit timeout settings
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0  // 5 second timeout for the request
        config.timeoutIntervalForResource = 10.0  // 10 second timeout for the resource
        config.requestCachePolicy = .reloadIgnoringLocalCacheData  // Don't use cache
        let session = URLSession(configuration: config)

        session.dataTaskPublisher(for: url)
            .map { (data, response) -> Bool in
                guard let httpResponse = response as? HTTPURLResponse else {
                    let message = "Backend check: No HTTP response received"
                    DebugLogger.shared.log(message)
                    print(message)
                    return false
                }
                let isAvailable = httpResponse.statusCode == 200
                let message =
                    "Backend check: Status \(httpResponse.statusCode), available: \(isAvailable)"
                DebugLogger.shared.log(message)
                print(message)
                return isAvailable
            }
            .catch { error -> Just<Bool> in
                let errorMessage = "Backend check error: \(error)"
                DebugLogger.shared.log(errorMessage)
                print(errorMessage)

                print("Error type: \(type(of: error))")
                if let urlError = error as? URLError {
                    let urlErrorMessage =
                        "URL Error code: \(urlError.errorCode), description: \(urlError.localizedDescription)"
                    DebugLogger.shared.log(urlErrorMessage)
                    print("URL Error code: \(urlError.errorCode)")
                    print("URL Error description: \(urlError.localizedDescription)")
                }
                return Just(false)
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAvailable in
                let resultMessage =
                    "Backend connection result: \(isAvailable ? "Connected" : "Disconnected")"
                DebugLogger.shared.log(resultMessage)
                print(resultMessage)

                self?.isBackendAvailable = isAvailable
                if !isAvailable {
                    self?.lastError =
                        "Backend server is not responding. Make sure the backend is running at http://127.0.0.1:8000"
                    let errorMessage =
                        "Backend unavailable. Last error: \(self?.lastError ?? "none")"
                    DebugLogger.shared.log(errorMessage)
                    print(errorMessage)

                    // Retry connection after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        DebugLogger.shared.log("Retrying backend connection...")
                        print("Retrying backend connection...")
                        self?.checkBackendConnection(completion: completion)
                    }
                } else {
                    self?.lastError = nil
                    completion(isAvailable)
                }
            }
            .store(in: &cancellables)
    }

    func loadNotes() {
        // First check if backend is available
        checkBackendConnection { [weak self] isAvailable in
            guard let self = self else { return }

            if !isAvailable {
                DebugLogger.shared.log("Backend not available, using sample data")
                print("Backend not available, using sample data")
                self.noteTree = NoteInfo.sample()
                NotificationCenter.default.post(
                    name: NSNotification.Name("NotesLoaded"),
                    object: nil
                )
                // Schedule a retry to load real notes when backend comes online
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                    print("Retrying to load notes from backend...")
                    self.loadNotes()
                }
                return
            }

            guard let url = URL(string: "notes", relativeTo: self.backendURL) else {
                print("Invalid URL for loading notes")
                self.noteTree = NoteInfo.sample()
                NotificationCenter.default.post(
                    name: NSNotification.Name("NotesLoaded"),
                    object: nil
                )
                return
            }

            DebugLogger.shared.log("Loading notes from backend: \(url.absoluteString)")
            DebugLogger.shared.log("Backend available status: \(isAvailable)")
            print("Loading notes from backend: \(url.absoluteString)")
            print("Backend available status: \(isAvailable)")

            URLSession.shared.dataTaskPublisher(for: url)
                .tryMap { (data, response) -> Data in
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    if httpResponse.statusCode != 200 {
                        if let errorData = try? JSONSerialization.jsonObject(with: data)
                            as? [String: Any],
                            let detail = errorData["detail"] as? String
                        {
                            print("Load notes failed: \(detail)")
                            self.lastError = detail
                        }
                        throw URLError(.badServerResponse)
                    }
                    return data
                }
                .decode(type: NotesResponse.self, decoder: JSONDecoder())
                .receive(on: DispatchQueue.main)
                .sink { completion in
                    if case .failure(let error) = completion {
                        let errorMessage = "Failed to load notes: \(error)"
                        DebugLogger.shared.log(errorMessage)
                        print("Failed to load notes: \(error)")

                        // Fallback to sample data for preview/testing
                        self.noteTree = NoteInfo.sample()
                        self.lastError = "Failed to load notes: \(error.localizedDescription)"

                        // Notify that notes were loaded (even if sample data)
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NotesLoaded"),
                            object: nil
                        )

                        // Retry after delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                            DebugLogger.shared.log("Retrying notes load after error...")
                            print("Retrying notes load after error...")
                            self.loadNotes()
                        }
                    }
                } receiveValue: { response in
                    // Convert backend notes to frontend format
                    let backendNotes = response.notes
                    var noteMap: [String: NoteInfo] = [:]

                    // First pass: create all notes without children
                    for backendNote in backendNotes {
                        noteMap[backendNote.id] = backendNote.toNoteInfo()
                    }

                    // Second pass: build hierarchy
                    var rootNotes: [NoteInfo] = []

                    for backendNote in backendNotes {
                        guard var note = noteMap[backendNote.id] else { continue }

                        // Add children if they exist in the map
                        var children: [NoteInfo] = []
                        for childId in backendNote.children {
                            if let childNote = noteMap[childId] {
                                children.append(childNote)
                            }
                        }

                        // Create updated note with children
                        note = NoteInfo(
                            id: note.id,
                            title: note.title,
                            path: note.path,
                            children: children,
                            type: note.type
                        )
                        noteMap[backendNote.id] = note

                        // If this note is not a child of any other note, it's a root note
                        var isChild = false
                        for otherBackendNote in backendNotes {
                            if otherBackendNote.children.contains(backendNote.id) {
                                isChild = true
                                break
                            }
                        }

                        if !isChild {
                            rootNotes.append(note)
                        }
                    }

                    self.noteTree = rootNotes
                    self.lastError = nil
                    let message =
                        "Loaded \(rootNotes.count) notes from backend (converted from \(backendNotes.count) backend notes)"
                    DebugLogger.shared.log(message)
                    print(message)
                    // Notify that notes were loaded
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NotesLoaded"),
                        object: nil
                    )
                }
                .store(in: &self.cancellables)
        }
    }

    func loadNoteContent(noteId: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "note/\(noteId)", relativeTo: backendURL) else {
            print("Invalid URL for loading note content")
            completion("")
            return
        }

        URLSession.shared.dataTaskPublisher(for: url)
            .tryMap { (data, response) -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if httpResponse.statusCode != 200 {
                    if let errorData = try? JSONSerialization.jsonObject(with: data)
                        as? [String: Any],
                        let detail = errorData["detail"] as? String
                    {
                        print("Load note content failed: \(detail)")
                    }
                    throw URLError(.badServerResponse)
                }
                return data
            }
            .decode(type: NoteContentResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { sinkCompletion in
                if case .failure(let error) = sinkCompletion {
                    print("Failed to load note content: \(error)")
                    DispatchQueue.main.async {
                        completion("")  // Return empty string on error
                    }
                }
            } receiveValue: { response in
                completion(response.content)
            }
            .store(in: &cancellables)
    }

    func saveNoteContent(noteId: String, content: String, completion: @escaping (Bool) -> Void) {
        // Check backend connection first
        checkBackendConnection { [weak self] isAvailable in
            guard let self = self else {
                completion(false)
                return
            }

            if !isAvailable {
                print("Backend not available, cannot save note")
                self.lastError = "Backend not available"
                completion(false)
                return
            }

            guard let url = URL(string: "update-note", relativeTo: self.backendURL) else {
                print("Invalid URL for saving note")
                self.lastError = "Invalid URL"
                completion(false)
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let requestBody = UpdateNoteRequest(note_id: noteId, content: content)

            do {
                request.httpBody = try JSONEncoder().encode(requestBody)
            } catch {
                print("Failed to encode request: \(error)")
                self.lastError = "Failed to encode request: \(error.localizedDescription)"
                completion(false)
                return
            }

            URLSession.shared.dataTaskPublisher(for: request)
                .tryMap { (data, response) -> Bool in
                    guard let httpResponse = response as? HTTPURLResponse else {
                        return false
                    }
                    if httpResponse.statusCode == 200 {
                        return true
                    } else {
                        // Try to parse error message
                        if let errorData = try? JSONSerialization.jsonObject(with: data)
                            as? [String: Any],
                            let detail = errorData["detail"] as? String
                        {
                            print("Save failed with error: \(detail)")
                            self.lastError = detail
                        } else {
                            self.lastError =
                                "Save failed with status code: \(httpResponse.statusCode)"
                        }
                        return false
                    }
                }
                .catch { error -> Just<Bool> in
                    print("Save error: \(error)")
                    self.lastError = "Save error: \(error.localizedDescription)"
                    return Just(false)
                }
                .receive(on: DispatchQueue.main)
                .sink { success in
                    completion(success)
                    if success {
                        print("Successfully saved note: \(noteId)")
                        self.lastError = nil
                    } else {
                        print("Failed to save note: \(noteId)")
                    }
                }
                .store(in: &self.cancellables)
        }
    }

    func createNewNote(parentId: String?) {
        // Check backend connection first
        checkBackendConnection { [weak self] isAvailable in
            guard let self = self else { return }

            if !isAvailable {
                print("Backend not available, cannot create note")
                self.lastError = "Backend not available"
                // Still create a local note for UI feedback
                let noteId = self.generateNoteId(parentId: parentId)
                let title = "New Note (Offline)"
                let path = parentId != nil ? "\(parentId!)/\(noteId)" : noteId

                // Add to local tree for immediate feedback
                let newNote = NoteInfo(
                    id: noteId, title: title, path: path, children: [], type: "note")
                var currentTree = self.noteTree
                currentTree.append(newNote)
                self.noteTree = currentTree

                // Select the new note
                NotificationCenter.default.post(
                    name: NSNotification.Name("NoteCreated"),
                    object: nil,
                    userInfo: ["noteId": noteId]
                )
                return
            }

            let noteId = self.generateNoteId(parentId: parentId)
            let title = "New Note"
            let path = parentId != nil ? "\(parentId!)/\(noteId)" : noteId

            _ = Note(id: noteId, title: title, path: path, parentId: parentId)

            // Save empty note to backend
            self.saveNoteContent(noteId: noteId, content: "# \(title)\n\nStart writing here...") {
                success in
                if success {
                    print("Successfully created note: \(noteId)")
                    // Reload notes to get updated tree
                    self.loadNotes()
                    // Select the new note
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // After notes are loaded, select the new note
                        // This is a workaround since we don't have a callback for loadNotes completion
                        // In a real implementation, we'd have better state management
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NoteCreated"),
                            object: nil,
                            userInfo: ["noteId": noteId]
                        )
                    }
                } else {
                    print("Failed to create note: \(noteId)")
                    // Show error to user
                    NotificationCenter.default.post(
                        name: NSNotification.Name("NoteCreationFailed"),
                        object: nil,
                        userInfo: ["noteId": noteId]
                    )
                }
            }
        }
    }

    func deleteNote(noteId: String) {
        // Call the new deleteNote method with completion handler
        deleteNote(noteId: noteId) { success in
            if !success {
                print("Failed to delete note: \(noteId)")
            }
        }
    }

    func getNote(id: String) -> Note? {
        // For now, create a placeholder note
        // In a real implementation, this would fetch from backend
        return Note(id: id, title: id, path: id)
    }

    // MARK: - Private Methods

    private func generateNoteId(parentId: String?) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = Int.random(in: 1000...9999)

        if let parentId = parentId {
            return "\(parentId)/note_\(timestamp)_\(random)"
        } else {
            return "note_\(timestamp)_\(random)"
        }
    }

    private func generateFolderId(parentId: String?) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let random = Int.random(in: 1000...9999)

        if let parentId = parentId {
            return "\(parentId)/folder_\(timestamp)_\(random)"
        } else {
            return "folder_\(timestamp)_\(random)"
        }
    }

    private func buildNoteTree(from noteInfos: [NoteInfo]) -> [NoteInfo] {
        // This would build a proper tree structure from flat list
        // For now, return as-is since backend provides tree structure
        return noteInfos
    }

    // MARK: - New Note Operations

    func createFolder(parentId: String?, completion: @escaping (Bool) -> Void) {
        checkBackendConnection { [weak self] isAvailable in
            guard let self = self else {
                completion(false)
                return
            }

            if !isAvailable {
                self.lastError = "Backend not available"
                completion(false)
                return
            }

            let folderId = self.generateFolderId(parentId: parentId)
            let folderPath = parentId != nil ? "\(parentId!)/\(folderId)" : folderId

            guard let url = URL(string: "create-folder", relativeTo: self.backendURL) else {
                self.lastError = "Invalid URL"
                completion(false)
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let requestBody = CreateFolderRequest(folder_path: folderPath)

            do {
                request.httpBody = try JSONEncoder().encode(requestBody)
            } catch {
                self.lastError = "Failed to encode request: \(error.localizedDescription)"
                completion(false)
                return
            }

            // Create optimistic folder for immediate UI feedback
            let optimisticFolder = NoteInfo(
                id: folderId,
                title: "New Folder",
                path: folderPath,
                children: [],
                type: "folder"
            )

            // Add to note tree immediately
            DispatchQueue.main.async {
                var newTree = self.noteTree
                newTree.append(optimisticFolder)
                self.noteTree = newTree
            }

            URLSession.shared.dataTaskPublisher(for: request)
                .tryMap { (data, response) -> (Bool, CreateFolderResponse?) in
                    guard let httpResponse = response as? HTTPURLResponse else {
                        return (false, nil)
                    }
                    if httpResponse.statusCode == 200 {
                        // Try to parse the response
                        do {
                            let response = try JSONDecoder().decode(
                                CreateFolderResponse.self, from: data)
                            return (response.isSuccess, response)
                        } catch {
                            print("Failed to parse create-folder response: \(error)")
                            return (true, nil)  // Assume success if we can't parse
                        }
                    } else {
                        if let errorData = try? JSONSerialization.jsonObject(with: data)
                            as? [String: Any],
                            let detail = errorData["detail"] as? String
                        {
                            self.lastError = detail
                        } else {
                            self.lastError = "Failed with status code: \(httpResponse.statusCode)"
                        }
                        return (false, nil)
                    }
                }
                .catch { error -> Just<(Bool, CreateFolderResponse?)> in
                    self.lastError = "Folder creation error: \(error.localizedDescription)"
                    return Just((false, nil))
                }
                .receive(on: DispatchQueue.main)
                .sink { (success, response) in
                    if success {
                        if let folderInfo = response?.folderInfo {
                            // Update the optimistic folder with backend data
                            print("Folder created successfully with backend data: \(folderInfo.id)")
                            // The folder is already in the tree optimistically
                            // When loadNotes() is called, it will get the correct type from backend
                        }
                        // Reload notes to show new folder with correct data from backend
                        self.loadNotes()
                    } else {
                        // Remove optimistic folder if creation failed
                        DispatchQueue.main.async {
                            var newTree = self.noteTree
                            newTree.removeAll { $0.id == folderId }
                            self.noteTree = newTree
                        }
                    }
                    completion(success)
                }
                .store(in: &self.cancellables)
        }
    }

    func renameNote(oldNoteId: String, newNoteId: String, completion: @escaping (Bool) -> Void) {
        checkBackendConnection { [weak self] isAvailable in
            guard let self = self else {
                completion(false)
                return
            }

            if !isAvailable {
                self.lastError = "Backend not available"
                completion(false)
                return
            }

            guard let url = URL(string: "rename-note", relativeTo: self.backendURL) else {
                self.lastError = "Invalid URL"
                completion(false)
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let requestBody = RenameNoteRequest(old_note_id: oldNoteId, new_note_id: newNoteId)

            do {
                request.httpBody = try JSONEncoder().encode(requestBody)
            } catch {
                self.lastError = "Failed to encode request: \(error.localizedDescription)"
                completion(false)
                return
            }

            URLSession.shared.dataTaskPublisher(for: request)
                .tryMap { (data, response) -> Bool in
                    guard let httpResponse = response as? HTTPURLResponse else {
                        return false
                    }
                    if httpResponse.statusCode == 200 {
                        return true
                    } else {
                        if let errorData = try? JSONSerialization.jsonObject(with: data)
                            as? [String: Any],
                            let detail = errorData["detail"] as? String
                        {
                            self.lastError = detail
                        } else {
                            self.lastError = "Failed with status code: \(httpResponse.statusCode)"
                        }
                        return false
                    }
                }
                .catch { error -> Just<Bool> in
                    self.lastError = "Rename error: \(error.localizedDescription)"
                    return Just(false)
                }
                .receive(on: DispatchQueue.main)
                .sink { success in
                    if success {
                        // Reload notes to show renamed note
                        self.loadNotes()
                        // Note: UI should update selection separately
                        // The selectedNoteId is managed by the UI (SidebarView)
                    }
                    completion(success)
                }
                .store(in: &self.cancellables)
        }
    }

    func deleteNote(noteId: String, completion: @escaping (Bool) -> Void = { _ in }) {
        DebugLogger.shared.log("deleteNote called for noteId: \(noteId)")
        checkBackendConnection { [weak self] isAvailable in
            guard let self = self else {
                DebugLogger.shared.log("deleteNote: self is nil")
                completion(false)
                return
            }

            if !isAvailable {
                self.lastError = "Backend not available"
                DebugLogger.shared.log("deleteNote: Backend not available")
                completion(false)
                return
            }

            guard let url = URL(string: "delete-note", relativeTo: self.backendURL) else {
                self.lastError = "Invalid URL"
                DebugLogger.shared.log("deleteNote: Invalid URL")
                completion(false)
                return
            }

            DebugLogger.shared.log("deleteNote: Sending request to \(url.absoluteString)")

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let requestBody = DeleteNoteRequest(note_id: noteId)

            do {
                request.httpBody = try JSONEncoder().encode(requestBody)
                DebugLogger.shared.log("deleteNote: Request body encoded successfully")
            } catch {
                self.lastError = "Failed to encode request: \(error.localizedDescription)"
                DebugLogger.shared.log(
                    "deleteNote: Failed to encode request: \(error.localizedDescription)")
                completion(false)
                return
            }

            URLSession.shared.dataTaskPublisher(for: request)
                .tryMap { (data, response) -> Bool in
                    guard let httpResponse = response as? HTTPURLResponse else {
                        DebugLogger.shared.log("deleteNote: No HTTP response received")
                        return false
                    }

                    DebugLogger.shared.log(
                        "deleteNote: Received HTTP response with status code: \(httpResponse.statusCode)"
                    )

                    if httpResponse.statusCode == 200 {
                        DebugLogger.shared.log("deleteNote: Successfully deleted note: \(noteId)")
                        return true
                    } else {
                        if let errorData = try? JSONSerialization.jsonObject(with: data)
                            as? [String: Any],
                            let detail = errorData["detail"] as? String
                        {
                            self.lastError = detail
                            DebugLogger.shared.log("deleteNote: Server error detail: \(detail)")
                        } else {
                            self.lastError = "Failed with status code: \(httpResponse.statusCode)"
                            DebugLogger.shared.log(
                                "deleteNote: Failed with status code: \(httpResponse.statusCode)")
                        }
                        return false
                    }
                }
                .catch { error -> Just<Bool> in
                    self.lastError = "Delete error: \(error.localizedDescription)"
                    DebugLogger.shared.log(
                        "deleteNote: Network error: \(error.localizedDescription)")
                    return Just(false)
                }
                .receive(on: DispatchQueue.main)
                .sink { success in
                    DebugLogger.shared.log(
                        "deleteNote: Completion handler called with success: \(success)")
                    if success {
                        DebugLogger.shared.log(
                            "deleteNote: Reloading notes after successful deletion")
                        // Reload notes to reflect deletion
                        self.loadNotes()
                        // Post notification that note was deleted
                        print("NoteManager: Posting NoteDeleted notification for: \(noteId)")
                        NotificationCenter.default.post(
                            name: NSNotification.Name("NoteDeleted"),
                            object: nil,
                            userInfo: ["noteId": noteId]
                        )
                        // Note: UI should clear selection separately
                        // The selectedNoteId is managed by the UI (SidebarView)
                    }
                    completion(success)
                }
                .store(in: &self.cancellables)
        }
    }
}

// MARK: - API Response Models

struct FileTreeResponse: Codable {
    let notes: [NoteInfo]
}

struct NoteContentResponse: Codable {
    let note_id: String
    let content: String
}

struct UpdateNoteRequest: Codable {
    let note_id: String
    let content: String
}

// MARK: - Preview Support

extension NoteManager {
    static var preview: NoteManager {
        let manager = NoteManager()
        manager.noteTree = NoteInfo.sample()
        return manager
    }
}
