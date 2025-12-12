"""Shared backend models for Grimoire."""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional

from pydantic import BaseModel, ConfigDict, Field


class NoteKind(str, Enum):
    NOTE = "note"
    FOLDER = "folder"


def _timestamp() -> float:
    return time.time()


@dataclass
class NoteRecord:
    """Represents a stored note or folder."""

    id: str
    title: str
    kind: NoteKind
    content: str = ""
    parent_id: Optional[str] = None
    children: List[str] = field(default_factory=list)
    created_at: float = field(default_factory=_timestamp)
    updated_at: float = field(default_factory=_timestamp)


# API payloads

class NoteNodePayload(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    id: str
    title: str
    kind: NoteKind = Field(alias="type")
    children: List[str] = Field(default_factory=list)


class NoteContentPayload(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    note_id: str = Field(alias="note_id")
    title: Optional[str] = None
    content: str


class SearchHitPayload(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    note_id: str = Field(alias="note_id")
    chunk_id: str = Field(alias="chunk_id")
    text: str
    score: float


class SearchResponsePayload(BaseModel):
    results: List[SearchHitPayload] = Field(default_factory=list)


class NotesResponsePayload(BaseModel):
    notes: List[NoteNodePayload] = Field(default_factory=list)


class CreateFolderResponsePayload(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    folder_id: str = Field(alias="folder_id")
    folder: NoteNodePayload
    success: bool = True


# Request payloads

class SearchRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    text: str
    note_id: str = Field(alias="note_id")


class UpdateNoteRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    note_id: str = Field(alias="note_id")
    content: str
    parent_id: Optional[str] = Field(default=None, alias="parent_id")


class CreateNoteRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    note_id: str = Field(alias="note_id")
    title: str
    content: str = ""
    parent_id: Optional[str] = Field(default=None, alias="parent_id")


class CreateFolderRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    folder_path: str = Field(alias="folder_path")


class RenameNoteRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    old_note_id: str = Field(alias="old_note_id")
    new_note_id: str = Field(alias="new_note_id")


class DeleteNoteRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    note_id: str = Field(alias="note_id")


class MoveItemRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    note_id: str = Field(alias="note_id")
    parent_id: Optional[str] = Field(default=None, alias="parent_id")
