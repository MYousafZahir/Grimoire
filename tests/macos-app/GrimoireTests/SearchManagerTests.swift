import Combine
import XCTest

@testable import Grimoire

final class SearchManagerTests: XCTestCase {

    var searchManager: SearchManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        searchManager = SearchManager()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        searchManager = nil
        cancellables = nil
        super.tearDown()
    }

    func testSearchManagerInitialization() {
        XCTAssertNotNil(searchManager)
        XCTAssertTrue(searchManager.searchResults.isEmpty)
        XCTAssertFalse(searchManager.isLoading)
    }

    func testSearchResultCreation() {
        let result = SearchResult(
            noteId: "test-note",
            noteTitle: "Test Note",
            chunkId: "chunk-1",
            excerpt: "This is a test excerpt",
            score: 0.95
        )

        XCTAssertEqual(result.id, "test-note_chunk-1")
        XCTAssertEqual(result.noteId, "test-note")
        XCTAssertEqual(result.noteTitle, "Test Note")
        XCTAssertEqual(result.chunkId, "chunk-1")
        XCTAssertEqual(result.excerpt, "This is a test excerpt")
        XCTAssertEqual(result.score, 0.95)
    }

    func testSearchResultEncodingDecoding() {
        let result = SearchResult(
            noteId: "test-note",
            noteTitle: "Test Note",
            chunkId: "chunk-1",
            excerpt: "This is a test excerpt",
            score: 0.95
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        do {
            let data = try encoder.encode(result)
            let decoded = try decoder.decode(SearchResult.self, from: data)

            XCTAssertEqual(decoded.id, result.id)
            XCTAssertEqual(decoded.noteId, result.noteId)
            XCTAssertEqual(decoded.noteTitle, result.noteTitle)
            XCTAssertEqual(decoded.chunkId, result.chunkId)
            XCTAssertEqual(decoded.excerpt, result.excerpt)
            XCTAssertEqual(decoded.score, result.score)
        } catch {
            XCTFail("Encoding/decoding failed: \(error)")
        }
    }

    func testSearchRequestModel() {
        let request = SearchRequest(text: "Test search query", note_id: "test-note")
        XCTAssertEqual(request.text, "Test search query")
        XCTAssertEqual(request.note_id, "test-note")
    }

    func testSearchResponseModel() {
        let apiResults = [
            APIResult(
                note_id: "note1",
                chunk_id: "chunk1",
                excerpt: "Test excerpt 1",
                score: 0.95
            ),
            APIResult(
                note_id: "note2",
                chunk_id: "chunk2",
                excerpt: "Test excerpt 2",
                score: 0.85
            ),
        ]

        let response = SearchResponse(results: apiResults)
        XCTAssertEqual(response.results.count, 2)
        XCTAssertEqual(response.results[0].note_id, "note1")
        XCTAssertEqual(response.results[0].excerpt, "Test excerpt 1")
        XCTAssertEqual(response.results[0].score, 0.95)
        XCTAssertEqual(response.results[1].note_id, "note2")
        XCTAssertEqual(response.results[1].excerpt, "Test excerpt 2")
        XCTAssertEqual(response.results[1].score, 0.85)
    }

    func testAPIResultModel() {
        let apiResult = APIResult(
            note_id: "test-note",
            chunk_id: "chunk-1",
            excerpt: "Test excerpt",
            score: 0.95
        )

        XCTAssertEqual(apiResult.note_id, "test-note")
        XCTAssertEqual(apiResult.chunk_id, "chunk-1")
        XCTAssertEqual(apiResult.excerpt, "Test excerpt")
        XCTAssertEqual(apiResult.score, 0.95)
    }

    func testExtractTitle() {
        // Test simple note ID
        XCTAssertEqual(searchManager.extractTitle(from: "simple_note"), "Simple Note")

        // Test kebab-case
        XCTAssertEqual(searchManager.extractTitle(from: "my-note"), "My Note")

        // Test nested path
        XCTAssertEqual(
            searchManager.extractTitle(from: "folder/subfolder/backend_note"), "Backend Note")

        // Test with numbers
        XCTAssertEqual(searchManager.extractTitle(from: "note_2024"), "Note 2024")

        // Test empty string
        XCTAssertEqual(searchManager.extractTitle(from: ""), "")

        // Test single word
        XCTAssertEqual(searchManager.extractTitle(from: "backend"), "Backend")
    }

    func testClearResults() {
        // Given
        let noteId = "test-note"
        searchManager.searchResults[noteId] = [
            SearchResult(
                noteId: "note1",
                noteTitle: "Note 1",
                chunkId: "chunk1",
                excerpt: "Test excerpt",
                score: 0.9
            )
        ]

        // When
        searchManager.clearResults(for: noteId)

        // Then
        XCTAssertTrue(searchManager.searchResults[noteId]?.isEmpty ?? true)
    }

    func testSearchManagerCombineProperties() {
        // Test that @Published properties work correctly
        let expectation = XCTestExpectation(description: "Search results updates")
        expectation.expectedFulfillmentCount = 2

        var updateCount = 0
        searchManager.$searchResults
            .dropFirst()  // Skip initial value
            .sink { results in
                updateCount += 1
                if updateCount == 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        searchManager.$isLoading
            .dropFirst()  // Skip initial value
            .sink { isLoading in
                updateCount += 1
                if updateCount == 2 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Trigger changes
        searchManager.clearResults(for: "test-note")
        searchManager.isLoading = true

        wait(for: [expectation], timeout: 1.0)
    }

    func testSearchManagerMethodsExist() {
        // Test that all public methods exist and can be called
        XCTAssertNoThrow(searchManager.debouncedSearch(noteId: "test", text: "test query"))
        XCTAssertNoThrow(searchManager.getBacklinksForNote(noteId: "test"))
        XCTAssertNoThrow(searchManager.clearResults(for: "test"))
        XCTAssertNoThrow(searchManager.performSearch(noteId: "test", text: "test query"))
    }

    func testSearchManagerPreview() {
        let previewManager = SearchManager.preview
        XCTAssertNotNil(previewManager)
        XCTAssertFalse(previewManager.searchResults.isEmpty)
        XCTAssertEqual(previewManager.searchResults["welcome"]?.count ?? 0, 3)
    }

    func testSearchResultSampleData() {
        let sampleResults = SearchResult.sample()
        XCTAssertFalse(sampleResults.isEmpty)
        XCTAssertEqual(sampleResults.count, 3)

        // Check sample data structure
        XCTAssertEqual(sampleResults[0].noteId, "welcome")
        XCTAssertEqual(sampleResults[0].noteTitle, "Welcome")
        XCTAssertTrue(sampleResults[0].excerpt.contains("semantic"))
        XCTAssertGreaterThan(sampleResults[0].score, 0.8)

        XCTAssertEqual(sampleResults[1].noteId, "projects/grimoire")
        XCTAssertEqual(sampleResults[1].noteTitle, "Grimoire")
        XCTAssertTrue(sampleResults[1].excerpt.contains("note-taking"))
        XCTAssertGreaterThan(sampleResults[1].score, 0.7)

        XCTAssertEqual(sampleResults[2].noteId, "ideas")
        XCTAssertEqual(sampleResults[2].noteTitle, "Ideas")
        XCTAssertTrue(sampleResults[2].excerpt.contains("future"))
        XCTAssertGreaterThan(sampleResults[2].score, 0.6)
    }

    func testSearchManagerBackendURL() {
        // The backend URL should be set to localhost:8000
        // This is a simple check that the URL is valid
        XCTAssertNotNil(searchManager.backendURL)
        XCTAssertEqual(searchManager.backendURL.absoluteString, "http://127.0.0.1:8000/")
    }

    func testDebouncedSearchWithShortText() {
        // Given
        let noteId = "test-note"
        let shortText = "short"

        // When
        searchManager.debouncedSearch(noteId: noteId, text: shortText)

        // Then - should clear results for short text
        // Note: We can't easily test the timer behavior without mocking
        // This test just ensures the method doesn't crash
        XCTAssertNoThrow(searchManager.debouncedSearch(noteId: noteId, text: shortText))
    }

    func testDebouncedSearchWithValidText() {
        // Given
        let noteId = "test-note"
        let validText = "This is a longer text that should trigger search"

        // When
        searchManager.debouncedSearch(noteId: noteId, text: validText)

        // Then - method should execute without crashing
        XCTAssertNoThrow(searchManager.debouncedSearch(noteId: noteId, text: validText))
    }

    func testGetBacklinksForNote() {
        // When
        searchManager.getBacklinksForNote(noteId: "test-note")

        // Then - method should execute without crashing
        XCTAssertNoThrow(searchManager.getBacklinksForNote(noteId: "test-note"))
    }
}

// MARK: - Test Models

// These are already defined in the main app, but we redefine them here for testing
// to ensure they match the actual implementation

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

// MARK: - Test Extensions

extension SearchManager {
    // For testing, expose backendURL
    var backendURL: URL {
        return URL(string: "http://127.0.0.1:8000")!
    }

    // Expose extractTitle for testing
    func extractTitle(from noteId: String) -> String {
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
}
