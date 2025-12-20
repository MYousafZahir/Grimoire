"""
Embedding module for Grimoire.

Uses sentence-transformers to convert text chunks into vector embeddings.
"""

import os
from typing import List, Optional

import numpy as np


class Embedder:
    """Handles text embedding using sentence-transformers."""

    def __init__(self, model_name: Optional[str] = None):
        """
        Initialize the embedder.

        Args:
            model_name: Name of the sentence-transformers model to use.
                       Defaults to `GRIMOIRE_SEARCH_EMBED_MODEL` or `BAAI/bge-small-en-v1.5`.
        """
        self.model_name = (model_name or os.environ.get("GRIMOIRE_SEARCH_EMBED_MODEL") or "BAAI/bge-small-en-v1.5")
        self.model = None
        self.embedding_dim = 384  # common for many small ST models; refined after load

    def load_model(self):
        """Lazy load the sentence-transformers model."""
        if self.model is not None:
            return
        try:
            print(f"Attempting to load sentence-transformers model: {self.model_name}")
            from sentence_transformers import SentenceTransformer
        except ImportError as e:
            raise RuntimeError(
                "sentence-transformers is required for embeddings. "
                f"Install it and ensure model '{self.model_name}' is available. Reason: {e}"
            ) from e

        try:
            from context_service import _resolve_hf_snapshot

            resolved = _resolve_hf_snapshot(self.model_name)
            self.model = SentenceTransformer(resolved)
            test_embedding = self.model.encode(["test"])
            self.embedding_dim = test_embedding.shape[1]
            print(
                f"✓ Model loaded successfully. Embedding dimension: {self.embedding_dim}"
            )
        except Exception as e:
            raise RuntimeError(
                f"Failed to load sentence-transformers model '{self.model_name}': {e}"
            ) from e

    def embed(self, text: str) -> List[float]:
        """
        Convert text to embedding vector.

        Args:
            text: Text to embed

        Returns:
            List of floats representing the embedding vector
        """
        self.load_model()

        if not text or not text.strip():
            return [0.0] * self.embedding_dim

        try:
            # Encode the text
            embedding = self.model.encode([text], convert_to_numpy=True)
            return embedding[0].tolist()
        except Exception as e:
            raise RuntimeError(f"Embedding failed: {e}") from e

    def embed_batch(self, texts: List[str]) -> List[List[float]]:
        """
        Convert multiple texts to embedding vectors.

        Args:
            texts: List of input texts to embed

        Returns:
            List of embedding vectors
        """
        self.load_model()

        if not texts:
            return []

        # Filter out empty texts
        valid_texts = [text for text in texts if text and text.strip()]
        if not valid_texts:
            return [[] for _ in texts]

        try:
            embeddings = self.model.encode(valid_texts, convert_to_numpy=True)
            result = []
            text_idx = 0

            for text in texts:
                if text and text.strip():
                    result.append(embeddings[text_idx].tolist())
                    text_idx += 1
                else:
                    result.append([0.0] * self.embedding_dim)

            return result
        except Exception as e:
            raise RuntimeError(f"Batch embedding failed: {str(e)}") from e

    def get_embedding_dim(self) -> int:
        """Get the dimension of embedding vectors."""
        self.load_model()
        return self.embedding_dim


    def cosine_similarity(self, vec1: List[float], vec2: List[float]) -> float:
        """
        Calculate cosine similarity between two vectors.

        Args:
            vec1: First embedding vector
            vec2: Second embedding vector

        Returns:
            Cosine similarity score between -1 and 1
        """
        if len(vec1) != len(vec2):
            raise ValueError(
                f"Vector dimensions don't match: {len(vec1)} vs {len(vec2)}"
            )

        # Convert to numpy arrays for efficient computation
        v1 = np.array(vec1)
        v2 = np.array(vec2)

        # Calculate cosine similarity
        dot_product = np.dot(v1, v2)
        norm1 = np.linalg.norm(v1)
        norm2 = np.linalg.norm(v2)

        if norm1 == 0 or norm2 == 0:
            return 0.0

        return float(dot_product / (norm1 * norm2))

    def normalize_vector(self, vector: List[float]) -> List[float]:
        """
        Normalize a vector to unit length.

        Args:
            vector: Input vector

        Returns:
            Normalized vector
        """
        v = np.array(vector)
        norm = np.linalg.norm(v)

        if norm == 0:
            return vector

        return (v / norm).tolist()

    def save_embeddings(self, embeddings: List[List[float]], filepath: str):
        """
        Save embeddings to a file.

        Args:
            embeddings: List of embedding vectors
            filepath: Path to save the embeddings
        """
        try:
            # Create directory if it doesn't exist
            os.makedirs(os.path.dirname(filepath), exist_ok=True)

            # Save as numpy array
            np_embeddings = np.array(embeddings)
            np.save(filepath, np_embeddings)
            print(f"Saved {len(embeddings)} embeddings to {filepath}")
        except Exception as e:
            raise RuntimeError(f"Failed to save embeddings: {str(e)}")

    def load_embeddings(self, filepath: str) -> List[List[float]]:
        """
        Load embeddings from a file.

        Args:
            filepath: Path to the embeddings file

        Returns:
            List of embedding vectors
        """
        try:
            if not os.path.exists(filepath):
                raise FileNotFoundError(f"Embeddings file not found: {filepath}")

            np_embeddings = np.load(filepath)
            return np_embeddings.tolist()
        except Exception as e:
            raise RuntimeError(f"Failed to load embeddings: {str(e)}")
