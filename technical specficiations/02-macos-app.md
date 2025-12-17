# Grimoire — macOS App (SwiftUI) Technical Specification

This document describes the SwiftUI macOS application architecture and how it interacts with the local backend.

---

## App Goals

- Native macOS note editor with:
  - sidebar tree (folders/notes)
  - chunk-based Markdown editing/rendering
  - semantic backlinks (cursor-conditioned context sidebar)
  - glossary panel (corpus-derived terms + verbatim definitions)
- Strict local-first behavior:
  - all reads/writes and indexing run on the user’s machine
  - backend is localhost only

---

## SwiftUI Architecture

The app uses a standard “Repository → Store → View” pattern:

- **Repository**: HTTP client layer
  - `macos-app/Data/NoteRepository.swift`
- **Store**: app state + async orchestration
  - `macos-app/Stores/NoteStore.swift`
- **Views**: SwiftUI UI tree
  - `macos-app/ContentView.swift` (app shell, boot flow)
  - editor/sidebar/context/glossary views in `macos-app/`

### `NoteStore` responsibilities

- Maintain:
  - note tree
  - current selection and loaded note content
  - save state and backend health
  - project list + current project
  - pending “reveal” (open note and highlight a chunk/excerpt)
  - loading overlays (startup, glossary rebuild)
- Translate UI intents into backend requests via `NoteRepository`
- Handle cancellation and debounce patterns (cursor movement, live updates)

### Boot flow

- On launch, the app shows a boot overlay until `/health` succeeds.
- Then it shows a **Project Selection** screen:
  - create project
  - open project (choose a `.grim` folder)
  - open recents
  - continue with active project
- After opening a project:
  - note tree is loaded from the backend
  - the editor loads the selected note content

---

## macOS Menu Bar Integration

The app installs menu items into the macOS menu bar (the top-of-screen menu) using AppKit integration from the SwiftUI app.

Key actions (under `File`):

- New Project…
- Open Project…
- Open Recents…
- Rebuild Glossary

Menu actions post internal notifications; `ContentView` listens for them and calls into `NoteStore`.

---

## Sidebar Tree UI

Requirements supported by the app:

- create notes/folders via context menu
- rename notes/folders
- drag-and-drop move notes and folders across the hierarchy
- multi-select behavior (shift/ctrl selection) for bulk operations

The source of truth for hierarchy is the backend tree (`GET /notes`), and move/rename operations are persisted via the backend endpoints.

---

## Chunk-Based Markdown Editor

The editor splits a note into “chunks” (paragraph-ish blocks). Behavior:

- All chunks render as Markdown except the chunk currently being edited.
- Clicking a chunk enters edit mode and positions the cursor at the click location.
- Keyboard shortcuts provide fast chunk creation and exiting edit mode.

The editor supports:

- toggling between render/edit modes at the chunk granularity
- multiline chunks (no internal scrolling; height grows with content)
- cross-chunk text selection (for copy/paste)

The backend still stores the note as a single Markdown document; chunk UI is a view-layer editing model.

---

## Semantic Backlinks Panel

The right-side panel displays up to 7 snippets returned by `POST /context`.

UX rules:

- When a new context request is triggered, the panel clears and shows a centered loading indicator.
- Results are rendered Markdown (no raw text).
- Each snippet supports “Open”:
  - opens source note
  - highlights the relevant excerpt/chunk until the user clicks away

---

## Glossary Panel

Glossary UI:

- lists glossary terms (People / Places / Things / Unknown)
- each term shows a verbatim definition excerpt and source note
- “Open” navigates to the source and highlights the definition excerpt

Rebuild:

- menu action triggers `POST /admin/rebuild-glossary`
- UI shows an overlay while rebuilding
- then shows an alert indicating:
  - number of terms
  - whether spaCy was used vs fallback extraction

---

## Error Handling

The app treats these cases distinctly:

- request cancelled (expected during rapid cursor movement or switching notes)
- backend offline (shows a startup failure overlay or a backend connection alert)
- non-2xx responses (surface backend error strings)

To avoid UX noise, cancellation errors are usually suppressed.

