import Foundation

protocol SearchRepository {
    func context(noteId: String, text: String, cursorOffset: Int, limit: Int) async throws -> [Backlink]
    func warmup(forceRebuild: Bool) async throws
}

enum SearchRepositoryError: Error, LocalizedError {
    case badStatus(Int, String?)
    case decoding
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .badStatus(let code, let detail):
            if let detail, !detail.isEmpty {
                return "Request failed with status \(code): \(detail)"
            }
            return "Request failed with status \(code)"
        case .decoding:
            return "Failed to decode response"
        case .invalidURL:
            return "Invalid backend URL"
        }
    }
}

struct HTTPSearchRepository: SearchRepository {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func context(noteId: String, text: String, cursorOffset: Int, limit: Int) async throws -> [Backlink] {
        guard let url = URL(string: "context", relativeTo: baseURL) else {
            throw SearchRepositoryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(
            ContextRequest(noteId: noteId, text: text, cursorOffset: cursorOffset, limit: limit)
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SearchRepositoryError.badStatus(-1, nil)
        }
        guard http.statusCode == 200 else {
            let detail = (try? JSONDecoder().decode(BackendErrorResponse.self, from: data).detail)
                ?? String(data: data, encoding: .utf8)
            throw SearchRepositoryError.badStatus(http.statusCode, detail)
        }

        let decoded: ContextResponse
        do {
            decoded = try JSONDecoder().decode(ContextResponse.self, from: data)
        } catch {
            throw SearchRepositoryError.decoding
        }
        return decoded.results.map {
            Backlink(
                id: "\($0.noteId)_\($0.chunkId)",
                noteId: $0.noteId,
                noteTitle: $0.noteId,
                chunkId: $0.chunkId,
                excerpt: $0.text,
                score: Double($0.score),
                concept: $0.concept
            )
        }
    }

    func warmup(forceRebuild: Bool) async throws {
        guard let url = URL(string: "admin/warmup", relativeTo: baseURL) else {
            throw SearchRepositoryError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Model download + indexing can take a while on first run.
        request.timeoutInterval = 60 * 15
        request.httpBody = try JSONEncoder().encode(WarmupRequest(forceRebuild: forceRebuild))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SearchRepositoryError.badStatus(-1, nil)
        }
        guard http.statusCode == 200 else {
            let detail = (try? JSONDecoder().decode(BackendErrorResponse.self, from: data).detail)
                ?? String(data: data, encoding: .utf8)
            throw SearchRepositoryError.badStatus(http.statusCode, detail)
        }

        _ = try? JSONDecoder().decode(WarmupResponse.self, from: data)
    }
}

// MARK: - DTOs

private struct ContextRequest: Codable {
    let noteId: String
    let text: String
    let cursorOffset: Int
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case text
        case cursorOffset = "cursor_offset"
        case limit
    }
}

private struct ContextResponse: Codable {
    let results: [ContextResult]
}

private struct BackendErrorResponse: Codable {
    let detail: String
}

private struct WarmupResponse: Codable {
    let success: Bool
    let embedderModel: String
    let rerankerEnabled: Bool
    let rerankerModel: String?
    let contextIndexChunks: Int

    enum CodingKeys: String, CodingKey {
        case success
        case embedderModel = "embedder_model"
        case rerankerEnabled = "reranker_enabled"
        case rerankerModel = "reranker_model"
        case contextIndexChunks = "context_index_chunks"
    }
}

private struct WarmupRequest: Codable {
    let forceRebuild: Bool

    enum CodingKeys: String, CodingKey {
        case forceRebuild = "force_rebuild"
    }
}

private struct ContextResult: Codable {
    let noteId: String
    let chunkId: String
    let text: String
    let score: Float
    let concept: String?

    enum CodingKeys: String, CodingKey {
        case noteId = "note_id"
        case chunkId = "chunk_id"
        case text
        case score
        case concept
    }
}
