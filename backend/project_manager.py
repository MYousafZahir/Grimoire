"""Project management for Grimoire (.grim projects).

A "project" is a directory with a `.grim` extension that contains its own notes
and indexes. This keeps note hierarchies and semantic indexes isolated per
project.
"""

from __future__ import annotations

import json
import re
import shutil
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional


@dataclass(frozen=True)
class ProjectInfo:
    name: str
    root: Path

    @property
    def notes_dir(self) -> Path:
        return self.root / "notes"

    @property
    def search_dir(self) -> Path:
        return self.root / "search"

    @property
    def context_dir(self) -> Path:
        return self.root / "context"

    @property
    def glossary_dir(self) -> Path:
        return self.root / "glossary"


class ProjectManager:
    """Creates, lists, and switches between local `.grim` projects."""

    def __init__(self, base_dir: Optional[Path] = None):
        backend_dir = Path(__file__).resolve().parent
        storage_dir = backend_dir / "storage"
        self._projects_dir = (base_dir or (storage_dir / "projects")).resolve()
        self._state_path = (storage_dir / "active_project.json").resolve()
        self._legacy_storage_dir = storage_dir

        self._projects_dir.mkdir(parents=True, exist_ok=True)
        self._ensure_default_project()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------
    def list_projects(self) -> List[ProjectInfo]:
        projects: List[ProjectInfo] = []
        for path in sorted(self._projects_dir.glob("*.grim")):
            if path.is_dir():
                projects.append(ProjectInfo(name=path.name, root=path))
        return projects

    def active_project(self) -> ProjectInfo:
        state = self._read_state()
        if state:
            path = Path(state.get("path", "")).expanduser()
            if path.exists() and path.is_dir() and path.suffix == ".grim":
                return self.ensure_layout(ProjectInfo(name=path.name, root=path.resolve()))

        projects = self.list_projects()
        if projects:
            project = self.ensure_layout(projects[0])
            self._write_state(project)
            return project

        project = self.create_project("Default")
        self._write_state(project)
        return project

    def create_project(self, name: str) -> ProjectInfo:
        safe = self._sanitize_project_name(name)
        root = (self._projects_dir / safe).resolve()
        root.mkdir(parents=True, exist_ok=True)
        project = self.ensure_layout(ProjectInfo(name=root.name, root=root))
        self._write_state(project)
        return project

    def open_project(self, name: Optional[str] = None, path: Optional[str] = None) -> ProjectInfo:
        if path:
            candidate = Path(path).expanduser().resolve()
            if candidate.suffix != ".grim" or not candidate.exists() or not candidate.is_dir():
                raise FileNotFoundError(f"Project not found: {path}")
            project = self.ensure_layout(ProjectInfo(name=candidate.name, root=candidate))
            self._write_state(project)
            return project

        if not name:
            raise ValueError("Must provide project name or path")

        safe = self._sanitize_project_name(name)
        candidate = (self._projects_dir / safe).resolve()
        if not candidate.exists():
            raise FileNotFoundError(f"Project not found: {safe}")
        project = self.ensure_layout(ProjectInfo(name=candidate.name, root=candidate))
        self._write_state(project)
        return project

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------
    def ensure_layout(self, project: ProjectInfo) -> ProjectInfo:
        project.root.mkdir(parents=True, exist_ok=True)
        project.notes_dir.mkdir(parents=True, exist_ok=True)
        project.search_dir.mkdir(parents=True, exist_ok=True)
        project.context_dir.mkdir(parents=True, exist_ok=True)
        project.glossary_dir.mkdir(parents=True, exist_ok=True)
        return project

    def _sanitize_project_name(self, name: str) -> str:
        trimmed = (name or "").strip()
        if not trimmed:
            trimmed = "Untitled"
        # Allow letters/numbers/space/dash/underscore, convert everything else to '-'.
        slug = re.sub(r"[^A-Za-z0-9 _.-]+", "-", trimmed).strip()
        slug = re.sub(r"\\s+", " ", slug).strip()
        slug = slug.replace(" ", "-")
        if not slug.lower().endswith(".grim"):
            slug += ".grim"
        # Avoid "." and ".."
        if slug in {".grim", "..grim"}:
            slug = f"Project-{int(time.time())}.grim"
        return slug

    def _read_state(self) -> Optional[Dict]:
        try:
            if self._state_path.exists():
                with open(self._state_path, "r", encoding="utf-8") as f:
                    return json.load(f)
        except Exception:
            return None
        return None

    def _write_state(self, project: ProjectInfo) -> None:
        payload = {"path": str(project.root), "updated_at": time.time()}
        self._state_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self._state_path, "w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2)

    def _ensure_default_project(self) -> None:
        # If there are already projects, do nothing.
        if any(self._projects_dir.glob("*.grim")):
            return

        default = self.create_project("Default")
        self._migrate_legacy_storage(default)

    def _migrate_legacy_storage(self, project: ProjectInfo) -> None:
        """Best-effort migration from legacy `backend/storage/*` layout."""

        notes_src = (self._legacy_storage_dir / "notes").resolve()
        if notes_src.exists() and notes_src.is_dir():
            try:
                if not any(project.notes_dir.iterdir()):
                    # Move notes directory into the project to avoid duplicate storage.
                    shutil.rmtree(project.notes_dir, ignore_errors=True)
                    shutil.move(str(notes_src), str(project.notes_dir))
                else:
                    # Merge/copy as a fallback.
                    for item in notes_src.iterdir():
                        dest = project.notes_dir / item.name
                        if dest.exists():
                            continue
                        if item.is_dir():
                            shutil.copytree(item, dest)
                        else:
                            shutil.copy2(item, dest)
            except Exception:
                pass

        # Search index files (classic search).
        for filename in ("faiss.index", "index.json", "note_tree.json"):
            src = (self._legacy_storage_dir / filename).resolve()
            if not src.exists():
                continue
            dest = (project.search_dir / filename).resolve()
            try:
                if not dest.exists():
                    shutil.move(str(src), str(dest))
            except Exception:
                pass

        # Context index files (semantic backlinks).
        for filename in ("context_index.json", "context_faiss.index"):
            src = (self._legacy_storage_dir / filename).resolve()
            if not src.exists():
                continue
            dest = (project.context_dir / filename).resolve()
            try:
                if not dest.exists():
                    shutil.move(str(src), str(dest))
            except Exception:
                pass
