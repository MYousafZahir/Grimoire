import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var noteManager: NoteManager
    @Binding var selectedNoteId: String?

    @State private var expandedFolders: Set<String> = []

    var body: some View {
        List(selection: $selectedNoteId) {
            ForEach(noteManager.noteTree) { noteInfo in
                NoteRow(noteInfo: noteInfo, expandedFolders: $expandedFolders, selectedNoteId: $selectedNoteId)
            }
        }
        .listStyle(SidebarListStyle())
        .contextMenu {
            Button("New Note") {
                noteManager.createNewNote(parentId: nil)
            }

            Button("New Child Note") {
                if let selectedId = selectedNoteId {
                    noteManager.createNewNote(parentId: selectedId)
                }
            }
            .disabled(selectedNoteId == nil)

            Divider()

            Button("Delete Note", role: .destructive) {
                if let selectedId = selectedNoteId {
                    noteManager.deleteNote(noteId: selectedId)
                }
            }
            .disabled(selectedNoteId == nil)
        }
        .toolbar {
            ToolbarItem {
                Button(action: {
                    noteManager.createNewNote(parentId: nil)
                }) {
                    Image(systemName: "plus")
                }
                .help("New Note")
            }

            ToolbarItem {
                Button(action: {
                    noteManager.loadNotes()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }
}

struct NoteRow: View {
    let noteInfo: NoteInfo
    @Binding var expandedFolders: Set<String>
    @Binding var selectedNoteId: String?
    @EnvironmentObject private var noteManager: NoteManager

    var body: some View {
        // Check if this is a folder (has type "folder" or has children)
        let isFolder = noteInfo.type == "folder" || !noteInfo.children.isEmpty

        if !isFolder {
            // This is a note (leaf node)
            Label {
                Text(noteInfo.title)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "note.text")
                    .foregroundColor(.blue)
            }
            .tag(noteInfo.id)
            .contextMenu {
                Button("New Child Note") {
                    noteManager.createNewNote(parentId: noteInfo.id)
                }

                Divider()

                Button("Delete", role: .destructive) {
                    noteManager.deleteNote(noteId: noteInfo.id)
                }
            }
        } else {
            // This is a folder (has children or marked as folder)
            DisclosureGroup(
                isExpanded: Binding(
                    get: { expandedFolders.contains(noteInfo.id) },
                    set: { isExpanded in
                        if isExpanded {
                            expandedFolders.insert(noteInfo.id)
                        } else {
                            expandedFolders.remove(noteInfo.id)
                        }
                    }
                )
            ) {
                ForEach(noteInfo.children) { child in
                    NoteRow(
                        noteInfo: child,
                        expandedFolders: $expandedFolders,
                        selectedNoteId: $selectedNoteId
                    )
                }
            } label: {
                Label {
                    Text(noteInfo.title)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "folder")
                        .foregroundColor(.yellow)
                }
            }
            .tag(noteInfo.id)
            .contextMenu {
                Button("New Note in Folder") {
                    noteManager.createNewNote(parentId: noteInfo.id)
                }

                Divider()

                Button("Delete Folder", role: .destructive) {
                    noteManager.deleteNote(noteId: noteInfo.id)
                }
            }
        }
    }
}

struct NoteInfo: Identifiable, Codable {
    let id: String
    let title: String
    let path: String
    let children: [NoteInfo]
    let type: String?

    // For preview purposes
    static func sample() -> [NoteInfo] {
        return [
            NoteInfo(
                id: "welcome",
                title: "Welcome",
                path: "welcome",
                children: [],
                type: "note"
            ),
            NoteInfo(
                id: "projects",
                title: "Projects",
                path: "projects",
                children: [
                    NoteInfo(
                        id: "projects/grimoire",
                        title: "Grimoire",
                        path: "projects/grimoire",
                        children: [
                            NoteInfo(
                                id: "projects/grimoire/backend",
                                title: "Backend",
                                path: "projects/grimoire/backend",
                                children: [],
                                type: "note"
                            ),
                            NoteInfo(
                                id: "projects/grimoire/frontend",
                                title: "Frontend",
                                path: "projects/grimoire/frontend",
                                children: [],
                                type: "note"
                            ),
                        ],
                        type: "folder"
                    )
                ],
                type: "folder"
            ),
            NoteInfo(
                id: "ideas",
                title: "Ideas",
                path: "ideas",
                children: [],
                type: "note"
            ),
            )
        ]
    }
}

#Preview {
    SidebarView(selectedNoteId: .constant("welcome"))
        .environmentObject(NoteManager())
        .frame(width: 250)
}
