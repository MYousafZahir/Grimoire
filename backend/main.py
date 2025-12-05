"""
FastAPI entrypoint for Grimoire backend.
Handles API endpoints for semantic search and note management.
"""

import json
import os
from typing import List, Optional

import uvicorn
from chunker import Chunker
from embedder import Embedder
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from indexer import Indexer
from pydantic import BaseModel

app = FastAPI(title="Grimoire Backend", description="Semantic notes backend API")

# Enable CORS for local development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, restrict to specific origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize components
chunker = Chunker()
embedder = Embedder()
indexer = Indexer()


# Data models
class SearchRequest(BaseModel):
    text: str
    note_id: str


class SearchResult(BaseModel):
    note_id: str
    chunk_id: str
    excerpt: str
    score: float


class SearchResponse(BaseModel):
    results: List[SearchResult]


class UpdateNoteRequest(BaseModel):
    note_id: str
    content: str


class NoteInfo(BaseModel):
    id: str
    title: str
    path: str
    children: List["NoteInfo"]
    type: Optional[str] = None


NoteInfo.model_rebuild()


class CreateFolderRequest(BaseModel):
    folder_path: str


class RenameNoteRequest(BaseModel):
    old_note_id: str
    new_note_id: str


class DeleteNoteRequest(BaseModel):
    note_id: str


class FileTreeResponse(BaseModel):
    notes: List[NoteInfo]


# API endpoints
@app.get("/")
async def root():
    """Health check endpoint."""
    return {"status": "ok", "service": "Grimoire Backend"}


@app.post("/search", response_model=SearchResponse)
async def search(request: SearchRequest):
    """
    Search for semantically related excerpts.

    Takes the current note content and returns excerpts from other notes
    that are semantically similar.
    """
    try:
        # Embed the search text
        query_embedding = embedder.embed(request.text)

        # Search the index for similar chunks
        results = indexer.search(
            query_embedding=query_embedding, exclude_note_id=request.note_id, top_k=10
        )

        return SearchResponse(results=results)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Search failed: {str(e)}")


@app.post("/update-note")
async def update_note(request: UpdateNoteRequest):
    """
    Update a note in the system.

    Re-chunks and re-embeds the note content, then updates the FAISS index.
    Also saves the markdown file to disk.
    """
    try:
        # Save the note content to file
        note_path = os.path.join("storage", "notes", f"{request.note_id}.md")
        os.makedirs(os.path.dirname(note_path), exist_ok=True)

        with open(note_path, "w", encoding="utf-8") as f:
            f.write(request.content)

        # Chunk the note content
        chunks = chunker.chunk(request.content, request.note_id)

        # Embed each chunk
        chunk_embeddings = []
        for chunk in chunks:
            embedding = embedder.embed(chunk["text"])
            chunk_embeddings.append(
                {
                    "note_id": request.note_id,
                    "chunk_id": chunk["chunk_id"],
                    "text": chunk["text"],
                    "embedding": embedding,
                }
            )

        # Update the index
        indexer.update_note(request.note_id, chunk_embeddings)

        return {"status": "success", "note_id": request.note_id}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Update failed: {str(e)}")


@app.get("/all-notes", response_model=FileTreeResponse)
async def get_all_notes():
    """
    Get the complete file tree for the sidebar.

    Returns a hierarchical structure of all notes in the system.
    """
    try:
        notes_tree = indexer.get_note_tree()
        return FileTreeResponse(notes=notes_tree)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get notes: {str(e)}")


@app.get("/notes", response_model=FileTreeResponse)
async def get_notes():
    """Alias for retrieving the full note tree."""
    return await get_all_notes()


@app.get("/note/{note_id}")
async def get_note(note_id: str):
    """
    Get the content of a specific note.
    """
    try:
        note_path = os.path.join("storage", "notes", f"{note_id}.md")
        if not os.path.exists(note_path):
            raise HTTPException(status_code=404, detail="Note not found")

        with open(note_path, "r", encoding="utf-8") as f:
            content = f.read()

        return {"note_id": note_id, "content": content}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get note: {str(e)}")


@app.post("/create-folder")
async def create_folder(request: CreateFolderRequest):
    """
    Create a new folder in the note hierarchy.
    """
    try:
        indexer.create_folder(request.folder_path)
        return {"status": "success", "folder_path": request.folder_path}
    except Exception as e:
        raise HTTPException(
            status_code=500, detail=f"Failed to create folder: {str(e)}"
        )


@app.post("/rename-note")
async def rename_note(request: RenameNoteRequest):
    """
    Rename a note (change its ID/path).
    """
    try:
        # First, rename the note file
        old_path = os.path.join("storage", "notes", f"{request.old_note_id}.md")
        new_path = os.path.join("storage", "notes", f"{request.new_note_id}.md")

        if os.path.exists(old_path):
            os.makedirs(os.path.dirname(new_path), exist_ok=True)
            os.rename(old_path, new_path)

        # Update the index
        success = indexer.rename_note(request.old_note_id, request.new_note_id)

        if success:
            return {
                "status": "success",
                "old_note_id": request.old_note_id,
                "new_note_id": request.new_note_id,
            }
        else:
            raise HTTPException(
                status_code=404, detail=f"Note {request.old_note_id} not found"
            )
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to rename note: {str(e)}")


@app.post("/delete-note")
async def delete_note(request: DeleteNoteRequest):
    """
    Delete a note or folder from the system.
    """
    try:
        # Update the index and get list of deleted note IDs
        success, deleted_note_ids = indexer.delete_note(request.note_id)

        if not success:
            raise HTTPException(
                status_code=404, detail=f"Note {request.note_id} not found"
            )

        # Delete all note files for the deleted notes
        for note_id in deleted_note_ids:
            note_path = os.path.join("storage", "notes", f"{note_id}.md")
            if os.path.exists(note_path):
                os.remove(note_path)
                print(f"Deleted note file: {note_path}")

        # Also delete the main note file if it exists (for regular notes)
        main_note_path = os.path.join("storage", "notes", f"{request.note_id}.md")
        if os.path.exists(main_note_path) and request.note_id not in deleted_note_ids:
            os.remove(main_note_path)
            print(f"Deleted main note file: {main_note_path}")

        return {"status": "success", "note_id": request.note_id}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to delete note: {str(e)}")


if __name__ == "__main__":
    uvicorn.run("main:app", host="127.0.0.1", port=8000, reload=False)
