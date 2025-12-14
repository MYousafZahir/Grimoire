import SwiftUI

struct GlossaryView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @StateObject private var store = GlossaryStore()

    @Binding var selectedNoteId: String?

    @State private var query: String = ""
    @State private var selectedConceptId: String? = nil

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 8) {
                HStack {
                    TextField("Search glossary", text: $query)
                        .textFieldStyle(.roundedBorder)
                    Button(action: { Task { await store.refresh() } }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("Refresh")
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                if store.isLoading && store.entries.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selectedConceptId) {
                        ForEach(filteredEntries, id: \.conceptId) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(entry.displayName)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Text(entry.kind.capitalized)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12))
                                            .cornerRadius(6)
                                    }
                                    if !entry.definitionExcerpt.isEmpty {
                                        Text(entry.definitionExcerpt)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                                Text("\(entry.chunkCount)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(Optional(entry.conceptId))
                        }
                    }
                    .listStyle(.sidebar)
                }
            }
            .navigationTitle("Glossary")
        } detail: {
            detailPane
        }
        .frame(minWidth: 760, minHeight: 520)
        .task {
            await store.refresh()
        }
        .onChange(of: selectedConceptId) { newValue in
            guard let conceptId = newValue else {
                store.clearSelection()
                return
            }
            Task { await store.select(conceptId: conceptId) }
        }
    }

    private var filteredEntries: [GlossaryEntrySummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return store.entries }
        return store.entries.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    @ViewBuilder
    private var detailPane: some View {
        if store.isLoadingDetail {
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading…")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let entry = store.selectedEntry {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(entry.kind.capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(6)
                        Spacer()
                        Text("\(entry.chunkCount) chunks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    if !entry.definitionExcerpt.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Definition")
                                    .font(.headline)
                                Spacer()
                                if let source = entry.sourceNoteId {
                                    Button("Open Source") {
                                        noteStore.requestReveal(
                                            noteId: source,
                                            contextChunkId: entry.definitionChunkId,
                                            excerpt: entry.definitionExcerpt
                                        )
                                        selectedNoteId = source
                                    }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }

                            Text(entry.definitionExcerpt)
                                .font(.callout)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                        }
                        .padding(.vertical, 6)
                    }

                    if !entry.surfaceForms.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Surface forms")
                                .font(.headline)
                            Text(entry.surfaceForms.joined(separator: ", "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }

                    if !entry.supporting.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Other supporting passages")
                                .font(.headline)
                            ForEach(entry.supporting) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(noteStore.title(for: item.noteId) ?? item.noteId)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        Button("Open") {
                                            noteStore.requestReveal(
                                                noteId: item.noteId,
                                                contextChunkId: item.chunkId,
                                                excerpt: item.excerpt
                                            )
                                            selectedNoteId = item.noteId
                                        }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                    }
                                    Text(item.excerpt)
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(10)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(8)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let error = store.lastError {
            VStack(spacing: 10) {
                Text("Glossary error")
                    .font(.headline)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button("Retry") { Task { await store.refresh() } }
                    .keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 10) {
                Text("Select a term")
                    .font(.headline)
                Text("People, places, and things mentioned across your project.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
