import SwiftUI
import XCTest

@testable import Grimoire

final class ViewsTests: XCTestCase {
    func testNoteNodeCodable() throws {
        let node = NoteNode(
            id: "id",
            title: "Title",
            path: "id",
            kind: .note,
            children: [
                NoteNode(id: "child", title: "Child", path: "child", kind: .note, children: [])
            ]
        )

        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(NoteNode.self, from: data)
        XCTAssertEqual(decoded.id, node.id)
        XCTAssertEqual(decoded.children.first?.id, "child")
    }

    func testBacklinkModel() {
        let backlink = Backlink(
            id: "note_chunk",
            noteId: "note",
            noteTitle: "Note",
            chunkId: "chunk",
            excerpt: "Excerpt",
            score: 0.8,
            concept: nil
        )

        XCTAssertEqual(backlink.id, "note_chunk")
        XCTAssertEqual(backlink.noteTitle, "Note")
    }

    func testViewsInitialize() {
        let selection = Binding<String?>(get: { nil }, set: { _ in })

        let content = ContentView()
            .environmentObject(NoteStore(repository: StubNoteRepository()))
            .environmentObject(BacklinksStore(repository: StubSearchRepository()))
        XCTAssertNotNil(content)

        let sidebar = SidebarView(selectedNoteId: selection)
            .environmentObject(NoteStore(repository: StubNoteRepository()))
            .environmentObject(BacklinksStore(repository: StubSearchRepository()))
        XCTAssertNotNil(sidebar)

        let editor = EditorView(selectedNoteId: selection)
            .environmentObject(NoteStore(repository: StubNoteRepository()))
            .environmentObject(BacklinksStore(repository: StubSearchRepository()))
        XCTAssertNotNil(editor)

        let backlinks = BacklinksView(selectedNoteId: selection)
            .environmentObject(NoteStore(repository: StubNoteRepository()))
            .environmentObject(BacklinksStore(repository: StubSearchRepository()))
        XCTAssertNotNil(backlinks)
    }
}

extension ViewsTests {
    static var allTests = [
        ("testNoteNodeCodable", testNoteNodeCodable),
        ("testBacklinkModel", testBacklinkModel),
        ("testViewsInitialize", testViewsInitialize),
    ]
}

// MARK: - Stubs

private final class StubNoteRepository: NoteRepository {
    func healthCheck() async -> Bool { true }
    func fetchCurrentProject() async throws -> ProjectInfo {
        ProjectInfo(name: "Default.grim", path: "/tmp/Default.grim", isActive: true)
    }
    func fetchProjects() async throws -> [ProjectInfo] { [try await fetchCurrentProject()] }
    func createProject(name: String) async throws -> ProjectInfo {
        ProjectInfo(name: name.hasSuffix(".grim") ? name : "\(name).grim", path: "/tmp/\(name).grim", isActive: true)
    }
    func openProject(path: String) async throws -> ProjectInfo {
        ProjectInfo(name: (path as NSString).lastPathComponent, path: path, isActive: true)
    }
    func fetchTree() async throws -> [NoteNode] { [] }
    func fetchContent(noteId: String) async throws -> NoteDocument {
        NoteDocument(id: noteId, title: noteId, content: "", kind: .note)
    }
    func saveContent(noteId: String, content: String, parentId: String?) async throws {}
    func createFolder(path: String) async throws -> NoteNode {
        NoteNode(id: path, title: path, path: path, kind: .folder, children: [])
    }
    func rename(noteId: String, newId: String) async throws {}
    func moveItem(noteId: String, parentId: String?) async throws {}
    func delete(noteId: String) async throws {}
}

private final class StubSearchRepository: SearchRepository {
    func context(noteId: String, text: String, cursorOffset: Int, limit: Int) async throws -> [Backlink] { [] }
    func warmup(forceRebuild: Bool) async throws {}
}
