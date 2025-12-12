import SwiftUI
import AppKit
import MarkdownUI

struct EditorView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @EnvironmentObject private var backlinksStore: BacklinksStore
    @Binding var selectedNoteId: String?

    @State private var noteContent: String = ""
    @State private var showPreview: Bool = false
    @State private var saveTask: Task<Void, Never>?
    @State private var chunks: [EditorChunk] = []
    @State private var activeChunkId: UUID? = nil
    @FocusState private var focusedChunkId: UUID?

    private var isFolderSelected: Bool {
        guard let selectedNoteId else { return false }
        return noteStore.isFolder(id: selectedNoteId)
            || noteStore.currentNoteKind == .folder
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let selectedNoteId {
                    Text(noteStore.title(for: selectedNoteId) ?? selectedNoteId)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("No Note Selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { showPreview.toggle() }) {
                    Image(systemName: showPreview ? "eye.slash" : "eye")
                        .foregroundColor(showPreview ? .accentColor : .secondary)
                }
                .help(showPreview ? "Hide Preview" : "Show Preview")
                .buttonStyle(.plain)

                statusLabel
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 1)

            if showPreview, let selectedNoteId, !isFolderSelected {
                ScrollView {
                    Markdown(noteContent.isEmpty ? " " : noteContent)
                        .markdownTheme(.docC)
                        .padding()
                }
            } else if let selectedNoteId, !isFolderSelected {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(chunks) { chunk in
                            ChunkRow(
                                chunk: chunk,
                                isActive: chunk.id == activeChunkId,
                                shouldFocus: chunk.id == focusedChunkId,
                                onActivate: { activateChunk(chunk.id) },
                                textBinding: binding(for: chunk)
                            )
                        }
                    }
                    .padding()
                }
            } else if let selectedNoteId, isFolderSelected {
                VStack(spacing: 20) {
                    Image(systemName: "folder")
                        .font(.system(size: 64))
                        .foregroundColor(.yellow)

                    Text("Folder Selected")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Text("Folders cannot be edited. Select a note to edit its content.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("Folder: \(selectedNoteId)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "note.text")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text("No Note Selected")
                        .font(.title2)
                        .foregroundColor(.secondary)

                    Text("Select a note from the sidebar or create a new one")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onExitCommand {
            clearChunkSelection()
        }
        .onChange(of: selectedNoteId) { _ in
            syncFromStore()
        }
        .onChange(of: noteStore.currentContent) { _ in
            syncFromStore()
        }
        .task {
            syncFromStore()
        }
    }

    private func syncFromStore() {
        guard selectedNoteId == noteStore.selection else { return }
        let incoming = noteStore.currentContent
        guard incoming != noteContent else { return }
        noteContent = incoming
        chunks = makeChunks(from: incoming)
        activeChunkId = nil
        focusedChunkId = nil
    }

    private func handleTextChange(_ newText: String, noteId: String) {
        noteStore.updateDraft(newText)
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            _ = await Task.detached(priority: .userInitiated) { @MainActor in
                await noteStore.saveDraft()
            }.value
        }

        backlinksStore.search(
            noteId: noteId,
            text: newText,
            titleProvider: { noteStore.title(for: $0) }
        )
    }

    private func activateChunk(_ id: UUID) {
        activeChunkId = id
        focusedChunkId = id
    }

    private func clearChunkSelection() {
        activeChunkId = nil
        focusedChunkId = nil
    }

    private func binding(for chunk: EditorChunk) -> Binding<String> {
        Binding(
            get: { chunk.text },
            set: { newValue in
                guard let selectedNoteId else { return }
                guard let index = chunks.firstIndex(where: { $0.id == chunk.id }) else { return }
                chunks[index].text = newValue

                let fullText = joinChunks(chunks)
                noteContent = fullText
                handleTextChange(fullText, noteId: selectedNoteId)

                let newTexts = splitParagraphs(fullText, keepTrailingEmpty: true)
                let currentTexts = chunks.map(\.text)
                if newTexts != currentTexts {
                    let activeIndex: Int
                    if newTexts.count > currentTexts.count {
                        activeIndex = min(index + 1, max(0, newTexts.count - 1))
                    } else {
                        activeIndex = min(index, max(0, newTexts.count - 1))
                    }
                    chunks = newTexts.map { EditorChunk(text: $0) }
                    activeChunkId = chunks.isEmpty ? nil : chunks[activeIndex].id
                    focusedChunkId = activeChunkId
                }
            }
        )
    }

    private func makeChunks(from text: String) -> [EditorChunk] {
        let paragraphs = splitParagraphs(text)
        if paragraphs.isEmpty {
            return [EditorChunk(text: "")]
        }
        return paragraphs.map { EditorChunk(text: $0) }
    }

    private func splitParagraphs(_ text: String, keepTrailingEmpty: Bool = false) -> [String] {
        guard !text.isEmpty else { return [""] }
        let pattern = "\\n(?:[ \\t]*\\n)+"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        guard let regex else {
            let parts = text.components(separatedBy: "\n\n")
            return parts.isEmpty ? [""] : parts
        }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result: [String] = []
        var last = 0
        for match in matches {
            let range = NSRange(location: last, length: match.range.location - last)
            let part = ns.substring(with: range)
            if !part.isEmpty {
                result.append(part)
            }
            last = match.range.location + match.range.length
        }
        let tail = ns.substring(from: last)
        if !tail.isEmpty {
            result.append(tail)
        }
        if keepTrailingEmpty,
           text.range(of: "\\n(?:[ \\t]*\\n)+\\s*$", options: .regularExpression) != nil {
            result.append("")
        }
        return result.isEmpty ? [""] : result
    }

    private func joinChunks(_ chunks: [EditorChunk]) -> String {
        chunks.map(\.text).joined(separator: "\n\n")
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch noteStore.saveState {
        case .idle:
            Text("Saved")
                .font(.caption)
                .foregroundColor(.green)
        case .editing:
            Text("Editing...")
                .font(.caption)
                .foregroundColor(.orange)
        case .saving:
            Text("Saving...")
                .font(.caption)
                .foregroundColor(.blue)
        case .failed(let message):
            let lower = message.lowercased()
            if lower.contains("cancel") || lower.contains("canceled") {
                Text("Editing...")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Text("Error: \(message)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }
}

private struct EditorChunk: Identifiable, Equatable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

private struct ChunkRow: View {
    let chunk: EditorChunk
    let isActive: Bool
    let shouldFocus: Bool
    let onActivate: () -> Void
    let textBinding: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isActive {
                ChunkTextEditor(text: textBinding, shouldFocus: shouldFocus)
                    .frame(minHeight: 120)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
            } else {
                if chunk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Click to start writing…")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { onActivate() }
                } else {
                    Markdown(chunk.text)
                        .markdownTheme(.docC)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .onTapGesture { onActivate() }
                }
            }
        }
    }
}

private struct ChunkTextEditor: NSViewRepresentable {
    @Binding var text: String
    let shouldFocus: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let textView = ChunkNSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.backgroundColor = .textBackgroundColor
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        textView.delegate = context.coordinator
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? ChunkNSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        if shouldFocus, nsView.window?.firstResponder != textView {
            nsView.window?.makeFirstResponder(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ChunkTextEditor

        init(_ parent: ChunkTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

private final class ChunkNSTextView: NSTextView {
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.contains(.control) {
            insertNewline(nil)
            return
        }
        super.keyDown(with: event)
    }
}
