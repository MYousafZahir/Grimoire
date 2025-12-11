import XCTest

@testable import Grimoire

final class NoteStoreTests: XCTestCase {
    func testInitialStateIsEmpty() {
        let store = NoteStore(repository: StubNoteRepository())
        XCTAssertTrue(store.tree.isEmpty)
        XCTAssertNil(store.selection)
        XCTAssertEqual(store.currentContent, "")
    }

    func testSampleTreeShape() {
        let sample = NoteNode.sampleTree()
        XCTAssertFalse(sample.isEmpty)
        XCTAssertEqual(sample.first?.id, "welcome")
        XCTAssertEqual(sample[1].children.first?.id, "grimoire")
    }

    func testGeneratedIdsAreUnique() async {
        let repository = StubNoteRepository()
        let store = NoteStore(repository: repository)
        let id1 = await store.createNote(parentId: nil)
        let id2 = await store.createNote(parentId: nil)
        XCTAssertNotEqual(id1, id2)
        XCTAssertTrue(id1?.hasPrefix("note_") ?? false)
    }

    func testSaveDraftPersists() async {
        let repository = StubNoteRepository()
        repository.tree = [
            NoteNode(id: "note-1", title: "Note", path: "note-1", kind: .note, children: [])
        ]
        let store = NoteStore(repository: repository)
        store.selection = "note-1"
        store.currentNoteKind = .note
        store.updateDraft("Hello world")
        await store.saveDraft()
        XCTAssertEqual(repository.savedNotes["note-1"], "Hello world")
    }
}

extension NoteStoreTests {
    static var allTests = [
        ("testInitialStateIsEmpty", testInitialStateIsEmpty),
        ("testSampleTreeShape", testSampleTreeShape),
        ("testGeneratedIdsAreUnique", testGeneratedIdsAreUnique),
        ("testSaveDraftPersists", testSaveDraftPersists),
    ]
}

// MARK: - Test Helpers

private final class StubNoteRepository: NoteRepository {
    var tree: [NoteNode] = []
    var savedNotes: [String: String] = [:]

    func healthCheck() async -> Bool { true }

    func fetchTree() async throws -> [NoteNode] { tree }

    func fetchContent(noteId: String) async throws -> NoteDocument {
        let content = savedNotes[noteId] ?? ""
        return NoteDocument(id: noteId, title: noteId, content: content, kind: .note)
    }

    func saveContent(noteId: String, content: String, parentId: String?) async throws {
        savedNotes[noteId] = content
    }

    func createFolder(path: String) async throws -> NoteNode {
        let folderId = path.replacingOccurrences(of: "/", with: "_")
        return NoteNode(id: folderId, title: folderId, path: path, kind: .folder, children: [])
    }

    func rename(noteId: String, newId: String) async throws {
        if let content = savedNotes.removeValue(forKey: noteId) {
            savedNotes[newId] = content
        }
    }

    func delete(noteId: String) async throws {
        savedNotes.removeValue(forKey: noteId)
    }
}
