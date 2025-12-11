import XCTest

@testable import Grimoire

final class BacklinksStoreTests: XCTestCase {
    func testInitialState() {
        let store = BacklinksStore(repository: StubSearchRepository())
        XCTAssertTrue(store.results.isEmpty)
        XCTAssertFalse(store.isSearching)
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
                score: 0.9
            )
        ]

        let store = BacklinksStore(repository: stub)
        store.search(
            noteId: "current",
            text: String(repeating: "a", count: 20),
            titleProvider: { _ in "Title" }
        )

        try? await Task.sleep(nanoseconds: 600_000_000)

        XCTAssertEqual(store.results.count, 1)
        XCTAssertEqual(store.results.first?.noteTitle, "Title")
        XCTAssertFalse(store.isSearching)
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

    func search(noteId: String, text: String) async throws -> [Backlink] {
        return stubbedResults
    }
}
