# Grimoire — Backend API Technical Specification

Base URL (default):

- `http://127.0.0.1:8000`

The authoritative OpenAPI documentation is served by FastAPI at:

- `GET /docs`
- `GET /openapi.json`

This document provides a stable, human-readable reference.

---

## Health

### `GET /health`

Returns a basic server status object.

---

## Projects

### `GET /projects`

Returns all known projects (usually under `backend/storage/projects`) and indicates which is active.

### `GET /projects/current`

Returns the current active project.

### `POST /projects/create`

Creates a new `.grim` project and makes it active.

Request body:

- `name: string`

### `POST /projects/open`

Opens an existing project by name (in the default projects directory) or by absolute path.

Request body:

- `name?: string`
- `path?: string` (preferred by the macOS app when opening a folder picker result)

---

## Notes (Tree and CRUD)

### `GET /notes`

Returns a flat list of all nodes (notes and folders), each with `children` IDs, enabling clients to reconstruct hierarchy.

### `GET /note/{note_id:path}`

Returns the content for a note by ID.

### `POST /update-note`

Saves a note’s content.

Request body:

- `note_id: string`
- `content: string` (Markdown)
- `parent_id?: string` (optional parent override)

### `POST /create-note`

Creates a note at a given path/ID.

### `POST /create-folder`

Creates a folder.

### `POST /rename-note`

Renames a note or folder by changing its ID/path.

Request body:

- `old_note_id: string`
- `new_note_id: string`

### `POST /move-item`

Moves a note or folder to a new parent folder.

Request body:

- `note_id: string`
- `parent_id?: string` (null/omitted means move to root)

### `POST /delete-note`

Deletes a note or folder (and children, if folder).

---

## Semantic Backlinks (“Context Sidebar”)

### `POST /context`

Returns up to a small set of snippets from other notes relevant to the cursor context.

Request body includes:

- current note id/text
- cursor position and/or window content

Response includes:

- list of snippet items (excerpt text, note references, similarity/score)

Exact payload types are defined in:

- `backend/context_models.py`

---

## Glossary

### `GET /glossary`

Returns all glossary terms with basic metadata and a short definition excerpt.

### `GET /glossary/{concept_id}`

Returns detail for one term:

- surface forms / aliases
- definition excerpt + chunk reference
- supporting excerpts

### `POST /admin/rebuild-glossary`

Forces a rebuild from current project notes.

Response includes:

- `terms`: number of terms created
- `spacy_notes`: number of notes extracted using spaCy
- `fallback_notes`: number of notes extracted using fallback (no spaCy)

---

## Index Admin

### `POST /admin/rebuild-index`

Rebuilds the semantic indexes for the project.

(Used for full reindexing when indexes are stale or after major algorithm changes.)

