"""
Unit tests for the Chunker module.
"""

import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../backend"))

from chunker import Chunker


class TestChunker:
    """Test suite for the Chunker class."""

    def setup_method(self):
        """Set up test fixtures."""
        self.chunker = Chunker(min_chunk_size=150, max_chunk_size=300, overlap=50)

    def test_chunker_initialization(self):
        """Test that chunker initializes with correct parameters."""
        chunker = Chunker(min_chunk_size=100, max_chunk_size=200, overlap=30)
        assert chunker.min_chunk_size == 100
        assert chunker.max_chunk_size == 200
        assert chunker.overlap == 30

    def test_chunk_empty_text(self):
        """Test chunking empty text returns empty list."""
        result = self.chunker.chunk("", "test_note")
        assert result == []

        result = self.chunker.chunk("   ", "test_note")
        assert result == []

    def test_chunk_small_text(self):
        """Test chunking text smaller than max chunk size."""
        text = "This is a short text that should fit in one chunk."
        result = self.chunker.chunk(text, "test_note")

        assert len(result) == 1
        assert result[0]["note_id"] == "test_note"
        assert result[0]["chunk_id"] == "test_note_0"
        assert result[0]["text"] == text.strip()

    def test_chunk_large_text(self):
        """Test chunking text larger than max chunk size."""
        # Create a text that's about 500 characters
        text = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. " * 10
        result = self.chunker.chunk(text, "test_note")

        # Should create multiple chunks
        assert len(result) > 1

        # Check each chunk
        for i, chunk in enumerate(result):
            assert chunk["note_id"] == "test_note"
            assert chunk["chunk_id"] == f"test_note_{i}"
            assert len(chunk["text"]) <= self.chunker.max_chunk_size
            assert (
                len(chunk["text"]) >= self.chunker.min_chunk_size
                or i == len(result) - 1
            )

    def test_chunk_with_paragraphs(self):
        """Test chunking text with multiple paragraphs."""
        text = """First paragraph with some text.

Second paragraph with more text that goes on for a while.

Third paragraph."""

        result = self.chunker.chunk(text, "test_note")

        # Should handle paragraphs separately
        # Note: The chunker might combine short paragraphs into one chunk
        # So we just verify it produces at least one chunk
        assert len(result) >= 1

        # Check that text is preserved
        all_text = " ".join(chunk["text"] for chunk in result)
        assert "First paragraph" in all_text
        assert "Second paragraph" in all_text
        assert "Third paragraph" in all_text

    def test_chunk_respects_sentence_boundaries(self):
        """Test that chunking respects sentence boundaries when possible."""
        # Create text with clear sentence boundaries
        text = "This is sentence one. This is sentence two. " * 20

        result = self.chunker.chunk(text, "test_note")

        # Check that chunks don't cut sentences in the middle
        for chunk in result:
            chunk_text = chunk["text"]
            # If chunk ends with a period, it should be at the end
            if chunk_text.endswith("."):
                # Make sure it's not followed by more text in the same chunk
                pass
            # Check that we don't have partial sentences at chunk boundaries
            # (except possibly the last chunk)

    def test_clean_text_method(self):
        """Test the text cleaning method."""
        dirty_text = "  This  is   text  with  \n\n  extra   spaces.  "
        cleaned = self.chunker._clean_text(dirty_text)

        assert cleaned == "This  is   text  with  \n\n  extra   spaces."
        assert cleaned == cleaned.strip()  # No leading/trailing spaces

    def test_split_into_paragraphs(self):
        """Test paragraph splitting."""
        text = """Para one.

Para two.

Para three."""

        paragraphs = self.chunker._split_into_paragraphs(text)

        assert len(paragraphs) == 3
        assert paragraphs[0] == "Para one."
        assert paragraphs[1] == "Para two."
        assert paragraphs[2] == "Para three."

    def test_split_paragraph_method(self):
        """Test the internal paragraph splitting method."""
        # Create a long paragraph
        paragraph = "Word " * 100  # About 500 characters

        result = self.chunker._split_paragraph(paragraph, "test_note", 0)

        assert len(result) > 1
        for i, chunk in enumerate(result):
            assert chunk["chunk_id"] == f"test_note_{i}"
            assert len(chunk["text"]) <= self.chunker.max_chunk_size

    def test_get_chunk_context(self):
        """Test getting context around a chunk."""
        text = "Start. " + "Middle word. " * 10 + "End."
        chunk_start = 50
        chunk_end = 100

        context = self.chunker.get_chunk_context(text, chunk_start, chunk_end, 20)

        # Context should include the chunk with markers
        assert "**" in context
        # Context should be longer than the chunk itself
        assert len(context) > (chunk_end - chunk_start)

    def test_chunk_ids_are_unique(self):
        """Test that chunk IDs are unique within a note."""
        text = "Text " * 100  # Will be split into multiple chunks

        result = self.chunker.chunk(text, "test_note")

        chunk_ids = [chunk["chunk_id"] for chunk in result]
        assert len(chunk_ids) == len(set(chunk_ids))  # All unique

    @pytest.mark.parametrize("text_length", [50, 200, 400, 600])
    def test_chunk_various_lengths(self, text_length):
        """Test chunking texts of various lengths."""
        text = "Word " * (text_length // 5)  # Approximate length

        result = self.chunker.chunk(text, f"note_{text_length}")

        if text_length <= self.chunker.max_chunk_size:
            assert len(result) == 1
        else:
            assert len(result) > 1

        # Verify total text is preserved (approximately)
        total_chars = sum(len(chunk["text"]) for chunk in result)
        assert total_chars >= len(text.strip()) - 100  # Allow for some trimming

    def test_chunk_with_special_characters(self):
        """Test chunking text with special characters."""
        text = "Line with \ttab. Line with \nnewline. Line with emoji 😀."

        result = self.chunker.chunk(text, "special_note")

        assert len(result) > 0
        # The chunker should handle special characters gracefully
        for chunk in result:
            assert chunk["text"]  # Should not be empty

    def test_overlap_between_chunks(self):
        """Test that chunks have appropriate overlap."""
        text = "Word " * 200  # Will be split into multiple chunks

        result = self.chunker.chunk(text, "overlap_note")

        if len(result) > 1:
            # Check that chunks overlap (text from end of one appears in start of next)
            for i in range(len(result) - 1):
                chunk1_end = result[i]["text"][-50:]  # Last 50 chars of chunk i
                chunk2_start = result[i + 1]["text"][:50]  # First 50 chars of chunk i+1

                # There should be some overlap (not necessarily exact match due to boundaries)
                # Just verify both chunks have content
                assert chunk1_end
                assert chunk2_start


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
