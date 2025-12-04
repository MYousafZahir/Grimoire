"""
Indexer module for Grimoire.

Manages FAISS index for semantic search and chunk metadata storage.
"""

import copy
import json
import os
from typing import Dict, List, Optional

import numpy as np


class Indexer:
    """Manages FAISS index and chunk metadata for semantic search."""

    def __init__(
        self,
        index_path: str = "storage/faiss.index",
        metadata_path: str = "storage/index.json",
        note_tree_path: str = "storage/note_tree.json",
    ):
        """
        Initialize the indexer.

        Args:
            index_path: Path to FAISS index file
            metadata_path: Path to chunk metadata JSON file
            note_tree_path: Path to note tree JSON file
        """
        self.index_path = index_path
        self.metadata_path = metadata_path
        self.note_tree_path = note_tree_path
        self.index = None
        self.metadata = {}
        self.note_tree = {}

        # Load existing index and metadata if available
        self._load_metadata()
        self._load_or_create_index()
        self._load_note_tree()

    def _load_metadata(self):
        """Load chunk metadata from JSON file."""
        try:
            if os.path.exists(self.metadata_path):
                with open(self.metadata_path, "r", encoding="utf-8") as f:
                    self.metadata = json.load(f)
                print(f"Loaded metadata for {len(self.metadata)} chunks")
            else:
                self.metadata = {}
                print("No existing metadata found, starting fresh")
        except Exception as e:
            print(f"Failed to load metadata: {e}")
            self.metadata = {}

    def _save_metadata(self):
        """Save chunk metadata to JSON file."""
        try:
            os.makedirs(os.path.dirname(self.metadata_path), exist_ok=True)
            with open(self.metadata_path, "w", encoding="utf-8") as f:
                json.dump(self.metadata, f, indent=2)
            return True
        except Exception as e:
            print(f"Failed to save metadata: {e}")
            import traceback

            traceback.print_exc()
            return False

    def _load_note_tree(self):
        """Load note tree from JSON file."""
        try:
            if os.path.exists(self.note_tree_path):
                with open(self.note_tree_path, "r", encoding="utf-8") as f:
                    self.note_tree = json.load(f)
                print(f"Loaded note tree from {self.note_tree_path}")
            else:
                self.note_tree = {}
                print("No existing note tree found, starting fresh")
        except Exception as e:
            print(f"Failed to load note tree: {e}")
            self.note_tree = {}

    def _save_note_tree(self):
        """Save note tree to JSON file."""
        try:
            os.makedirs(os.path.dirname(self.note_tree_path), exist_ok=True)
            with open(self.note_tree_path, "w", encoding="utf-8") as f:
                json.dump(self.note_tree, f, indent=2)
            print(f"Saved note tree to {self.note_tree_path}")
            return True
        except Exception as e:
            print(f"Failed to save note tree: {e}")
            import traceback

            traceback.print_exc()
            return False

    def _load_or_create_index(self):
        """Load existing FAISS index or create a new one."""
        try:
            import faiss

            if os.path.exists(self.index_path):
                print(f"Loading FAISS index from {self.index_path}")
                self.index = faiss.read_index(self.index_path)
                print(f"Index loaded with {self.index.ntotal} vectors")
            else:
                print("No existing FAISS index found, will create when needed")
                self.index = None

        except ImportError:
            print("FAISS not installed. Install with: pip install faiss-cpu")
            self.index = None
        except Exception as e:
            print(f"Failed to load FAISS index: {e}")
            self.index = None

    def _create_index(self, embedding_dim: int):
        """Create a new FAISS index with the given dimension."""
        try:
            import faiss

            print(f"Creating new FAISS index with dimension {embedding_dim}")
            # Use IndexFlatIP for cosine similarity (vectors should be normalized)
            self.index = faiss.IndexFlatIP(embedding_dim)

            # Save the empty index
            os.makedirs(os.path.dirname(self.index_path), exist_ok=True)
            faiss.write_index(self.index, self.index_path)

        except ImportError:
            raise ImportError(
                "FAISS not installed. Install with: pip install faiss-cpu"
            )
        except Exception as e:
            raise RuntimeError(f"Failed to create FAISS index: {e}")

    def update_note(self, note_id: str, chunk_embeddings: List[Dict]):
        """
        Update a note in the index.

        Args:
            note_id: ID of the note
            chunk_embeddings: List of dicts with chunk_id, text, and embedding

        Returns:
            bool: True if update was successful, False otherwise
        """
        # Remove existing chunks for this note
        self._remove_note_chunks(note_id)

        if not chunk_embeddings:
            return True

        # Add new chunks
        for chunk_data in chunk_embeddings:
            chunk_id = chunk_data["chunk_id"]

            # Store metadata
            self.metadata[chunk_id] = {
                "note_id": note_id,
                "chunk_id": chunk_id,
                "text": chunk_data["text"],
                "embedding": chunk_data["embedding"],
            }

            # Add to FAISS index
            self._add_to_index(chunk_id, chunk_data["embedding"])

        # Update note tree
        note_tree_saved = self._update_note_tree(note_id)

        # Save changes and return success status
        metadata_saved = self._save_metadata()
        index_saved = self._save_index()

        if metadata_saved and index_saved and note_tree_saved:
            print(f"Updated note: {note_id}")
            return True
        else:
            print(
                f"Warning: Failed to save metadata, index, or note tree when updating note: {note_id}, but update was performed in memory"
            )
            return False

    def _remove_note_chunks(self, note_id: str):
        """Remove all chunks for a given note from the index."""
        chunks_to_remove = []

        # Find all chunks for this note
        for chunk_id, metadata in self.metadata.items():
            if metadata["note_id"] == note_id:
                chunks_to_remove.append(chunk_id)

        # Remove from metadata
        for chunk_id in chunks_to_remove:
            del self.metadata[chunk_id]

        # Rebuild index if we have FAISS
        if self.index and chunks_to_remove:
            self._rebuild_index()

    def _add_to_index(self, chunk_id: str, embedding: List[float]):
        """Add a single embedding to the FAISS index."""
        if self.index is None:
            # Create index with correct dimension
            self._create_index(len(embedding))

        # Convert to numpy array and reshape for FAISS
        embedding_np = np.array([embedding], dtype=np.float32)

        # Add to index
        self.index.add(embedding_np)

        # Store the index position in metadata
        if chunk_id in self.metadata:
            self.metadata[chunk_id]["index_position"] = self.index.ntotal - 1

    def _rebuild_index(self):
        """Rebuild the FAISS index from current metadata."""
        if not self.metadata:
            self.index = None
            return

        # Get embedding dimension from first chunk
        first_chunk = next(iter(self.metadata.values()))
        embedding_dim = len(first_chunk["embedding"])

        # Create new index
        try:
            import faiss

            self.index = faiss.IndexFlatIP(embedding_dim)

            # Add all embeddings
            embeddings = []
            for chunk_id, metadata in self.metadata.items():
                embedding = metadata["embedding"]
                embeddings.append(embedding)

                # Update index position
                metadata["index_position"] = len(embeddings) - 1

            if embeddings:
                embeddings_np = np.array(embeddings, dtype=np.float32)
                self.index.add(embeddings_np)

        except ImportError:
            self.index = None

    def _save_index(self):
        """Save the FAISS index to disk."""
        if self.index is not None:
            try:
                import faiss

                os.makedirs(os.path.dirname(self.index_path), exist_ok=True)
                faiss.write_index(self.index, self.index_path)
                return True
            except Exception as e:
                print(f"Failed to save FAISS index: {e}")
                import traceback

                traceback.print_exc()
                return False
        return True  # Return True if no index to save

    def search(
        self, query_embedding: List[float], exclude_note_id: str = None, top_k: int = 10
    ) -> List[Dict]:
        """
        Search for similar chunks.

        Args:
            query_embedding: Query embedding vector
            exclude_note_id: Optional note ID to exclude from results
            top_k: Number of results to return

        Returns:
            List of search results with note_id, chunk_id, excerpt, and score
        """
        if self.index is None or self.index.ntotal == 0:
            return []

        # Convert query to numpy array
        query_np = np.array([query_embedding], dtype=np.float32)

        try:
            # Search the index
            distances, indices = self.index.search(
                query_np, min(top_k * 2, self.index.ntotal)
            )

            results = []
            seen_chunks = set()

            # Convert indices to chunk metadata
            for i, (distance, idx) in enumerate(zip(distances[0], indices[0])):
                if idx == -1:  # No more results
                    continue

                # Find chunk by index position
                chunk_id = None
                for cid, metadata in self.metadata.items():
                    if metadata.get("index_position") == idx:
                        chunk_id = cid
                        break

                if not chunk_id or chunk_id in seen_chunks:
                    continue

                metadata = self.metadata[chunk_id]

                # Skip if excluding this note
                if exclude_note_id and metadata["note_id"] == exclude_note_id:
                    continue

                # Convert cosine similarity from FAISS (assuming normalized vectors)
                score = float(distance)

                results.append(
                    {
                        "note_id": metadata["note_id"],
                        "chunk_id": chunk_id,
                        "excerpt": metadata["text"],
                        "score": score,
                    }
                )

                seen_chunks.add(chunk_id)

                if len(results) >= top_k:
                    break

            # Sort by score (descending)
            results.sort(key=lambda x: x["score"], reverse=True)
            return results

        except Exception as e:
            print(f"Search failed: {e}")
            return []

    def _update_note_tree(self, note_id: str) -> bool:
        """Update the note tree structure.

        Returns:
            bool: True if note tree was successfully saved, False otherwise
        """
        # Extract path from note_id (e.g., "parent/child/note" -> ["parent", "child"])
        parts = note_id.split("/")

        current = self.note_tree
        for i, part in enumerate(parts[:-1]):  # Skip the actual note name
            if part not in current:
                current[part] = {"type": "folder"}
            else:
                # Ensure existing folder has type field set
                if not isinstance(current[part], dict):
                    current[part] = {"type": "folder"}
                elif "type" not in current[part]:
                    current[part]["type"] = "folder"
            current = current[part]

        # Add the note to the tree
        note_name = parts[-1]
        if note_name not in current:
            current[note_name] = {"type": "note", "id": note_id}

        # Save the updated tree
        save_result = self._save_note_tree()
        if not save_result:
            print(f"Warning: Failed to save note tree after updating note: {note_id}")
            return False
        return True

    def create_folder(self, folder_path: str):
        """Create a folder in the note tree."""
        try:
            parts = folder_path.split("/")

            current = self.note_tree
            for part in parts:
                if part not in current:
                    current[part] = {"type": "folder"}
                else:
                    # Ensure existing folder has type field set
                    if not isinstance(current[part], dict):
                        current[part] = {"type": "folder"}
                    elif "type" not in current[part]:
                        current[part]["type"] = "folder"
                current = current[part]

            # Ensure the final folder has type: "folder"
            if not isinstance(current, dict):
                # This shouldn't happen since we set it above, but just in case
                current = {"type": "folder"}
            elif "type" not in current:
                current["type"] = "folder"

            # Mark as folder (not a note)
            # Folders are represented as dicts with type: "folder"
            success = self._save_note_tree()
            if success:
                print(f"Created folder: {folder_path}")
                return True
            else:
                print(
                    f"Warning: Failed to save note tree for folder: {folder_path}, but folder was created in memory"
                )
                return False  # Return False when save fails
        except Exception as e:
            print(f"Error in create_folder: {e}")
            import traceback

            traceback.print_exc()
            return False  # Return False on exception

    def rename_note(self, old_note_id: str, new_note_id: str):
        """Rename a note or folder in the index."""
        # Check if it's a note with metadata or a folder in the note tree
        is_note = old_note_id in [m["note_id"] for m in self.metadata.values()]
        is_folder = self._note_exists_in_tree(old_note_id)

        if not (is_note or is_folder):
            print(f"Note/folder {old_note_id} not found")
            return False

        # Update metadata if it's a note
        if is_note:
            for chunk_id, metadata in list(self.metadata.items()):
                if metadata["note_id"] == old_note_id:
                    metadata["note_id"] = new_note_id

        # For folders, we need to update the tree structure
        # _update_folder_in_tree will handle removal and recreation
        if is_folder:
            folder_updated = self._update_folder_in_tree(old_note_id, new_note_id)
            note_tree_saved = folder_updated
        else:
            # For notes, remove from old location and add to new
            self._remove_from_note_tree(old_note_id)
            note_tree_saved = self._update_note_tree(new_note_id)

        metadata_saved = self._save_metadata()

        if metadata_saved and note_tree_saved:
            print(
                f"Renamed {'folder' if is_folder else 'note'} from {old_note_id} to {new_note_id}"
            )
            return True
        else:
            print(
                f"Warning: Failed to save metadata or note tree when renaming {old_note_id} to {new_note_id}, but rename was performed in memory"
            )
            return False  # Return False when save fails

    def _note_exists_in_tree(self, note_id: str) -> bool:
        """Check if a note or folder exists in the tree."""
        parts = note_id.split("/")

        def exists_recursive(node, path_parts):
            if not path_parts:
                return True

            current_part = path_parts[0]
            if current_part not in node:
                return False

            if len(path_parts) == 1:
                return True
            else:
                return exists_recursive(node[current_part], path_parts[1:])

        return exists_recursive(self.note_tree, parts)

    def _update_folder_in_tree(self, old_folder_id: str, new_folder_id: str) -> bool:
        """Update a folder's location in the tree.

        Returns:
            bool: True if folder was successfully updated, False otherwise
        """
        # Get the old folder and its contents
        old_parts = old_folder_id.split("/")
        new_parts = new_folder_id.split("/")

        # Navigate to the old folder and make a deep copy of its contents
        old_parent = self.note_tree
        old_folder_contents = None
        for i, part in enumerate(old_parts):
            if part not in old_parent:
                print(f"Folder not found: {old_folder_id}")
                return False
            if i == len(old_parts) - 1:
                # This is the folder itself - make a deep copy before removal
                old_folder_contents = copy.deepcopy(old_parent[part])
                # If folder is empty ({}), ensure it has type: "folder"
                if old_folder_contents == {}:
                    old_folder_contents = {"type": "folder"}
            else:
                old_parent = old_parent[part]

        # old_folder_contents should always be set at this point if we didn't return False
        if old_folder_contents is None:
            print(
                f"Unexpected error: Failed to get folder contents for {old_folder_id}"
            )
            return False

        # Remove from old location

        removed = self._remove_from_note_tree(old_folder_id)
        if not removed:
            print(
                f"Warning: Failed to remove folder from old location: {old_folder_id}"
            )

        # Add to new location with folder type
        current = self.note_tree
        for part in new_parts:
            if part not in current:
                current[part] = {"type": "folder"}
            else:
                # Ensure existing folder has type field set
                if not isinstance(current[part], dict):
                    current[part] = {"type": "folder"}
                elif "type" not in current[part]:
                    current[part]["type"] = "folder"

            current = current[part]

        # Ensure the final folder has type: "folder"
        if not isinstance(current, dict):
            current = {"type": "folder"}
        elif "type" not in current:
            current["type"] = "folder"

        # Copy contents from old folder to new folder
        # We need to update paths for all items in the folder

        def update_paths_in_subtree(subtree, old_base_path, new_base_path):
            """Recursively update paths in a subtree."""
            result = {}
            for name, data in subtree.items():
                if isinstance(data, dict):
                    if data.get("type") == "note":
                        # Update note ID
                        old_note_id = data.get("id", "")
                        if old_note_id.startswith(old_base_path + "/"):
                            new_note_id = (
                                new_base_path + old_note_id[len(old_base_path) :]
                            )
                            result[name] = {"type": "note", "id": new_note_id}
                        else:
                            result[name] = copy.deepcopy(data)
                    else:
                        # This is a subfolder or folder
                        result[name] = update_paths_in_subtree(
                            data,
                            old_base_path + "/" + name if old_base_path else name,
                            new_base_path + "/" + name if new_base_path else name,
                        )
                        # Ensure folder has type
                        if "type" not in result[name]:
                            result[name]["type"] = "folder"
                else:
                    result[name] = data
            return result

        # Update all paths in the copied subtree
        updated_contents = update_paths_in_subtree(
            old_folder_contents, old_folder_id, new_folder_id
        )

        # Merge updated contents into new location
        for key, value in updated_contents.items():
            current[key] = value

        # If the folder was empty, ensure it has type: "folder" in the new location
        if not updated_contents and "type" not in current:
            current["type"] = "folder"

        # Save the updated tree
        save_result = self._save_note_tree()
        if not save_result:
            print(
                f"Warning: Failed to save note tree after updating folder: {old_folder_id} -> {new_folder_id}"
            )
            return False

        print(f"Updated folder from {old_folder_id} to {new_folder_id}")
        return True

    def _remove_from_note_tree(self, note_id: str) -> bool:
        """Remove a note or folder from the tree structure.

        Returns:
            bool: True if the note/folder was successfully removed, False otherwise
        """
        parts = note_id.split("/")

        def remove_recursive(node, path_parts):
            if not path_parts:
                return True

            current_part = path_parts[0]

            if current_part not in node:
                return False

            if len(path_parts) == 1:
                # This is the note or folder to remove
                del node[current_part]
                return True
            else:
                # Continue deeper
                if remove_recursive(node[current_part], path_parts[1:]):
                    # Clean up empty folders
                    if not node[current_part]:
                        del node[current_part]
                    return True
                return False

        success = remove_recursive(self.note_tree, parts)
        if not success:
            print(f"Warning: Failed to remove note/folder from tree: {note_id}")
        return success

    def delete_note(self, note_id: str):
        """Delete a note or folder from the index.

        Returns:
            tuple: (success, deleted_note_ids) where success is a boolean and
                   deleted_note_ids is a list of note IDs that were deleted
                   (for folders, includes all notes inside the folder)
        """
        # Check if the item exists
        if not self._note_exists_in_tree(note_id):
            # Also check if it exists in metadata (for notes that might not be in tree yet)
            has_metadata = any(
                metadata["note_id"] == note_id for metadata in self.metadata.values()
            )
            if not has_metadata:
                print(f"Note/folder not found: {note_id}")
                return False, []

        # Check if this is a folder by looking at the note tree structure
        def is_item_folder(item_id: str) -> bool:
            """Check if an item is a folder by traversing the note tree."""
            parts = item_id.split("/")
            node = self.note_tree
            for i, part in enumerate(parts):
                if part not in node:
                    return False
                if i == len(parts) - 1:
                    # This is the item itself
                    item_data = node[part]
                    # Check if it's marked as a folder or has children (is a dict with other items)
                    if isinstance(item_data, dict):
                        if item_data.get("type") == "folder":
                            return True
                        # If it's a dict with keys other than "type" and "id", it's a folder
                        keys = set(item_data.keys())
                        if len(keys) > 2 or (keys - {"type", "id"}):
                            return True
                    return False
                else:
                    node = node[part]
            return False

        is_folder = is_item_folder(note_id)

        notes_to_delete = []

        if is_folder:
            # For folders, find all notes inside recursively
            def collect_notes_from_tree(node, current_path=""):
                notes = []
                for name, data in node.items():
                    if isinstance(data, dict):
                        if data.get("type") == "note":
                            # This is a note
                            note_path = (
                                f"{current_path}/{name}" if current_path else name
                            )
                            notes.append(data.get("id", note_path))
                        else:
                            # This is a folder, recurse into it
                            folder_path = (
                                f"{current_path}/{name}" if current_path else name
                            )
                            notes.extend(collect_notes_from_tree(data, folder_path))
                return notes

            # Find the folder in the tree
            parts = note_id.split("/")
            node = self.note_tree
            for part in parts:
                if part in node:
                    node = node[part]
                else:
                    # Folder not found
                    print(f"Folder not found: {note_id}")
                    return False, []

            # Double-check this is actually a folder
            if not is_folder:
                # This shouldn't happen if is_item_folder returned True, but just in case
                print(
                    f"Warning: Item {note_id} was identified as folder but doesn't appear to be one"
                )
                # Treat it as a regular note
                notes_to_delete = [note_id]
                is_folder = False
            else:
                # Collect all notes in this folder and subfolders
                notes_to_delete = collect_notes_from_tree(node)

            # Also include the folder itself if it has a note ID (unlikely but possible)
            if any(
                metadata["note_id"] == note_id for metadata in self.metadata.values()
            ):
                notes_to_delete.append(note_id)
        else:
            # For regular notes, just delete this note
            notes_to_delete = [note_id]

        # Remove chunks from metadata for all notes to delete
        chunks_to_remove = []
        for chunk_id, metadata in self.metadata.items():
            if metadata["note_id"] in notes_to_delete:
                chunks_to_remove.append(chunk_id)

        for chunk_id in chunks_to_remove:
            del self.metadata[chunk_id]

        # Remove from note tree
        self._remove_from_note_tree(note_id)

        # Rebuild index
        self._rebuild_index()

        metadata_saved = self._save_metadata()
        index_saved = self._save_index()
        note_tree_saved = self._save_note_tree()

        if metadata_saved and index_saved and note_tree_saved:
            print(f"Deleted {'folder' if is_folder else 'note'}: {note_id}")
            if is_folder and notes_to_delete:
                print(f"  Also deleted {len(notes_to_delete)} notes inside the folder")
            return True, notes_to_delete
        else:
            print(
                f"Warning: Failed to save when deleting {'folder' if is_folder else 'note'}: {note_id}, but deletion was performed in memory"
            )
            return (
                False,
                notes_to_delete,
            )  # Return False when save fails, but still return the list

    def get_note_tree(self) -> List[Dict]:
        """
        Get the hierarchical note structure for the sidebar.

        Returns:
            List of NoteInfo objects representing the tree
        """

        def build_tree(node: Dict, path: str = "") -> List[Dict]:
            result = []

            for name, data in node.items():
                if isinstance(data, dict):
                    if data.get("type") == "note":
                        # This is a note
                        result.append(
                            {
                                "id": data["id"],
                                "title": name,
                                "path": path + "/" + name if path else name,
                                "children": [],
                                "type": "note",
                            }
                        )
                    else:
                        # This is a folder
                        folder_path = path + "/" + name if path else name
                        children = build_tree(data, folder_path)
                        result.append(
                            {
                                "id": folder_path,
                                "title": name,
                                "path": folder_path,
                                "children": children,
                                "type": "folder",
                            }
                        )

            return result

        return build_tree(self.note_tree)

    def get_chunk(self, chunk_id: str) -> Optional[Dict]:
        """Get metadata for a specific chunk."""
        return self.metadata.get(chunk_id)

    def get_note_chunks(self, note_id: str) -> List[Dict]:
        """Get all chunks for a specific note."""
        return [
            metadata
            for metadata in self.metadata.values()
            if metadata["note_id"] == note_id
        ]

    def get_stats(self) -> Dict:
        """Get statistics about the index."""
        stats = {
            "total_chunks": len(self.metadata),
            "total_notes": len(set(m["note_id"] for m in self.metadata.values())),
            "faiss_index_size": self.index.ntotal if self.index else 0,
            "metadata_file": self.metadata_path,
            "index_file": self.index_path,
        }

        # Count chunks per note
        chunks_per_note = {}
        for metadata in self.metadata.values():
            note_id = metadata["note_id"]
            chunks_per_note[note_id] = chunks_per_note.get(note_id, 0) + 1

        stats["chunks_per_note"] = chunks_per_note

        return stats

    def clear(self):
        """Clear the entire index."""
        self.metadata = {}
        self.note_tree = {}
        self.index = None

        # Remove files
        for path in [self.index_path, self.metadata_path]:
            if os.path.exists(path):
                os.remove(path)

        print("Index cleared")
