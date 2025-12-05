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
    text: str
    score: float


class NoteInfo(BaseModel):
    id: str
    title: str
    type: Optional[str] = None
    children: List[str] = []


class CreateFolderRequest(BaseModel):
    folder_path: str


class RenameNoteRequest(BaseModel):
    old_note_id: str
    new_note_id: str


class DeleteNoteRequest(BaseModel):
    note_id: str


# Health check endpoint
@app.get("/")
async def root():
    return {"status": "ok", "message": "Grimoire backend is running"}


# Search endpoint
@app.post("/search")
async def search(request: SearchRequest):
    try:
        # Chunk the search text
        chunks = chunker.chunk_text(request.text)

        # Embed each chunk
        embeddings = []
        for chunk in chunks:
            embedding = embedder.embed_text(chunk)
            embeddings.append(embedding)

        # Search the index
        results = []
        for i, embedding in enumerate(embeddings):
            search_results = indexer.search(embedding, top_k=5)
            for result in search_results:
                results.append(
                    SearchResult(
                        note_id=result["note_id"],
                        chunk_id=result["chunk_id"],
                        text=result["text"],
                        score=result["score"],
                    )
                )

        # Deduplicate and sort by score
        unique_results = {}
        for result in results:
            key = (result.note_id, result.chunk_id)
            if key not in unique_results or result.score > unique_results[key].score:
                unique_results[key] = result

        sorted_results = sorted(
            unique_results.values(), key=lambda x: x.score, reverse=True
        )

        return {"results": sorted_results[:10]}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Get all notes endpoint
@app.get("/notes")
async def get_notes():
    try:
        # Get all notes from storage
        notes_dir = os.path.join(os.path.dirname(__file__), "storage", "notes")
        if not os.path.exists(notes_dir):
            return {"notes": []}

        notes = []
        for filename in os.listdir(notes_dir):
            if filename.endswith(".json"):
                note_path = os.path.join(notes_dir, filename)
                with open(note_path, "r") as f:
                    note_data = json.load(f)

                # Determine if it's a folder (has .folder.json suffix)
                is_folder = filename.endswith(".folder.json")
                note_id = filename.replace(".json", "").replace(".folder", "")

                notes.append(
                    NoteInfo(
                        id=note_id,
                        title=note_data.get("title", "Untitled"),
                        type="folder" if is_folder else "note",
                        children=note_data.get("children", []),
                    )
                )

        return {"notes": notes}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Create folder endpoint
@app.post("/create-folder")
async def create_folder(request: CreateFolderRequest):
    try:
        folder_path = request.folder_path
        print(f"DEBUG: Creating folder with path: {folder_path}")

        # Create folder metadata file
        notes_dir = os.path.join(os.path.dirname(__file__), "storage", "notes")
        os.makedirs(notes_dir, exist_ok=True)

        folder_id = folder_path.replace("/", "_")
        folder_filename = f"{folder_id}.folder.json"
        folder_filepath = os.path.join(notes_dir, folder_filename)
        print(f"DEBUG: Folder ID: {folder_id}, filename: {folder_filename}")

        folder_data = {
            "title": os.path.basename(folder_path),
            "path": folder_path,
            "children": [],
            "created_at": str(os.path.getctime(folder_filepath))
            if os.path.exists(folder_filepath)
            else str(os.path.getctime(notes_dir)),
            "updated_at": str(os.path.getctime(folder_filepath))
            if os.path.exists(folder_filepath)
            else str(os.path.getctime(notes_dir)),
        }

        with open(folder_filepath, "w") as f:
            json.dump(folder_data, f, indent=2)
        print(f"DEBUG: Wrote folder data to {folder_filepath}")

        # Update parent folder if needed
        parent_path = os.path.dirname(folder_path)
        if parent_path and parent_path != ".":
            parent_id = parent_path.replace("/", "_")
            parent_filename = f"{parent_id}.folder.json"
            parent_filepath = os.path.join(notes_dir, parent_filename)
            print(f"DEBUG: Parent path: {parent_path}, parent ID: {parent_id}")

            if os.path.exists(parent_filepath):
                with open(parent_filepath, "r") as f:
                    parent_data = json.load(f)

                if folder_id not in parent_data.get("children", []):
                    parent_data.setdefault("children", []).append(folder_id)
                    with open(parent_filepath, "w") as f:
                        json.dump(parent_data, f, indent=2)
                    print(
                        f"DEBUG: Updated parent folder {parent_id} with child {folder_id}"
                    )

        # Return full folder data for frontend to update optimistically
        response_data = {
            "success": True,
            "folder_id": folder_id,
            "folder": {
                "id": folder_id,
                "title": os.path.basename(folder_path),
                "type": "folder",
                "children": [],
            },
        }
        print(f"DEBUG: Returning response: {response_data}")
        return response_data

    except Exception as e:
        print(f"ERROR in create_folder: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


# Rename note endpoint
@app.post("/rename-note")
async def rename_note(request: RenameNoteRequest):
    try:
        old_note_id = request.old_note_id
        new_note_id = request.new_note_id

        notes_dir = os.path.join(os.path.dirname(__file__), "storage", "notes")

        # Check if old note exists
        old_note_path = os.path.join(notes_dir, f"{old_note_id}.json")
        old_folder_path = os.path.join(notes_dir, f"{old_note_id}.folder.json")

        if not os.path.exists(old_note_path) and not os.path.exists(old_folder_path):
            raise HTTPException(status_code=404, detail="Note not found")

        # Rename the file
        if os.path.exists(old_note_path):
            new_note_path = os.path.join(notes_dir, f"{new_note_id}.json")
            os.rename(old_note_path, new_note_path)

            # Update the note data
            with open(new_note_path, "r") as f:
                note_data = json.load(f)

            note_data["title"] = new_note_id.replace("_", " ")
            with open(new_note_path, "w") as f:
                json.dump(note_data, f, indent=2)

        if os.path.exists(old_folder_path):
            new_folder_path = os.path.join(notes_dir, f"{new_note_id}.folder.json")
            os.rename(old_folder_path, new_folder_path)

            # Update the folder data
            with open(new_folder_path, "r") as f:
                folder_data = json.load(f)

            folder_data["title"] = new_note_id.replace("_", " ")
            with open(new_folder_path, "w") as f:
                json.dump(folder_data, f, indent=2)

        # Update parent references
        for filename in os.listdir(notes_dir):
            if filename.endswith(".folder.json"):
                filepath = os.path.join(notes_dir, filename)
                with open(filepath, "r") as f:
                    data = json.load(f)

                if "children" in data and old_note_id in data["children"]:
                    data["children"] = [
                        new_note_id if child == old_note_id else child
                        for child in data["children"]
                    ]
                    with open(filepath, "w") as f:
                        json.dump(data, f, indent=2)

        return {"success": True}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# Delete note endpoint
@app.post("/delete-note")
async def delete_note(request: DeleteNoteRequest):
    try:
        note_id = request.note_id

        notes_dir = os.path.join(os.path.dirname(__file__), "storage", "notes")

        # Check if note exists
        note_path = os.path.join(notes_dir, f"{note_id}.json")
        folder_path = os.path.join(notes_dir, f"{note_id}.folder.json")

        if not os.path.exists(note_path) and not os.path.exists(folder_path):
            raise HTTPException(status_code=404, detail="Note not found")

        # Delete the file(s)
        if os.path.exists(note_path):
            os.remove(note_path)

        if os.path.exists(folder_path):
            # If it's a folder, also delete all children
            with open(folder_path, "r") as f:
                folder_data = json.load(f)

            children = folder_data.get("children", [])
            for child_id in children:
                child_note_path = os.path.join(notes_dir, f"{child_id}.json")
                child_folder_path = os.path.join(notes_dir, f"{child_id}.folder.json")

                if os.path.exists(child_note_path):
                    os.remove(child_note_path)
                if os.path.exists(child_folder_path):
                    os.remove(child_folder_path)

            os.remove(folder_path)

        # Remove from parent references
        for filename in os.listdir(notes_dir):
            if filename.endswith(".folder.json"):
                filepath = os.path.join(notes_dir, filename)
                with open(filepath, "r") as f:
                    data = json.load(f)

                if "children" in data and note_id in data["children"]:
                    data["children"].remove(note_id)
                    with open(filepath, "w") as f:
                        json.dump(data, f, indent=2)

        return {"success": True}

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
