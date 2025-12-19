# Grimoire — Projects & Storage Technical Specification

This document specifies how Grimoire projects work, what a `.grim` project contains, and how notes/folders are persisted.

---

## Project Definition (`.grim`)

A **project** is a directory whose name ends with `.grim` (e.g. `world_building.grim`).

Projects are stored by default under:

- `backend/storage/projects/*.grim`

Projects can also be opened from arbitrary paths via the app’s “Open Project…” flow.

---

## Project Layout (On Disk)

Each project is self-contained and contains:

```
<Project>.grim/
├── notes/        # note + folder JSON records (source of truth)
├── search/       # legacy search index files
├── context/      # semantic backlinks (cursor-conditioned context) index files
└── glossary/     # glossary cache/output
```

The backend ensures these directories exist when a project is created/opened:

- `backend/project_manager.py` (`ensure_layout`)

---

## Active Project Pointer

The backend keeps a pointer to the active project at:

- `backend/storage/active_project.json`

This file stores:

- `path`: absolute path to the active `.grim` directory
- `updated_at`: timestamp

On backend startup, `GrimoireAppState` loads this to pick the initial project.

---

## Notes and Folders Persistence

Notes and folders are stored as individual JSON files under:

- `<Project>.grim/notes/`

These JSON files encode a `NoteRecord`:

- `id`: stable identifier (path-like)
- `title`: display name
- `kind`: `note` or `folder`
- `parent_id`: nullable parent folder ID
- `children`: list of child IDs (primarily for folders; may be repaired on load)
- `content`: Markdown content (notes only)
- timestamps (`created_at`, `updated_at`)

`backend/storage.py`:

- loads records from disk
- repairs relationships to produce a consistent tree
- supports create/rename/move/delete operations

### Tree representation

The backend returns a flat list of all nodes from `GET /notes`.

Each node includes `children` IDs; the client reconstructs the hierarchy.

This “flat list with children references” approach avoids a class of UI bugs where nested nodes disappear when only roots are returned.

---

## Recent Projects

The macOS app maintains a list of recent project paths in `UserDefaults`:

- key: `grimoire.recentProjectPaths`

This list is displayed in the Project Selection screen and is also available through “Open Recents…”.

---

## Migration / Legacy Storage

Earlier versions stored notes/indexes under `backend/storage/*` directly.

The `ProjectManager` performs a best-effort migration into the default project the first time it runs if no `.grim` projects exist.

---

## Operational Guarantees

- Project isolation: indexes and glossary never read across projects.
- Notes are durable and inspectable: JSON files on disk.
- Semantic indexes are rebuildable: derived data can be deleted and rebuilt from notes.

