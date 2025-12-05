import SwiftUI

struct BacklinksView: View {
    @EnvironmentObject private var searchManager: SearchManager
    @EnvironmentObject private var noteManager: NoteManager
    @Binding var selectedNoteId: String?

    @State private var isLoading: Bool = false
    @State private var searchResults: [SearchResult] = []
    @State private var selectedResultId: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Semantic Backlinks")
                    .font(.headline)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Button(action: {
                    refreshBacklinks()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Backlinks")
                .buttonStyle(.plain)
                .disabled(isLoading)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 1)

            // Results list
            if searchResults.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "link")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("No backlinks found")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Text(
                        "As you type, semantically related excerpts from other notes will appear here."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedResultId) {
                    ForEach(searchResults) { result in
                        BacklinkRow(result: result, selectedNoteId: $selectedNoteId)
                            .tag(result.id)
                            .contextMenu {
                                Button("Open Note") {
                                    openNote(result.noteId)
                                }

                                Button("Copy Excerpt") {
                                    copyToClipboard(result.excerpt)
                                }

                                Divider()

                                Button("Hide This Result") {
                                    hideResult(result.id)
                                }
                            }
                    }
                }
                .listStyle(.plain)
            }

            // Footer with stats
            if !searchResults.isEmpty {
                HStack {
                    Text("\(searchResults.count) related excerpts")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let topScore = searchResults.first?.score {
                        Text("Top similarity: \(Int(topScore * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .border(Color(NSColor.separatorColor), width: 1)
            }
        }
        .onChange(of: selectedNoteId) { newValue in
            if let noteId = newValue {
                loadBacklinksForNote(noteId)
            } else {
                searchResults = []
            }
        }
        .onReceive(searchManager.$searchResults) { results in
            if let currentNoteId = selectedNoteId,
                let noteResults = results[currentNoteId]
            {
                // Convert SearchAPIResult to SearchResult
                let convertedResults = noteResults.map { apiResult in
                    // Get note title from note manager if available
                    let noteTitle =
                        noteManager.getNote(id: apiResult.noteId)?.title ?? "Unknown Note"

                    return SearchResult(
                        noteId: apiResult.noteId,
                        noteTitle: noteTitle,
                        chunkId: apiResult.chunkId,
                        excerpt: apiResult.text,
                        score: Double(apiResult.score)
                    )
                }
                searchResults = convertedResults
                isLoading = false
            }
        }
        .onAppear {
            if let noteId = selectedNoteId {
                loadBacklinksForNote(noteId)
            }
        }
    }

    private func refreshBacklinks() {
        if let noteId = selectedNoteId {
            loadBacklinksForNote(noteId)
        }
    }

    private func openNote(_ noteId: String) {
        selectedNoteId = noteId
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func hideResult(_ resultId: String) {
        searchResults.removeAll { $0.id == resultId }
    }

    private func loadBacklinksForNote(_ noteId: String) {
        isLoading = true
        searchResults = []

        // Search manager will update searchResults via @Published property
        // We'll handle the conversion in onReceive above
    }
}

struct BacklinkRow: View {
    let result: SearchResult
    @Binding var selectedNoteId: String?
    @EnvironmentObject private var noteManager: NoteManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Note title
            HStack {
                Image(systemName: "note.text")
                    .font(.caption)
                    .foregroundColor(.blue)

                Text(result.noteTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                // Similarity score
                Text("\(Int(result.score * 100))%")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(scoreColor(result.score))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(scoreColor(result.score).opacity(0.2))
                    )
            }

            // Excerpt
            Text(result.excerpt)
                .font(.body)
                .lineLimit(3)
                .foregroundColor(.primary)
                .padding(.leading, 20)

            // Context info
            HStack {
                Text("From: \(result.noteId)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Open") {
                    selectedNoteId = result.noteId
                }
                .buttonStyle(.link)
                .font(.caption)
            }
            .padding(.leading, 20)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .onTapGesture {
            selectedNoteId = result.noteId
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        switch score {
        case 0.8...1.0:
            return .green
        case 0.6..<0.8:
            return .blue
        case 0.4..<0.6:
            return .orange
        default:
            return .red
        }
    }
}

struct SearchResult: Identifiable, Codable {
    let id: String
    let noteId: String
    let noteTitle: String
    let chunkId: String
    let excerpt: String
    let score: Double

    init(noteId: String, noteTitle: String, chunkId: String, excerpt: String, score: Double) {
        self.id = "\(noteId)_\(chunkId)"
        self.noteId = noteId
        self.noteTitle = noteTitle
        self.chunkId = chunkId
        self.excerpt = excerpt
        self.score = score
    }

    // For preview
    static func sample() -> [SearchResult] {
        return [
            SearchResult(
                noteId: "machine-learning",
                noteTitle: "Machine Learning Basics",
                chunkId: "ml_1",
                excerpt:
                    "Machine learning is a subset of artificial intelligence that enables systems to learn and improve from experience without being explicitly programmed.",
                score: 0.92
            ),
            SearchResult(
                noteId: "neural-networks",
                noteTitle: "Neural Networks",
                chunkId: "nn_3",
                excerpt:
                    "Neural networks are computing systems inspired by biological neural networks that constitute animal brains. They learn to perform tasks by considering examples.",
                score: 0.87
            ),
            SearchResult(
                noteId: "data-science",
                noteTitle: "Data Science Workflow",
                chunkId: "ds_2",
                excerpt:
                    "The typical data science workflow involves data collection, cleaning, exploration, modeling, and interpretation of results.",
                score: 0.76
            ),
            SearchResult(
                noteId: "python-ml",
                noteTitle: "Python for ML",
                chunkId: "pyml_4",
                excerpt:
                    "Python has become the dominant programming language for machine learning due to its extensive libraries like scikit-learn, TensorFlow, and PyTorch.",
                score: 0.68
            ),
        ]
    }
}

#Preview {
    BacklinksView(selectedNoteId: .constant("welcome"))
        .environmentObject(SearchManager())
        .environmentObject(NoteManager())
        .frame(width: 300, height: 600)
}
