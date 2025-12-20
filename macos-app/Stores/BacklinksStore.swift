import Foundation

@MainActor
final class BacklinksStore: ObservableObject {
    @Published var results: [Backlink] = []
    @Published var isSearching: Bool = false
    @Published var lastError: String? = nil

    private let repository: SearchRepository
    private var debounceTask: Task<Void, Never>?
    private var inFlightTask: Task<Void, Never>?
    private var pendingQuery: Query?
    private var runningQuery: Query?

    init(repository: SearchRepository = HTTPSearchRepository()) {
        self.repository = repository
    }

    func beginLoading(clearResults: Bool = true) {
        if clearResults {
            results = []
        }
        isSearching = true
        lastError = nil
    }

    func warmup(forceRebuild: Bool) async throws {
        try await repository.warmup(forceRebuild: forceRebuild)
    }

    func clear() {
        debounceTask?.cancel()
        inFlightTask?.cancel()
        results = []
        isSearching = false
        pendingQuery = nil
        runningQuery = nil
        lastError = nil
    }

    func search(
        noteId: String,
        text: String,
        cursorOffset: Int,
        limit: Int = 3,
        titleProvider: @escaping (String) -> String?
    ) {
        // Keep text untrimmed so `cursorOffset` (computed against the same string)
        // stays valid when the backend clamps/splits on offsets.
        let normalizedText = text

        if normalizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            results = []
            isSearching = false
            pendingQuery = nil
            runningQuery = nil
            lastError = nil
            return
        }

        let normalized = Query(
            noteId: noteId,
            text: normalizedText,
            cursorOffset: max(0, cursorOffset),
            limit: max(1, limit)
        )

        // If the latest pending query is identical, do nothing.
        if pendingQuery == normalized { return }
        pendingQuery = normalized

        // If we are currently computing a query for a different note, cancel it.
        if let runningQuery, runningQuery.noteId != normalized.noteId {
            inFlightTask?.cancel()
        }

        isSearching = true
        lastError = nil

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            // Realtime: cursor click or debounced move (~75ms).
            try? await Task.sleep(nanoseconds: 75_000_000)
            guard let self else { return }
            await self.startNextIfIdle(titleProvider: titleProvider)
        }
    }

    func refresh(titleProvider: @escaping (String) -> String?) {
        guard let pendingQuery else { return }
        search(
            noteId: pendingQuery.noteId,
            text: pendingQuery.text,
            cursorOffset: pendingQuery.cursorOffset,
            limit: pendingQuery.limit,
            titleProvider: titleProvider
        )
    }

    func dropResults(for noteId: String) {
        results.removeAll { $0.noteId == noteId }
    }

    private func startNextIfIdle(titleProvider: @escaping (String) -> String?) async {
        guard inFlightTask == nil else { return }
        guard let query = pendingQuery else {
            isSearching = false
            return
        }

        runningQuery = query

        inFlightTask = Task { [weak self] in
            guard let self else { return }
            await self.perform(query, titleProvider: titleProvider)
        }
    }

    private func perform(_ query: Query, titleProvider: @escaping (String) -> String?) async {
        defer {
            inFlightTask = nil
        }

        do {
            let apiResults = try await repository.context(
                noteId: query.noteId,
                text: query.text,
                cursorOffset: query.cursorOffset,
                limit: query.limit
            )
            let mapped = apiResults.map { backlink in
                Backlink(
                    id: backlink.id,
                    noteId: backlink.noteId,
                    noteTitle: titleProvider(backlink.noteId) ?? backlink.noteTitle,
                    chunkId: backlink.chunkId,
                    excerpt: backlink.excerpt,
                    score: backlink.score,
                    concept: backlink.concept
                )
            }
            results = mapped
                .filter { $0.noteId != query.noteId }
                .sorted { (lhs, rhs) in
                    if lhs.score != rhs.score { return lhs.score > rhs.score }
                    return lhs.id < rhs.id
                }
            lastError = nil
        } catch {
            if Self.isCancellation(error) {
                return
            }
            results = []
            lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }

        // If the user changed cursor/note while we were running, kick off the latest query.
        if let pendingQuery, pendingQuery != query {
            await startNextIfIdle(titleProvider: titleProvider)
            return
        }
        isSearching = false
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        let ns = error as NSError
        // Be defensive: cancellations sometimes show up wrapped/untyped.
        return ns.code == NSURLErrorCancelled || (ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled)
    }
}

private struct Query: Equatable {
    let noteId: String
    let text: String
    let cursorOffset: Int
    let limit: Int
}
