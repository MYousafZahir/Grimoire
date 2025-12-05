import Combine
import Foundation
import SwiftUI
import os.signpost

class SearchManager: ObservableObject {
    // BUG FIX: Thread-safe cache implementation
    private let cacheQueue = DispatchQueue(
        label: "com.grimoire.search.cache",
        attributes: .concurrent)
    private var _cachedSearchResults: [String: [SearchAPIResult]] = [:]

    @Published private(set) var searchResults: [String: [SearchAPIResult]] = [:]

    @Published var isLoading: Bool = false

    // Trailing slash ensures relative endpoints resolve to the correct base
    @AppStorage("backendURL") private var backendURLString: String = "http://127.0.0.1:8000/"
    private var backendURL: URL { normalizedBackendURL() ?? URL(string: "http://127.0.0.1:8000/")! }
    private var cancellables = Set<AnyCancellable>()
    private var searchTimers: [String: Timer] = [:]

    init() {
        setupNotifications()
        // logDebug("SearchManager initialized")
        print("SearchManager initialized")
    }

    // MARK: - Public Methods

    func debouncedSearch(noteId: String, text: String) {
        // Cancel any existing timer for this note
        searchTimers[noteId]?.invalidate()

        // Don't search empty text or very short text
        guard text.count > 10 else {
            print(
                "Search text too short (\(text.count) chars), clearing results for note: \(noteId)")
            clearResults(for: noteId)
            return
        }

        // Create a new timer
        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            // logDebug("Debounced search triggered for note: \(noteId), text length: \(text.count)")
            print("Debounced search triggered for note: \(noteId), text length: \(text.count)")
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
        // logDebug("Clearing search results for note: \(noteId)")
        print("Clearing search results for note: \(noteId)")
        updateResults([], for: noteId)
    }

    func clearResultsContainingNote(_ deletedNoteId: String) {
        // Start cache operation timing
        var signpostID: OSSignpostID? = nil
        if #available(macOS 10.14, *) {
            // signpostID = SignpostManager.shared.beginCacheOperation("clearResultsContainingNote", key: deletedNoteId)
        }

        // logDebug("Starting cache clearing for deleted note: \(deletedNoteId)")
        print("Starting cache clearing for deleted note: \(deletedNoteId)")

        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else {
                if #available(macOS 10.14, *) {
                    // SignpostManager.shared.endCacheOperation(signpostID!, success: false)
                }
                return
            }

            // logDebug("SearchManager: Clearing cached results containing note: \(deletedNoteId)")
            print("SearchManager: Clearing cached results containing note: \(deletedNoteId)")
            print(
                "SearchManager: Current cached results keys: \(self._cachedSearchResults.keys.sorted())"
            )

            var clearedFromNotes: [String] = []
            var totalRemoved = 0
            var hadResultsForDeletedNote = false
            var updatedResults: [String: [SearchAPIResult]] = [:]

            // Check if we have results for the deleted note itself
            if self._cachedSearchResults[deletedNoteId] != nil {
                hadResultsForDeletedNote = true
            }

            // Filter out backlinks to the deleted note from all cached results
            for (noteId, results) in self._cachedSearchResults {
                let filteredResults = results.filter { $0.noteId != deletedNoteId }
                let removedCount = results.count - filteredResults.count

                if removedCount > 0 {
                    updatedResults[noteId] = filteredResults
                    clearedFromNotes.append("\(noteId): \(removedCount) results")
                    totalRemoved += removedCount
                    print(
                        "SearchManager: Cleared \(removedCount) backlinks to deleted note \(deletedNoteId) from cache for note \(noteId)"
                    )
                } else {
                    // Keep unchanged results
                    updatedResults[noteId] = results
                }
            }

            // Also remove any cached results for the deleted note itself
            updatedResults.removeValue(forKey: deletedNoteId)

            if hadResultsForDeletedNote {
                print(
                    "SearchManager: Also cleared cached results for the deleted note itself: \(deletedNoteId)"
                )
            }

            // Update the thread-safe cache
            self._cachedSearchResults = updatedResults

            // logDebug("SearchManager: Cleared from notes: \(clearedFromNotes)")
            print("SearchManager: Cleared from notes: \(clearedFromNotes)")
            // logDebug("SearchManager: Total backlinks removed: \(totalRemoved)")
            print("SearchManager: Total backlinks removed: \(totalRemoved)")
            print(
                "SearchManager: After clearing, cached results keys: \(self._cachedSearchResults.keys.sorted())"
            )

            // Post notification that cache was cleared
            NotificationCenter.default.post(
                name: NSNotification.Name("SearchCacheCleared"),
                object: nil,
                userInfo: ["deletedNoteId": deletedNoteId, "totalRemoved": totalRemoved]
            )

            // Update @Published property on main thread
            DispatchQueue.main.async {
                self.searchResults = updatedResults
            }

            // End cache operation timing
            if #available(macOS 10.14, *) {
                // SignpostManager.shared.endCacheOperation(signpostID!, success: true)
            }
            // logDebug("Cache clearing completed for note: \(deletedNoteId)")
            print("Cache clearing completed for note: \(deletedNoteId)")
        }
    }

    // MARK: - Private Methods

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NoteDeleted"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let noteId = notification.userInfo?["noteId"] as? String {
                // logDebug("SearchManager received NoteDeleted notification for note: \(noteId)")
                print("SearchManager received NoteDeleted notification for note: \(noteId)")
                self?.clearResultsContainingNote(noteId)
            }
        }
    }

    private func performSearch(noteId: String, text: String) {
        guard !text.isEmpty else {
            // Empty search - just clear results
            clearResults(for: noteId)
            return
        }

        // logDebug("Performing search for note: \(noteId), text length: \(text.count)")
        print("Performing search for note: \(noteId), text length: \(text.count)")

        guard let url = URL(string: "search", relativeTo: backendURL) else {
            // logError("Invalid URL for search")
            print("ERROR: Invalid URL for search")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = ["text": text, "note_id": noteId]

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            // logError("Failed to encode search request: \(error)")
            print("ERROR: Failed to encode search request: \(error)")
            return
        }

        isLoading = true

        URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { (data, response) -> Data in
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                if httpResponse.statusCode != 200 {
                    throw URLError(.badServerResponse)
                }
                return data
            }
            .decode(type: SearchResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isLoading = false
                if case .failure(let error) = completion {
                    // logError("Search failed: \(error)")
                    print("ERROR: Search failed: \(error)")
                }
            } receiveValue: { [weak self] response in
                print(
                    "Search completed for note: \(noteId), found \(response.results.count) results")
                self?.updateResults(response.results, for: noteId)
            }
            .store(in: &cancellables)
    }

    // MARK: - Thread-Safe Cache Methods

    private func normalizedBackendURL() -> URL? {
        var urlString = backendURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        if !urlString.isEmpty, !urlString.hasSuffix("/") {
            urlString += "/"
        }

        return URL(string: urlString)
    }

    private func updateResults(_ results: [SearchAPIResult], for noteId: String) {
        // Update thread-safe cache first
        cacheQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            self._cachedSearchResults[noteId] = results

            // Then update @Published property on main thread
            DispatchQueue.main.async {
                self.searchResults[noteId] = results
            }
        }
    }
}

// MARK: - Data Models

struct SearchAPIResult: Codable {
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

struct SearchResponse: Codable {
    let results: [SearchAPIResult]
}
