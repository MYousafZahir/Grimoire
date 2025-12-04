import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var noteManager: NoteManager
    @EnvironmentObject private var searchManager: SearchManager

    @State private var selectedNoteId: String? = nil
    @State private var sidebarWidth: CGFloat = 250
    @State private var backlinksWidth: CGFloat = 300

    var body: some View {
        NavigationSplitView {
            // Left sidebar - Note hierarchy
            SidebarView(selectedNoteId: $selectedNoteId)
                .frame(minWidth: 200, idealWidth: sidebarWidth, maxWidth: 400)
                .toolbar {
                    ToolbarItem {
                        Button(action: {
                            noteManager.createNewNote(parentId: nil)
                        }) {
                            Image(systemName: "plus")
                        }
                        .help("New Note")
                    }
                }
        } detail: {
            // Main editor area
            HStack(spacing: 0) {
                // Editor
                EditorView(
                    selectedNoteId: $selectedNoteId,
                    onTextChange: { text in
                        if let noteId = selectedNoteId {
                            searchManager.debouncedSearch(noteId: noteId, text: text)
                        }
                    }
                )
                .frame(minWidth: 400)

                // Right sidebar - Backlinks
                BacklinksView(selectedNoteId: $selectedNoteId)
                    .frame(minWidth: 250, idealWidth: backlinksWidth, maxWidth: 500)
                    .background(Color(NSColor.controlBackgroundColor))
                    .border(Color(NSColor.separatorColor), width: 1)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            // Load initial data
            noteManager.loadNotes()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(NoteManager())
        .environmentObject(SearchManager())
}
