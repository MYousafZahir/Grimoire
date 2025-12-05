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


class UpdateNoteRequest(BaseModel):
    note_id: str
    content: str
    parent_id: Optional[str] = None


class CreateNoteRequest(BaseModel):
    note_id: str
    title: str
    content: str = ""
    parent_id: Optional[str] = None


# Health check endpoints
@app.get("/")
async def root():
    return {"status": "ok", "message": "Grimoire backend is running"}


@app.get("/health")
async def health():
    return {"status": "ok", "message": "Grimoire backend is running"}


# Get single note content endpoint
@app.get("/note/{note_id}")
async def get_note(note_id: str):
    try:
        # Normalize note_id - replace slashes with underscores for flat file storage
        normalized_note_id = note_id.replace("/", "_")
        print(
            f"DEBUG: Getting note with id: {note_id}, normalized: {normalized_note_id}"
        )

        notes_dir = os.path.join(os.path.dirname(__file__), "storage", "notes")

        # Try to find the note file
        note_filename = f"{normalized_note_id}.json"
        note_filepath = os.path.join(notes_dir, note_filename)

        if not os.path.exists(note_filepath):
            # Also try without normalization in case note_id is already normalized
            note_filename = f"{note_id}.json"
            note_filepath = os.path.join(notes_dir, note_filename)

        if not os.path.exists(note_filepath):
            print(f"DEBUG: Note not found at {note_filepath}")
            raise HTTPException(status_code=404, detail="Note not found")

        with open(note_filepath, "r") as f:
            note_data = json.load(f)

        print(f"DEBUG: Loaded note from {note_filepath}")

        return {
            "note_id": note_id,
            "content": note_data.get("content", ""),
            "title": note_data.get("title", note_id),
        }

    except HTTPException:
        raise
    except Exception as e:
        print(f"ERROR in get_note: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


# Search endpoint
@app.post("/search")
async def search(request: SearchRequest):
    try:
        print(
            f"DEBUG: Search request for note_id: {request.note_id}, text length: {len(request.text)}"
        )

        # Chunk the search text using the correct method
        chunk_results = chunker.chunk(request.text, request.note_id)

        # Embed each chunk
        embeddings = []
        for chunk_data in chunk_results:
            embedding = embedder.embed(chunk_data["text"])
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
                        text=result["excerpt"],  # indexer returns 'excerpt' not 'text'
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


# Update note endpoint
@app.post("/update-note")
async def update_note(request: UpdateNoteRequest):
    try:
        note_id = request.note_id
        content = request.content
        parent_id = request.parent_id

        # Normalize note_id - replace slashes with underscores for flat file storage
        normalized_note_id = note_id.replace("/", "_")
        print(
            f"DEBUG: Updating note with id: {note_id}, normalized: {normalized_note_id}, parent_id: {parent_id}"
        )

        notes_dir = os.path.join(os.path.dirname(__file__), "storage", "notes")
        os.makedirs(notes_dir, exist_ok=True)

        # Use normalized note_id for filename
        note_filename = f"{normalized_note_id}.json"
        note_filepath = os.path.join(notes_dir, note_filename)

        is_new_note = not os.path.exists(note_filepath)

        if not is_new_note:
            # Load existing note data
            with open(note_filepath, "r") as f:
                note_data = json.load(f)
            note_data["content"] = content
            note_data["updated_at"] = str(os.path.getmtime(note_filepath))
        else:
            # Create new note - extract a readable title from the note_id
            title_parts = normalized_note_id.split("_")
            # Try to create a readable title - use last meaningful part
            if "note" in title_parts:
                title = "New Note"
            else:
                title = normalized_note_id.replace("_", " ")

            note_data = {
                "title": title,
                "content": content,
                "path": note_id,
                "parent_id": parent_id,
                "created_at": str(os.path.getctime(notes_dir)),
                "updated_at": str(os.path.getctime(notes_dir)),
            }

        with open(note_filepath, "w") as f:
            json.dump(note_data, f, indent=2)
        print(f"DEBUG: Wrote note data to {note_filepath}")

        # Update search index with the new/updated content
        try:
            print(f"DEBUG: Updating search index for note: {normalized_note_id}")

            # Chunk the content
            chunks = chunker.chunk(content, normalized_note_id)

            # Embed each chunk
            chunk_embeddings = []
            for chunk_data in chunks:
                embedding = embedder.embed(chunk_data["text"])
                chunk_embeddings.append(
                    {
                        "chunk_id": chunk_data["chunk_id"],
                        "text": chunk_data["text"],
                        "embedding": embedding,
                    }
                )

            # Update the index
            indexer.update_note(normalized_note_id, chunk_embeddings)
            print(
                f"DEBUG: Successfully updated search index for note: {normalized_note_id} with {len(chunk_embeddings)} chunks"
            )
        except Exception as e:
            print(
                f"WARNING: Failed to update search index for note {normalized_note_id}: {e}"
            )
            import traceback

            print(f"Traceback: {traceback.format_exc()}")
            # Don't fail the request if indexing fails

        # If this is a new note with a parent, update the parent folder's children
        if is_new_note and parent_id:
            # Normalize parent_id as well
            normalized_parent_id = parent_id.replace("/", "_")
            parent_filename = f"{normalized_parent_id}.folder.json"
            parent_filepath = os.path.join(notes_dir, parent_filename)
            print(f"DEBUG: Looking for parent folder at: {parent_filepath}")

            if os.path.exists(parent_filepath):
                with open(parent_filepath, "r") as f:
                    parent_data = json.load(f)

                if normalized_note_id not in parent_data.get("children", []):
                    parent_data.setdefault("children", []).append(normalized_note_id)
                    with open(parent_filepath, "w") as f:
                        json.dump(parent_data, f, indent=2)
                    print(
                        f"DEBUG: Updated parent folder {normalized_parent_id} with child {normalized_note_id}"
                    )
            else:
                print(f"DEBUG: Parent folder not found at {parent_filepath}")

        return {"success": True, "note_id": normalized_note_id}

    except Exception as e:
        print(f"ERROR in update_note: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


# Create note endpoint
@app.post("/create-note")
async def create_note(request: CreateNoteRequest):
    try:
        note_id = request.note_id
        title = request.title
        content = request.content
        parent_id = request.parent_id
        print(f"DEBUG: Creating note with id: {note_id}, title: {title}")

        notes_dir = os.path.join(os.path.dirname(__file__), "storage", "notes")
        os.makedirs(notes_dir, exist_ok=True)

        note_filename = f"{note_id}.json"
        note_filepath = os.path.join(notes_dir, note_filename)

        note_data = {
            "title": title,
            "content": content,
            "path": note_id,
            "parent_id": parent_id,
            "created_at": str(os.path.getctime(notes_dir)),
            "updated_at": str(os.path.getctime(notes_dir)),
        }

        with open(note_filepath, "w") as f:
            json.dump(note_data, f, indent=2)
        print(f"DEBUG: Wrote note data to {note_filepath}")

        # Update parent folder if needed
        if parent_id:
            parent_filename = f"{parent_id}.folder.json"
            parent_filepath = os.path.join(notes_dir, parent_filename)

            if os.path.exists(parent_filepath):
                with open(parent_filepath, "r") as f:
                    parent_data = json.load(f)

                if note_id not in parent_data.get("children", []):
                    parent_data.setdefault("children", []).append(note_id)
                    with open(parent_filepath, "w") as f:
                        json.dump(parent_data, f, indent=2)
                    print(
                        f"DEBUG: Updated parent folder {parent_id} with child {note_id}"
                    )

        return {
            "success": True,
            "note_id": note_id,
            "note": {
                "id": note_id,
                "title": title,
                "type": "note",
                "children": [],
            },
        }

    except Exception as e:
        print(f"ERROR in create_note: {str(e)}")
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
        print(f"DEBUG: Deleting note/folder: {note_id}")

        notes_dir = os.path.join(os.path.dirname(__file__), "storage", "notes")

        # Check if note exists
        note_path = os.path.join(notes_dir, f"{note_id}.json")
        folder_path = os.path.join(notes_dir, f"{note_id}.folder.json")

        if not os.path.exists(note_path) and not os.path.exists(folder_path):
            raise HTTPException(status_code=404, detail="Note not found")

        # Collect all note IDs that will be deleted (for index cleanup)
        notes_to_delete = []

        # Delete the file(s)
        if os.path.exists(note_path):
            notes_to_delete.append(note_id)
            os.remove(note_path)
            print(f"DEBUG: Deleted note file: {note_path}")

        if os.path.exists(folder_path):
            # If it's a folder, also delete all children
            with open(folder_path, "r") as f:
                folder_data = json.load(f)

            children = folder_data.get("children", [])
            for child_id in children:
                child_note_path = os.path.join(notes_dir, f"{child_id}.json")
                child_folder_path = os.path.join(notes_dir, f"{child_id}.folder.json")

                if os.path.exists(child_note_path):
                    notes_to_delete.append(child_id)
                    os.remove(child_note_path)
                    print(f"DEBUG: Deleted child note: {child_id}")
                if os.path.exists(child_folder_path):
                    os.remove(child_folder_path)
                    print(f"DEBUG: Deleted child folder: {child_id}")

            os.remove(folder_path)
            print(f"DEBUG: Deleted folder file: {folder_path}")

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

        # Remove from search index
        print(
            f"DEBUG: Removing {len(notes_to_delete)} note(s) from search index: {notes_to_delete}"
        )
        for deleted_note_id in notes_to_delete:
            try:
                success, _ = indexer.delete_note(deleted_note_id)
                if success:
                    print(f"DEBUG: Removed {deleted_note_id} from search index")
                else:
                    print(
                        f"DEBUG: Note {deleted_note_id} was not in search index (may not have had indexed content)"
                    )
            except Exception as e:
                print(f"WARNING: Failed to remove {deleted_note_id} from index: {e}")

        return {"success": True}

    except Exception as e:
        print(f"ERROR in delete_note: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


# Admin endpoint to rebuild search index
@app.post("/admin/rebuild-index")
async def rebuild_index():
    """
    Rebuild the entire search index from scratch.
    This will remove stale entries for deleted notes.
    """
    try:
        print("DEBUG: Starting index rebuild...")
        notes_dir = os.path.join(os.path.dirname(__file__), "storage", "notes")

        if not os.path.exists(notes_dir):
            return {
                "success": True,
                "message": "No notes directory found, nothing to index",
                "notes_indexed": 0,
            }

        # Clear the index
        indexer.clear()
        print("DEBUG: Cleared existing index")

        # Rebuild from all existing notes
        notes_indexed = 0
        notes_failed = []

        for filename in os.listdir(notes_dir):
            if filename.endswith(".json") and not filename.endswith(".folder.json"):
                note_path = os.path.join(notes_dir, filename)
                note_id = filename.replace(".json", "")

                try:
                    with open(note_path, "r") as f:
                        note_data = json.load(f)

                    content = note_data.get("content", "")
                    if content and content.strip():
                        # Chunk the content
                        chunks = chunker.chunk(content, note_id)

                        # Embed each chunk
                        chunk_embeddings = []
                        for chunk_data in chunks:
                            embedding = embedder.embed(chunk_data["text"])
                            chunk_embeddings.append(
                                {
                                    "chunk_id": chunk_data["chunk_id"],
                                    "text": chunk_data["text"],
                                    "embedding": embedding,
                                }
                            )

                        # Update the index
                        indexer.update_note(note_id, chunk_embeddings)
                        notes_indexed += 1
                        print(
                            f"DEBUG: Indexed note: {note_id} with {len(chunk_embeddings)} chunks"
                        )
                    else:
                        print(f"DEBUG: Skipped empty note: {note_id}")

                except Exception as e:
                    print(f"ERROR: Failed to index note {note_id}: {e}")
                    notes_failed.append(note_id)

        message = f"Successfully rebuilt index with {notes_indexed} notes"
        if notes_failed:
            message += f". Failed to index {len(notes_failed)} notes: {notes_failed}"

        print(f"DEBUG: {message}")

        return {
            "success": True,
            "message": message,
            "notes_indexed": notes_indexed,
            "notes_failed": len(notes_failed),
        }

    except Exception as e:
        print(f"ERROR in rebuild_index: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=8000)
