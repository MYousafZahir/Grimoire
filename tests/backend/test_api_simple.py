"""
Simplified API tests for the FastAPI backend.
"""

import json
import os

# Add backend to Python path
import sys
import tempfile
from unittest.mock import Mock, patch

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../backend"))

# Import the app
from main import app


class TestFastAPISimple:
    """Simplified test suite for FastAPI endpoints."""

    def setup_method(self):
        """Set up test fixtures."""
        self.client = TestClient(app)

        # Create temporary directory for test files
        self.temp_dir = tempfile.mkdtemp()
        self.test_notes_dir = os.path.join(self.temp_dir, "notes")
        os.makedirs(self.test_notes_dir, exist_ok=True)

        # Mock the components to avoid complex setup
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

        # Patch os.path.join for note files
        self.path_patch = patch("main.os.path.join")
        self.mock_path_join = self.path_patch.start()

        def mock_path_join(*args):
            # Simple mock that redirects note files to test directory
            if (
                len(args) > 1
                and "notes" in str(args[0])
                and str(args[-1]).endswith(".md")
            ):
                return os.path.join(self.test_notes_dir, args[-1])
            # Use actual os.path.join for other paths
            import os as real_os

            return real_os.path.join(*args)

        self.mock_path_join.side_effect = mock_path_join

        # Patch os.makedirs
        self.makedirs_patch = patch("main.os.makedirs")
        self.mock_makedirs = self.makedirs_patch.start()
        self.mock_makedirs.return_value = None

        # Patch os.path.exists for note files
        self.exists_patch = patch("main.os.path.exists")
        self.mock_exists = self.exists_patch.start()

        def mock_exists(path):
            # Check if file exists in test directory
            if path.startswith(self.test_notes_dir):
                return os.path.exists(path)
            # For other paths, return True for notes we create
            if "notes" in str(path) and str(path).endswith(".md"):
                note_name = os.path.basename(path)
                test_path = os.path.join(self.test_notes_dir, note_name)
                return os.path.exists(test_path)
            return True

        self.mock_exists.side_effect = mock_exists

    def teardown_method(self):
        """Clean up test fixtures."""
        # Stop all patches
        self.chunker_patch.stop()
        self.embedder_patch.stop()
        self.indexer_patch.stop()
        self.path_patch.stop()
        self.makedirs_patch.stop()
        self.exists_patch.stop()

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
            }
        ]

        self.mock_embedder_instance.embed.return_value = [0.1, 0.2, 0.3]
        self.mock_indexer_instance.search.return_value = mock_results

        # Test search request
        search_request = {"text": "test query", "note_id": "current_note"}
        response = self.client.post("/search", json=search_request)

        assert response.status_code == 200
        data = response.json()

        assert "results" in data
        assert len(data["results"]) == 1
        assert data["results"][0]["note_id"] == "note_1"
        assert data["results"][0]["excerpt"] == "Test excerpt 1"
        assert data["results"][0]["score"] == 0.95

    def test_update_note_endpoint(self):
        """Test the update-note endpoint."""
        # Mock chunker and embedder
        self.mock_chunker_instance.chunk.return_value = []
        self.mock_embedder_instance.embed.return_value = [0.1, 0.2, 0.3]

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

    def test_get_all_notes_endpoint(self):
        """Test the all-notes endpoint."""
        # Mock note tree
        mock_note_tree = [
            {
                "id": "note_1",
                "title": "Note 1",
                "path": "note_1",
                "children": [],
            }
        ]

        self.mock_indexer_instance.get_note_tree.return_value = mock_note_tree

        response = self.client.get("/all-notes")

        assert response.status_code == 200
        data = response.json()

        assert "notes" in data
        assert len(data["notes"]) == 1
        assert data["notes"][0]["id"] == "note_1"
        assert data["notes"][0]["title"] == "Note 1"

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
        # Make sure the note doesn't exist
        note_path = os.path.join(self.test_notes_dir, "nonexistent_note.md")
        if os.path.exists(note_path):
            os.remove(note_path)

        response = self.client.get("/note/nonexistent_note")

        assert response.status_code == 404
        data = response.json()
        assert "detail" in data
        assert "Note not found" in data["detail"]

    def test_update_note_creates_directory(self):
        """Test that update-note creates the notes directory if it doesn't exist."""
        # Remove test directory
        import shutil

        shutil.rmtree(self.test_notes_dir, ignore_errors=True)

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

    def test_note_content_preserved(self):
        """Test that note content is preserved exactly when saved and retrieved."""
        note_id = "preservation_test"
        test_content = "# Test Note\n\nLine 1\nLine 2\n\nLine 3"

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


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
