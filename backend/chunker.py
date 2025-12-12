"""
Text chunking module for Grimoire.

Splits notes into 150-300 character excerpts for semantic linking.
"""

import re
from typing import Dict, List


class Chunker:
    """Handles splitting text into meaningful chunks for embedding."""

    def __init__(
        self, min_chunk_size: int = 150, max_chunk_size: int = 300, overlap: int = 50
    ):
        """
        Initialize the chunker.

        Args:
            min_chunk_size: Minimum chunk size in characters
            max_chunk_size: Maximum chunk size in characters
            overlap: Overlap between consecutive chunks in characters
        """
        self.min_chunk_size = min_chunk_size
        self.max_chunk_size = max_chunk_size
        self.overlap = overlap

    def chunk(self, text: str, note_id: str) -> List[Dict[str, str]]:
        """
        Split text into chunks for embedding.

        Args:
            text: The text to chunk
            note_id: Identifier for the note

        Returns:
            List of dictionaries with chunk_id and text
        """
        if not text or not text.strip():
            return []

        # Clean and normalize the text
        text = self._clean_text(text)

        # Split into paragraphs first
        paragraphs = self._split_into_paragraphs(text)

        chunks = []
        chunk_counter = 0

        for paragraph in paragraphs:
            if len(paragraph) <= self.max_chunk_size:
                # Paragraph is small enough to be its own chunk
                chunk_id = f"{note_id}_{chunk_counter}"
                chunks.append(
                    {
                        "chunk_id": chunk_id,
                        "text": paragraph,
                        "note_id": note_id,
                        "start_char": 0,  # Will be calculated properly in a real implementation
                        "end_char": len(paragraph),
                    }
                )
                chunk_counter += 1
            else:
                # Need to split paragraph into smaller chunks
                paragraph_chunks = self._split_paragraph(
                    paragraph, note_id, chunk_counter
                )
                chunks.extend(paragraph_chunks)
                chunk_counter += len(paragraph_chunks)

        return chunks

    def _clean_text(self, text: str) -> str:
        """Clean and normalize text before chunking.

        Preserve newlines so markdown excerpts render correctly.
        """
        text = text.replace("\r\n", "\n").replace("\r", "\n")
        text = text.replace("<!-- grimoire-chunk -->", "")
        return text.strip()

    def _split_into_paragraphs(self, text: str) -> List[str]:
        """Split text into paragraphs."""
        # Split by double newlines, preserving meaningful paragraph breaks
        paragraphs = re.split(r"\n\s*\n", text)
        # Filter out empty paragraphs
        paragraphs = [p.strip() for p in paragraphs if p.strip()]
        return paragraphs

    def _split_paragraph(
        self, paragraph: str, note_id: str, start_counter: int
    ) -> List[Dict[str, str]]:
        """Split a long paragraph into appropriately sized chunks."""
        chunks = []
        current_pos = 0
        chunk_counter = start_counter

        while current_pos < len(paragraph):
            # Determine chunk end position
            chunk_end = current_pos + self.max_chunk_size

            if chunk_end >= len(paragraph):
                # Last chunk
                chunk_text = paragraph[current_pos:]
            else:
                # Try to break at sentence boundary
                chunk_text = paragraph[current_pos:chunk_end]

                # Look for sentence boundaries in the last 50 characters
                sentence_boundaries = [". ", "! ", "? ", "\n", "; "]
                boundary_pos = -1

                for boundary in sentence_boundaries:
                    pos = chunk_text.rfind(boundary)
                    if pos > self.min_chunk_size:
                        boundary_pos = pos + len(boundary)
                        break

                if boundary_pos > 0:
                    chunk_text = chunk_text[:boundary_pos]
                    chunk_end = current_pos + boundary_pos
                else:
                    # No good boundary found, break at word boundary
                    last_space = chunk_text.rfind(" ")
                    if last_space > self.min_chunk_size:
                        chunk_text = chunk_text[:last_space]
                        chunk_end = current_pos + last_space

            # Create chunk
            chunk_id = f"{note_id}_{chunk_counter}"
            chunks.append(
                {
                    "chunk_id": chunk_id,
                    "text": chunk_text.strip(),
                    "note_id": note_id,
                    "start_char": current_pos,
                    "end_char": chunk_end,
                }
            )

            # Move position for next chunk
            current_pos = (
                chunk_end - self.overlap if chunk_end < len(paragraph) else chunk_end
            )
            chunk_counter += 1

            # Ensure we don't get stuck in infinite loop
            if current_pos <= chunks[-1]["start_char"]:
                current_pos = chunks[-1]["end_char"]

        return chunks

    def get_chunk_context(
        self, text: str, chunk_start: int, chunk_end: int, context_chars: int = 100
    ) -> str:
        """
        Get context around a chunk for better display.

        Args:
            text: The full text
            chunk_start: Start position of the chunk
            chunk_end: End position of the chunk
            context_chars: Number of characters of context to include on each side

        Returns:
            Text with context markers
        """
        context_start = max(0, chunk_start - context_chars)
        context_end = min(len(text), chunk_end + context_chars)

        context_text = text[context_start:context_end]

        # Add markers to show where the chunk is
        chunk_in_context_start = chunk_start - context_start
        chunk_in_context_end = chunk_end - context_start

        # Create a marked version if we have the full chunk
        if chunk_in_context_start >= 0 and chunk_in_context_end <= len(context_text):
            marked_text = (
                context_text[:chunk_in_context_start]
                + "**"
                + context_text[chunk_in_context_start:chunk_in_context_end]
                + "**"
                + context_text[chunk_in_context_end:]
            )
            return marked_text

        return context_text
