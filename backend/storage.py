"""Filesystem-backed storage for notes and folders."""

from __future__ import annotations

import json
import time
from dataclasses import replace
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from models import NoteKind, NoteNodePayload, NoteRecord, NotesResponsePayload


class NoteStorage:
    """Local JSON storage with hierarchical helpers."""

    def __init__(self, root: Optional[Path] = None):
        base_dir = Path(root) if root else Path(__file__).resolve().parent / "storage" / "notes"
        base_dir.mkdir(parents=True, exist_ok=True)
        self.notes_dir = base_dir

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------
    def get_tree(self) -> NotesResponsePayload:
        records = self._load_all_records()
        nodes = {rid: self._to_node(record) for rid, record in records.items()}

        # Build parent/child relationships
        root_ids: Set[str] = set(nodes.keys())

        # Start from a clean slate; stored children can be stale or inconsistent.
        for node in nodes.values():
            node.children = []

        for record in records.values():
            parent_id = record.parent_id
            if parent_id and parent_id in nodes:
                if record.id not in nodes[parent_id].children:
                    nodes[parent_id].children.append(record.id)
                root_ids.discard(record.id)

            # Fall back to stored children to recover older data
            for child in record.children:
                if child in nodes:
                    child_record = records[child]
                    child_parent = child_record.parent_id
                    if child_parent is not None:
                        if child_parent != record.id:
                            continue
                    else:
                        # Folders with no parent_id are roots (derived from id);
                        # don't reattach them via stale children lists.
                        if child_record.kind == NoteKind.FOLDER:
                            continue
                    if child not in nodes[record.id].children:
                        nodes[record.id].children.append(child)
                    root_ids.discard(child)

        # Sort children for stable output
        for node in nodes.values():
            node.children = sorted(
                set(node.children),
                key=lambda cid: nodes.get(cid).title if cid in nodes else cid,
            )

        # Return a flat list of all nodes. Clients (e.g., the macOS app)
        # reconstruct hierarchy from the children ids. Returning only roots
        # causes child items to be missing from client-side trees.
        all_nodes = list(nodes.values())
        all_nodes.sort(key=lambda n: n.title.lower())
        return NotesResponsePayload(notes=all_nodes)

    def list_records(self) -> Dict[str, NoteRecord]:
        """Expose all records for services that need to rebuild derived state."""
        return self._load_all_records()

    def get_note(self, note_id: str) -> NoteRecord:
        normalized = self._normalize_id(note_id)
        candidates = self._candidate_paths(normalized)
        for path, kind in candidates:
            if path.exists():
                return self._read_record(path, normalized, kind)
        raise FileNotFoundError(f"Note not found: {note_id}")

    def save_note_content(
        self, note_id: str, content: str, parent_id: Optional[str]
    ) -> Tuple[NoteRecord, bool]:
        normalized = self._normalize_id(note_id)
        records = self._load_all_records()
        existing = records.get(normalized)
        is_new = existing is None

        record = existing or NoteRecord(
            id=normalized,
            title=self._title_from_id(normalized),
            kind=NoteKind.NOTE,
            parent_id=parent_id or self._derive_parent_id(normalized),
        )

        record.content = content
        record.parent_id = parent_id or record.parent_id or self._derive_parent_id(
            normalized
        )
        if is_new:
            record.created_at = time.time()
        record.updated_at = time.time()

        records[record.id] = record
        self._persist_all(records)
        self._ensure_parent_link(record)
        return record, is_new

    def create_folder(self, folder_path: str) -> Tuple[NoteRecord, bool]:
        normalized = self._normalize_id(folder_path)
        records = self._load_all_records()
        existing = records.get(normalized)
        is_new = existing is None

        folder = existing or NoteRecord(
            id=normalized,
            title=self._title_from_id(normalized),
            kind=NoteKind.FOLDER,
            parent_id=self._derive_parent_id(normalized),
            children=list(existing.children if existing else []),
        )

        # Ensure folder location is derived from its path-style id.
        folder.parent_id = self._derive_parent_id(normalized)
        if is_new:
            folder.created_at = time.time()
        folder.updated_at = time.time()

        records[folder.id] = folder
        self._persist_all(records)
        self._ensure_parent_link(folder)

        return folder, is_new

    def delete_item(self, note_id: str) -> List[str]:
        normalized = self._normalize_id(note_id)
        records = self._load_all_records()
        if normalized not in records:
            raise FileNotFoundError(f"Note or folder not found: {note_id}")

        targets = self._collect_descendants(normalized, records)
        deleted_ids: List[str] = []

        # Update parents before deleting
        for record in list(records.values()):
            if record.children:
                record.children = [cid for cid in record.children if cid not in targets]
                records[record.id] = record

        for target_id in targets:
            record = records.pop(target_id, None)
            if record:
                deleted_ids.append(target_id)
                for path, _ in self._candidate_paths(target_id):
                    if path.exists():
                        path.unlink()

        self._persist_all(records)
        return deleted_ids

    def rename_item(self, old_id: str, new_name: str) -> str:
        normalized_old = self._normalize_id(old_id)
        records = self._load_all_records()
        if normalized_old not in records:
            raise FileNotFoundError(f"Note or folder not found: {old_id}")

        old_record = records[normalized_old]

        if "/" in new_name:
            normalized_new_root = self._normalize_id(new_name)
        else:
            parent = old_record.parent_id or self._derive_parent_id(normalized_old)
            normalized_new_root = (
                f"{parent}/{self._normalize_id(new_name)}" if parent else self._normalize_id(new_name)
            )

        if normalized_new_root == normalized_old:
            return normalized_old

        targets = self._collect_descendants(normalized_old, records)

        def rebase(identifier: Optional[str]) -> Optional[str]:
            if identifier is None:
                return None
            identifier = self._normalize_id(identifier)
            if identifier == normalized_old:
                return normalized_new_root
            if identifier.startswith(normalized_old + "/"):
                return normalized_new_root + identifier[len(normalized_old) :]
            return identifier

        updated_records: Dict[str, NoteRecord] = {}
        for current_id, record in records.items():
            new_id = rebase(record.id) if record.id in targets else record.id
            new_parent = rebase(record.parent_id)
            new_children = [rebase(child) or child for child in record.children]
            new_title = record.title
            if record.id == normalized_old:
                new_title = self._title_from_id(normalized_new_root)
            updated = replace(
                record,
                id=new_id,
                title=new_title,
                parent_id=new_parent,
                children=new_children,
                updated_at=time.time(),
            )

            updated_records[new_id] = updated

        # Remove old files for moved items
        for target_id in targets:
            if target_id == normalized_new_root:
                continue
            original_record = records[target_id]
            for path, _ in self._candidate_paths(original_record.id, original_record.kind):
                if path.exists():
                    path.unlink()

        self._persist_all(updated_records)
        return normalized_new_root

    def move_item(self, note_id: str, parent_id: Optional[str]) -> NoteRecord:
        """Move an existing note or folder by updating parent_id.

        This keeps the item's id stable, unlike rename_item which rebases ids.
        """
        normalized_id = self._normalize_id(note_id)
        normalized_parent = self._normalize_id(parent_id) if parent_id else None

        records = self._load_all_records()
        if normalized_id not in records:
            raise FileNotFoundError(f"Note or folder not found: {note_id}")

        record = records[normalized_id]
        old_parent_id = record.parent_id

        # Remove from old parent
        if old_parent_id and old_parent_id in records:
            old_parent = records[old_parent_id]
            if record.id in old_parent.children:
                old_parent.children = [cid for cid in old_parent.children if cid != record.id]
                old_parent.updated_at = time.time()
                records[old_parent.id] = old_parent

        # Add to new parent
        if normalized_parent:
            parent_record = records.get(normalized_parent)
            if not parent_record:
                parent_record = NoteRecord(
                    id=normalized_parent,
                    title=self._title_from_id(normalized_parent),
                    kind=NoteKind.FOLDER,
                    parent_id=self._derive_parent_id(normalized_parent),
                )
            if record.id not in parent_record.children:
                parent_record.children.append(record.id)
            parent_record.updated_at = time.time()
            records[parent_record.id] = parent_record

        record.parent_id = normalized_parent
        record.updated_at = time.time()
        records[record.id] = record

        self._persist_all(records)
        return record

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------
    def _normalize_id(self, raw_id: str) -> str:
        return raw_id.strip().strip("/")

    def _safe_stem(self, note_id: str) -> str:
        normalized = self._normalize_id(note_id)
        return normalized.replace("/", "__")

    def _derive_parent_id(self, note_id: str) -> Optional[str]:
        normalized = self._normalize_id(note_id)
        if "/" not in normalized:
            return None
        return normalized.rsplit("/", 1)[0]

    def _title_from_id(self, note_id: str) -> str:
        leaf = self._normalize_id(note_id).rsplit("/", 1)[-1]
        return leaf.replace("_", " ").strip() or "Untitled"

    def _candidate_paths(
        self, note_id: str, kind: Optional[NoteKind] = None
    ) -> List[Tuple[Path, NoteKind]]:
        stem = self._safe_stem(note_id)
        paths: List[Tuple[Path, NoteKind]] = []
        if kind in (None, NoteKind.NOTE):
            paths.append((self.notes_dir / f"{stem}.json", NoteKind.NOTE))
        if kind in (None, NoteKind.FOLDER):
            paths.append((self.notes_dir / f"{stem}.folder.json", NoteKind.FOLDER))
        return paths

    def _load_all_records(self) -> Dict[str, NoteRecord]:
        records: Dict[str, NoteRecord] = {}
        for path in self.notes_dir.glob("*.json"):
            if path.name.endswith(".folder.json"):
                continue
            try:
                record = self._read_record(path, path.stem.replace("__", "/"), NoteKind.NOTE)
                records[record.id] = record
            except Exception:
                continue

        for path in self.notes_dir.glob("*.folder.json"):
            try:
                stem = path.name.replace(".folder.json", "").replace("__", "/")
                record = self._read_record(path, stem, NoteKind.FOLDER)
                records[record.id] = record
            except Exception:
                continue

        return records

    def _read_record(self, path: Path, note_id: str, kind: NoteKind) -> NoteRecord:
        with open(path, "r", encoding="utf-8") as handle:
            raw = json.load(handle)

        record_id = self._normalize_id(raw.get("id") or raw.get("path") or note_id)
        title = raw.get("title") or self._title_from_id(record_id)
        parent_id = raw.get("parent_id") or self._derive_parent_id(record_id)
        children = raw.get("children", [])
        created_at = raw.get("created_at", time.time())
        updated_at = raw.get("updated_at", time.time())

        content = raw.get("content", "") if kind == NoteKind.NOTE else ""

        # Folders are represented with path-style ids; keep parent_id consistent
        # with the id to avoid stale or mislinked hierarchies.
        if kind == NoteKind.FOLDER:
            parent_id = self._derive_parent_id(record_id)

        return NoteRecord(
            id=record_id,
            title=title,
            kind=kind,
            content=content,
            parent_id=parent_id,
            children=children,
            created_at=created_at,
            updated_at=updated_at,
        )

    def _persist_all(self, records: Dict[str, NoteRecord]):
        self.notes_dir.mkdir(parents=True, exist_ok=True)
        for record in records.values():
            self._write_record(record)

    def _write_record(self, record: NoteRecord):
        payload = {
            "id": record.id,
            "title": record.title,
            "path": record.id,
            "parent_id": record.parent_id,
            "children": record.children,
            "created_at": record.created_at,
            "updated_at": record.updated_at,
        }

        path: Path
        if record.kind == NoteKind.FOLDER:
            payload["type"] = "folder"
            payload["content"] = ""
            path = self._candidate_paths(record.id, NoteKind.FOLDER)[0][0]
        else:
            payload["type"] = "note"
            payload["content"] = record.content
            path = self._candidate_paths(record.id, NoteKind.NOTE)[0][0]

        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)

    def _ensure_parent_link(self, record: NoteRecord):
        parent_id = record.parent_id
        if not parent_id:
            return

        try:
            parent = self.get_note(parent_id)
        except FileNotFoundError:
            parent = NoteRecord(
                id=parent_id,
                title=self._title_from_id(parent_id),
                kind=NoteKind.FOLDER,
            )

        if record.id not in parent.children:
            parent.children.append(record.id)
            parent.updated_at = time.time()
            self._write_record(parent)

    def _collect_descendants(self, root_id: str, records: Dict[str, NoteRecord]) -> List[str]:
        adjacency = self._build_adjacency(records)
        to_visit = [root_id]
        seen: Set[str] = set()

        while to_visit:
            current = to_visit.pop()
            if current in seen:
                continue
            seen.add(current)
            to_visit.extend(adjacency.get(current, []))

        return list(seen)

    def _build_adjacency(self, records: Dict[str, NoteRecord]) -> Dict[str, List[str]]:
        adjacency: Dict[str, List[str]] = {}
        for record in records.values():
            if record.parent_id:
                adjacency.setdefault(record.parent_id, []).append(record.id)
            if record.children:
                adjacency.setdefault(record.id, []).extend(record.children)
        return adjacency

    def _to_node(self, record: NoteRecord) -> NoteNodePayload:
        return NoteNodePayload(
            id=record.id,
            title=record.title,
            kind=record.kind,
            children=list(record.children),
        )
