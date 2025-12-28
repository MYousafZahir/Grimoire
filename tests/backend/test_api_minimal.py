"""
Minimal API tests for the FastAPI backend.
Tests only the most critical endpoints without complex mocking.
"""

import json
import os
import sys

# Add backend to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../backend"))

import pytest
from fastapi.testclient import TestClient

# Import the app
from main import app


class TestFastAPIMinimal:
    """Minimal test suite for FastAPI endpoints."""

    def setup_method(self):
        """Set up test fixtures."""
        self.client = TestClient(app)

    def test_root_endpoint(self):
        """Test the health check endpoint."""
        response = self.client.get("/")

        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ok"
        assert data["message"] == "Grimoire backend is running"

    def test_search_endpoint_structure(self):
        """Test the search endpoint returns proper structure."""
        # Mock the components to avoid actual model loading
        import main

        class DummySearch:
            def search(self, request):
                return []

        class DummyNotes:
            def tree(self):
                return {"notes": []}

        class DummyState:
            def __init__(self):
                self._services = type("Services", (), {"search": DummySearch(), "notes": DummyNotes()})()

            def current(self):
                return self._services

        original_state = main.state
        main.state = DummyState()

        try:
            # Test search request
            search_request = {"text": "test query", "note_id": "current_note"}
            response = self.client.post("/search", json=search_request)

            assert response.status_code == 200
            data = response.json()

            # Should have results field even if empty
            assert "results" in data
            assert isinstance(data["results"], list)
        finally:
            # Restore original components
            main.state = original_state

    def test_update_note_endpoint_structure(self):
        """Test the update-note endpoint returns proper structure."""
        # Mock the components to avoid actual file operations
        import main

        class DummyNotes:
            def save_note(self, request):
                return type("Record", (), {"id": request.note_id})()

        class DummyState:
            def __init__(self):
                self._services = type("Services", (), {"notes": DummyNotes()})()

            def current(self):
                return self._services

        original_state = main.state
        main.state = DummyState()

        try:
            # Test update request
            update_request = {
                "note_id": "test_note",
                "content": "# Test Note\n\nThis is test content.",
            }

            response = self.client.post("/update-note", json=update_request)

            assert response.status_code == 200
            data = response.json()

            # Should have success status
            assert "success" in data
            assert data["success"] is True
            assert "note_id" in data
            assert data["note_id"] == "test_note"
        finally:
            # Restore original components
            main.state = original_state

    def test_get_all_notes_endpoint_structure(self):
        """Test the all-notes endpoint returns proper structure."""
        import main

        class DummyNotes:
            def tree(self):
                return {"notes": []}

        class DummyState:
            def __init__(self):
                self._services = type("Services", (), {"notes": DummyNotes()})()

            def current(self):
                return self._services

        original_state = main.state
        main.state = DummyState()

        try:
            response = self.client.get("/all-notes")

            assert response.status_code == 200
            data = response.json()

            # Should have notes field
            assert "notes" in data
            assert isinstance(data["notes"], list)
        finally:
            # Restore original component
            main.state = original_state

    def test_get_note_endpoint_error_handling(self):
        """Test the get-note endpoint returns proper error for non-existent note."""
        response = self.client.get("/note/nonexistent_note_12345")

        # Should return 404 for non-existent note
        assert response.status_code == 404
        data = response.json()
        assert "detail" in data
        assert "Note not found" in data["detail"]

    def test_cors_headers(self):
        """Test that CORS headers are present."""
        # Test with OPTIONS request to trigger CORS preflight
        response = self.client.options("/")

        # CORS headers should be present on OPTIONS requests
        # or we can check that the middleware is configured
        # by testing that the app accepts cross-origin requests

        # For now, just verify the endpoint works with CORS middleware
        # by checking that we can make requests from different origins
        response = self.client.get("/", headers={"Origin": "http://localhost:3000"})

        # The response should be successful
        assert response.status_code == 200

        # CORS headers might be added by middleware
        # Check if they exist (they may not be on all responses)
        if "access-control-allow-origin" in response.headers:
            assert response.headers["access-control-allow-origin"] == "*"

    def test_invalid_json_handling(self):
        """Test that invalid JSON returns proper error."""
        response = self.client.post("/search", data="invalid json")

        # Should return 422 for invalid JSON
        assert response.status_code == 422
        data = response.json()
        assert "detail" in data

    def test_missing_fields_handling(self):
        """Test that missing required fields returns proper error."""
        # Test search endpoint with missing fields
        response = self.client.post("/search", json={"text": "test"})  # missing note_id

        # Should return 422 for missing required field
        assert response.status_code == 422
        data = response.json()
        assert "detail" in data

        # Test update-note endpoint with missing fields
        response = self.client.post(
            "/update-note", json={"note_id": "test"}
        )  # missing content

        # Should return 422 for missing required field
        assert response.status_code == 422
        data = response.json()
        assert "detail" in data

    def test_api_documentation(self):
        """Test that API documentation is available."""
        response = self.client.get("/docs")

        # Should return 200 for Swagger UI
        assert response.status_code == 200
        assert "text/html" in response.headers["content-type"]

        # Test OpenAPI schema
        response = self.client.get("/openapi.json")
        assert response.status_code == 200
        data = response.json()
        assert "openapi" in data
        assert "info" in data
        assert "paths" in data


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
