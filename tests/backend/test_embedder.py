"""
Unit tests for the Embedder module.
"""

import os
import sys
from unittest.mock import MagicMock, Mock, patch

import numpy as np
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../backend"))

from embedder import Embedder


class TestEmbedder:
    """Test suite for the Embedder class."""

    def setup_method(self):
        """Set up test fixtures."""
        self.embedder = Embedder(model_name="all-MiniLM-L6-v2")

    def test_embedder_initialization(self):
        """Test that embedder initializes with correct parameters."""
        embedder = Embedder(model_name="test-model")
        assert embedder.model_name == "test-model"
        assert embedder.model is None
        assert embedder.embedding_dim == 384  # Default for MiniLM-L6-v2

    @patch("sentence_transformers.SentenceTransformer")
    def test_load_model(self, mock_sentence_transformer):
        """Test loading the sentence-transformers model."""
        # Mock the model
        mock_model = Mock()
        mock_model.encode.return_value = np.array([[0.1] * 384])
        mock_sentence_transformer.return_value = mock_model

        # Load the model
        self.embedder.load_model()

        # Verify model was loaded
        assert self.embedder.model is not None
        mock_sentence_transformer.assert_called_once_with("all-MiniLM-L6-v2")
        assert self.embedder.embedding_dim == 384
        # Reset the mock for other tests
        self.embedder.model = None

    @patch("sentence_transformers.SentenceTransformer")
    def test_embed_single_text(self, mock_sentence_transformer):
        """Test embedding a single text."""
        # Mock the model
        mock_model = Mock()
        expected_embedding = np.array([[0.1, 0.2, 0.3, 0.4]])  # 2D array
        mock_model.encode.return_value = expected_embedding
        mock_sentence_transformer.return_value = mock_model

        # Set embedding dimension
        self.embedder.embedding_dim = 4

        # Test embedding without loading model (it will load automatically)
        text = "This is a test sentence."
        result = self.embedder.embed(text)

        # Verify
        mock_model.encode.assert_called_with([text], convert_to_numpy=True)
        assert result == expected_embedding[0].tolist()
        assert len(result) == 4

    def test_embed_empty_text(self):
        """Test embedding empty text returns zero vector."""
        # Mock model loading to avoid actual model download
        with patch.object(self.embedder, "model", Mock()):
            self.embedder.embedding_dim = 384
            result = self.embedder.embed("")

            assert result == [0.0] * 384
            assert len(result) == 384

    @patch("sentence_transformers.SentenceTransformer")
    def test_embed_batch(self, mock_sentence_transformer):
        """Test batch embedding."""
        # Mock the model
        mock_model = Mock()
        expected_embeddings = np.array([[0.1, 0.2, 0.3, 0.4], [0.5, 0.6, 0.7, 0.8]])
        mock_model.encode.return_value = expected_embeddings
        mock_sentence_transformer.return_value = mock_model

        # Set embedding dimension
        self.embedder.embedding_dim = 4

        # Test batch embedding without loading model
        texts = ["First sentence.", "Second sentence."]
        result = self.embedder.embed_batch(texts)

        # Verify
        mock_model.encode.assert_called_with(texts, convert_to_numpy=True)
        assert len(result) == 2
        assert result[0] == expected_embeddings[0].tolist()
        assert result[1] == expected_embeddings[1].tolist()

    @patch("sentence_transformers.SentenceTransformer")
    def test_embed_batch_with_empty_texts(self, mock_sentence_transformer):
        """Test batch embedding with empty texts."""
        # Mock the model
        mock_model = Mock()
        mock_model.encode.return_value = np.array([[0.1, 0.2, 0.3, 0.4]])
        mock_sentence_transformer.return_value = mock_model

        # Set embedding dimension
        self.embedder.embedding_dim = 4

        # Test batch embedding with empty text
        texts = ["Valid text", "", "   "]
        result = self.embedder.embed_batch(texts)

        # Verify
        mock_model.encode.assert_called_with(["Valid text"], convert_to_numpy=True)
        assert len(result) == 3
        assert result[0] == [0.1, 0.2, 0.3, 0.4]  # Valid text
        assert result[1] == [0.0, 0.0, 0.0, 0.0]  # Empty text
        assert result[2] == [0.0, 0.0, 0.0, 0.0]  # Whitespace-only text

    def test_get_embedding_dimension(self):
        """Test getting embedding dimension."""
        # Mock model loading
        with patch.object(self.embedder, "model", Mock()):
            self.embedder.embedding_dim = 512
            result = self.embedder.get_embedding_dimension()

            assert result == 512

    def test_cosine_similarity(self):
        """Test cosine similarity calculation."""
        # Test with identical vectors
        vec1 = [1.0, 0.0, 0.0]
        vec2 = [1.0, 0.0, 0.0]
        similarity = self.embedder.cosine_similarity(vec1, vec2)
        assert abs(similarity - 1.0) < 0.0001

        # Test with orthogonal vectors
        vec1 = [1.0, 0.0, 0.0]
        vec2 = [0.0, 1.0, 0.0]
        similarity = self.embedder.cosine_similarity(vec1, vec2)
        assert abs(similarity - 0.0) < 0.0001

        # Test with opposite vectors
        vec1 = [1.0, 0.0, 0.0]
        vec2 = [-1.0, 0.0, 0.0]
        similarity = self.embedder.cosine_similarity(vec1, vec2)
        assert abs(similarity - (-1.0)) < 0.0001

        # Test with zero vectors
        vec1 = [0.0, 0.0, 0.0]
        vec2 = [1.0, 0.0, 0.0]
        similarity = self.embedder.cosine_similarity(vec1, vec2)
        assert similarity == 0.0

    def test_cosine_similarity_dimension_mismatch(self):
        """Test cosine similarity with dimension mismatch."""
        vec1 = [1.0, 0.0]
        vec2 = [1.0, 0.0, 0.0]

        with pytest.raises(ValueError, match="Vector dimensions don't match"):
            self.embedder.cosine_similarity(vec1, vec2)

    def test_normalize_vector(self):
        """Test vector normalization."""
        # Test with non-zero vector
        vector = [3.0, 4.0, 0.0]
        normalized = self.embedder.normalize_vector(vector)

        # Check length is approximately 1
        length = np.linalg.norm(normalized)
        assert abs(length - 1.0) < 0.0001

        # Check direction is preserved
        assert abs(normalized[0] - 0.6) < 0.0001
        assert abs(normalized[1] - 0.8) < 0.0001
        assert normalized[2] == 0.0

        # Test with zero vector
        vector = [0.0, 0.0, 0.0]
        normalized = self.embedder.normalize_vector(vector)
        assert normalized == vector  # Should return original

    @patch("embedder.np.save")
    @patch("embedder.os.makedirs")
    def test_save_embeddings(self, mock_makedirs, mock_np_save):
        """Test saving embeddings to file."""
        embeddings = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
        filepath = "test_embeddings.npy"

        self.embedder.save_embeddings(embeddings, filepath)

        mock_makedirs.assert_called_once()
        mock_np_save.assert_called_once()

    @patch("embedder.np.load")
    def test_load_embeddings(self, mock_np_load):
        """Test loading embeddings from file."""
        expected_embeddings = np.array([[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]])
        mock_np_load.return_value = expected_embeddings

        with patch("embedder.os.path.exists", return_value=True):
            result = self.embedder.load_embeddings("test_embeddings.npy")

            mock_np_load.assert_called_once_with("test_embeddings.npy")
            assert result == expected_embeddings.tolist()

    @patch("embedder.os.path.exists")
    def test_load_embeddings_file_not_found(self, mock_exists):
        """Test loading embeddings when file doesn't exist."""
        mock_exists.return_value = False

        with pytest.raises(RuntimeError, match="Failed to load embeddings"):
            self.embedder.load_embeddings("nonexistent.npy")

    @patch("sentence_transformers.SentenceTransformer")
    def test_embed_exception_handling(self, mock_sentence_transformer):
        """Test exception handling during embedding."""
        # Mock model that raises an exception
        mock_model = Mock()
        mock_model.encode.side_effect = Exception("Model error")
        mock_sentence_transformer.return_value = mock_model

        # Set embedding dimension
        self.embedder.embedding_dim = 384

        # Test that exception is properly raised
        with pytest.raises(RuntimeError, match="Failed to load model"):
            self.embedder.embed("test text")

    def test_embedding_consistency(self):
        """Test that embedding produces consistent results."""
        # Mock the model
        with patch.object(self.embedder, "model", Mock()):
            self.embedder.embedding_dim = 384

            # Create a mock embedding
            mock_embedding = np.array([float(i % 10) / 10 for i in range(384)])

            # Mock the encode method
            self.embedder.model.encode = Mock(return_value=mock_embedding)

            # Embed the same text twice
            text = "Consistency test"
            result1 = self.embedder.embed(text)
            result2 = self.embedder.embed(text)

            # Should get the same result
            assert result1 == result2

    @pytest.mark.parametrize("text_length", [10, 100, 1000])
    def test_embed_various_lengths(self, text_length):
        """Test embedding texts of various lengths."""
        # Mock the model
        with patch.object(self.embedder, "model", Mock()):
            self.embedder.embedding_dim = 384

            # Create a mock embedding (2D array)
            mock_embedding = np.array([[0.1] * 384])
            self.embedder.model.encode = Mock(return_value=mock_embedding)

            # Create text of specified length
            text = "x" * text_length

            # Should handle all lengths
            result = self.embedder.embed(text)
            # Should return a list of floats
            assert isinstance(result, list)
            assert len(result) == 384
            assert all(isinstance(x, float) for x in result)


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
