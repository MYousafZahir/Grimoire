"""Service layer for coordinating storage and search."""

from __future__ import annotations

import time
from typing import Iterable, List

from chunker import Chunker
from context_models import ContextRequest
from context_service import ContextService
from glossary_service import GlossaryService
from embedder import Embedder
from indexer import Indexer
from models import (
    CreateFolderRequest,
    CreateNoteRequest,
    NoteContentPayload,
    NoteKind,
    NoteRecord,
    SearchHitPayload,
    SearchRequest,
)
from storage import NoteStorage


class SearchService:
    """Wraps chunking, embedding, and vector index operations."""

    def __init__(
        self,
        chunker: Chunker | None = None,
        embedder: Embedder | None = None,
        indexer: Indexer | None = None,
    ):
        self.chunker = chunker or Chunker()
        self.embedder = embedder or Embedder()
        self.indexer = indexer or Indexer()

    def search(self, request: SearchRequest) -> List[SearchHitPayload]:
        if not request.text.strip():
            return []

        chunks = self.chunker.chunk(request.text, request.note_id)
        if not chunks:
            return []

        embeddings = [self.embedder.embed(chunk["text"]) for chunk in chunks]
        results: List[SearchHitPayload] = []

        for embedding in embeddings:
            try:
                matches = self.indexer.search(
                    embedding, exclude_note_id=request.note_id, top_k=5
                )
            except Exception as exc:  # Defensive: keep search available even if index is unavailable
                print(f"Search warning: {exc}")
                continue

            for match in matches:
                results.append(
                    SearchHitPayload(
                        note_id=match["note_id"],
                        chunk_id=match["chunk_id"],
                        text=match["excerpt"],
                        score=float(match["score"]),
                    )
                )

        deduped = {}
        for hit in results:
            key = (hit.note_id, hit.chunk_id)
            if key not in deduped or hit.score > deduped[key].score:
                deduped[key] = hit

        sorted_hits = sorted(deduped.values(), key=lambda h: h.score, reverse=True)
        return sorted_hits[:10]

    def index_note(self, record: NoteRecord) -> int:
        """Index a note's content. Returns number of chunks processed."""
        if record.kind != NoteKind.NOTE:
            return 0

        if not record.content.strip():
            self.indexer.delete_note(record.id)
            return 0

        chunks = self.chunker.chunk(record.content, record.id)
        chunk_embeddings = []
        for chunk in chunks:
            embedding = self.embedder.embed(chunk["text"])
            chunk_embeddings.append(
                {
                    "chunk_id": chunk["chunk_id"],
                    "text": chunk["text"],
                    "embedding": embedding,
                }
            )

        try:
            self.indexer.update_note(record.id, chunk_embeddings)
        except Exception as exc:
            print(f"Index update failed for {record.id}: {exc}")
        return len(chunk_embeddings)

    def delete_notes(self, note_ids: Iterable[str]):
        for note_id in note_ids:
            try:
                self.indexer.delete_note(note_id)
            except Exception as exc:
                print(f"Index cleanup failed for {note_id}: {exc}")

    def rebuild(self, records: Iterable[NoteRecord]) -> int:
        processed = 0
        try:
            self.indexer.clear()
        except Exception as exc:
            print(f"Index clear failed: {exc}")

        for record in records:
            if record.kind != NoteKind.NOTE or not record.content.strip():
                continue
            self.index_note(record)
            processed += 1

        return processed


class NoteService:
    """Coordinates storage operations with indexing."""

    def __init__(
        self,
        storage: NoteStorage | None = None,
        search: SearchService | None = None,
        context: ContextService | None = None,
        glossary: GlossaryService | None = None,
    ):
        self.storage = storage or NoteStorage()
        self.search = search or SearchService()
        self.context = context or ContextService()
        self.glossary = glossary

    def tree(self) -> NotesResponsePayload:
        return self.storage.get_tree()

    def get_note(self, note_id: str) -> NoteContentPayload:
        record = self.storage.get_note(note_id)
        return NoteContentPayload(note_id=record.id, title=record.title, content=record.content)

    def save_note(self, request) -> NoteRecord:
        record, _ = self.storage.save_note_content(
            request.note_id, request.content, request.parent_id
        )
        self.search.index_note(record)
        self.context.index_note(record)
        if self.glossary is not None:
            self.glossary.update_for_note(record.id)
        return record

    def create_note(self, request: CreateNoteRequest) -> NoteRecord:
        record, _ = self.storage.save_note_content(
            request.note_id,
            request.content,
            request.parent_id,
        )
        if request.title:
            record.title = request.title
            record.updated_at = time.time()
            self.storage._write_record(record)
        self.search.index_note(record)
        self.context.index_note(record)
        if self.glossary is not None:
            self.glossary.update_for_note(record.id)
        return record

    def create_folder(self, request: CreateFolderRequest) -> NoteRecord:
        folder, _ = self.storage.create_folder(request.folder_path)
        return folder

    def delete_item(self, note_id: str) -> List[str]:
        deleted_ids = self.storage.delete_item(note_id)
        self.search.delete_notes(deleted_ids)
        self.context.delete_notes(deleted_ids)
        if self.glossary is not None:
            self.glossary.delete_notes(deleted_ids)
        return deleted_ids

    def rename_item(self, old_id: str, new_id: str) -> str:
        new_root = self.storage.rename_item(old_id, new_id)
        records = self.storage.list_records()
        self.search.rebuild(records.values())
        self.context.rebuild(records.values())
        if self.glossary is not None:
            self.glossary.rebuild()
        return new_root

    def move_item(self, note_id: str, parent_id: str | None) -> NoteRecord:
        record = self.storage.move_item(note_id, parent_id)
        # Id is stable; no need to rebuild semantic index.
        return record

    def rebuild_index(self) -> int:
        records = self.storage.list_records()
        self.context.rebuild(records.values())
        if self.glossary is not None:
            self.glossary.rebuild()
        return self.search.rebuild(records.values())

    def semantic_context(self, request: ContextRequest):
        # Lazy bootstrap: if the user has an existing corpus, build the context index
        # the first time it is needed instead of requiring a full manual rebuild.
        records = self.storage.list_records()
        built = self.context.ensure_built(records.values())
        if not built:
            raise RuntimeError(
                "Semantic context index is unavailable. "
                "Run POST /admin/warmup (or rebuild index) and ensure local models are installed."
            )
        return self.context.context(request)
