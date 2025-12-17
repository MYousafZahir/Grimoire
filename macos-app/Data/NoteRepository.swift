import Foundation

protocol NoteRepository {
    func healthCheck() async -> Bool
    func fetchCurrentProject() async throws -> ProjectInfo
    func fetchProjects() async throws -> [ProjectInfo]
    func createProject(name: String) async throws -> ProjectInfo
    func openProject(path: String) async throws -> ProjectInfo
    func rebuildGlossary() async throws -> GlossaryRebuildResult
    func fetchTree() async throws -> [NoteNode]
    func fetchContent(noteId: String) async throws -> NoteDocument
    func saveContent(noteId: String, content: String, parentId: String?) async throws
    func createFolder(path: String) async throws -> NoteNode
    func rename(noteId: String, newId: String) async throws
    func moveItem(noteId: String, parentId: String?) async throws
    func delete(noteId: String) async throws
}

struct GlossaryRebuildResult: Hashable, Codable {
    let terms: Int
    let spacyNotes: Int
    let fallbackNotes: Int

    enum CodingKeys: String, CodingKey {
        case terms
        case spacyNotes = "spacy_notes"
        case fallbackNotes = "fallback_notes"
    }
}

enum NoteRepositoryError: Error, LocalizedError {
    case badStatus(Int)
    case decoding
    case invalidURL
    case unknown

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "Request failed with status \(code)"
        case .decoding:
            return "Failed to decode response"
        case .invalidURL:
            return "Invalid backend URL"
        case .unknown:
            return "Unknown error"
        }
    }
}

struct HTTPNoteRepository: NoteRepository {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func healthCheck() async -> Bool {
        guard let url = URL(string: "health", relativeTo: baseURL) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    func fetchCurrentProject() async throws -> ProjectInfo {
        guard let url = URL(string: "projects/current", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }
        let data = try await perform(request: URLRequest(url: url))
        let decoded = try JSONDecoder().decode(ProjectResponse.self, from: data)
        return decoded.project.toDomain()
    }

    func fetchProjects() async throws -> [ProjectInfo] {
        guard let url = URL(string: "projects", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }
        let data = try await perform(request: URLRequest(url: url))
        let decoded = try JSONDecoder().decode(ProjectsResponse.self, from: data)
        return decoded.projects.map { $0.toDomain() }
    }

    func createProject(name: String) async throws -> ProjectInfo {
        guard let url = URL(string: "projects/create", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CreateProjectRequest(name: name))
        let data = try await perform(request: request)
        let decoded = try JSONDecoder().decode(ProjectResponse.self, from: data)
        return decoded.project.toDomain()
    }

    func openProject(path: String) async throws -> ProjectInfo {
        guard let url = URL(string: "projects/open", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenProjectRequest(path: path))
        let data = try await perform(request: request)
        let decoded = try JSONDecoder().decode(ProjectResponse.self, from: data)
        return decoded.project.toDomain()
    }

    func rebuildGlossary() async throws -> GlossaryRebuildResult {
        guard let url = URL(string: "admin/rebuild-glossary", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        let data = try await perform(request: request)
        struct Response: Codable {
            let terms: Int?
            let spacyNotes: Int?
            let fallbackNotes: Int?

            enum CodingKeys: String, CodingKey {
                case terms
                case spacyNotes = "spacy_notes"
                case fallbackNotes = "fallback_notes"
            }
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw NoteRepositoryError.decoding
        }
        return GlossaryRebuildResult(
            terms: decoded.terms ?? 0,
            spacyNotes: decoded.spacyNotes ?? 0,
            fallbackNotes: decoded.fallbackNotes ?? 0
        )
    }

    func fetchTree() async throws -> [NoteNode] {
        guard let url = URL(string: "notes", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }

        let data = try await perform(request: URLRequest(url: url))
        let decoded = try JSONDecoder().decode(NotesResponse.self, from: data)
        return buildTree(from: decoded.notes)
    }

    func fetchContent(noteId: String) async throws -> NoteDocument {
        let encodedId = noteId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? noteId
        guard let url = URL(string: "note/\(encodedId)", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }

        let data = try await perform(request: URLRequest(url: url))
        let decoded = try JSONDecoder().decode(NoteContentResponse.self, from: data)

        return NoteDocument(
            id: decoded.noteId,
            title: decoded.title ?? decoded.noteId,
            content: decoded.content,
            kind: .note
        )
    }

    func saveContent(noteId: String, content: String, parentId: String?) async throws {
        guard let url = URL(string: "update-note", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = UpdateNoteRequest(noteId: noteId, content: content, parentId: parentId)
        request.httpBody = try JSONEncoder().encode(body)

        _ = try await perform(request: request)
    }

    func createFolder(path: String) async throws -> NoteNode {
        guard let url = URL(string: "create-folder", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(CreateFolderRequest(folderPath: path))

        let data = try await perform(request: request)

        if let response = try? JSONDecoder().decode(CreateFolderResponse.self, from: data),
            let folder = response.folder
        {
            return NoteNode(
                id: folder.id,
                title: folder.title,
                path: path,
                kind: .folder,
                children: []
            )
        }

        let folderId = path.replacingOccurrences(of: "/", with: "_")
        let title = path.split(separator: "/").last.map(String.init) ?? folderId
        return NoteNode(id: folderId, title: title, path: path, kind: .folder, children: [])
    }

    func rename(noteId: String, newId: String) async throws {
        guard let url = URL(string: "rename-note", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RenameNoteRequest(oldNoteId: noteId, newNoteId: newId))

        _ = try await perform(request: request)
    }

    func moveItem(noteId: String, parentId: String?) async throws {
        guard let url = URL(string: "move-item", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(MoveItemRequest(noteId: noteId, parentId: parentId))

        _ = try await perform(request: request)
    }

    func delete(noteId: String) async throws {
        guard let url = URL(string: "delete-note", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeleteNoteRequest(noteId: noteId))

        _ = try await perform(request: request)
    }
}

// MARK: - Helpers

private extension HTTPNoteRepository {
    struct ProjectResponse: Codable {
        let project: ProjectInfoDTO
    }

    struct ProjectsResponse: Codable {
        let projects: [ProjectInfoDTO]
    }

    struct ProjectInfoDTO: Codable {
        let name: String
        let path: String
        let isActive: Bool?

        enum CodingKeys: String, CodingKey {
            case name
            case path
            case isActive = "is_active"
        }

        func toDomain() -> ProjectInfo {
            ProjectInfo(name: name, path: path, isActive: isActive ?? false)
        }
    }

    struct CreateProjectRequest: Codable {
        let name: String
    }

    struct OpenProjectRequest: Codable {
        let path: String
    }

    struct BackendNoteInfo: Codable {
        let id: String
        let title: String
        let type: String?
        let kind: String?
        let children: [String]
    }

    struct NotesResponse: Codable {
        let notes: [BackendNoteInfo]
    }

    struct NoteContentResponse: Codable {
        let noteId: String
        let content: String
        let title: String?

        enum CodingKeys: String, CodingKey {
            case noteId = "note_id"
            case content
            case title
        }
    }

    struct UpdateNoteRequest: Codable {
        let noteId: String
        let content: String
        let parentId: String?

        enum CodingKeys: String, CodingKey {
            case noteId = "note_id"
            case content
            case parentId = "parent_id"
        }
    }

    struct CreateFolderRequest: Codable {
        let folderPath: String

        enum CodingKeys: String, CodingKey {
            case folderPath = "folder_path"
        }
    }

    struct CreateFolderResponse: Codable {
        let folderId: String?
        let folder: FolderPayload?

        enum CodingKeys: String, CodingKey {
            case folderId = "folder_id"
            case folder
        }
    }

    struct FolderPayload: Codable {
        let id: String
        let title: String
        let type: String?
        let kind: String?
        let children: [String]
    }

    struct RenameNoteRequest: Codable {
        let oldNoteId: String
        let newNoteId: String

        enum CodingKeys: String, CodingKey {
            case oldNoteId = "old_note_id"
            case newNoteId = "new_note_id"
        }
    }

    struct MoveItemRequest: Codable {
        let noteId: String
        let parentId: String?

        enum CodingKeys: String, CodingKey {
            case noteId = "note_id"
            case parentId = "parent_id"
        }
    }

    struct DeleteNoteRequest: Codable {
        let noteId: String

        enum CodingKeys: String, CodingKey {
            case noteId = "note_id"
        }
    }

    func perform(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NoteRepositoryError.unknown
        }
        guard http.statusCode == 200 else {
            throw NoteRepositoryError.badStatus(http.statusCode)
        }
        return data
    }

    func buildTree(from backendNotes: [BackendNoteInfo]) -> [NoteNode] {
        struct BaseNode {
            let id: String
            let title: String
            let kind: NoteKind
        }

        var baseMap: [String: BaseNode] = [:]
        var childrenMap: [String: [String]] = [:]

        for note in backendNotes {
            let rawKind = note.type ?? note.kind ?? (note.children.isEmpty ? "note" : "folder")
            let kind: NoteKind = rawKind == "folder" ? .folder : .note
            baseMap[note.id] = BaseNode(id: note.id, title: note.title, kind: kind)
            childrenMap[note.id] = note.children
        }

        var rootIds = Set(baseMap.keys)
        for childIds in childrenMap.values {
            for childId in childIds {
                rootIds.remove(childId)
            }
        }

        func makeNode(_ id: String, visiting: Set<String>) -> NoteNode? {
            guard let base = baseMap[id] else { return nil }
            if visiting.contains(id) {
                return NoteNode(id: base.id, title: base.title, path: base.id, kind: base.kind, children: [])
            }
            var nextVisiting = visiting
            nextVisiting.insert(id)
            let childNodes = (childrenMap[id] ?? []).compactMap { makeNode($0, visiting: nextVisiting) }
            return NoteNode(
                id: base.id,
                title: base.title,
                path: base.id,
                kind: base.kind,
                children: childNodes
            )
        }

        let roots = rootIds.compactMap { makeNode($0, visiting: []) }
        return roots.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
