"""Pydantic models for cursor-conditioned semantic context retrieval."""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field


class ContextRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    note_id: str = Field(alias="note_id")
    text: str
    cursor_offset: int = Field(alias="cursor_offset", ge=0)
    limit: int = Field(default=7, ge=1, le=20)
    include_debug: bool = Field(default=False, alias="include_debug")


class ContextSnippetPayload(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    note_id: str = Field(alias="note_id")
    chunk_id: str = Field(alias="chunk_id")
    text: str
    score: float
    concept: Optional[str] = None
    debug: Optional[Dict[str, Any]] = None


class ContextResponsePayload(BaseModel):
    results: List[ContextSnippetPayload] = Field(default_factory=list)


class WarmupResponsePayload(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    success: bool = True
    embedder_model: str = Field(alias="embedder_model")
    reranker_enabled: bool = Field(alias="reranker_enabled")
    reranker_model: Optional[str] = Field(default=None, alias="reranker_model")
    context_index_chunks: int = Field(alias="context_index_chunks")


class WarmupRequest(BaseModel):
    model_config = ConfigDict(populate_by_name=True)

    force_rebuild: bool = Field(default=False, alias="force_rebuild")
