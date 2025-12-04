"""
Embedding module for Grimoire.

Uses sentence-transformers to convert text chunks into vector embeddings.
Falls back to simple embeddings if sentence-transformers is not available.
"""

import os
from typing import List, Optional

import numpy as np


class Embedder:
    """Handles text embedding using sentence-transformers."""

    def __init__(self, model_name: str = "all-MiniLM-L6-v2"):
        """
        Initialize the embedder.

        Args:
            model_name: Name of the sentence-transformers model to use.
                       Default is "all-MiniLM-L6-v2" (good balance of speed/quality).
        """
        self.model_name = model_name
        self.model = None
        self.embedding_dim = 384  # Default for MiniLM-L6-v2
        self.use_fallback = False

    def load_model(self):
        """Lazy load the sentence-transformers model with fallback."""
        if self.model is None:
            try:
                print(
                    f"Attempting to load sentence-transformers model: {self.model_name}"
                )
                from sentence_transformers import SentenceTransformer

                print(f"✓ Imported SentenceTransformer")
                self.model = SentenceTransformer(self.model_name)
                print(f"✓ Created SentenceTransformer instance")
                # Get actual embedding dimension
                test_embedding = self.model.encode(["test"])
                self.embedding_dim = test_embedding.shape[1]
                self.use_fallback = False
                print(
                    f"✓ Model loaded successfully. Embedding dimension: {self.embedding_dim}"
                )
            except ImportError as e:
                print(
                    f"Warning: sentence-transformers not installed. Using fallback embeddings. Error: {e}"
                )
                print("Install with: pip install sentence-transformers")
                self.use_fallback = True
                self.embedding_dim = 384  # Use default dimension
            except Exception as e:
                print(
                    f"Warning: Failed to load model: {str(e)}. Using fallback embeddings."
                )
                import traceback

                print(f"Full traceback: {traceback.format_exc()}")
                self.use_fallback = True
                self.embedding_dim = 384  # Use default dimension

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
            # Return zero vector for empty text
            return [0.0] * self.embedding_dim

        if self.use_fallback or self.model is None:
            # Use fallback embedding
            print(f"Using fallback embedding for text of length: {len(text)}")
            return self._fallback_embed(text)

        try:
            # Encode the text
            embedding = self.model.encode([text], convert_to_numpy=True)
            return embedding[0].tolist()
        except Exception as e:
            # Fall back to simple embedding if model encoding fails
            return self._fallback_embed(text)

    def embed_batch(self, texts: List[str]) -> List[List[float]]:
        """
        Convert multiple texts to embedding vectors.

        Args:
            texts: List of input texts to embed

        Returns:
            List of embedding vectors
        """
        self.load_model()

        if self.use_fallback or self.model is None:
            # Fallback: simple hash-based embeddings for basic functionality
            print(f"Using fallback batch embedding for {len(texts)} texts")
            return [self._fallback_embed(text) for text in texts]

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
            raise RuntimeError(f"Batch embedding failed: {str(e)}")

    def get_embedding_dim(self) -> int:
        """Get the dimension of embedding vectors."""
        self.load_model()
        return self.embedding_dim

    def _fallback_embed(self, text: str) -> List[float]:
        """
        Simple fallback embedding when sentence-transformers is not available.
        Creates deterministic pseudo-random embeddings based on text hash.

        Args:
            text: Input text

        Returns:
            List of floats representing a simple embedding
        """
        import hashlib
        import math

        # Create a deterministic hash from the text
        text_hash = hashlib.md5(text.encode("utf-8")).hexdigest()
        hash_int = int(text_hash[:8], 16)  # Use first 8 chars for seed

        # Generate deterministic pseudo-random embedding
        embedding = []
        for i in range(self.embedding_dim):
            # Use different seeds for each dimension
            seed = hash_int + i * 997  # Prime number for variation
            # Simple pseudo-random function
            value = math.sin(seed) * 0.5 + 0.5  # Normalize to 0-1
            embedding.append(float(value))

        return embedding

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
