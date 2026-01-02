"""FastAPI entrypoint for the Grimoire backend."""

from __future__ import annotations

import asyncio
from pathlib import Path
from uuid import uuid4
import uvicorn
from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
import traceback

from models import (
    CreateFolderRequest,
    CreateNoteRequest,
    CreateProjectRequest,
    DeleteNoteRequest,
    GlossaryResponsePayload,
    GlossaryTermDetailPayload,
    NoteContentPayload,
    NotesResponsePayload,
    MoveItemRequest,
    OpenProjectRequest,
    ProjectInfoPayload,
    ProjectResponsePayload,
    ProjectsResponsePayload,
    RenameNoteRequest,
    SearchRequest,
    SearchResponsePayload,
    UpdateNoteRequest,
)
from context_models import ContextRequest, ContextResponsePayload, WarmupRequest, WarmupResponsePayload
from app_state import GrimoireAppState

app = FastAPI(title="Grimoire Backend", description="Semantic notes backend API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

state = GrimoireAppState()

_ALLOWED_IMAGE_EXTENSIONS: set[str] = {
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".heic",
    ".heif",
}
_MAX_ATTACHMENT_BYTES = 25 * 1024 * 1024


@app.get("/", tags=["health"])
async def root():
    return {"status": "ok", "message": "Grimoire backend is running"}


@app.get("/health", tags=["health"])
async def health():
    return {"status": "ok", "message": "Grimoire backend is running"}


@app.post("/attachments", tags=["attachments"])
async def upload_attachment(file: UploadFile = File(...)):
    try:
        if not file.filename:
            raise HTTPException(status_code=400, detail="Missing filename")
        ext = Path(file.filename).suffix.lower()
        if ext not in _ALLOWED_IMAGE_EXTENSIONS:
            raise HTTPException(status_code=400, detail=f"Unsupported image type: {ext or '(none)'}")
        if file.content_type and not file.content_type.startswith("image/"):
            raise HTTPException(status_code=400, detail=f"Unsupported content type: {file.content_type}")

        data = await file.read()
        if not data:
            raise HTTPException(status_code=400, detail="Empty upload")
        if len(data) > _MAX_ATTACHMENT_BYTES:
            raise HTTPException(status_code=413, detail="Attachment too large")

        services = state.current()
        attachments_dir = services.project.attachments_dir
        attachments_dir.mkdir(parents=True, exist_ok=True)

        filename = f"{uuid4().hex}{ext}"
        dest = (attachments_dir / filename).resolve()
        root = attachments_dir.resolve()
        if root not in dest.parents:
            raise HTTPException(status_code=400, detail="Invalid attachment path")

        await asyncio.to_thread(dest.write_bytes, data)
        return {"url": f"/attachments/{filename}", "filename": filename}
    except HTTPException:
        raise
    except Exception as exc:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(exc))


@app.get("/attachments/{filename}", tags=["attachments"])
async def get_attachment(filename: str):
    try:
        if not filename:
            raise HTTPException(status_code=400, detail="Missing attachment name")
        if Path(filename).name != filename:
            raise HTTPException(status_code=400, detail="Invalid attachment path")

        services = state.current()
        root = services.project.attachments_dir.resolve()
        path = (root / filename).resolve()
        if root not in path.parents:
            raise HTTPException(status_code=400, detail="Invalid attachment path")
        if not path.exists() or not path.is_file():
            raise HTTPException(status_code=404, detail="Attachment not found")

        return FileResponse(path=str(path))
    except HTTPException:
        raise
    except Exception as exc:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(exc))

@app.get("/projects", response_model=ProjectsResponsePayload, tags=["projects"])
async def list_projects():
    try:
        current_root = state.current().project.root
        projects = []
        for project in state.project_manager.list_projects():
            projects.append(
                ProjectInfoPayload(
                    name=project.name,
                    path=str(project.root),
                    is_active=project.root.resolve() == current_root.resolve(),
                )
            )
        # If the active project is external (opened by path), include it too.
        if not any(p.is_active for p in projects):
            active = state.current().project
            projects.insert(
                0,
                ProjectInfoPayload(
                    name=active.name,
                    path=str(active.root),
                    is_active=True,
                ),
            )
        return ProjectsResponsePayload(projects=projects)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.get("/projects/current", response_model=ProjectResponsePayload, tags=["projects"])
async def current_project():
    try:
        project = state.current().project
        return ProjectResponsePayload(
            project=ProjectInfoPayload(name=project.name, path=str(project.root), is_active=True)
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/projects/create", response_model=ProjectResponsePayload, tags=["projects"])
async def create_project(request: CreateProjectRequest):
    try:
        services = state.create_project(request.name)
        project = services.project
        return ProjectResponsePayload(
            project=ProjectInfoPayload(name=project.name, path=str(project.root), is_active=True)
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/projects/open", response_model=ProjectResponsePayload, tags=["projects"])
async def open_project(request: OpenProjectRequest):
    try:
        services = state.open_project(name=request.name, path=request.path)
        project = services.project
        return ProjectResponsePayload(
            project=ProjectInfoPayload(name=project.name, path=str(project.root), is_active=True)
        )
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Project not found")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.get("/notes", response_model=NotesResponsePayload, tags=["notes"])
async def notes():
    try:
        return state.current().notes.tree()
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.get("/glossary", response_model=GlossaryResponsePayload, tags=["glossary"])
async def glossary():
    try:
        services = state.current()
        services.glossary.ensure_built()
        terms = []
        for entry in services.glossary.list_entries():
            terms.append(
                {
                    "concept_id": entry.concept_id,
                    "display_name": entry.display_name,
                    "kind": entry.kind,
                    "chunk_count": int(len(entry.chunk_ids)),
                    "definition_excerpt": entry.definition_excerpt,
                    "source_note_id": entry.source_note_id,
                    "last_updated": float(entry.last_updated),
                }
            )
        return GlossaryResponsePayload(terms=terms)
    except Exception as exc:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(exc))


@app.get("/glossary/{concept_id}", response_model=GlossaryTermDetailPayload, tags=["glossary"])
async def glossary_term(concept_id: str):
    try:
        services = state.current()
        services.glossary.ensure_built()
        entry = services.glossary.entry(concept_id)
        if entry is None:
            raise HTTPException(status_code=404, detail="Term not found")
        supporting = [
            {"chunk_id": cid, "note_id": nid, "excerpt": ex}
            for (cid, nid, ex) in (entry.supporting or [])
        ]
        return GlossaryTermDetailPayload(
            concept_id=entry.concept_id,
            display_name=entry.display_name,
            kind=entry.kind,
            chunk_count=int(len(entry.chunk_ids)),
            surface_forms=entry.surface_forms,
            definition_excerpt=entry.definition_excerpt,
            definition_chunk_id=entry.definition_chunk_id,
            source_note_id=entry.source_note_id,
            supporting=supporting,
        )
    except HTTPException:
        raise
    except Exception as exc:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(exc))


@app.get("/all-notes", response_model=NotesResponsePayload, tags=["notes"])
async def all_notes():
    return await notes()


@app.get("/note/{note_id:path}", response_model=NoteContentPayload, tags=["notes"])
async def get_note(note_id: str):
    try:
        return state.current().notes.get_note(note_id)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/update-note", tags=["notes"])
async def update_note(request: UpdateNoteRequest):
    try:
        record = state.current().notes.save_note(request)
        return {"success": True, "note_id": record.id}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/create-note", tags=["notes"])
async def create_note(request: CreateNoteRequest):
    try:
        record = state.current().notes.create_note(request)
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
        folder = state.current().notes.create_folder(request)
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
        new_id = state.current().notes.rename_item(request.old_note_id, request.new_note_id)
        return {"success": True, "note_id": new_id}
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/move-item", tags=["notes"])
async def move_item(request: MoveItemRequest):
    try:
        record = state.current().notes.move_item(request.note_id, request.parent_id)
        return {"success": True, "note_id": record.id, "parent_id": record.parent_id}
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/delete-note", tags=["notes"])
async def delete(request: DeleteNoteRequest):
    try:
        deleted = state.current().notes.delete_item(request.note_id)
        return {"success": True, "deleted": deleted}
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="Note not found")
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/search", response_model=SearchResponsePayload, tags=["search"])
async def search(request: SearchRequest):
    try:
        hits = await asyncio.to_thread(state.current().search.search, request)
        return SearchResponsePayload(results=hits)
    except Exception as exc:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/context", response_model=ContextResponsePayload, tags=["search"])
async def context(request: ContextRequest):
    try:
        hits = await asyncio.to_thread(state.current().notes.semantic_context, request)
        return ContextResponsePayload(results=hits)
    except Exception as exc:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/admin/rebuild-index", tags=["admin"])
async def rebuild_index():
    try:
        processed = await asyncio.to_thread(state.current().notes.rebuild_index)
        return {"success": True, "notes_indexed": processed}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/admin/rebuild-glossary", tags=["admin"])
async def rebuild_glossary():
    try:
        services = state.current()
        count = await asyncio.to_thread(services.glossary.rebuild)
        return {
            "success": True,
            "terms": int(count),
            "spacy_notes": int(getattr(services.glossary, "last_build_spacy_notes", 0)),
            "fallback_notes": int(getattr(services.glossary, "last_build_fallback_notes", 0)),
        }
    except Exception as exc:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/admin/warmup", response_model=WarmupResponsePayload, tags=["admin"])
async def warmup(request: WarmupRequest = WarmupRequest()):
    try:
        services = state.current()
        records = services.storage.list_records()
        # When force_rebuild is requested, rebuild both the semantic-context index
        # and the classic search index to keep the app consistent after upgrades.
        if request.force_rebuild:
            await asyncio.to_thread(services.notes.rebuild_index)
        return await asyncio.to_thread(
            services.context.warmup,
            records.values(),
            bool(request.force_rebuild),
        )
    except Exception as exc:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=str(exc))


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
