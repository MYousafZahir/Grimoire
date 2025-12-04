"""
Integration tests for the FastAPI backend API.
"""

import json
import os
import sys
import tempfile
from unittest.mock import Mock, patch

import pytest
from fastapi.testclient import TestClient

# Add backend to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../backend"))

# Import the app
from main import app


class TestFastAPIEndpoints:
    """Test suite for FastAPI endpoints."""

    def setup_method(self):
        """Set up test fixtures."""
        # Create test client
        self.client = TestClient(app)

        # Create temporary directory for test files
        self.temp_dir = tempfile.mkdtemp()
        self.test_notes_dir = os.path.join(self.temp_dir, "notes")

        # Patch storage paths - use a simpler approach
        self.storage_patch = patch("main.os.path.join")
        self.mock_path_join = self.storage_patch.start()

        def mock_path_join(*args):
            # Check if this is a note file path
            if (
                len(args) >= 2
                and "notes" in str(args[0])
                and str(args[-1]).endswith(".md")
            ):
                # Redirect note files to test directory
                return os.path.join(self.test_notes_dir, args[-1])
            # For other paths, use the mock's default behavior
            return os.path.join(*args)

        self.mock_path_join.side_effect = mock_path_join

        # Create test notes directory
        os.makedirs(self.test_notes_dir, exist_ok=True)

        # Mock the components
        self.chunker_patch = patch("main.chunker")
        self.embedder_patch = patch("main.embedder")
        self.indexer_patch = patch("main.indexer")

        self.mock_chunker = self.chunker_patch.start()
        self.mock_embedder = self.embedder_patch.start()
        self.mock_indexer = self.indexer_patch.start()

        # Set up mock instances
        self.mock_chunker_instance = Mock()
        self.mock_embedder_instance = Mock()
        self.mock_indexer_instance = Mock()

        self.mock_chunker.return_value = self.mock_chunker_instance
        self.mock_embedder.return_value = self.mock_embedder_instance
        self.mock_indexer.return_value = self.mock_indexer_instance

    def teardown_method(self):
        """Clean up test fixtures."""
        # Stop all patches
        self.storage_patch.stop()
        self.chunker_patch.stop()
        self.embedder_patch.stop()
        self.indexer_patch.stop()

        # Clean up temporary directory
        import shutil

        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_root_endpoint(self):
        """Test the health check endpoint."""
        response = self.client.get("/")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["service"] == "Grimoire Backend"

    def test_search_endpoint(self):
        """Test the search endpoint."""
        # Mock search results
        mock_results = [
            {
                "note_id": "note_1",
                "chunk_id": "chunk_1",
                "excerpt": "Test excerpt 1",
                "score": 0.95,
            },
            {
                "note_id": "note_2",
                "chunk_id": "chunk_2",
                "excerpt": "Test excerpt 2",
                "score": 0.85,
            },
        ]

        self.mock_embedder_instance.embed.return_value = [0.1, 0.2, 0.3]
        self.mock_indexer_instance.search.return_value = mock_results

        # Test search request
        search_request = {"text": "test query", "note_id": "current_note"}
        response = self.client.post("/search", json=search_request)

        assert response.status_code == 200
        data = response.json()

        # Verify response structure
        assert "results" in data
        assert len(data["results"]) == 2
        assert data["results"][0]["note_id"] == "note_1"
        assert data["results"][0]["excerpt"] == "Test excerpt 1"
        assert data["results"][0]["score"] == 0.95

        # Verify mocks were called
        self.mock_embedder_instance.embed.assert_called_once_with("test query")
        self.mock_indexer_instance.search.assert_called_once_with(
            query_embedding=[0.1, 0.2, 0.3], exclude_note_id="current_note", top_k=10
        )

    def test_search_endpoint_error(self):
        """Test search endpoint error handling."""
        # Mock embedding to raise exception
        self.mock_embedder_instance.embed.side_effect = Exception("Embedding failed")

        search_request = {"text": "test query", "note_id": "current_note"}
        response = self.client.post("/search", json=search_request)

        assert response.status_code == 500
        data = response.json()
        assert "detail" in data
        assert "Search failed" in data["detail"]

    def test_update_note_endpoint(self):
        """Test the update-note endpoint."""
        # Mock chunker and embedder
        mock_chunks = [
            {"chunk_id": "chunk_1", "text": "Chunk 1 text"},
            {"chunk_id": "chunk_2", "text": "Chunk 2 text"},
        ]

        self.mock_chunker_instance.chunk.return_value = mock_chunks
        self.mock_embedder_instance.embed.side_effect = [
            [0.1, 0.2, 0.3],
            [0.4, 0.5, 0.6],
        ]

        # Test update request
        update_request = {
            "note_id": "test_note",
            "content": "# Test Note\n\nThis is test content.",
        }

        response = self.client.post("/update-note", json=update_request)

        assert response.status_code == 200
        data = response.json()

        assert data["status"] == "success"
        assert data["note_id"] == "test_note"

        # Verify file was saved
        note_path = os.path.join(self.test_notes_dir, "test_note.md")
        assert os.path.exists(note_path)

        with open(note_path, "r") as f:
            content = f.read()
        assert content == "# Test Note\n\nThis is test content."

        # Verify mocks were called
        self.mock_chunker_instance.chunk.assert_called_once_with(
            "# Test Note\n\nThis is test content.", "test_note"
        )
        assert self.mock_embedder_instance.embed.call_count == 2
        self.mock_indexer_instance.update_note.assert_called_once()

    def test_update_note_endpoint_error(self):
        """Test update-note endpoint error handling."""
        # Mock chunker to raise exception
        self.mock_chunker_instance.chunk.side_effect = Exception("Chunking failed")

        update_request = {
            "note_id": "test_note",
            "content": "Test content",
        }

        response = self.client.post("/update-note", json=update_request)

        assert response.status_code == 500
        data = response.json()
        assert "detail" in data
        assert "Update failed" in data["detail"]

    def test_get_all_notes_endpoint(self):
        """Test the all-notes endpoint."""
        # Mock note tree
        mock_note_tree = [
            {
                "id": "note_1",
                "title": "Note 1",
                "path": "note_1",
                "children": [],
            },
            {
                "id": "folder_1",
                "title": "Folder 1",
                "path": "folder_1",
                "children": [
                    {
                        "id": "folder_1/note_2",
                        "title": "Note 2",
                        "path": "folder_1/note_2",
                        "children": [],
                    }
                ],
            },
        ]

        self.mock_indexer_instance.get_note_tree.return_value = mock_note_tree

        response = self.client.get("/all-notes")

        assert response.status_code == 200
        data = response.json()

        assert "notes" in data
        assert len(data["notes"]) == 2

        # Verify structure
        assert data["notes"][0]["id"] == "note_1"
        assert data["notes"][0]["title"] == "Note 1"
        assert data["notes"][1]["id"] == "folder_1"
        assert data["notes"][1]["title"] == "Folder 1"
        assert len(data["notes"][1]["children"]) == 1

        # Verify mock was called
        self.mock_indexer_instance.get_note_tree.assert_called_once()

    def test_get_all_notes_endpoint_error(self):
        """Test all-notes endpoint error handling."""
        # Mock indexer to raise exception
        self.mock_indexer_instance.get_note_tree.side_effect = Exception(
            "Tree generation failed"
        )

        response = self.client.get("/all-notes")

        assert response.status_code == 500
        data = response.json()
        assert "detail" in data
        assert "Failed to get notes" in data["detail"]

    def test_get_note_endpoint(self):
        """Test the get-note endpoint."""
        # Create a test note file
        note_id = "test_note"
        note_content = "# Test Note\n\nThis is the content."

        note_path = os.path.join(self.test_notes_dir, f"{note_id}.md")
        with open(note_path, "w") as f:
            f.write(note_content)

        response = self.client.get(f"/note/{note_id}")

        assert response.status_code == 200
        data = response.json()

        assert data["note_id"] == note_id
        assert data["content"] == note_content

    def test_get_note_endpoint_not_found(self):
        """Test get-note endpoint when note doesn't exist."""
        response = self.client.get("/note/nonexistent_note")

        assert response.status_code == 404
        data = response.json()
        assert "detail" in data
        assert "Note not found" in data["detail"]

    def test_get_note_endpoint_error(self):
        """Test get-note endpoint error handling."""
        # Mock os.path.exists to raise exception
        with patch("main.os.path.exists", side_effect=Exception("File system error")):
            response = self.client.get("/note/test_note")

            assert response.status_code == 500
            data = response.json()
            assert "detail" in data
            assert "Failed to get note" in data["detail"]

    def test_update_note_creates_directory(self):
        """Test that update-note creates the notes directory if it doesn't exist."""
        # Remove test directory to simulate non-existent directory
        import shutil

        shutil.rmtree(self.test_notes_dir, ignore_ok=True)

        # Mock chunker and embedder
        self.mock_chunker_instance.chunk.return_value = []
        self.mock_embedder_instance.embed.return_value = [0.1, 0.2, 0.3]

        update_request = {
            "note_id": "test_note",
            "content": "Test content",
        }

        response = self.client.post("/update-note", json=update_request)

        assert response.status_code == 200
        # Directory should have been created
        assert os.path.exists(self.test_notes_dir)

    def test_search_with_different_top_k(self):
        """Test search with different top_k values through indexer."""
        # Mock search to verify top_k parameter
        self.mock_embedder_instance.embed.return_value = [0.1, 0.2, 0.3]
        self.mock_indexer_instance.search.return_value = []

        search_request = {"text": "test query", "note_id": "current_note"}

        # First call with default top_k
        response = self.client.post("/search", json=search_request)
        assert response.status_code == 200

        # Verify default top_k was used
        self.mock_indexer_instance.search.assert_called_with(
            query_embedding=[0.1, 0.2, 0.3], exclude_note_id="current_note", top_k=10
        )

    def test_note_content_preserved(self):
        """Test that note content is preserved exactly when saved and retrieved."""
        note_id = "preservation_test"
        test_content = "# Test Note\n\nLine 1\nLine 2\n\nLine 3 with special chars: éàç\n\tTabbed line"

        # Save the note
        update_request = {"note_id": note_id, "content": test_content}
        self.mock_chunker_instance.chunk.return_value = []
        self.mock_embedder_instance.embed.return_value = [0.1, 0.2, 0.3]

        update_response = self.client.post("/update-note", json=update_request)
        assert update_response.status_code == 200

        # Retrieve the note
        get_response = self.client.get(f"/note/{note_id}")
        assert get_response.status_code == 200

        retrieved_content = get_response.json()["content"]
        assert retrieved_content == test_content

    def test_empty_note_handling(self):
        """Test handling of empty notes."""
        # Test updating with empty content
        update_request = {"note_id": "empty_note", "content": ""}

        self.mock_chunker_instance.chunk.return_value = []
        self.mock_embedder_instance.embed.return_value = [0.0, 0.0, 0.0]

        response = self.client.post("/update-note", json=update_request)
        assert response.status_code == 200

        # Verify empty file was created
        note_path = os.path.join(self.test_notes_dir, "empty_note.md")
        assert os.path.exists(note_path)

        with open(note_path, "r") as f:
            content = f.read()
        assert content == ""

    def test_note_with_special_characters_in_id(self):
        """Test handling of note IDs with special characters."""
        note_id = "note-with-dashes_and_underscores/and/slashes"
        test_content = "Test content"

        update_request = {"note_id": note_id, "content": test_content}
        self.mock_chunker_instance.chunk.return_value = []
        self.mock_embedder_instance.embed.return_value = [0.1, 0.2, 0.3]

        response = self.client.post("/update-note", json=update_request)
        assert response.status_code == 200

        # Verify file was created with .md extension
        expected_filename = f"{note_id}.md"
        note_path = os.path.join(self.test_notes_dir, expected_filename)
        assert os.path.exists(note_path)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
