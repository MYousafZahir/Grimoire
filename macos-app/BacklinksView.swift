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

                if backlinksStore.isSearching {
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
                .disabled(backlinksStore.isSearching)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 1)

            if backlinksStore.results.isEmpty {
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
                    ForEach(backlinksStore.results, id: \.id) { result in
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

            if !backlinksStore.results.isEmpty {
                HStack {
                    Text("\(backlinksStore.results.count) related excerpts")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if let topScore = backlinksStore.results.first?.score {
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
        .onChange(of: selectedNoteId) { _ in
            backlinksStore.clear()
        }
    }

    private func refreshBacklinks() {
        backlinksStore.refresh { noteStore.title(for: $0) }
    }

    private func openNote(_ noteId: String) {
        selectedNoteId = noteId
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
    @Binding var selectedNoteId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
