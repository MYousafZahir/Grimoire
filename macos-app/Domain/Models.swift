import Foundation

enum NoteKind: String, Codable {
    case note
    case folder
}

struct NoteNode: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let path: String
    let kind: NoteKind
    var children: [NoteNode]

    var isFolder: Bool { kind == .folder }
}

struct NoteDocument {
    let id: String
    let title: String
    let content: String
    let kind: NoteKind
}

struct Backlink: Identifiable, Hashable {
    let id: String
    let noteId: String
    let noteTitle: String
    let chunkId: String
    let excerpt: String
    let score: Double
}

extension NoteNode {
    static func sampleTree() -> [NoteNode] {
        [
            NoteNode(
                id: "welcome",
                title: "Welcome",
                path: "welcome",
                kind: .note,
                children: []
            ),
            NoteNode(
                id: "projects",
                title: "Projects",
                path: "projects",
                kind: .folder,
                children: [
                    NoteNode(
                        id: "grimoire",
                        title: "Grimoire",
                        path: "projects/grimoire",
                        kind: .folder,
                        children: [
                            NoteNode(
                                id: "grimoire-backend",
                                title: "Backend",
                                path: "projects/grimoire/backend",
                                kind: .note,
                                children: []
                            ),
                            NoteNode(
                                id: "grimoire-frontend",
                                title: "Frontend",
                                path: "projects/grimoire/frontend",
                                kind: .note,
                                children: []
                            ),
                        ]
                    )
                ]
            ),
            NoteNode(
                id: "ideas",
                title: "Ideas",
                path: "ideas",
                kind: .note,
                children: []
            ),
        ]
    }
}
