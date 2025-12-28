"""
Simplified unit tests for the Indexer module.
Focuses on core functionality without FAISS mocking complexity.
"""

import json
import os
import sys
import tempfile
from unittest.mock import Mock, patch

import pytest

# Add backend to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../backend"))

from indexer import Indexer


class TestIndexerSimple:
    """Simplified test suite for the Indexer class."""

    def setup_method(self):
        """Set up test fixtures."""
        # Create temporary directory for test files
        self.temp_dir = tempfile.mkdtemp()
        self.index_path = os.path.join(self.temp_dir, "faiss.index")
        self.metadata_path = os.path.join(self.temp_dir, "index.json")
        self.note_tree_path = os.path.join(self.temp_dir, "note_tree.json")

        # Create indexer with test paths
        self.indexer = Indexer(
            index_path=self.index_path,
            metadata_path=self.metadata_path,
            note_tree_path=self.note_tree_path,
        )

    def teardown_method(self):
        """Clean up test fixtures."""
        # Clean up temporary directory
        import shutil

        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_indexer_initialization(self):
        """Test that indexer initializes with correct parameters."""
        assert self.indexer.index_path == self.index_path
        assert self.indexer.metadata_path == self.metadata_path
        assert self.indexer.metadata == {}
        assert self.indexer.note_tree == {}

    def test_load_metadata_existing_file(self):
        """Test loading metadata from existing file."""
        # Create test metadata
        test_metadata = {
            "chunk_1": {
                "note_id": "note_1",
                "chunk_id": "chunk_1",
                "text": "Test text",
                "embedding": [0.1, 0.2, 0.3],
            }
        }

        # Write metadata file
        with open(self.metadata_path, "w") as f:
            json.dump(test_metadata, f)

        # Create new indexer to load the metadata
        indexer = Indexer(index_path=self.index_path, metadata_path=self.metadata_path)

        assert indexer.metadata == test_metadata

    def test_load_metadata_nonexistent_file(self):
        """Test loading metadata when file doesn't exist."""
        # Remove metadata file if it exists
        if os.path.exists(self.metadata_path):
            os.remove(self.metadata_path)

        # Create new indexer
        indexer = Indexer(index_path=self.index_path, metadata_path=self.metadata_path)

        assert indexer.metadata == {}

    def test_update_note(self):
        """Test updating a note in the index."""
        # Mock _add_to_index and _update_note_tree
        self.indexer._add_to_index = Mock()
        self.indexer._update_note_tree = Mock()
        self.indexer._save_metadata = Mock()
        self.indexer._save_index = Mock()

        # Test data
        note_id = "test_note"
        chunk_embeddings = [
            {
                "chunk_id": "chunk_1",
                "text": "First chunk",
                "embedding": [0.1, 0.2, 0.3],
            },
            {
                "chunk_id": "chunk_2",
                "text": "Second chunk",
                "embedding": [0.4, 0.5, 0.6],
            },
        ]

        # Update note
        self.indexer.update_note(note_id, chunk_embeddings)

        # Verify metadata was stored
        assert len(self.indexer.metadata) == 2
        assert "chunk_1" in self.indexer.metadata
        assert "chunk_2" in self.indexer.metadata

        # Verify methods were called
        assert self.indexer._add_to_index.call_count == 2
        self.indexer._update_note_tree.assert_called_once_with(note_id)
        self.indexer._save_metadata.assert_called_once()
        self.indexer._save_index.assert_called_once()

    def test_update_note_empty_chunks(self):
        """Test updating a note with empty chunks."""
        # Mock methods
        self.indexer._remove_note_chunks = Mock()

        # Update with empty chunks
        self.indexer.update_note("test_note", [])

        # Should call remove_note_chunks but not add anything
        self.indexer._remove_note_chunks.assert_called_once_with("test_note")
        assert len(self.indexer.metadata) == 0

    def test_remove_note_chunks(self):
        """Test removing chunks for a specific note."""
        # Add some test metadata
        self.indexer.metadata = {
            "chunk_1": {"note_id": "note_1", "text": "Text 1"},
            "chunk_2": {"note_id": "note_1", "text": "Text 2"},
            "chunk_3": {"note_id": "note_2", "text": "Text 3"},
        }

        # Mock _rebuild_index
        self.indexer._rebuild_index = Mock()

        # Remove chunks for note_1
        self.indexer._remove_note_chunks("note_1")

        # Verify only note_2 chunks remain
        assert len(self.indexer.metadata) == 1
        assert "chunk_3" in self.indexer.metadata
        assert "chunk_1" not in self.indexer.metadata
        assert "chunk_2" not in self.indexer.metadata

        # Should call rebuild_index only if index exists
        # Since index is None in this test, rebuild_index won't be called
        self.indexer._rebuild_index.assert_not_called()

    def test_update_note_tree(self):
        """Test updating the note tree structure."""
        # Test with simple note ID
        self.indexer._update_note_tree("simple_note")
        assert "simple_note" in self.indexer.note_tree
        assert self.indexer.note_tree["simple_note"]["type"] == "note"
        assert self.indexer.note_tree["simple_note"]["id"] == "simple_note"

        # Test with nested note ID
        self.indexer._update_note_tree("folder/subfolder/nested_note")

        # Check tree structure
        assert "folder" in self.indexer.note_tree
        assert "subfolder" in self.indexer.note_tree["folder"]
        assert "nested_note" in self.indexer.note_tree["folder"]["subfolder"]
        assert (
            self.indexer.note_tree["folder"]["subfolder"]["nested_note"]["type"]
            == "note"
        )
        assert (
            self.indexer.note_tree["folder"]["subfolder"]["nested_note"]["id"]
            == "folder/subfolder/nested_note"
        )

    def test_get_note_tree(self):
        """Test getting the hierarchical note tree."""
        # Build a test tree
        self.indexer.note_tree = {
            "folder1": {
                "note1": {"type": "note", "id": "folder1/note1"},
                "subfolder": {
                    "note2": {"type": "note", "id": "folder1/subfolder/note2"}
                },
            },
            "note3": {"type": "note", "id": "note3"},
        }

        # Get note tree
        tree = self.indexer.get_note_tree()

        # Verify structure
        assert len(tree) == 2  # folder1 and note3

        # Check folder1
        folder1 = next(item for item in tree if item["title"] == "folder1")
        assert folder1["id"] == "folder1"
        assert folder1["path"] == "folder1"
        assert len(folder1["children"]) == 2  # note1 and subfolder

        # Check note1
        note1 = next(item for item in folder1["children"] if item["title"] == "note1")
        assert note1["id"] == "folder1/note1"
        assert note1["path"] == "folder1/note1"
        assert note1["children"] == []

        # Check subfolder
        subfolder = next(
            item for item in folder1["children"] if item["title"] == "subfolder"
        )
        assert subfolder["id"] == "folder1/subfolder"
        assert subfolder["path"] == "folder1/subfolder"
        assert len(subfolder["children"]) == 1

        # Check note3
        note3 = next(item for item in tree if item["title"] == "note3")
        assert note3["id"] == "note3"
        assert note3["path"] == "note3"
        assert note3["children"] == []

    def test_get_chunk(self):
        """Test getting a specific chunk."""
        # Add test metadata
        test_chunk = {
            "note_id": "test_note",
            "chunk_id": "test_chunk",
            "text": "Test text",
            "embedding": [0.1, 0.2, 0.3],
        }
        self.indexer.metadata["test_chunk"] = test_chunk

        # Get chunk
        result = self.indexer.get_chunk("test_chunk")
        assert result == test_chunk

        # Get non-existent chunk
        result = self.indexer.get_chunk("nonexistent")
        assert result is None

    def test_get_note_chunks(self):
        """Test getting all chunks for a note."""
        # Add test metadata
        self.indexer.metadata = {
            "chunk_1": {"note_id": "note_1", "text": "Text 1"},
            "chunk_2": {"note_id": "note_1", "text": "Text 2"},
            "chunk_3": {"note_id": "note_2", "text": "Text 3"},
        }

        # Get chunks for note_1
        chunks = self.indexer.get_note_chunks("note_1")

        assert len(chunks) == 2
        assert all(chunk["note_id"] == "note_1" for chunk in chunks)

        # Get chunks for non-existent note
        chunks = self.indexer.get_note_chunks("nonexistent")
        assert chunks == []

    def test_get_stats(self):
        """Test getting index statistics."""
        # Add test metadata
        self.indexer.metadata = {
            "chunk_1": {"note_id": "note_1", "text": "Text 1"},
            "chunk_2": {"note_id": "note_1", "text": "Text 2"},
            "chunk_3": {"note_id": "note_2", "text": "Text 3"},
        }

        # Mock index
        mock_index = Mock()
        mock_index.ntotal = 3
        self.indexer.index = mock_index

        # Get stats
        stats = self.indexer.get_stats()

        # Verify stats
        assert stats["total_chunks"] == 3
        assert stats["total_notes"] == 2
        assert stats["faiss_index_size"] == 3
        assert stats["metadata_file"] == self.metadata_path
        assert stats["index_file"] == self.index_path
        assert "chunks_per_note" in stats
        assert stats["chunks_per_note"]["note_1"] == 2
        assert stats["chunks_per_note"]["note_2"] == 1

    def test_clear(self):
        """Test clearing the entire index."""
        # Add test data
        self.indexer.metadata = {"chunk_1": {"note_id": "note_1"}}
        self.indexer.note_tree = {"note_1": {"type": "note", "id": "note_1"}}

        # Create dummy files
        with open(self.index_path, "w") as f:
            f.write("dummy index")
        with open(self.metadata_path, "w") as f:
            json.dump({"test": "data"}, f)

        # Mock index
        mock_index = Mock()
        self.indexer.index = mock_index

        # Clear index
        self.indexer.clear()

        # Verify everything was cleared
        assert self.indexer.metadata == {}
        assert self.indexer.note_tree == {}
        assert self.indexer.index is None

        # Verify files were removed
        assert not os.path.exists(self.index_path)
        assert not os.path.exists(self.metadata_path)

    def test_search_empty_index(self):
        """Test searching empty index."""
        self.indexer.index = None
        results = self.indexer.search([0.1, 0.2, 0.3])
        assert results == []

    def test_search_index_with_zero_vectors(self):
        """Test searching index with zero vectors."""
        mock_index = Mock()
        mock_index.ntotal = 0
        self.indexer.index = mock_index

        results = self.indexer.search([0.1, 0.2, 0.3])
        assert results == []

    def test_save_index_none(self):
        """Test saving when index is None."""
        self.indexer.index = None
        self.indexer._save_index()
        # Should not raise any exception


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
