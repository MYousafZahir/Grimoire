"""FastAPI entrypoint for the Grimoire backend."""

from __future__ import annotations

import uvicorn
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware

from models import (
    CreateFolderRequest,
    CreateNoteRequest,
    DeleteNoteRequest,
    NoteContentPayload,
    NotesResponsePayload,
    RenameNoteRequest,
    SearchRequest,
    SearchResponsePayload,
    UpdateNoteRequest,
)
from services import NoteService, SearchService
from storage import NoteStorage

app = FastAPI(title="Grimoire Backend", description="Semantic notes backend API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

storage = NoteStorage()
search_service = SearchService()
note_service = NoteService(storage=storage, search=search_service)


@app.get("/", tags=["health"])
async def root():
    return {"status": "ok", "message": "Grimoire backend is running"}


@app.get("/health", tags=["health"])
async def health():
    return {"status": "ok", "message": "Grimoire backend is running"}


@app.get("/notes", response_model=NotesResponsePayload, tags=["notes"])
async def notes():
    try:
        return note_service.tree()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.get("/all-notes", response_model=NotesResponsePayload, tags=["notes"])
async def all_notes():
    return await notes()


@app.get("/note/{note_id:path}", response_model=NoteContentPayload, tags=["notes"])
async def get_note(note_id: str):
    try:
        return note_service.get_note(note_id)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/update-note", tags=["notes"])
async def update_note(request: UpdateNoteRequest):
    try:
        record = note_service.save_note(request)
        return {"success": True, "note_id": record.id}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/create-note", tags=["notes"])
async def create_note(request: CreateNoteRequest):
    try:
        record = note_service.create_note(request)
        return {
            "success": True,
            "note_id": record.id,
            "note": {
                "id": record.id,
                "title": record.title,
                "type": record.kind.value,
                "children": record.children,
            },
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/create-folder", tags=["notes"])
async def create_folder(request: CreateFolderRequest):
    try:
        folder = note_service.create_folder(request)
        return {
            "success": True,
            "folder_id": folder.id,
            "folder": {
                "id": folder.id,
                "title": folder.title,
                "type": folder.kind.value,
                "children": folder.children,
            },
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/rename-note", tags=["notes"])
async def rename(request: RenameNoteRequest):
    try:
        new_id = note_service.rename_item(request.old_note_id, request.new_note_id)
        return {"success": True, "note_id": new_id}
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/delete-note", tags=["notes"])
async def delete(request: DeleteNoteRequest):
    try:
        deleted = note_service.delete_item(request.note_id)
        return {"success": True, "deleted": deleted}
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/search", response_model=SearchResponsePayload, tags=["search"])
async def search(request: SearchRequest):
    try:
        hits = search_service.search(request)
        return SearchResponsePayload(results=hits)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/admin/rebuild-index", tags=["admin"])
async def rebuild_index():
    try:
        processed = note_service.rebuild_index()
        return {"success": True, "notes_indexed": processed}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
