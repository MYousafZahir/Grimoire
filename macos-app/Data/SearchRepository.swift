import Foundation

protocol SearchRepository {
    func search(noteId: String, text: String) async throws -> [Backlink]
}

struct HTTPSearchRepository: SearchRepository {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func search(noteId: String, text: String) async throws -> [Backlink] {
        guard let url = URL(string: "search", relativeTo: baseURL) else {
            throw NoteRepositoryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SearchRequest(noteId: noteId, text: text))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NoteRepositoryError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.results.map {
            Backlink(
                id: "\($0.noteId)_\($0.chunkId)",
                noteId: $0.noteId,
                noteTitle: $0.noteId,
                chunkId: $0.chunkId,
                excerpt: $0.text,
                score: Double($0.score)
            )
        }
    }
}

// MARK: - DTOs

private struct SearchRequest: Codable {
    let noteId: String
    let text: String

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case text
    }
}

private struct SearchResponse: Codable {
    let results: [SearchResult]
}

private struct SearchResult: Codable {
    let noteId: String
    let chunkId: String
    let text: String
    let score: Float

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case chunkId = "chunk_id"
        case text
        case score
    }
}
