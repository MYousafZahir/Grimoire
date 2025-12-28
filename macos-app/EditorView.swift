import SwiftUI
import AppKit
import ImageIO
import MarkdownUI
import NaturalLanguage
import NetworkImage
import UniformTypeIdentifiers

struct EditorView: View {
    @EnvironmentObject private var noteStore: NoteStore
    @EnvironmentObject private var backlinksStore: BacklinksStore
    @Binding var selectedNoteId: String?

    @AppStorage("backendURL") private var backendURL: String = "http://127.0.0.1:8000"

    @State private var noteContent: String = ""
    @State private var showPreview: Bool = false
    @State private var saveTask: Task<Void, Never>?
    @State private var chunks: [EditorChunk] = []
    @State private var activeChunkId: UUID? = nil
    @FocusState private var focusedChunkId: UUID?
    @State private var selectionOverlayModel: SelectionOverlayModel = .empty
    @State private var pendingCursorPlacement: PendingCursorPlacement? = nil
    @State private var cursorOffsetInCleanedText: Int = 0
    @State private var lastActiveChunkForBacklinks: UUID? = nil
    @State private var chunkHeights: [UUID: CGFloat] = [:]
    @State private var highlightedChunkId: UUID? = nil
    @State private var contentNoteId: String? = nil
    @State private var imageUploadError: String? = nil

    private var isFolderSelected: Bool {
        guard let selectedNoteId else { return false }
        return noteStore.isFolder(id: selectedNoteId)
            || noteStore.currentNoteKind == .folder
    }

    private var resolvedBackendURL: URL? {
        URL(string: backendURL)
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

            if showPreview, selectedNoteId != nil, !isFolderSelected {
                ScrollView {
                    Markdown(markdownForRendering(noteContent), imageBaseURL: resolvedBackendURL)
                        .grimoireMarkdownStyle()
                        .textSelection(.enabled)
                        .padding()
                }
            } else if selectedNoteId != nil, !isFolderSelected {
                if activeChunkId == nil {
                    ScrollView {
                        ZStack(alignment: .topLeading) {
                            Markdown(markdownForRendering(noteContent), imageBaseURL: resolvedBackendURL)
                                .grimoireMarkdownStyle()
                                .allowsHitTesting(false)

                            SelectionTextOverlay(
                                attributedText: selectionOverlayModel.attributedText,
                                onEditSelectionIndex: { selectionIndex in
                                    handleRenderEditClick(selectionIndex)
                                }
                            )
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                        .padding()
                    }
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(chunks) { chunk in
                                    let isOnlyEmptyChunk = chunks.count == 1
                                        && chunk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    let (overlayText, overlayMapping) = clickOverlayForChunk(chunk.text)
                                ChunkRow(
                                    chunk: chunk,
                                    isActive: chunk.id == activeChunkId,
                                    isHighlighted: chunk.id == highlightedChunkId,
                                    shouldFocus: chunk.id == activeChunkId,
                                    showEmptyPlaceholder: isOnlyEmptyChunk,
                                    measuredHeight: heightBinding(for: chunk.id),
                                    requestedSelection: pendingSelectionRange(for: chunk),
                                    onSelectionApplied: { clearPendingCursorPlacementIfNeeded(chunk.id) },
                                    onActivate: { activateChunk(chunk.id) },
                                    overlayText: overlayText,
                                    overlayVisibleToMarkdown: overlayMapping,
                                    imageBaseURL: resolvedBackendURL,
                                    onActivateAtMarkdownIndex: { markdownIndex in
                                        activateChunkAtIndex(chunkId: chunk.id, markdownIndex: markdownIndex)
                                    },
                                    onExitCommand: clearChunkSelection,
                                    onMergeWithPrevious: { mergeChunkWithPrevious(chunk.id) },
                                    onCursorLocationChange: { location in
                                        updateCursorOffsetForChunk(chunkId: chunk.id, localUTF16Cursor: location)
                                    },
                                    onAutoChunk: { text, cursor in
                                        autoChunkIfNeeded(chunkId: chunk.id, newText: text, localUTF16Cursor: cursor)
                                    },
                                    onUploadImage: uploadImage,
                                    onUploadError: { message in imageUploadError = message },
                                    textBinding: binding(for: chunk)
                                )
                                    .id(chunk.id)
                                }
                            }
                            .padding()
                        }
                        .onAppear {
                            guard let activeChunkId else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                proxy.scrollTo(activeChunkId, anchor: .center)
                            }
                        }
                        .onChange(of: activeChunkId) { newValue in
                            guard let newValue else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                                proxy.scrollTo(newValue, anchor: .center)
                            }
                        }
                    }
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
        .alert("Image Upload Failed", isPresented: Binding(get: { imageUploadError != nil }, set: { if !$0 { imageUploadError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(imageUploadError ?? "")
        }
        .onChange(of: activeChunkId) { newValue in
            // Ensure the backlinks panel clears immediately when switching chunks,
            // including switches triggered by chunk splitting/merging.
            if newValue != lastActiveChunkForBacklinks, newValue != nil {
                backlinksStore.beginLoading(clearResults: true)
            }
            lastActiveChunkForBacklinks = newValue
        }
        .onExitCommand {
            clearChunkSelection()
        }
        .onChange(of: selectedNoteId) { _ in
            backlinksStore.clear()
            syncFromStore()
        }
        .onChange(of: noteStore.pendingReveal?.id) { _ in
            applyPendingRevealIfPossible()
        }
        .onChange(of: noteStore.isLoadingNote) { isLoading in
            if !isLoading {
                applyPendingRevealIfPossible()
            }
        }
        .onChange(of: noteStore.currentContent) { _ in
            syncFromStore()
        }
        .task {
            syncFromStore()
        }
    }

    private func uploadImage(data: Data, filename: String, mimeType: String?) async throws -> String {
        guard let baseURL = URL(string: backendURL) else {
            throw AttachmentRepositoryError.invalidURL
        }
        return try await HTTPAttachmentRepository(baseURL: baseURL).uploadImage(
            data: data,
            filename: filename,
            mimeType: mimeType
        )
    }

    private func syncFromStore() {
        guard selectedNoteId == noteStore.selection else { return }
        let incoming = noteStore.currentContent
        guard incoming != noteContent else { return }
        noteContent = incoming
        contentNoteId = selectedNoteId
        chunks = makeChunks(from: incoming)
        activeChunkId = nil
        focusedChunkId = nil
        pendingCursorPlacement = nil
        cursorOffsetInCleanedText = 0
        highlightedChunkId = nil
        selectionOverlayModel = buildSelectionOverlayModel(from: chunks)
        applyPendingRevealIfPossible()

        if let noteId = selectedNoteId, noteStore.currentNoteKind == .note {
            let cleaned = stripChunkMarkers(incoming)
            backlinksStore.search(
                noteId: noteId,
                text: cleaned,
                cursorOffset: cursorOffsetInCleanedText,
                titleProvider: { noteStore.title(for: $0) }
            )
        }
    }

    private func applyPendingRevealIfPossible() {
        guard let request = noteStore.pendingReveal else { return }
        guard request.noteId == selectedNoteId else { return }
        // Wait until the newly-selected note has finished loading; during the loading window,
        // `selectedNoteId` may already be the new note while `currentContent` is still the old note.
        guard noteStore.loadedNoteId == request.noteId else { return }
        // Ensure our local `chunks`/`noteContent` match the same note before attempting to resolve
        // offsets/chunk ids. Otherwise this can apply the reveal to the previous note's chunks and
        // then get wiped by `syncFromStore`, requiring a second click.
        guard contentNoteId == request.noteId else { return }
        guard noteStore.currentNoteKind == .note else { return }
        guard !chunks.isEmpty else { return }

        let targetChunkId = resolveTargetChunkId(for: request)
        guard let targetChunkId else { return }
        noteStore.clearReveal(requestId: request.id)
        // Move into chunk-editing view (so we can scroll precisely), then highlight until the
        // user clicks away to a different chunk.
        activateChunk(targetChunkId)
        withAnimation(.easeInOut(duration: 0.12)) {
            highlightedChunkId = targetChunkId
        }
    }

    private func clearHighlight() {
        highlightedChunkId = nil
    }

    private func resolveTargetChunkId(for request: NoteRevealRequest) -> UUID? {
        if let contextChunkId = request.contextChunkId,
           let parsed = parseContextChunkId(contextChunkId) {
            // Offsets are measured against the backend's "cleaned" note text
            // (chunk markers removed, separators replaced with blank lines).
            let start = parsed.start
            let end = max(parsed.end, start)
            if let match = chunkIdOverlappingCleanRange(start: start, end: end) {
                return match
            }
        }

        // Fallback: try matching excerpt text to a chunk.
        if let excerpt = request.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !excerpt.isEmpty {
            let probe = String(excerpt.prefix(120))
            if let chunk = chunks.first(where: { $0.text.localizedCaseInsensitiveContains(probe) }) {
                return chunk.id
            }
        }
        return nil
    }

    private func parseContextChunkId(_ chunkId: String) -> (noteId: String, start: Int, end: Int, idx: Int?)? {
        let parts = chunkId.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 4 else { return nil }
        let startPart = parts[parts.count - 3]
        let endPart = parts[parts.count - 2]
        let idxPart = parts[parts.count - 1]
        guard let start = Int(startPart), let end = Int(endPart) else { return nil }
        let noteId = parts[..<(parts.count - 3)].joined(separator: ":")
        let idx = Int(idxPart)
        return (noteId: noteId, start: start, end: end, idx: idx)
    }

    private func chunkIdOverlappingCleanRange(start: Int, end: Int) -> UUID? {
        let separatorCount = "\n\n".unicodeScalars.count
        var cursor = 0
        var best: (id: UUID, overlap: Int)? = nil

        for (i, chunk) in chunks.enumerated() {
            let chunkStart = cursor
            let chunkEnd = cursor + chunk.text.unicodeScalars.count
            let overlap = max(0, min(chunkEnd, end) - max(chunkStart, start))
            if overlap > 0 {
                if best == nil || overlap > best!.overlap {
                    best = (id: chunk.id, overlap: overlap)
                }
            } else if start >= chunkStart && start <= chunkEnd {
                // Touching range or empty chunk: treat as a weak match.
                if best == nil {
                    best = (id: chunk.id, overlap: 0)
                }
            }

            cursor = chunkEnd
            if i != (chunks.count - 1) {
                cursor += separatorCount
            }
        }
        return best?.id
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
            text: stripChunkMarkers(newText),
            cursorOffset: cursorOffsetInCleanedText,
            titleProvider: { noteStore.title(for: $0) }
        )
    }

    private func activateChunk(_ id: UUID) {
        if let highlightedChunkId, highlightedChunkId != id {
            clearHighlight()
        }
        if activeChunkId != id {
            backlinksStore.beginLoading(clearResults: true)
        }
        activeChunkId = id
        focusedChunkId = id
        if pendingCursorPlacement?.chunkId != id {
            updateCursorOffsetForChunk(chunkId: id, localUTF16Cursor: 0)
        }
    }

    private func activateChunkAtIndex(chunkId: UUID, markdownIndex: Int) {
        pendingCursorPlacement = PendingCursorPlacement(chunkId: chunkId, markdownIndex: markdownIndex)
        updateCursorOffsetForChunk(chunkId: chunkId, localUTF16Cursor: markdownIndex)
        activateChunk(chunkId)
    }

    private func handleRenderEditClick(_ selectionIndex: Int) {
        guard let (chunkId, markdownIndex) = selectionOverlayModel.hitTest(selectionIndex) else { return }
        activateChunkAtIndex(chunkId: chunkId, markdownIndex: markdownIndex)
    }

    private func updateCursorOffsetForChunk(chunkId: UUID, localUTF16Cursor: Int) {
        guard let chunkIndex = chunks.firstIndex(where: { $0.id == chunkId }) else { return }
        let separatorScalarCount = "\n\n".unicodeScalars.count

        var offset = 0
        if chunkIndex > 0 {
            for i in 0..<chunkIndex {
                offset += chunks[i].text.unicodeScalars.count
                offset += separatorScalarCount
            }
        }

        let chunkText = chunks[chunkIndex].text
        let clampedUTF16 = max(0, min(localUTF16Cursor, (chunkText as NSString).length))
        let utf16Index = String.Index(utf16Offset: clampedUTF16, in: chunkText)
        let scalarIndex = utf16Index.samePosition(in: chunkText.unicodeScalars) ?? chunkText.unicodeScalars.endIndex
        let localScalar = chunkText.unicodeScalars.distance(from: chunkText.unicodeScalars.startIndex, to: scalarIndex)

        cursorOffsetInCleanedText = max(0, offset + localScalar)

        guard let noteId = selectedNoteId, noteStore.currentNoteKind == .note else { return }
        backlinksStore.search(
            noteId: noteId,
            text: stripChunkMarkers(noteContent),
            cursorOffset: cursorOffsetInCleanedText,
            titleProvider: { noteStore.title(for: $0) }
        )
    }

    private func pendingSelectionRange(for chunk: EditorChunk) -> NSRange? {
        guard let pendingCursorPlacement else { return nil }
        guard pendingCursorPlacement.chunkId == chunk.id else { return nil }
        let length = (chunk.text as NSString).length
        let clamped = max(0, min(pendingCursorPlacement.markdownIndex, length))
        return NSRange(location: clamped, length: 0)
    }

    private func heightBinding(for chunkId: UUID) -> Binding<CGFloat> {
        Binding(
            get: { chunkHeights[chunkId] ?? 120 },
            set: { chunkHeights[chunkId] = $0 }
        )
    }

    private func clearPendingCursorPlacementIfNeeded(_ chunkId: UUID) {
        guard pendingCursorPlacement?.chunkId == chunkId else { return }
        pendingCursorPlacement = nil
    }

    private func tokenCount(_ text: String) -> Int {
        // Approximate tokens as whitespace-delimited terms; good enough for UI chunk sizing.
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private func splitIntoSentenceSpans(_ text: String) -> [String] {
        let trimmed = text
        if trimmed.isEmpty { return [""] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = trimmed

        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: trimmed.startIndex..<trimmed.endIndex) { range, _ in
            ranges.append(range)
            return true
        }
        if ranges.isEmpty { return [trimmed] }

        var spans: [String] = []
        for i in 0..<ranges.count {
            let start = ranges[i].lowerBound
            let end = (i + 1 < ranges.count) ? ranges[i + 1].lowerBound : trimmed.endIndex
            spans.append(String(trimmed[start..<end]))
        }
        return spans
    }

    private func packSpansIntoChunks(_ spans: [String], minTokens: Int, targetTokens: Int, maxTokens: Int) -> [String] {
        var chunksOut: [String] = []
        var current = ""
        var currentTokens = 0

        func flushCurrent() {
            let part = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty || chunksOut.isEmpty {
                chunksOut.append(part)
            }
            current = ""
            currentTokens = 0
        }

        for span in spans {
            let spanText = span
            let spanTokens = tokenCount(spanText)
            if currentTokens == 0 {
                current = spanText
                currentTokens = spanTokens
                if currentTokens >= maxTokens {
                    flushCurrent()
                }
                continue
            }

            let tentativeTokens = currentTokens + spanTokens
            // Prefer to cut near the target once we're past minTokens.
            if currentTokens >= minTokens && tentativeTokens > targetTokens {
                flushCurrent()
                current = spanText
                currentTokens = spanTokens
                if currentTokens >= maxTokens {
                    flushCurrent()
                }
                continue
            }

            if tentativeTokens > maxTokens {
                flushCurrent()
                current = spanText
                currentTokens = spanTokens
                if currentTokens >= maxTokens {
                    flushCurrent()
                }
                continue
            }

            current += spanText
            currentTokens = tentativeTokens
        }

        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            flushCurrent()
        }
        return chunksOut.isEmpty ? [""] : chunksOut
    }

    private func autoChunkIfNeeded(chunkId: UUID, newText: String, localUTF16Cursor: Int) {
        // Hard cap: when exceeded, split into ~sidebar-sized chunks.
        let hardMax = 220
        guard tokenCount(newText) > hardMax else { return }

        let minTokens = 80
        let targetTokens = 140

        let spans = splitIntoSentenceSpans(newText)
        let parts = packSpansIntoChunks(spans, minTokens: minTokens, targetTokens: targetTokens, maxTokens: hardMax)
        guard parts.count > 1 else { return }

        guard let selectedNoteId else { return }
        guard let index = chunks.firstIndex(where: { $0.id == chunkId }) else { return }

        // Map cursor into the new chunk parts by UTF-16 offset.
        let clampedCursor = max(0, min(localUTF16Cursor, (newText as NSString).length))
        var running = 0
        var targetPartIndex = 0
        var targetLocalCursor = 0
        for (i, part) in parts.enumerated() {
            let len = (part as NSString).length
            if clampedCursor <= running + len {
                targetPartIndex = i
                targetLocalCursor = max(0, clampedCursor - running)
                break
            }
            running += len
        }

        // Replace current chunk with packed parts, keeping the original id for the part
        // that contains the cursor so focus remains stable.
        chunks.remove(at: index)
        var inserted: [EditorChunk] = []
        for (i, part) in parts.enumerated() {
            if i == targetPartIndex {
                inserted.append(EditorChunk(id: chunkId, text: part))
            } else {
                inserted.append(EditorChunk(text: part))
            }
        }
        chunks.insert(contentsOf: inserted, at: index)

        noteContent = joinChunks(chunks)
        handleTextChange(noteContent, noteId: selectedNoteId)

        activeChunkId = chunkId
        focusedChunkId = chunkId
        pendingCursorPlacement = PendingCursorPlacement(chunkId: chunkId, markdownIndex: targetLocalCursor)
    }

    private func buildSelectionOverlayModel(from chunks: [EditorChunk]) -> SelectionOverlayModel {
        guard !chunks.isEmpty else { return .empty }

        let bodyFontSize = NSFont.systemFontSize
        let font = NSFont.systemFont(ofSize: bodyFontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = bodyFontSize * 0.235295
        paragraphStyle.paragraphSpacing = bodyFontSize * 0.8

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.clear,
        ]

        let document = NSMutableAttributedString()
        var chunkModels: [SelectionChunkModel] = []

        for (index, chunk) in chunks.enumerated() {
            let (visible, visibleToMarkdown) = markdownToVisibleWithMapping(chunk.text)
            let attributed = NSAttributedString(string: visible, attributes: baseAttributes)

            let start = document.length
            document.append(attributed)
            let range = NSRange(location: start, length: attributed.length)

            chunkModels.append(
                SelectionChunkModel(id: chunk.id, range: range, visibleToMarkdown: visibleToMarkdown)
            )

            if index != chunks.count - 1 {
                document.append(NSAttributedString(string: "\n", attributes: baseAttributes))
            }
        }

        return SelectionOverlayModel(attributedText: document, chunks: chunkModels)
    }

    private func clickOverlayForChunk(_ markdown: String) -> (NSAttributedString, [Int]) {
        let bodyFontSize = NSFont.systemFontSize
        let font = NSFont.systemFont(ofSize: bodyFontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping
        paragraphStyle.lineSpacing = bodyFontSize * 0.235295
        paragraphStyle.paragraphSpacing = bodyFontSize * 0.8

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: NSColor.clear,
        ]

        let (visible, visibleToMarkdown) = markdownToVisibleWithMapping(markdown)
        let attributed = NSAttributedString(string: visible, attributes: baseAttributes)
        return (attributed, visibleToMarkdown)
    }

    private func markdownToVisibleWithMapping(_ markdown: String) -> (String, [Int]) {
        let md = markdown as NSString
        let mdLength = md.length

        var result = ""
        var mapping: [Int] = [0]

        var index = 0
        var atLineStart = true
        var inCodeSpan = false
        var inCodeBlock = false

        func appendVisible(_ s: String, mdAdvanceTo: Int) {
            result += s
            let utf16Count = (s as NSString).length
            if utf16Count > 0 {
                mapping.append(contentsOf: repeatElement(mdAdvanceTo, count: utf16Count))
            }
        }

        func peekASCII(_ offset: Int) -> UInt16? {
            let i = index + offset
            guard i >= 0, i < mdLength else { return nil }
            return md.character(at: i)
        }

        while index < mdLength {
            let lineStartIndex = index

            if atLineStart {
                if peekASCII(0) == 0x60, peekASCII(1) == 0x60, peekASCII(2) == 0x60 {
                    // Skip fence line and toggle code block mode.
                    inCodeBlock.toggle()
                    let lineRange = md.lineRange(for: NSRange(location: index, length: 0))
                    index = lineRange.location + lineRange.length
                    atLineStart = true
                    continue
                }

                // Skip headings like "### "
                if peekASCII(0) == 0x23 {
                    var i = index
                    var count = 0
                    while i < mdLength, md.character(at: i) == 0x23, count < 6 {
                        count += 1
                        i += 1
                    }
                    if i < mdLength, md.character(at: i) == 0x20 {
                        index = i + 1
                        atLineStart = false
                        continue
                    }
                }

                // Skip blockquote marker "> "
                if peekASCII(0) == 0x3E {
                    var i = index + 1
                    if i < mdLength, md.character(at: i) == 0x20 { i += 1 }
                    index = i
                    atLineStart = false
                    continue
                }

                // Skip unordered list markers "- ", "* ", "+ "
                if let c = peekASCII(0), (c == 0x2D || c == 0x2A || c == 0x2B),
                   peekASCII(1) == 0x20 {
                    index += 2
                    atLineStart = false
                    continue
                }

                // Skip ordered list markers like "1. "
                if let c0 = peekASCII(0), c0 >= 0x30, c0 <= 0x39 {
                    var i = index
                    while i < mdLength {
                        let c = md.character(at: i)
                        if c < 0x30 || c > 0x39 { break }
                        i += 1
                    }
                    if i + 1 < mdLength, md.character(at: i) == 0x2E, md.character(at: i + 1) == 0x20 {
                        index = i + 2
                        atLineStart = false
                        continue
                    }
                }
            }

            let ch = md.character(at: index)

            // Newline handling: preserve paragraph breaks, treat soft breaks as spaces.
            if ch == 0x0A {
                let next = peekASCII(1)
                if inCodeBlock {
                    appendVisible("\n", mdAdvanceTo: index + 1)
                } else if next == 0x0A {
                    // Paragraph break: collapse consecutive newlines into a single paragraph break.
                    var j = index
                    while j < mdLength, md.character(at: j) == 0x0A {
                        j += 1
                    }
                    appendVisible("\n", mdAdvanceTo: j)
                    index = j
                    atLineStart = true
                    continue
                } else {
                    // Hard break: two spaces before newline.
                    let prev1 = (index - 1 >= 0) ? md.character(at: index - 1) : 0
                    let prev2 = (index - 2 >= 0) ? md.character(at: index - 2) : 0
                    if prev1 == 0x20, prev2 == 0x20 {
                        appendVisible("\n", mdAdvanceTo: index + 1)
                    } else {
                        appendVisible(" ", mdAdvanceTo: index + 1)
                    }
                }
                index += 1
                atLineStart = true
                continue
            }

            atLineStart = false

            if !inCodeBlock {
                // Inline code span markers.
                if ch == 0x60 {
                    inCodeSpan.toggle()
                    index += 1
                    continue
                }

                // Escape: skip backslash, keep next char.
                if ch == 0x5C, index + 1 < mdLength {
                    let nextRange = md.rangeOfComposedCharacterSequence(at: index + 1)
                    let next = md.substring(with: nextRange)
                    appendVisible(next, mdAdvanceTo: nextRange.location + nextRange.length)
                    index = nextRange.location + nextRange.length
                    continue
                }

                if !inCodeSpan {
                    // Images: skip leading '!'.
                    if ch == 0x21, peekASCII(1) == 0x5B {
                        index += 1
                        continue
                    }

                    // Links: skip brackets and destinations, keep link text.
                    if ch == 0x5B { // '['
                        index += 1
                        continue
                    }
                    if ch == 0x5D { // ']'
                        if peekASCII(1) == 0x28 { // '('
                            index += 2
                            var depth = 1
                            while index < mdLength, depth > 0 {
                                let c = md.character(at: index)
                                if c == 0x28 { depth += 1 }
                                if c == 0x29 { depth -= 1 }
                                index += 1
                            }
                            continue
                        } else {
                            index += 1
                            continue
                        }
                    }

                    // Emphasis/strikethrough markers: skip.
                    if ch == 0x2A || ch == 0x5F || ch == 0x7E {
                        index += 1
                        continue
                    }
                }
            }

            let composedRange = md.rangeOfComposedCharacterSequence(at: index)
            let s = md.substring(with: composedRange)
            appendVisible(s, mdAdvanceTo: composedRange.location + composedRange.length)
            index = composedRange.location + composedRange.length

            // If we got stuck on a zero-length range, advance to avoid infinite loops.
            if index == lineStartIndex {
                index += 1
            }
        }

        if mapping.count != (result as NSString).length + 1 {
            // Ensure the mapping is always indexable for insertion points.
            mapping = Array(mapping.prefix((result as NSString).length + 1))
            while mapping.count < (result as NSString).length + 1 {
                mapping.append(mdLength)
            }
        }

        return (result, mapping)
    }

    private func clearChunkSelection() {
        activeChunkId = nil
        focusedChunkId = nil
        clearHighlight()
        compactEmptyChunksIfNeeded()
        pendingCursorPlacement = nil
        selectionOverlayModel = buildSelectionOverlayModel(from: chunks)
    }

    private func compactEmptyChunksIfNeeded() {
        let hasNonEmpty = chunks.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !hasNonEmpty {
            if chunks.count != 1 || !(chunks.first?.text.isEmpty ?? true) {
                chunks = [EditorChunk(text: "")]
                noteContent = joinChunks(chunks)
                if let noteId = selectedNoteId {
                    handleTextChange(noteContent, noteId: noteId)
                }
            }
            return
        }
        // Keep empty chunks: they represent intentional blank-line spacing.
    }

    private func mergeChunkWithPrevious(_ chunkId: UUID) {
        guard let selectedNoteId else { return }
        guard let index = chunks.firstIndex(where: { $0.id == chunkId }) else { return }
        guard index > 0 else { return }

        let prevIndex = index - 1
        var prevText = chunks[prevIndex].text
        let currText = chunks[index].text

        if !prevText.isEmpty && !currText.isEmpty {
            if !prevText.hasSuffix("\n") {
                prevText += "\n"
            }
        }
        prevText += currText

        chunks[prevIndex].text = prevText
        chunks.remove(at: index)

        let fullText = joinChunks(chunks)
        noteContent = fullText
        handleTextChange(fullText, noteId: selectedNoteId)

        activeChunkId = chunks[prevIndex].id
        focusedChunkId = activeChunkId
    }

    private func binding(for chunk: EditorChunk) -> Binding<String> {
        Binding(
            get: { chunks.first(where: { $0.id == chunk.id })?.text ?? "" },
            set: { newValue in
                guard let selectedNoteId else { return }
                guard let index = chunks.firstIndex(where: { $0.id == chunk.id }) else { return }
                chunks[index].text = newValue

                let fullText = joinChunks(chunks)
                noteContent = fullText
                handleTextChange(fullText, noteId: selectedNoteId)

                let newTexts = splitChunks(fullText, allowLegacyBlankSplit: false)
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
        let paragraphs = splitChunks(text)
        if paragraphs.isEmpty {
            return [EditorChunk(text: "")]
        }
        return paragraphs.map { EditorChunk(text: $0) }
    }

    private func splitChunks(_ text: String, allowLegacyBlankSplit: Bool = true) -> [String] {
        guard !text.isEmpty else { return [""] }

        if text.contains(grimoireChunkMarker) {
            let parts = text.components(separatedBy: grimoireChunkSeparator)
            return parts.isEmpty ? [""] : parts
        }

        if !allowLegacyBlankSplit {
            return [text]
        }

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
            let part = ns.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            result.append(part)
            last = match.range.location + match.range.length
        }
        let tail = ns.substring(from: last).trimmingCharacters(in: .whitespacesAndNewlines)
        result.append(tail)

        return result.isEmpty ? [""] : result
    }

    private func joinChunks(_ chunks: [EditorChunk]) -> String {
        chunks.map(\.text).joined(separator: grimoireChunkSeparator)
    }

    private func stripChunkMarkers(_ text: String) -> String {
        text
            .replacingOccurrences(of: grimoireChunkSeparator, with: "\n\n")
            .replacingOccurrences(of: grimoireChunkMarker, with: "")
    }

    private func markdownForRendering(_ text: String) -> String {
        let cleaned = stripChunkMarkers(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? " " : cleaned
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
    let isHighlighted: Bool
    let shouldFocus: Bool
    let showEmptyPlaceholder: Bool
    let measuredHeight: Binding<CGFloat>
    let requestedSelection: NSRange?
    let onSelectionApplied: () -> Void
    let onActivate: () -> Void
    let overlayText: NSAttributedString
    let overlayVisibleToMarkdown: [Int]
    let imageBaseURL: URL?
    let onActivateAtMarkdownIndex: (Int) -> Void
    let onExitCommand: () -> Void
    let onMergeWithPrevious: () -> Void
    let onCursorLocationChange: (Int) -> Void
    let onAutoChunk: (String, Int) -> Void
    let onUploadImage: (Data, String, String?) async throws -> String
    let onUploadError: (String) -> Void
    let textBinding: Binding<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isActive {
                ChunkTextEditor(
                    text: textBinding,
                    shouldFocus: shouldFocus,
                    requestedSelection: requestedSelection,
                    onSelectionApplied: onSelectionApplied,
                    onCursorLocationChange: onCursorLocationChange,
                    onExitCommand: onExitCommand,
                    onMergeWithPrevious: onMergeWithPrevious,
                    measuredHeight: measuredHeight,
                    onAutoChunk: onAutoChunk,
                    onUploadImage: onUploadImage,
                    onUploadError: onUploadError
                )
                    .frame(minHeight: 44, idealHeight: measuredHeight.wrappedValue, maxHeight: measuredHeight.wrappedValue)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(6)
            } else {
                if chunk.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Group {
                        if showEmptyPlaceholder {
                            Text("Click to start writing…")
                                .font(.body)
                                .foregroundColor(.secondary)
                        } else {
                            Color.clear
                                .frame(height: 18)
                        }
                    }
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onActivateAtMarkdownIndex(0)
                    }
                } else {
                    Markdown(chunk.text, imageBaseURL: imageBaseURL)
                        .grimoireMarkdownStyle()
                        .padding(.vertical, 2)
                        // Fallback: if the overlay ever fails to receive the click, still switch
                        // chunks immediately (cursor will default to start of chunk).
                        .onTapGesture {
                            onActivateAtMarkdownIndex(0)
                        }
                        // Overlay matches the Markdown view's exact size, so hit-testing is reliable.
                        .overlay(alignment: .topLeading) {
                            SelectionTextOverlay(
                                attributedText: overlayText,
                                onEditSelectionIndex: { selectionIndex in
                                    let idx = max(0, min(selectionIndex, max(0, overlayVisibleToMarkdown.count - 1)))
                                    onActivateAtMarkdownIndex(overlayVisibleToMarkdown[idx])
                                }
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .contentShape(Rectangle())
                        }
                }
            }
        }
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHighlighted ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHighlighted ? Color.accentColor.opacity(0.80) : Color.clear, lineWidth: 2)
        )
        .animation(.easeInOut(duration: 0.15), value: isHighlighted)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isHighlighted ? Color.accentColor : Color.clear)
                .frame(width: 4)
                .padding(.vertical, 6)
                .padding(.leading, 2)
        }
        .simultaneousGesture(
            TapGesture().onEnded {
                if !isActive { onActivate() }
            },
            including: .subviews
        )
    }
}

private struct ChunkTextEditor: NSViewRepresentable {
    @Binding var text: String
    let shouldFocus: Bool
    let requestedSelection: NSRange?
    let onSelectionApplied: () -> Void
    let onCursorLocationChange: (Int) -> Void
    let onExitCommand: () -> Void
    let onMergeWithPrevious: () -> Void
    @Binding var measuredHeight: CGFloat
    let onAutoChunk: (String, Int) -> Void
    let onUploadImage: (Data, String, String?) async throws -> String
    let onUploadError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> ChunkEditorContainerView {
        let container = ChunkEditorContainerView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let textView = ChunkNSTextView()
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = []
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainer?.widthTracksTextView = true
        // Allow the text container to grow vertically so we can measure full content height.
        // If this tracks the view height, `usedRect` will be capped to the current frame and
        // the chunk will never expand as you add lines.
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.onExitCommand = onExitCommand
        textView.chunkSeparator = grimoireChunkSeparator
        textView.wantsInitialFocus = shouldFocus
        textView.onMergeWithPrevious = onMergeWithPrevious
        textView.delegate = context.coordinator
        textView.string = text
        textView.pendingSelection = requestedSelection
        textView.onHeightChange = { height in
            if abs(measuredHeight - height) > 0.5 {
                measuredHeight = height
            }
        }
        textView.onAutoChunk = onAutoChunk
        textView.uploadImage = onUploadImage
        textView.onUploadError = onUploadError
        textView.registerForDraggedTypes([.fileURL, .tiff, .png, .init("public.jpeg"), .init("public.png")])

        container.attach(textView: textView)
        return container
    }

    func updateNSView(_ nsView: ChunkEditorContainerView, context: Context) {
        guard let textView = nsView.textView else { return }
        textView.uploadImage = onUploadImage
        textView.onUploadError = onUploadError
        // While the user is actively editing (focused), do not overwrite the NSTextView's
        // content from SwiftUI state updates; doing so can reset the insertion point and
        // cause "caret jumps to end" while typing.
        let isFocused = (nsView.window?.firstResponder === textView)
        if textView.string != text, !(shouldFocus && isFocused) {
            let hadSelection = textView.selectedRange()
            textView.string = text
            if requestedSelection == nil {
                let length = (textView.string as NSString).length
                let clampedLoc = max(0, min(hadSelection.location, length))
                let clampedLen = max(0, min(hadSelection.length, length - clampedLoc))
                textView.setSelectedRange(NSRange(location: clampedLoc, length: clampedLen))
            }
        }
        textView.wantsInitialFocus = shouldFocus
        textView.pendingSelection = requestedSelection
        // Hand off cursor placement to the NSTextView immediately so SwiftUI doesn't
        // keep re-sending the same requestedSelection during subsequent renders.
        if requestedSelection != nil {
            onSelectionApplied()
        }
        if shouldFocus {
            // Apply focus/selection synchronously whenever possible to avoid a race where
            // the first keystroke lands at the default insertion point (often the end).
            if let window = nsView.window, window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }

            if let requestedSelection = requestedSelection {
                let length = (textView.string as NSString).length
                let clamped = max(0, min(requestedSelection.location, length))
                if textView.lastAppliedSelectionLocation != clamped {
                    textView.lastAppliedSelectionLocation = clamped
                    let range = NSRange(location: clamped, length: 0)
                    textView.setSelectedRange(range)
                    textView.scrollRangeToVisible(range)
                    onSelectionApplied()
                }
            }

            // If we don't have a window yet, try again shortly.
            if nsView.window == nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    if let window = nsView.window, window.firstResponder !== textView {
                        window.makeFirstResponder(textView)
                    }
                    if let requestedSelection = requestedSelection {
                        let length = (textView.string as NSString).length
                        let clamped = max(0, min(requestedSelection.location, length))
                        if textView.lastAppliedSelectionLocation != clamped {
                            textView.lastAppliedSelectionLocation = clamped
                            let range = NSRange(location: clamped, length: 0)
                            textView.setSelectedRange(range)
                            textView.scrollRangeToVisible(range)
                            onSelectionApplied()
                        }
                    }
                }
            }
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
            if let tv = textView as? ChunkNSTextView {
                tv.reportHeight()
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.onCursorLocationChange(textView.selectedRange().location)
        }
    }
}

private final class ChunkNSTextView: NSTextView {
    var onExitCommand: (() -> Void)?
    var chunkSeparator: String = grimoireChunkSeparator
    var wantsInitialFocus: Bool = false
    var onMergeWithPrevious: (() -> Void)?
    var pendingSelection: NSRange?
    var lastAppliedSelectionLocation: Int?
    var onHeightChange: ((CGFloat) -> Void)?
    var onAutoChunk: ((String, Int) -> Void)?
    var uploadImage: ((Data, String, String?) async throws -> String)?
    var onUploadError: ((String) -> Void)?
    private var isRequestingAutoChunk: Bool = false
    private var isUploadingImage: Bool = false

    private func applyPendingSelectionIfNeeded() {
        guard let pendingSelection else { return }
        let length = (string as NSString).length
        let clamped = max(0, min(pendingSelection.location, length))
        guard lastAppliedSelectionLocation != clamped else { return }
        lastAppliedSelectionLocation = clamped
        let range = NSRange(location: clamped, length: 0)
        setSelectedRange(range)
        scrollRangeToVisible(range)
        self.pendingSelection = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsInitialFocus, let window, window.firstResponder !== self {
            window.makeFirstResponder(self)
        }
        applyPendingSelectionIfNeeded()
        reportHeight()
    }

    override func cancelOperation(_ sender: Any?) {
        onExitCommand?()
    }

    override func keyDown(with event: NSEvent) {
        // Critical: ensure the clicked insertion point is applied before the first
        // keystroke is handled; otherwise the first character can be inserted at
        // the default caret location (often end-of-chunk), then the caret jumps.
        applyPendingSelectionIfNeeded()

        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers?.lowercased() {
            if chars == "v" {
                // NSTextView can disable paste for non-rich text when the clipboard doesn't
                // contain a string; still allow Cmd+V to upload+insert images.
                if event.modifierFlags.contains(.shift) {
                    pasteAsPlainText(nil)
                } else {
                    paste(nil)
                }
                return
            }
            if chars == "z" {
                if event.modifierFlags.contains(.shift) {
                    undoManager?.redo()
                } else {
                    undoManager?.undo()
                }
                return
            }
            if chars == "y" {
                undoManager?.redo()
                return
            }
        }

        if event.keyCode == 51 {
            let range = selectedRange()
            if range.location == 0, range.length == 0 {
                onMergeWithPrevious?()
                return
            }
        }

        if event.keyCode == 53 {
            onExitCommand?()
            return
        }
        if event.keyCode == 36, event.modifierFlags.contains(.shift) {
            insertChunkSeparator()
            return
        }
        super.keyDown(with: event)
        requestAutoChunkIfNeeded()
    }

    private func insertChunkSeparator() {
        let range = selectedRange()
        if let textStorage {
            textStorage.replaceCharacters(in: range, with: chunkSeparator)
            didChangeText()
        } else {
            insertText(chunkSeparator, replacementRange: range)
        }
    }

    func reportHeight() {
        guard let layoutManager, let textContainer else { return }
        let length = (string as NSString).length
        if length > 0 {
            layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: length))
        } else {
            layoutManager.ensureLayout(for: textContainer)
        }
        let used = layoutManager.usedRect(for: textContainer)
        let height = used.height + textContainerInset.height * 2 + 10
        onHeightChange?(max(44, height))
    }

    private func requestAutoChunkIfNeeded() {
        guard !isRequestingAutoChunk else { return }
        let hardMax = 220
        let tokens = string.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
        guard tokens > hardMax else { return }
        isRequestingAutoChunk = true
        let cursor = selectedRange().location
        let snapshot = string
        DispatchQueue.main.async { [weak self] in
            self?.onAutoChunk?(snapshot, cursor)
            self?.isRequestingAutoChunk = false
        }
    }

    override func paste(_ sender: Any?) {
        if handlePasteboardImage(NSPasteboard.general) {
            return
        }
        super.paste(sender)
        reportHeight()
        requestAutoChunkIfNeeded()
    }

    override func pasteAsPlainText(_ sender: Any?) {
        if handlePasteboardImage(NSPasteboard.general) {
            return
        }
        super.pasteAsPlainText(sender)
        reportHeight()
        requestAutoChunkIfNeeded()
    }

    override func pasteAsRichText(_ sender: Any?) {
        if handlePasteboardImage(NSPasteboard.general) {
            return
        }
        super.pasteAsRichText(sender)
        reportHeight()
        requestAutoChunkIfNeeded()
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(paste(_:)) || selector == #selector(pasteAsPlainText(_:)) {
            paste(nil)
            return
        }
        super.doCommand(by: selector)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if handlePasteboardImage(sender.draggingPasteboard) {
            return true
        }
        return super.performDragOperation(sender)
    }

    private func handlePasteboardImage(_ pasteboard: NSPasteboard) -> Bool {
        if let extracted = PasteboardImageExtractor.extract(from: pasteboard) {
            uploadAndInsert(data: extracted.data, filename: extracted.filename, mimeType: extracted.mimeType)
            return true
        }
        if pasteboardProbablyContainsImage(pasteboard) {
            onUploadError?("An image was detected on the clipboard, but Grimoire couldn’t read the image bytes.")
            return true
        }
        return false
    }

    private func pasteboardProbablyContainsImage(_ pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadItem(withDataConformingToTypes: [UTType.image.identifier]) {
            return true
        }
        if let items = pasteboard.pasteboardItems {
            for item in items {
                for type in item.types {
                    if let ut = UTType(type.rawValue), ut.conforms(to: .image) {
                        return true
                    }
                }
            }
        }
        return false
    }

    private func uploadAndInsert(data: Data, filename: String, mimeType: String?) {
        guard let uploadImage else {
            onUploadError?("Image upload is not configured.")
            return
        }
        isUploadingImage = true
        let insertionRange = selectedRange()

        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isUploadingImage = false }

            do {
                let urlPath = try await uploadImage(data, filename, mimeType)
                self.applyPendingSelectionIfNeeded()
                self.insertMarkdownImage(urlPath: urlPath, preferredRange: insertionRange)
            } catch {
                self.onUploadError?(error.localizedDescription)
            }
        }
    }

    private func insertMarkdownImage(urlPath: String, preferredRange: NSRange) {
        let current = string as NSString
        let length = current.length
        let loc = max(0, min(preferredRange.location, length))
        let range = NSRange(location: loc, length: 0)

        let beforeChar = (loc > 0) ? current.substring(with: NSRange(location: loc - 1, length: 1)) : ""
        let afterChar = (loc < length) ? current.substring(with: NSRange(location: loc, length: 1)) : ""

        let leading = (loc > 0 && beforeChar != "\n") ? "\n\n" : ""
        let trailing: String
        if loc == length {
            trailing = "\n"
        } else {
            trailing = (afterChar != "\n") ? "\n\n" : "\n"
        }

        let markdown = "\(leading)![](\(urlPath))\(trailing)"

        if let textStorage {
            textStorage.replaceCharacters(in: range, with: markdown)
            didChangeText()
        } else {
            insertText(markdown, replacementRange: range)
        }

        let newLoc = min(loc + (markdown as NSString).length, (string as NSString).length)
        setSelectedRange(NSRange(location: newLoc, length: 0))
        reportHeight()
        requestAutoChunkIfNeeded()
    }
}

private final class ChunkEditorContainerView: NSView {
    var textView: ChunkNSTextView?
    private var lastWidth: CGFloat = 0

    func attach(textView: ChunkNSTextView) {
        self.textView = textView
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func layout() {
        super.layout()
        guard let textView else { return }
        guard bounds.width > 0 else { return }
        guard abs(bounds.width - lastWidth) > 0.5 else { return }
        lastWidth = bounds.width
        if let tc = textView.textContainer {
            tc.containerSize = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        }
        textView.reportHeight()
    }
}

private let grimoireChunkMarker = "<!-- grimoire-chunk -->"
private let grimoireChunkSeparator = "\n\n<!-- grimoire-chunk -->\n\n"

private struct SelectionTextOverlay: NSViewRepresentable {
    let attributedText: NSAttributedString
    let onEditSelectionIndex: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onEditSelectionIndex: onEditSelectionIndex)
    }

    func makeNSView(context: Context) -> SelectionTextOverlayView {
        let view = SelectionTextOverlayView()
        view.onEditSelectionIndex = context.coordinator.onEditSelectionIndex
        view.update(attributedText: attributedText)
        return view
    }

    func updateNSView(_ nsView: SelectionTextOverlayView, context: Context) {
        nsView.onEditSelectionIndex = context.coordinator.onEditSelectionIndex
        nsView.update(attributedText: attributedText)
    }

    final class Coordinator {
        let onEditSelectionIndex: (Int) -> Void

        init(onEditSelectionIndex: @escaping (Int) -> Void) {
            self.onEditSelectionIndex = onEditSelectionIndex
        }
    }
}

private final class SelectionTextOverlayView: NSView {
    private let textView = EditOrSelectTextView()
    private var lastWidth: CGFloat = 0
    var onEditSelectionIndex: ((Int) -> Void)? {
        didSet { textView.onEditSelectionIndex = onEditSelectionIndex }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        textView.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textColor = .clear
        textView.insertionPointColor = .clear
        textView.allowsUndo = false
        textView.usesFindPanel = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let selectionColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.35)
        textView.selectedTextAttributes = [.backgroundColor: selectionColor]

        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(attributedText: NSAttributedString) {
        textView.textStorage?.setAttributedString(attributedText)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0 else { return }
        guard abs(bounds.width - lastWidth) > 0.5 else { return }
        lastWidth = bounds.width
        textView.textContainer?.containerSize = NSSize(width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    }
}

private final class EditOrSelectTextView: NSTextView {
    var onEditSelectionIndex: ((Int) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        nil
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            if let window, window.firstResponder !== self {
                window.makeFirstResponder(self)
            }
            super.mouseDown(with: event)
            return
        }

        guard event.clickCount == 1 else {
            super.mouseDown(with: event)
            return
        }

        guard let layoutManager, let textContainer else { return }
        let viewPoint = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        var fraction: CGFloat = 0
        let idx = layoutManager.characterIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: &fraction
        )
        onEditSelectionIndex?(idx)
    }
}

private struct PendingCursorPlacement: Equatable {
    let chunkId: UUID
    let markdownIndex: Int
}

private struct SelectionChunkModel: Equatable {
    let id: UUID
    let range: NSRange
    let visibleToMarkdown: [Int]
}

private struct SelectionOverlayModel {
    let attributedText: NSAttributedString
    let chunks: [SelectionChunkModel]

    static let empty = SelectionOverlayModel(attributedText: NSAttributedString(string: ""), chunks: [])

    func hitTest(_ selectionIndex: Int) -> (UUID, Int)? {
        guard !chunks.isEmpty else { return nil }

        for chunk in chunks {
            if NSLocationInRange(selectionIndex, chunk.range) {
                let local = max(0, selectionIndex - chunk.range.location)
                let idx = min(local, max(0, chunk.visibleToMarkdown.count - 1))
                return (chunk.id, chunk.visibleToMarkdown[idx])
            }
        }

        // Clicked between chunks: choose the nearest previous chunk, falling back to the first.
        let sorted = chunks.sorted { $0.range.location < $1.range.location }
        var lastBefore: SelectionChunkModel?
        for chunk in sorted {
            if selectionIndex < chunk.range.location {
                break
            }
            lastBefore = chunk
        }
        if let chunk = lastBefore ?? sorted.first {
            guard let last = chunk.visibleToMarkdown.last else { return nil }
            return (chunk.id, last)
        }
        return nil
    }
}

private enum GrimoireMarkdownImageConstants {
    static let maxPixelSize = 2048
    static let cacheCostLimit = 64 * 1024 * 1024
    static let cacheCountLimit = 64
    static let diskCacheLimit = 100 * 1024 * 1024
    static let timeoutInterval: TimeInterval = 15
}

private final class GrimoireNetworkImageCache: NetworkImageCache {
    private let cache = NSCache<NSURL, CGImage>()

    init(
        totalCostLimit: Int = GrimoireMarkdownImageConstants.cacheCostLimit,
        countLimit: Int = GrimoireMarkdownImageConstants.cacheCountLimit
    ) {
        cache.totalCostLimit = totalCostLimit
        cache.countLimit = countLimit
    }

    func image(for url: URL) -> CGImage? {
        cache.object(forKey: url as NSURL)
    }

    func setImage(_ image: CGImage, for url: URL) {
        let cost = image.bytesPerRow * image.height
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }
}

private actor GrimoireNetworkImageLoader: NetworkImageLoader {
    static let shared = GrimoireNetworkImageLoader()

    private let cache: NetworkImageCache
    private let data: (URL) async throws -> (Data, URLResponse)
    private let maxPixelSize: Int
    private var ongoingTasks: [URL: Task<CGImage, Error>] = [:]

    init(
        cache: NetworkImageCache = GrimoireNetworkImageCache(),
        session: URLSession = .imageLoading(
            memoryCapacity: 0,
            diskCapacity: GrimoireMarkdownImageConstants.diskCacheLimit,
            timeoutInterval: GrimoireMarkdownImageConstants.timeoutInterval
        ),
        maxPixelSize: Int = GrimoireMarkdownImageConstants.maxPixelSize
    ) {
        self.cache = cache
        self.data = session.data(from:)
        self.maxPixelSize = maxPixelSize
    }

    func image(from url: URL) async throws -> CGImage {
        if let cached = cache.image(for: url) {
            return cached
        }
        if let task = ongoingTasks[url] {
            return try await task.value
        }

        let task = Task<CGImage, Error> { [data, cache, maxPixelSize] in
            let (payload, response) = try await data(url)
            guard let statusCode = (response as? HTTPURLResponse)?.statusCode,
                  200..<300 ~= statusCode else {
                throw URLError(.badServerResponse)
            }

            guard let image = Self.decodeImage(from: payload, maxPixelSize: maxPixelSize) else {
                throw URLError(.cannotDecodeContentData)
            }

            cache.setImage(image, for: url)
            return image
        }

        ongoingTasks[url] = task
        do {
            let image = try await task.value
            ongoingTasks.removeValue(forKey: url)
            return image
        } catch {
            ongoingTasks.removeValue(forKey: url)
            throw error
        }
    }

    private static func decodeImage(from data: Data, maxPixelSize: Int) -> CGImage? {
        // Downsample to keep large attachments from ballooning memory.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]

        if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return thumbnail
        }

        return nil
    }
}

private struct GrimoireResizeToFit<Content: View>: View {
    private let idealSize: CGSize
    private let content: Content

    init(idealSize: CGSize, @ViewBuilder content: () -> Content) {
        self.idealSize = idealSize
        self.content = content()
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            GrimoireResizeToFitLayout { self.content }
        } else {
            GrimoireResizeToFitLegacy(idealSize: idealSize, content: content)
        }
    }
}

private struct GrimoireResizeToFitLegacy<Content: View>: View {
    @State private var size: CGSize?

    let idealSize: CGSize
    let content: Content

    var body: some View {
        GeometryReader { proxy in
            let size = sizeThatFits(proposal: proxy.size)
            content
                .frame(width: size.width, height: size.height)
                .preference(key: GrimoireSizePreference.self, value: size)
        }
        .frame(width: size?.width, height: size?.height)
        .onPreferenceChange(GrimoireSizePreference.self) { size in
            self.size = size
        }
    }

    private func sizeThatFits(proposal: CGSize) -> CGSize {
        guard proposal.width < idealSize.width else {
            return idealSize
        }

        let aspectRatio = idealSize.width / idealSize.height
        return CGSize(width: proposal.width, height: proposal.width / aspectRatio)
    }
}

private struct GrimoireSizePreference: PreferenceKey {
    static let defaultValue: CGSize? = nil

    static func reduce(value: inout CGSize?, nextValue: () -> CGSize?) {
        value = value ?? nextValue()
    }
}

@available(macOS 13.0, *)
private struct GrimoireResizeToFitLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard let view = subviews.first else {
            return .zero
        }

        var size = view.sizeThatFits(.unspecified)

        if let width = proposal.width, size.width > width {
            let aspectRatio = size.width / size.height
            size.width = width
            size.height = width / aspectRatio
        }
        return size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let view = subviews.first else { return }
        view.place(at: bounds.origin, proposal: .init(bounds.size))
    }
}

private struct GrimoireImageFailureView: View {
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
                .foregroundColor(.red)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.red.opacity(0.5), lineWidth: 1)
        )
    }
}

private struct GrimoireImageLoadingView: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
            Text("Loading image...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GrimoireMarkdownImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        Group {
            if let url {
                NetworkImage(url: url) { state in
                    switch state {
                    case .empty:
                        GrimoireImageLoadingView()
                    case .failure:
                        GrimoireImageFailureView(message: "Image failed to load")
                    case .success(let image, let idealSize):
                        GrimoireResizeToFit(idealSize: idealSize) {
                            image.resizable()
                        }
                    }
                }
            } else {
                GrimoireImageFailureView(message: "Invalid image URL")
            }
        }
    }
}

private struct GrimoireMarkdownInlineImageProvider: InlineImageProvider {
    func image(with url: URL, label: String) async throws -> Image {
        do {
            let image = try await GrimoireNetworkImageLoader.shared.image(from: url)
            return Image(image, scale: 1, label: Text(label))
        } catch {
            return Image(systemName: "exclamationmark.triangle.fill")
        }
    }
}

extension View {
    func grimoireMarkdownStyle() -> some View {
        self.markdownTheme(.docC)
            .markdownImageProvider(GrimoireMarkdownImageProvider())
            .markdownInlineImageProvider(GrimoireMarkdownInlineImageProvider())
            .networkImageLoader(GrimoireNetworkImageLoader.shared)
    }
}
