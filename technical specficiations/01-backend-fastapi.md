# Grimoire — Backend (Python/FastAPI) Technical Specification

This document describes the backend server architecture, how it is structured, and how it serves projects, notes, semantic context, and the glossary.

---

## Process Model

- A single local FastAPI server listens on `127.0.0.1:8000` by default.
- The server is started via `./grimoire` (recommended) or manually with Python from `backend/`.
- The backend is local-only (intended for localhost). The macOS app uses HTTP to call it.

---

## Core Modules

### `backend/main.py` (FastAPI routes)

Defines REST endpoints for:

- health checks
- projects
- note CRUD
- moving/renaming items (folders/notes)
- semantic context (`/context`)
- glossary endpoints (`/glossary`, `/admin/rebuild-glossary`)

The app state is held in a global:

- `state = GrimoireAppState()`

All request handlers operate through `state.current()` which returns project-scoped services.

### `backend/app_state.py` (Project-scoped services)

`GrimoireAppState` owns the currently active project and constructs:

- `NoteStorage` — filesystem-backed notes store
- `SearchService` — “classic” search index (legacy)
- `ContextService` — semantic backlinks (“context sidebar”)
- `GlossaryService` — automated glossary
- `NoteService` — orchestration layer used by API handlers

Switching projects swaps *all* of these so indices are isolated.

### `backend/project_manager.py` (Projects)

Defines `.grim` projects as directories containing:

- `notes/`
- `search/`
- `context/`
- `glossary/`

Maintains the “active” project pointer at:

- `backend/storage/active_project.json`

### `backend/storage.py` (Notes/folders persistence)

`NoteStorage` stores each note/folder as a JSON file under the project’s `notes/` directory.

Key responsibilities:

- Build the full tree (`get_tree()`) as a flat list of nodes with `children` IDs.
- Create notes/folders with stable path-derived IDs.
- Rename items and keep parent/child relationships consistent.
- Move items between parents (restructuring hierarchy).

### `backend/context_service.py` (Semantic backlinks)

`ContextService` and `ContextIndex` provide:

- chunk-level indexing of notes
- dense retrieval (FAISS/HNSW)
- optional lexical retrieval components
- reranking with a local cross-encoder
- cursor-conditioned retrieval endpoint (`POST /context`)

See `technical%20specficiations/04-semantic-backlinks.md`.

### `backend/glossary_service.py` (Automated glossary)

Implements a non-generative, corpus-derived glossary:

- Extract entity mentions using spaCy when available
- Fall back to a conservative heuristic extractor when spaCy is unavailable
- Score/filter candidate entities (“termhood”)
- Cluster into entity records with aliases
- Select verbatim definition sentences from the corpus

See `technical%20specficiations/05-glossary.md`.

---

## API Surface (Summary)

See `technical%20specficiations/08-api.md` for full payloads.

**Health**
- `GET /health`

**Projects**
- `GET /projects`
- `GET /projects/current`
- `POST /projects/create`
- `POST /projects/open`

**Notes**
- `GET /notes`
- `GET /note/{note_id}`
- `POST /update-note`
- `POST /create-note`
- `POST /create-folder`
- `POST /rename-note`
- `POST /move-item`
- `POST /delete-note`

**Semantic backlinks**
- `POST /context`

**Glossary**
- `GET /glossary`
- `GET /glossary/{concept_id}`
- `POST /admin/rebuild-glossary`

---

## Project Isolation

All storage/indexing paths are derived from the active project directory. For example:

- notes live at `<project>.grim/notes/`
- context index lives at `<project>.grim/context/`
- glossary cache lives at `<project>.grim/glossary/`

This prevents cross-project leakage in both stored notes and derived indexes.

---

## Local Model Loading

The backend uses local ML models for embeddings/reranking. Model files are cached locally by the underlying libraries (Hugging Face cache).

- Embeddings: `BAAI/bge-small-en-v1.5`
- Reranker: `BAAI/bge-reranker-base` (optional; can be disabled/unavailable)
- spaCy pipeline: `en_core_web_sm` (optional; fallback exists)

If a model is unavailable, services degrade gracefully (with a quality hit). The UI surfaces rebuild status for glossary rebuilds.

