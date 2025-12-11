import Foundation

@MainActor
final class BacklinksStore: ObservableObject {
    @Published var results: [Backlink] = []
    @Published var isSearching: Bool = false

    private let repository: SearchRepository
    private var searchTask: Task<Void, Never>?
    private var lastQuery: (noteId: String, text: String)?

    init(repository: SearchRepository = HTTPSearchRepository()) {
        self.repository = repository
    }

    func clear() {
        searchTask?.cancel()
        results = []
        isSearching = false
        lastQuery = nil
    }

    func search(
        noteId: String,
        text: String,
        titleProvider: @escaping (String) -> String?
    ) {
        searchTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else {
            results = []
            isSearching = false
            return
        }

        lastQuery = (noteId, trimmed)
        isSearching = true

        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self else { return }
            await self.performSearch(noteId: noteId, text: trimmed, titleProvider: titleProvider)
        }
    }

    func refresh(titleProvider: @escaping (String) -> String?) {
        guard let lastQuery else { return }
        search(
            noteId: lastQuery.noteId,
            text: lastQuery.text,
            titleProvider: titleProvider
        )
    }

    func dropResults(for noteId: String) {
        results.removeAll { $0.noteId == noteId }
    }

    private func performSearch(
        noteId: String,
        text: String,
        titleProvider: (String) -> String?
    ) async {
        do {
            let apiResults = try await repository.search(noteId: noteId, text: text)
            let mapped = apiResults.map { backlink in
                Backlink(
                    id: backlink.id,
                    noteId: backlink.noteId,
                    noteTitle: titleProvider(backlink.noteId) ?? backlink.noteTitle,
                    chunkId: backlink.chunkId,
                    excerpt: backlink.excerpt,
                    score: backlink.score
                )
            }
            results = mapped.filter { $0.noteId != noteId }
            isSearching = false
        } catch {
            isSearching = false
            results = []
        }
    }
}
