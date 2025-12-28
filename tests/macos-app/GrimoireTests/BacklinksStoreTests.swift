import XCTest

@testable import Grimoire

@MainActor
final class BacklinksStoreTests: XCTestCase {
    func testInitialState() {
        let store = BacklinksStore(repository: StubSearchRepository())
        let results = store.results
        let isSearching = store.isSearching
        XCTAssertTrue(results.isEmpty)
        XCTAssertFalse(isSearching)
    }

    func testSearchPopulatesResults() async {
        let stub = StubSearchRepository()
        stub.stubbedResults = [
            Backlink(
                id: "note1_chunk1",
                noteId: "note1",
                noteTitle: "note1",
                chunkId: "chunk1",
                excerpt: "Test excerpt",
                score: 0.9,
                concept: nil
            )
        ]

        let store = BacklinksStore(repository: stub)
        store.search(
            noteId: "current",
            text: String(repeating: "a", count: 20),
            cursorOffset: 0,
            titleProvider: { _ in "Title" }
        )

        try? await Task.sleep(nanoseconds: 600_000_000)

        let results = store.results
        let isSearching = store.isSearching
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.noteTitle, "Title")
        XCTAssertFalse(isSearching)
    }
}

extension BacklinksStoreTests {
    static var allTests = [
        ("testInitialState", testInitialState),
        ("testSearchPopulatesResults", testSearchPopulatesResults),
    ]
}

// MARK: - Test Helpers

private final class StubSearchRepository: SearchRepository {
    var stubbedResults: [Backlink] = []

    func context(noteId: String, text: String, cursorOffset: Int, limit: Int) async throws -> [Backlink] {
        return stubbedResults
    }

    func warmup(forceRebuild: Bool) async throws {}
}
