import SwiftUI
import MarkdownUI

struct BacklinksView: View {
    @EnvironmentObject private var backlinksStore: BacklinksStore
    @EnvironmentObject private var noteStore: NoteStore
    @Binding var selectedNoteId: String?

    @State private var selectedResultId: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Semantic Backlinks")
                    .font(.headline)

                Spacer()

                Button(action: {
                    refreshBacklinks()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh Backlinks")
                .buttonStyle(.plain)
                .disabled(backlinksStore.isSearching)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 1)

            if backlinksStore.results.isEmpty {
                if backlinksStore.isSearching {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading semantic backlinks…")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "link")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("Nothing worth showing yet")
                            .font(.title3)
                            .foregroundColor(.secondary)

                        Text(
                            "No high-quality semantic backlinks were found for this cursor location."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                List(selection: $selectedResultId) {
                    ForEach(backlinksStore.results, id: \.id) { result in
                        BacklinkRow(result: result, onReveal: reveal, selectedNoteId: $selectedNoteId)
                            .tag(result.id)
                            .contextMenu {
                                Button("Open Note") {
                                    reveal(result)
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

            if let error = backlinksStore.lastError,
               !error.contains("Code=-999"),
               !error.contains("cancelled") {
                Text("Backlinks error: \(error)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .border(Color(NSColor.separatorColor), width: 1)
            }

            if !backlinksStore.results.isEmpty {
                HStack {
                    Text("\(backlinksStore.results.count) related excerpts")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let topScore = backlinksStore.results.map(\.score).max() {
                        Text("Top match: \(Int(topScore * 100))%")
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
    }

    private func refreshBacklinks() {
        backlinksStore.refresh { noteStore.title(for: $0) }
    }

    private func reveal(_ result: Backlink) {
        selectedNoteId = result.noteId
        noteStore.requestReveal(noteId: result.noteId, contextChunkId: result.chunkId, excerpt: result.excerpt)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func hideResult(_ resultId: String) {
        backlinksStore.results.removeAll { $0.id == resultId }
    }
}

struct BacklinkRow: View {
    let result: Backlink
    let onReveal: (Backlink) -> Void
    @Binding var selectedNoteId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let concept = result.concept, !concept.isEmpty {
                Text(concept)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }

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

            Markdown(excerptMarkdown)
                .markdownTheme(.docC)
                .foregroundColor(.primary)
                .padding(.leading, 20)

            HStack {
                Text("From: \(result.noteId)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button("Open") {
                    onReveal(result)
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
            onReveal(result)
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

    private var excerptMarkdown: String {
        var text = result.excerpt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return " " }

        var didTruncate = false
        let lines = text.components(separatedBy: .newlines)
        if lines.count > 3 {
            text = lines.prefix(3).joined(separator: "\n")
            didTruncate = true
        }

        let maxChars = 500
        if text.count > maxChars {
            let idx = text.index(text.startIndex, offsetBy: maxChars)
            text = String(text[..<idx])
            didTruncate = true
        }

        if didTruncate {
            text += "…"
        }
        return text
    }
}
