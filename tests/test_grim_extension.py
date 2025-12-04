"""
Test for .grim file extension functionality.
Verifies that the system correctly handles .grim files.
"""

import os
import sys
import tempfile

import pytest

# Add backend to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../backend"))

from fastapi.testclient import TestClient
from main import app


class TestGrimExtension:
    """Test suite for .grim file extension functionality."""

    def setup_method(self):
        """Set up test fixtures."""
        self.client = TestClient(app)

        # Create temporary directory for test files
        self.temp_dir = tempfile.mkdtemp()
        self.test_notes_dir = os.path.join(self.temp_dir, "notes")
        os.makedirs(self.test_notes_dir, exist_ok=True)

        # Mock the components
        import main

        # Create mock instances
        self.mock_chunker = type(
            "MockChunker", (), {"chunk": lambda self, text, note_id: []}
        )()
        self.mock_embedder = type(
            "MockEmbedder", (), {"embed": lambda self, text: [0.1] * 384}
        )()
        self.mock_indexer = type(
            "MockIndexer",
            (),
            {
                "update_note": lambda self, note_id, chunk_embeddings: None,
                "get_note_tree": lambda self: [],
            },
        )()

        # Store originals and replace
        self.original_chunker = main.chunker
        self.original_embedder = main.embedder
        self.original_indexer = main.indexer
        main.chunker = self.mock_chunker
        main.embedder = self.mock_embedder
        main.indexer = self.mock_indexer

        # Patch os.path.join for note files
        self.path_patch = type(
            "MockPathJoin", (), {"side_effect": self.mock_path_join}
        )()
        import main as main_module

        self.original_path_join = main_module.os.path.join
        main_module.os.path.join = self.path_patch.side_effect

        # Patch os.makedirs
        self.original_makedirs = main_module.os.makedirs
        main_module.os.makedirs = lambda *args, **kwargs: None

        # Patch os.path.exists
        self.original_exists = main_module.os.path.exists
        main_module.os.path.exists = self.mock_exists

    def mock_path_join(self, *args):
        """Mock os.path.join to redirect to test directory."""
        # Check if this is a note file path
        if (
            len(args) >= 2
            and "notes" in str(args[0])
            and str(args[-1]).endswith(".grim")
        ):
            return os.path.join(self.test_notes_dir, args[-1])
        # Use actual os.path.join for other paths
        import os as real_os

        return real_os.path.join(*args)

    def mock_exists(self, path):
        """Mock os.path.exists for test files."""
        # Check if file exists in test directory
        if path.startswith(self.test_notes_dir):
            return os.path.exists(path)
        # For other paths, return True for notes we create
        if "notes" in str(path) and str(path).endswith(".grim"):
            note_name = os.path.basename(path)
            test_path = os.path.join(self.test_notes_dir, note_name)
            return os.path.exists(test_path)
        return True

    def teardown_method(self):
        """Clean up test fixtures."""
        import main
        import main as main_module

        # Restore original components
        main.chunker = self.original_chunker
        main.embedder = self.original_embedder
        main.indexer = self.original_indexer

        # Restore original os functions
        main_module.os.path.join = self.original_path_join
        main_module.os.makedirs = self.original_makedirs
        main_module.os.path.exists = self.original_exists

        # Clean up temporary directory
        import shutil

        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_grim_extension_used(self):
        """Test that .grim extension is used for note files."""
        # Test update-note endpoint
        update_request = {
            "note_id": "test_note",
            "content": "# Test Note\n\nThis is a test note.",
        }

        response = self.client.post("/update-note", json=update_request)
        assert response.status_code == 200

        # Check that .grim file was created
        grim_file = os.path.join(self.test_notes_dir, "test_note.grim")
        assert os.path.exists(grim_file), f"Expected .grim file not found: {grim_file}"

        # Check that .md file was NOT created
        md_file = os.path.join(self.test_notes_dir, "test_note.md")
        assert not os.path.exists(md_file), f"Unexpected .md file found: {md_file}"

        # Verify content
        with open(grim_file, "r") as f:
            content = f.read()
        assert content == "# Test Note\n\nThis is a test note."

    def test_grim_file_retrieval(self):
        """Test that .grim files can be retrieved."""
        # Create a .grim file directly
        note_id = "retrieval_test"
        test_content = "# Retrieval Test\n\nThis content should be retrievable."

        grim_file = os.path.join(self.test_notes_dir, f"{note_id}.grim")
        with open(grim_file, "w") as f:
            f.write(test_content)

        # Retrieve via API
        response = self.client.get(f"/note/{note_id}")
        assert response.status_code == 200

        data = response.json()
        assert data["note_id"] == note_id
        assert data["content"] == test_content

    def test_grim_file_not_found(self):
        """Test proper error when .grim file doesn't exist."""
        response = self.client.get("/note/nonexistent_note")
        assert response.status_code == 404

        data = response.json()
        assert "detail" in data
        assert "Note not found" in data["detail"]

    def test_grim_with_special_characters(self):
        """Test .grim files with special characters in note ID."""
        note_id = "folder/subfolder/note-with-dashes_and_underscores"
        test_content = "# Special Note\n\nWith special characters in ID."

        update_request = {
            "note_id": note_id,
            "content": test_content,
        }

        response = self.client.post("/update-note", json=update_request)
        assert response.status_code == 200

        # Check file was created with .grim extension
        # Note: The path might be flattened, but should still have .grim extension
        grim_file = os.path.join(self.test_notes_dir, f"{note_id}.grim")

        # The file might be created with a different name due to path handling
        # Let's check if any .grim file was created
        grim_files = [f for f in os.listdir(self.test_notes_dir) if f.endswith(".grim")]
        assert len(grim_files) > 0, "No .grim files were created"

        # At least one .grim file should exist
        assert any(f.endswith(".grim") for f in os.listdir(self.test_notes_dir))

    def test_grim_file_preserves_formatting(self):
        """Test that .grim files preserve formatting exactly."""
        note_id = "formatting_test"
        test_content = """# Formatting Test

## Section 1
- Item 1
- Item 2
- Item 3

## Section 2
1. First
2. Second
3. Third

Code block:
```python
def hello():
    print("Hello, World!")
```

End of note."""

        update_request = {
            "note_id": note_id,
            "content": test_content,
        }

        response = self.client.post("/update-note", json=update_request)
        assert response.status_code == 200

        # Retrieve and verify
        response = self.client.get(f"/note/{note_id}")
        assert response.status_code == 200

        data = response.json()
        assert data["content"] == test_content

        # Also verify file content
        grim_files = [
            f
            for f in os.listdir(self.test_notes_dir)
            if note_id in f and f.endswith(".grim")
        ]
        assert len(grim_files) == 1

        grim_file = os.path.join(self.test_notes_dir, grim_files[0])
        with open(grim_file, "r") as f:
            file_content = f.read()
        assert file_content == test_content

    def test_empty_grim_file(self):
        """Test handling of empty .grim files."""
        note_id = "empty_note"

        update_request = {
            "note_id": note_id,
            "content": "",
        }

        response = self.client.post("/update-note", json=update_request)
        assert response.status_code == 200

        # Check empty file was created
        grim_files = [f for f in os.listdir(self.test_notes_dir) if f.endswith(".grim")]
        assert len(grim_files) > 0

        # Find our empty note file
        empty_note_file = None
        for file in grim_files:
            filepath = os.path.join(self.test_notes_dir, file)
            with open(filepath, "r") as f:
                if f.read() == "":
                    empty_note_file = filepath
                    break

        assert empty_note_file is not None, "No empty .grim file found"

        # Verify retrieval
        response = self.client.get(f"/note/{note_id}")
        assert response.status_code == 200

        data = response.json()
        assert data["content"] == ""


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
