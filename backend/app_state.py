"""Backend application state for project-scoped services."""

from __future__ import annotations

import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from context_service import ContextIndex, ContextService
from indexer import Indexer
from project_manager import ProjectInfo, ProjectManager
from services import NoteService, SearchService
from storage import NoteStorage


@dataclass
class ProjectServices:
    project: ProjectInfo
    storage: NoteStorage
    search: SearchService
    context: ContextService
    notes: NoteService


class GrimoireAppState:
    """Holds the currently-open project and all project-scoped services."""

    def __init__(self, project_manager: Optional[ProjectManager] = None):
        self._lock = threading.RLock()
        self.project_manager = project_manager or ProjectManager()
        self._services: Optional[ProjectServices] = None
        self._load_project(self.project_manager.active_project())

    def current(self) -> ProjectServices:
        with self._lock:
            assert self._services is not None
            return self._services

    def open_project(self, *, name: Optional[str] = None, path: Optional[str] = None) -> ProjectServices:
        project = self.project_manager.open_project(name=name, path=path)
        with self._lock:
            self._load_project(project)
            assert self._services is not None
            return self._services

    def create_project(self, name: str) -> ProjectServices:
        project = self.project_manager.create_project(name)
        with self._lock:
            self._load_project(project)
            assert self._services is not None
            return self._services

    def _load_project(self, project: ProjectInfo) -> None:
        project = self.project_manager.ensure_layout(project)

        storage = NoteStorage(root=project.notes_dir)
        indexer = Indexer(
            index_path=str((project.search_dir / "faiss.index").resolve()),
            metadata_path=str((project.search_dir / "index.json").resolve()),
            note_tree_path=str((project.search_dir / "note_tree.json").resolve()),
        )
        search = SearchService(indexer=indexer)

        context_index = ContextIndex(
            metadata_path=str((project.context_dir / "context_index.json").resolve()),
            faiss_path=str((project.context_dir / "context_faiss.index").resolve()),
        )
        context = ContextService(index=context_index)

        notes = NoteService(storage=storage, search=search, context=context)

        self._services = ProjectServices(
            project=project,
            storage=storage,
            search=search,
            context=context,
            notes=notes,
        )
