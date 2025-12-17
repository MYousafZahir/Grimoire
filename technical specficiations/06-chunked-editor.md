# Grimoire — Chunked Markdown Editor Technical Specification

This document describes the chunk-based Markdown editing model used by the macOS app.

---

## Design Goals

- Render most of the note as Markdown for readability.
- Only keep the currently edited region in an editable text view.
- Support very large notes without losing “where am I?” context.
- Keep editing fast while still enabling cross-note context retrieval.

---

## Note Representation

**Storage format (backend):**

- Notes are stored as a single Markdown document (plain text inside a JSON record).

**View/edit format (UI):**

- The macOS app splits the note content into a sequence of “chunks”.
- Each chunk maps to a contiguous range of characters in the underlying Markdown document.

The chunked editor is a UI model; it does not change the fundamental storage model (single Markdown document per note).

---

## Chunk Boundaries

Chunks are intended to align with natural reading blocks:

- paragraph boundaries
- headings
- list blocks
- code fences (treated as atomic blocks)

Chunks are also constrained to avoid pathological UI states:

- extremely long single chunks are automatically split so chunks stay usable
- chunks do not have internal scroll bars; the chunk height grows with content

---

## Render vs Edit Modes

- **Render mode**: chunk is displayed as Markdown (via MarkdownUI).
- **Edit mode**: chunk is displayed as a native text editor view and the cursor is placed where the user clicks.

Rules:

- exactly one chunk is “editing” at a time
- clicking a chunk enters edit mode immediately (no “two click” focus state)
- pressing `Esc` exits edit mode and returns the entire note to render mode

---

## Keybindings (Editor)

The app maintains a keybinding legend accessible from the sidebar UI.

Behavior:

- `Enter` inserts a newline in the current chunk.
- `Shift+Enter` exits the current chunk and creates a new chunk below, entering edit mode in the new chunk.
- `Backspace` at the start of a chunk merges the chunk with the previous chunk.

(Keybindings are intentionally constrained to avoid conflicts with native selection and IME behaviors.)

---

## Text Selection

The editor supports:

- standard macOS text selection within a chunk
- cross-chunk selection for copy/paste

Cross-chunk selection is implemented so that selection is not artificially clipped at chunk boundaries.

---

## Interaction with Semantic Backlinks

The backlinks system is cursor-conditioned:

- changes in the current paragraph/chunk can trigger a new `/context` request
- while a request is running, the backlinks panel shows a centered loading indicator
- when results arrive, the panel updates and the user can open/highlight source passages

---

## Edge Cases

- Empty notes must remain editable (a note with no content still provides an editable entry point).
- Chunk auto-splitting must preserve cursor position and undo/redo semantics.

