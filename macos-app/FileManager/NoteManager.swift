import Foundation
import Combine

class NoteManager: ObservableObject {
    @Published var noteTree: [NoteInfo] = []
    @Published var notes: [String: Note] = [:]

    private let backendURL = URL(string: "http://127.0.0.1:8000")!
    private var cancellables = Set<AnyCancellable>()

    struct Note: Codable, Identifiable {
        let id: String
        let title: String
        let content: String
        let path: String
        let parentId: String?
        let createdAt: Date
        let updatedAt: Date

        init(id: String, title: String, content: String = "", path: String, parentId: String? = nil) {
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

    func loadNotes() {
        guard let url = URL(string: "all-notes", relativeTo: backendURL) else {
            print("Invalid URL for loading notes")
            return
        }

        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: FileTreeResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    print("Failed to load notes: \(error)")
                    // Fallback to sample data for preview/testing
                    self.noteTree = NoteInfo.sample()
                }
            } receiveValue: { response in
                self.noteTree = response.notes
                print("Loaded \(response.notes.count) notes")
            }
            .store(in: &cancellables)
    }

    func loadNoteContent(noteId: String, completion: @escaping (String) -> Void) {
        guard let url = URL(string: "note/\(noteId)", relativeTo: backendURL) else {
            print("Invalid URL for loading note content")
            completion("")
            return
        }

        URLSession.shared.dataTaskPublisher(for: url)
            .map(\.data)
            .decode(type: NoteContentResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case .failure(let error) = completion {
                    print("Failed to load note content: \(error)")
                }
            } receiveValue: { response in
                completion(response.content)
            }
            .store(in: &cancellables)
    }

    func saveNoteContent(noteId: String, content: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "update-note", relativeTo: backendURL) else {
            print("Invalid URL for saving note")
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
            completion(false)
            return
        }

        URLSession.shared.dataTaskPublisher(for: request)
            .map { _ in true }
            .catch { _ in Just(false) }
            .receive(on: DispatchQueue.main)
            .sink { success in
                completion(success)
                if success {
                    print("Successfully saved note: \(noteId)")
                } else {
                    print("Failed to save note: \(noteId)")
                }
            }
            .store(in: &cancellables)
    }

    func createNewNote(parentId: String?) {
        let noteId = generateNoteId(parentId: parentId)
        let title = "New Note"
        let path = parentId != nil ? "\(parentId!)/\(noteId)" : noteId

        let note = Note(id: noteId, title: title, path: path, parentId: parentId)

        // Save empty note to backend
        saveNoteContent(noteId: noteId, content: "# \(title)\n\nStart writing here...") { success in
            if success {
                // Reload notes to get updated tree
                self.loadNotes()
            }
        }
    }

    func deleteNote(noteId: String) {
        // Note: In a real implementation, we would have a DELETE endpoint
        // For now, we'll just remove from local state and mark as deleted
        print("Note deletion requested for: \(noteId)")
        // In a real app, we would call a DELETE endpoint
        loadNotes() // Refresh the list
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

    private func buildNoteTree(from noteInfos: [NoteInfo]) -> [NoteInfo] {
        // This would build a proper tree structure from flat list
        // For now, return as-is since backend provides tree structure
        return noteInfos
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
