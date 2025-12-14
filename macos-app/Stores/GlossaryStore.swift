import Foundation

@MainActor
final class GlossaryStore: ObservableObject {
    @Published var entries: [GlossaryEntrySummary] = []
    @Published var selectedEntry: GlossaryEntryDetail? = nil
    @Published var isLoading: Bool = false
    @Published var isLoadingDetail: Bool = false
    @Published var lastError: String? = nil

    private let repository: GlossaryRepository

    init(repository: GlossaryRepository = HTTPGlossaryRepository()) {
        self.repository = repository
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await repository.listEntries()
            lastError = nil
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    func select(conceptId: String) async {
        isLoadingDetail = true
        defer { isLoadingDetail = false }
        do {
            selectedEntry = try await repository.entryDetails(conceptId: conceptId)
            lastError = nil
        } catch {
            selectedEntry = nil
            lastError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    func clearSelection() {
        selectedEntry = nil
    }
}
