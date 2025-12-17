# Grimoire — System Overview (Architecture)

Grimoire is a local-first macOS notes application with:

- A project system (`.grim` projects) so each project has isolated notes and indexes.
- A SwiftUI macOS UI that edits Markdown as “chunks” and renders non-focused chunks.
- A Python/FastAPI backend that stores notes, builds indexes, serves semantic context (“semantic backlinks”), and builds a corpus-derived glossary.

Nothing calls external APIs at runtime; all models run locally (with optional one-time downloads for local model weights).

---

## High-Level Architecture

Grimoire is split into two processes:

1. **macOS app (SwiftUI)**: the UI and interaction logic.
2. **backend server (FastAPI)**: data + indexing + retrieval + glossary.

They communicate over HTTP on localhost (default `http://127.0.0.1:8000`).

### Why a local backend?

- Keeps ML / indexing logic in Python where the ecosystem is strong (FAISS, embedding stacks).
- Keeps the macOS app lightweight and focused on UX.
- Keeps everything local and inspectable (files on disk, deterministic pipelines).

---

## Runtime Data Flow

### App boot

1. `./grimoire` starts the FastAPI backend and then builds/launches the macOS app.
2. The macOS app connects to the backend via `/health`.
3. The macOS app shows a **Project Selection** screen:
   - create a new project (`.grim`)
   - open an existing project
   - open recent projects
4. Once a project is opened, the app loads the note tree and the initial note.

### Note editing

1. UI selects a note → `GET /note/{note_id}`
2. UI edits Markdown chunk text locally.
3. UI saves to backend → `POST /update-note`
4. Backend persists the note and schedules background updates (context index/glossary updates depending on the subsystem).

### Semantic backlinks (“context sidebar”)

1. Cursor click/movement in the editor triggers a debounced request → `POST /context`
2. Backend retrieves a small set of relevant snippets from the project’s indexed chunks.
3. UI renders the returned snippets and allows “Open” into the source note and highlights the excerpt.

### Glossary

1. UI opens Glossary panel → `GET /glossary` (builds if needed)
2. UI can open a term detail view → `GET /glossary/{concept_id}`
3. User can explicitly rebuild → `POST /admin/rebuild-glossary`
4. UI shows an overlay while rebuilding and then an alert describing whether spaCy or fallback extraction was used.

---

## On-Disk Layout (Projects)

Projects are directories with a `.grim` extension (e.g. `world_building.grim`).

Each project contains:

- `notes/` — note/folder records stored as JSON
- `search/` — legacy search index files
- `context/` — semantic backlinks (cursor-conditioned context) index files
- `glossary/` — glossary cache/output

The backend also maintains:

- `backend/storage/active_project.json` — points at the currently active project folder

See `technical%20specficiations/03-projects-and-storage.md` for details.

---

## Subsystems

- **Projects & storage**: `backend/project_manager.py`, `backend/app_state.py`, `backend/storage.py`
- **Notes + hierarchy**: `backend/storage.py`, `backend/services.py`, SwiftUI sidebar tree
- **Chunking**: `backend/chunker.py` and editor-side chunk UI
- **Semantic backlinks (“context”)**: `backend/context_service.py` and `POST /context`
- **Glossary**: `backend/glossary_service.py` and `/glossary*` endpoints
- **Build/launch tooling**: `./grimoire`, `./cleanup.sh`, `./.rebuild.sh`

---

## Models (Local)

Model usage is intentionally non-generative:

- **Embeddings**: `BAAI/bge-small-en-v1.5` (dense embeddings)
- **Reranker**: `BAAI/bge-reranker-base` (cross-encoder scoring for ranking)
- **Syntax** (glossary term extraction): `spaCy en_core_web_sm` (optional; fallback exists)

No generative LLM is used. All excerpts/definitions displayed are verbatim text from notes.

