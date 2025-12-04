import SwiftUI
import XCTest

@testable import Grimoire

final class ViewsTests: XCTestCase {

    // MARK: - NoteInfo Tests

    func testNoteInfoInitialization() {
        let noteInfo = NoteInfo(
            id: "test-id",
            title: "Test Note",
            path: "test/path",
            children: []
        )

        XCTAssertEqual(noteInfo.id, "test-id")
        XCTAssertEqual(noteInfo.title, "Test Note")
        XCTAssertEqual(noteInfo.path, "test/path")
        XCTAssertTrue(noteInfo.children.isEmpty)
    }

    func testNoteInfoWithChildren() {
        let child1 = NoteInfo(
            id: "child-1", title: "Child 1", path: "test/path/child-1", children: [])
        let child2 = NoteInfo(
            id: "child-2", title: "Child 2", path: "test/path/child-2", children: [])

        let parent = NoteInfo(
            id: "parent",
            title: "Parent Note",
            path: "test/path",
            children: [child1, child2]
        )

        XCTAssertEqual(parent.children.count, 2)
        XCTAssertEqual(parent.children[0].id, "child-1")
        XCTAssertEqual(parent.children[1].id, "child-2")
    }

    func testNoteInfoIdentifiable() {
        let noteInfo = NoteInfo(id: "unique-id", title: "Test", path: "test", children: [])
        XCTAssertEqual(noteInfo.id, "unique-id")
    }

    func testNoteInfoCodable() throws {
        let noteInfo = NoteInfo(
            id: "test-id",
            title: "Test Note",
            path: "test/path",
            children: [
                NoteInfo(id: "child", title: "Child", path: "test/path/child", children: [])
            ]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(noteInfo)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(NoteInfo.self, from: data)

        XCTAssertEqual(decoded.id, noteInfo.id)
        XCTAssertEqual(decoded.title, noteInfo.title)
        XCTAssertEqual(decoded.path, noteInfo.path)
        XCTAssertEqual(decoded.children.count, 1)
        XCTAssertEqual(decoded.children[0].id, "child")
    }

    func testNoteInfoSampleData() {
        let sample = NoteInfo.sample()
        XCTAssertFalse(sample.isEmpty)
        XCTAssertEqual(sample.count, 3)

        // Check welcome note
        XCTAssertEqual(sample[0].id, "welcome")
        XCTAssertEqual(sample[0].title, "Welcome")
        XCTAssertTrue(sample[0].children.isEmpty)

        // Check projects hierarchy
        XCTAssertEqual(sample[1].id, "projects")
        XCTAssertEqual(sample[1].title, "Projects")
        XCTAssertEqual(sample[1].children.count, 1)

        let grimoireProject = sample[1].children[0]
        XCTAssertEqual(grimoireProject.id, "projects/grimoire")
        XCTAssertEqual(grimoireProject.title, "Grimoire")
        XCTAssertEqual(grimoireProject.children.count, 2)

        // Check ideas note
        XCTAssertEqual(sample[2].id, "ideas")
        XCTAssertEqual(sample[2].title, "Ideas")
        XCTAssertTrue(sample[2].children.isEmpty)
    }

    // MARK: - SearchResult Tests

    func testSearchResultInitialization() {
        let searchResult = SearchResult(
            noteId: "test-note",
            noteTitle: "Test Note",
            chunkId: "chunk-1",
            excerpt: "This is a test excerpt",
            score: 0.95
        )

        XCTAssertEqual(searchResult.id, "test-note_chunk-1")
        XCTAssertEqual(searchResult.noteId, "test-note")
        XCTAssertEqual(searchResult.noteTitle, "Test Note")
        XCTAssertEqual(searchResult.chunkId, "chunk-1")
        XCTAssertEqual(searchResult.excerpt, "This is a test excerpt")
        XCTAssertEqual(searchResult.score, 0.95)
    }

    func testSearchResultIdentifiable() {
        let searchResult = SearchResult(
            noteId: "note-1",
            noteTitle: "Note 1",
            chunkId: "chunk-1",
            excerpt: "Test",
            score: 0.9
        )

        XCTAssertEqual(searchResult.id, "note-1_chunk-1")
    }

    func testSearchResultCodable() throws {
        let searchResult = SearchResult(
            noteId: "test-note",
            noteTitle: "Test Note",
            chunkId: "chunk-1",
            excerpt: "Test excerpt",
            score: 0.95
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(searchResult)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SearchResult.self, from: data)

        XCTAssertEqual(decoded.id, searchResult.id)
        XCTAssertEqual(decoded.noteId, searchResult.noteId)
        XCTAssertEqual(decoded.noteTitle, searchResult.noteTitle)
        XCTAssertEqual(decoded.chunkId, searchResult.chunkId)
        XCTAssertEqual(decoded.excerpt, searchResult.excerpt)
        XCTAssertEqual(decoded.score, searchResult.score)
    }

    func testSearchResultSampleData() {
        let sample = SearchResult.sample()
        XCTAssertFalse(sample.isEmpty)
        XCTAssertEqual(sample.count, 3)

        // Check first sample result
        XCTAssertEqual(sample[0].noteId, "welcome")
        XCTAssertEqual(sample[0].noteTitle, "Welcome")
        XCTAssertTrue(sample[0].excerpt.contains("semantic"))
        XCTAssertGreaterThan(sample[0].score, 0.8)

        // Check second sample result
        XCTAssertEqual(sample[1].noteId, "projects/grimoire")
        XCTAssertEqual(sample[1].noteTitle, "Grimoire")
        XCTAssertTrue(sample[1].excerpt.contains("note-taking"))
        XCTAssertGreaterThan(sample[1].score, 0.7)

        // Check third sample result
        XCTAssertEqual(sample[2].noteId, "ideas")
        XCTAssertEqual(sample[2].noteTitle, "Ideas")
        XCTAssertTrue(sample[2].excerpt.contains("future"))
        XCTAssertGreaterThan(sample[2].score, 0.6)
    }

    func testSearchResultScoreFormatting() {
        let searchResult = SearchResult(
            noteId: "test",
            noteTitle: "Test",
            chunkId: "chunk-1",
            excerpt: "Test",
            score: 0.857
        )

        // Test that score can be formatted as percentage
        let percentage = Int(searchResult.score * 100)
        XCTAssertEqual(percentage, 85)
    }

    // MARK: - View Model Tests

    func testContentViewInitialization() {
        let contentView = ContentView()
        XCTAssertNotNil(contentView)
    }

    func testSidebarViewInitialization() {
        let binding = Binding<String?>(get: { nil }, set: { _ in })
        let sidebarView = SidebarView(selectedNoteId: binding)
        XCTAssertNotNil(sidebarView)
    }

    func testEditorViewInitialization() {
        let binding = Binding<String?>(get: { nil }, set: { _ in })
        let editorView = EditorView(selectedNoteId: binding, onTextChange: { _ in })
        XCTAssertNotNil(editorView)
    }

    func testBacklinksViewInitialization() {
        let binding = Binding<String?>(get: { nil }, set: { _ in })
        let backlinksView = BacklinksView(selectedNoteId: binding)
        XCTAssertNotNil(backlinksView)
    }

    func testSettingsViewInitialization() {
        let settingsView = SettingsView()
        XCTAssertNotNil(settingsView)
    }

    // MARK: - Preview Tests

    func testPreviewProvidersCompile() {
        // These tests ensure that the preview providers compile correctly
        // We can't actually run previews in tests, but we can verify the types

        let contentView = ContentView()
        XCTAssertTrue(type(of: contentView) == ContentView.self)

        // Note: We can't actually test #Preview macros in unit tests
        // This is just to verify the view types are correct
    }

    // MARK: - View Properties Tests

    func testContentViewProperties() {
        // Test that ContentView has the expected properties
        let contentView = ContentView()

        // Use reflection to check properties (simplified approach)
        let mirror = Mirror(reflecting: contentView)
        let propertyNames = mirror.children.map { $0.label ?? "" }

        // Check for expected property names
        XCTAssertTrue(propertyNames.contains("selectedNoteId"))
        XCTAssertTrue(propertyNames.contains("sidebarWidth"))
        XCTAssertTrue(propertyNames.contains("backlinksWidth"))
    }

    func testSidebarViewProperties() {
        let binding = Binding<String?>(get: { nil }, set: { _ in })
        let sidebarView = SidebarView(selectedNoteId: binding)

        let mirror = Mirror(reflecting: sidebarView)
        let propertyNames = mirror.children.map { $0.label ?? "" }

        XCTAssertTrue(propertyNames.contains("selectedNoteId"))
    }

    func testEditorViewProperties() {
        let binding = Binding<String?>(get: { nil }, set: { _ in })
        let editorView = EditorView(selectedNoteId: binding, onTextChange: { _ in })

        let mirror = Mirror(reflecting: editorView)
        let propertyNames = mirror.children.map { $0.label ?? "" }

        XCTAssertTrue(propertyNames.contains("selectedNoteId"))
        XCTAssertTrue(propertyNames.contains("onTextChange"))
    }

    func testBacklinksViewProperties() {
        let binding = Binding<String?>(get: { nil }, set: { _ in })
        let backlinksView = BacklinksView(selectedNoteId: binding)

        let mirror = Mirror(reflecting: backlinksView)
        let propertyNames = mirror.children.map { $0.label ?? "" }

        XCTAssertTrue(propertyNames.contains("selectedNoteId"))
    }

    // MARK: - Integration Tests

    func testViewsWorkWithNoteManager() {
        let noteManager = NoteManager.preview
        let searchManager = SearchManager.preview

        // Create a ContentView with the managers
        let contentView = ContentView()
            .environmentObject(noteManager)
            .environmentObject(searchManager)

        XCTAssertNotNil(contentView)

        // Verify note manager has data
        XCTAssertFalse(noteManager.noteTree.isEmpty)

        // Verify search manager has data
        XCTAssertFalse(searchManager.searchResults.isEmpty)
    }

    func testViewsWorkWithSampleData() {
        // Test that views can work with sample data for previews
        let sampleNotes = NoteInfo.sample()
        let sampleResults = SearchResult.sample()

        XCTAssertFalse(sampleNotes.isEmpty)
        XCTAssertFalse(sampleResults.isEmpty)

        // Verify sample data structure
        XCTAssertEqual(sampleNotes.count, 3)
        XCTAssertEqual(sampleResults.count, 3)
    }

    // MARK: - Performance Tests

    func testNoteInfoSamplePerformance() {
        measure {
            _ = NoteInfo.sample()
        }
    }

    func testSearchResultSamplePerformance() {
        measure {
            _ = SearchResult.sample()
        }
    }

    func testNoteInfoEncodingPerformance() throws {
        let noteInfo = NoteInfo.sample()[0]
        let encoder = JSONEncoder()

        measure {
            _ = try? encoder.encode(noteInfo)
        }
    }

    func testSearchResultEncodingPerformance() throws {
        let searchResult = SearchResult.sample()[0]
        let encoder = JSONEncoder()

        measure {
            _ = try? encoder.encode(searchResult)
        }
    }
}
