import Foundation

struct GlossaryEntrySummary: Identifiable, Hashable, Codable {
    let conceptId: String
    let displayName: String
    let kind: String
    let chunkCount: Int
    let definitionExcerpt: String
    let sourceNoteId: String?
    let lastUpdated: Double

    var id: String { conceptId }

    enum CodingKeys: String, CodingKey {
        case conceptId = "concept_id"
        case displayName = "display_name"
        case kind
        case chunkCount = "chunk_count"
        case definitionExcerpt = "definition_excerpt"
        case sourceNoteId = "source_note_id"
        case lastUpdated = "last_updated"
    }
}

struct GlossaryEntryDetail: Hashable, Codable {
    struct Supporting: Hashable, Codable, Identifiable {
        let chunkId: String
        let noteId: String
        let excerpt: String

        var id: String { chunkId }

        enum CodingKeys: String, CodingKey {
            case chunkId = "chunk_id"
            case noteId = "note_id"
            case excerpt
        }
    }

    let conceptId: String
    let displayName: String
    let kind: String
    let chunkCount: Int
    let surfaceForms: [String]
    let definitionExcerpt: String
    let definitionChunkId: String?
    let sourceNoteId: String?
    let supporting: [Supporting]

    enum CodingKeys: String, CodingKey {
        case conceptId = "concept_id"
        case displayName = "display_name"
        case kind
        case chunkCount = "chunk_count"
        case surfaceForms = "surface_forms"
        case definitionExcerpt = "definition_excerpt"
        case definitionChunkId = "definition_chunk_id"
        case sourceNoteId = "source_note_id"
        case supporting
    }
}

protocol GlossaryRepository {
    func listEntries() async throws -> [GlossaryEntrySummary]
    func entryDetails(conceptId: String) async throws -> GlossaryEntryDetail
}

enum GlossaryRepositoryError: Error, LocalizedError {
    case badStatus(Int)
    case decoding
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            return "Request failed with status \(code)"
        case .decoding:
            return "Failed to decode response"
        case .invalidURL:
            return "Invalid backend URL"
        }
    }
}

struct HTTPGlossaryRepository: GlossaryRepository {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func listEntries() async throws -> [GlossaryEntrySummary] {
        guard let url = URL(string: "glossary", relativeTo: baseURL) else {
            throw GlossaryRepositoryError.invalidURL
        }
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else { throw GlossaryRepositoryError.badStatus(-1) }
        guard http.statusCode == 200 else { throw GlossaryRepositoryError.badStatus(http.statusCode) }

        struct Response: Codable { let terms: [GlossaryEntrySummary] }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw GlossaryRepositoryError.decoding
        }
        return decoded.terms
    }

    func entryDetails(conceptId: String) async throws -> GlossaryEntryDetail {
        let encoded = conceptId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? conceptId
        guard let url = URL(string: "glossary/\(encoded)", relativeTo: baseURL) else {
            throw GlossaryRepositoryError.invalidURL
        }
        let (data, response) = try await session.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse else { throw GlossaryRepositoryError.badStatus(-1) }
        guard http.statusCode == 200 else { throw GlossaryRepositoryError.badStatus(http.statusCode) }
        guard let decoded = try? JSONDecoder().decode(GlossaryEntryDetail.self, from: data) else {
            throw GlossaryRepositoryError.decoding
        }
        return decoded
    }
}
