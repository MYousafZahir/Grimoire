import Combine
import Foundation

class SearchManager: ObservableObject {
    @Published var searchResults: [String: [SearchResult]] = [:]
    @Published var isLoading: Bool = false

    private let backendURL = URL(string: "http://127.0.0.1:8000")!
    private var cancellables = Set<AnyCancellable>()
    private var searchTimers: [String: Timer] = [:]

    // MARK: - Public Methods

    func debouncedSearch(noteId: String, text: String) {
        // Cancel any existing timer for this note
        searchTimers[noteId]?.invalidate()

        // Don't search empty text or very short text
        guard text.count > 10 else {
            clearResults(for: noteId)
            return
        }

        // Create a new timer
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            self?.performSearch(noteId: noteId, text: text)
        }

        searchTimers[noteId] = timer
    }

    func getBacklinksForNote(noteId: String) {
        // Get current note content from NoteManager or local storage
        // For now, we'll trigger a search with empty text to get existing backlinks
        performSearch(noteId: noteId, text: "")
    }

    func clearResults(for noteId: String) {
        DispatchQueue.main.async {
            self.searchResults[noteId] = []
        }
    }

    // MARK: - Private Methods

    private func performSearch(noteId: String, text: String) {
        guard let url = URL(string: "search", relativeTo: backendURL) else {
            print("Invalid URL for search")
            return
        }

        isLoading = true

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = SearchRequest(text: text, note_id: noteId)

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            print("Failed to encode search request: \(error)")
            isLoading = false
            return
        }

        URLSession.shared.dataTaskPublisher(for: request)
            .map(\.data)
            .decode(type: SearchResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false

                if case .failure(let error) = completion {
                    print("Search failed: \(error)")
                    // Fallback to sample data for preview/testing
                    if text.count > 10 {
                        self?.searchResults[noteId] = SearchResult.sample()
                    } else {
                        self?.searchResults[noteId] = []
                    }
                }
            } receiveValue: { [weak self] response in
                // Convert API results to SearchResult objects
                let results = response.results.map { apiResult in
                    SearchResult(
                        noteId: apiResult.note_id,
                        noteTitle: self?.extractTitle(from: apiResult.note_id) ?? apiResult.note_id,
                        chunkId: apiResult.chunk_id,
                        excerpt: apiResult.excerpt,
                        score: apiResult.score
                    )
                }

                self?.searchResults[noteId] = results
                print("Found \(results.count) backlinks for note: \(noteId)")
            }
            .store(in: &cancellables)
    }

    private func extractTitle(from noteId: String) -> String {
        // Extract a readable title from the note ID
        // e.g., "projects/grimoire/backend" -> "Backend"
        let components = noteId.split(separator: "/")
        if let lastComponent = components.last {
            // Convert snake_case or kebab-case to Title Case
            let title = String(lastComponent)
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized

            return title
        }
        return noteId
    }

    deinit {
        // Clean up timers
        searchTimers.values.forEach { $0.invalidate() }
        searchTimers.removeAll()
    }
}

// MARK: - API Request/Response Models

struct SearchRequest: Codable {
    let text: String
    let note_id: String
}

struct SearchResponse: Codable {
    let results: [APIResult]
}

struct APIResult: Codable {
    let note_id: String
    let chunk_id: String
    let excerpt: String
    let score: Double
}

// MARK: - Preview Support

extension SearchManager {
    static var preview: SearchManager {
        let manager = SearchManager()
        manager.searchResults["welcome"] = SearchResult.sample()
        return manager
    }
}
