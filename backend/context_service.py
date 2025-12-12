"""Cursor-conditioned semantic context retrieval for the semantic backlinks panel.

This module implements a deterministic, inspectable retriever that models reader state:
- prefix (known) text before cursor
- window (focus) around cursor
- optional suffix (near future)

It uses corpus-internal concept statistics + retrieval + redundancy control.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

import numpy as np

from context_models import ContextRequest, ContextSnippetPayload, WarmupResponsePayload
from embedder import Embedder
from models import NoteKind, NoteRecord


def _configure_cpu_threading_defaults():
    """Conservatively limit CPU threading to avoid libomp/torch instability.

    Some torch + OpenMP configurations on macOS can segfault under load when using
    many threads. Default to single-threaded execution unless the user overrides.
    """
    os.environ.setdefault("OMP_NUM_THREADS", os.environ.get("GRIMOIRE_OMP_NUM_THREADS", "1"))
    os.environ.setdefault("MKL_NUM_THREADS", os.environ.get("GRIMOIRE_MKL_NUM_THREADS", "1"))
    os.environ.setdefault(
        "VECLIB_MAXIMUM_THREADS",
        os.environ.get("GRIMOIRE_VECLIB_MAXIMUM_THREADS", "1"),
    )
    os.environ.setdefault("NUMEXPR_NUM_THREADS", os.environ.get("GRIMOIRE_NUMEXPR_NUM_THREADS", "1"))
    os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")


_configure_cpu_threading_defaults()


def _configure_torch_threads():
    try:
        import torch  # type: ignore

        threads = int(os.environ.get("GRIMOIRE_TORCH_NUM_THREADS", "1"))
        interop = int(os.environ.get("GRIMOIRE_TORCH_NUM_INTEROP_THREADS", "1"))
        threads = max(1, threads)
        interop = max(1, interop)
        torch.set_num_threads(threads)
        torch.set_num_interop_threads(interop)
    except Exception as exc:
        print(f"context_service: torch thread config skipped: {exc}")


def _normalize_dense(vec: Sequence[float]) -> np.ndarray:
    arr = np.asarray(vec, dtype=np.float32)
    norm = float(np.linalg.norm(arr))
    if norm <= 0:
        return arr
    return arr / norm


def _dot(a: np.ndarray, b: np.ndarray) -> float:
    if a.size == 0 or b.size == 0:
        return 0.0
    return float(np.dot(a, b))


def _sigmoid(x: float) -> float:
    # Numerically stable sigmoid.
    if x >= 0:
        z = math.exp(-x)
        return 1.0 / (1.0 + z)
    z = math.exp(x)
    return z / (1.0 + z)


def _stable_int_id(text: str) -> int:
    """Legacy deterministic id helper.

    Note: FAISS expects signed int64 ids. This helper now returns a signed int64
    value (and avoids -1), but ContextIndex prefers a persisted sequential id
    mapping to avoid collisions and overflow across upgrades.
    """
    digest = hashlib.sha1(text.encode("utf-8")).digest()[:8]
    value = int.from_bytes(digest, byteorder="big", signed=True)
    return -2 if value == -1 else value


def _clean_text(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


_BLANK_SPLIT_RE = re.compile(r"\n[ \t]*\n+")


@dataclass(frozen=True)
class Block:
    start: int
    end: int
    text: str


def split_blocks(text: str) -> List[Block]:
    """Split markdown into blocks separated by blank lines.

    Offsets are note-relative within `text`.
    """
    text = _clean_text(text)
    if not text:
        return [Block(start=0, end=0, text="")]

    blocks: List[Block] = []
    last = 0
    for match in _BLANK_SPLIT_RE.finditer(text):
        raw = text[last : match.start()]
        # Trim only outer newlines/spaces but keep offset mapping.
        leading = len(raw) - len(raw.lstrip("\n"))
        trailing = len(raw) - len(raw.rstrip("\n"))
        start = last + leading
        end = match.start() - trailing
        if end < start:
            start = last
            end = match.start()
        part = text[start:end].strip()
        if part:
            blocks.append(Block(start=start, end=end, text=part))
        last = match.end()

    raw_tail = text[last:]
    leading = len(raw_tail) - len(raw_tail.lstrip("\n"))
    trailing = len(raw_tail) - len(raw_tail.rstrip("\n"))
    start = last + leading
    end = len(text) - trailing
    part = text[start:end].strip()
    if part or not blocks:
        blocks.append(Block(start=start, end=end, text=part))

    return blocks


_HEADING_RE = re.compile(r"(?m)^[ \t]{0,3}#{1,6}[ \t]+(.+?)\s*$")
_CAP_PHRASE_RE = re.compile(r"\b(?:[A-Z][A-Za-z0-9'_-]*)(?:\s+[A-Z][A-Za-z0-9'_-]*){0,4}\b")


def _normalize_concept_label(label: str) -> str:
    label = label.strip()
    label = re.sub(r"`+", "", label)
    label = re.sub(r"[^\w\s-]", "", label)
    label = re.sub(r"\s+", " ", label)
    return label.lower().strip()


def extract_concept_candidates(text: str) -> List[str]:
    """Heuristic concept extraction from user markdown."""
    text = _clean_text(text)
    candidates: List[str] = []

    for match in _HEADING_RE.finditer(text):
        title = match.group(1).strip()
        if title:
            candidates.append(title)

    for match in _CAP_PHRASE_RE.finditer(text):
        phrase = match.group(0).strip()
        if len(phrase) >= 3:
            candidates.append(phrase)

    # De-duplicate while preserving deterministic order.
    seen: Set[str] = set()
    out: List[str] = []
    for item in candidates:
        norm = _normalize_concept_label(item)
        if not norm or norm in seen:
            continue
        if len(norm) < 3:
            continue
        seen.add(norm)
        out.append(item.strip())
    return out


def _count_occurrences(haystack: str, needle: str) -> int:
    if not needle:
        return 0
    # Case-insensitive, word-boundary-ish match.
    pattern = re.compile(rf"(?i)(?<!\\w){re.escape(needle)}(?!\\w)")
    return len(pattern.findall(haystack))


def _sentences_excerpt(text: str, max_sentences: int = 3, max_chars: int = 600) -> str:
    text = text.strip()
    if not text:
        return ""
    # Simple sentence splitter; deterministic and local.
    parts = re.split(r"(?<=[.!?])\s+", text)
    excerpt = " ".join(parts[:max_sentences]).strip()
    if len(excerpt) > max_chars:
        excerpt = excerpt[:max_chars].rstrip()
    return excerpt


class _SparseTokenizer:
    @staticmethod
    def tokenize(text: str) -> List[str]:
        text = text.lower()
        return re.findall(r"[a-z0-9_'-]{2,}", text)


class ContextEmbedder:
    """Dense embedder wrapper for realtime semantic context.

    Default model is BAAI/bge-small-en-v1.5 (fast enough for CPU realtime).
    """

    def __init__(self, model_name: str = "BAAI/bge-small-en-v1.5"):
        self.model_name = model_name
        self._model = None
        self._fallback = Embedder(model_name=model_name)

    def _configure_torch_threads(self):
        _configure_torch_threads()

    def _load(self):
        if self._model is not None:
            return
        try:
            from sentence_transformers import SentenceTransformer  # type: ignore

            self._configure_torch_threads()
            self._model = SentenceTransformer(self.model_name)
        except Exception as exc:
            # Keep app usable even if the optional dependency isn't installed yet.
            print(f"ContextEmbedder: model unavailable, falling back. Reason: {exc}")
            self._model = None

    def encode_dense(self, text: str) -> np.ndarray:
        text = text.strip()
        if not text:
            return _normalize_dense([0.0] * self._fallback.get_embedding_dim())
        self._load()
        if self._model is None:
            return _normalize_dense(self._fallback.embed(text))
        try:
            vec = self._model.encode(
                [text],
                convert_to_numpy=True,
                normalize_embeddings=True,
                show_progress_bar=False,
            )[0]
            return np.asarray(vec, dtype=np.float32)
        except TypeError:
            vec = self._model.encode([text], convert_to_numpy=True, show_progress_bar=False)[0]
            return _normalize_dense(vec)

    def embedding_dim(self) -> int:
        vec = self.encode_dense("dim probe")
        return int(vec.shape[0])


class ContextReranker:
    def __init__(self, model_name: str):
        self.model_name = model_name
        self._model = None
        enabled = os.environ.get("GRIMOIRE_ENABLE_RERANKER", "1").strip().lower()
        self.enabled = enabled not in ("0", "false", "no", "off")

    def _load(self):
        if not self.enabled:
            return
        if self._model is not None:
            return
        try:
            from FlagEmbedding import FlagReranker  # type: ignore

            _configure_torch_threads()
            self._model = FlagReranker(self.model_name, use_fp16=False)
        except Exception as exc:
            print(f"ContextReranker: unavailable, disabling. Reason: {exc}")
            self._model = None
            self.enabled = False

    def score(self, query: str, documents: List[str]) -> Optional[List[float]]:
        query = query.strip()
        if not self.enabled or not query or not documents:
            return None
        self._load()
        if self._model is None:
            return None

        pairs = [(query, d) for d in documents]
        try:
            scores = self._model.compute_score(sentence_pairs=pairs)  # type: ignore[arg-type]
        except TypeError:
            scores = self._model.compute_score(pairs)  # type: ignore[misc]
        except Exception as exc:
            print(f"ContextReranker: scoring failed: {exc}")
            return None

        if isinstance(scores, (float, int)):
            return [float(scores)] * len(documents)
        return [float(s) for s in scores]


class ContextIndex:
    def __init__(
        self,
        metadata_path: Optional[str] = None,
        faiss_path: Optional[str] = None,
    ):
        base_dir = Path(__file__).resolve().parent
        default_metadata = base_dir / "storage" / "context_index.json"
        default_faiss = base_dir / "storage" / "context_faiss.index"

        self.metadata_path = str(default_metadata if metadata_path is None else metadata_path)
        # FAISS/HNSW dense retrieval index path.
        self.faiss_path = str(default_faiss if faiss_path is None else faiss_path)

        # Migration: older builds may have written indexes relative to CWD.
        if metadata_path is None and not default_metadata.exists():
            candidates = [
                Path("storage/context_index.json").resolve(),
                (base_dir.parent / "storage" / "context_index.json").resolve(),
            ]
            for candidate in candidates:
                if candidate.exists():
                    self.metadata_path = str(candidate)
                    break

        if faiss_path is None and not default_faiss.exists():
            candidates = [
                Path("storage/context_faiss.index").resolve(),
                (base_dir.parent / "storage" / "context_faiss.index").resolve(),
            ]
            for candidate in candidates:
                if candidate.exists():
                    self.faiss_path = str(candidate)
                    break

        self._chunk: Dict[str, Dict] = {}
        self._chunk_int: Dict[str, int] = {}
        self._int_chunk: Dict[str, str] = {}

        self._concept_label: Dict[str, str] = {}
        self._concept_chunks: Dict[str, Set[str]] = {}
        self._concept_centroid: Dict[str, Optional[np.ndarray]] = {}
        self._concept_dirty: Set[str] = set()

        # token -> {chunk_id: weight}
        self._sparse_postings: Dict[str, Dict[str, float]] = {}

        # BM25 index (lexical).
        self._bm25_dirty: bool = True
        self._bm25_postings: Dict[str, List[Tuple[str, int]]] = {}
        self._bm25_doc_len: Dict[str, int] = {}
        self._bm25_df: Dict[str, int] = {}
        self._bm25_avgdl: float = 0.0

        # Dense retrieval cache + FAISS/HNSW index.
        self._dense_dirty: bool = True
        self._dense_matrix: Optional[np.ndarray] = None  # shape: (n, d)
        self._dense_chunk_ids: List[str] = []
        self._dense_note_ids: List[str] = []
        self._dense_dim: Optional[int] = None
        self._faiss_dirty: bool = True
        self._faiss_index = None
        self._note_prefix_dirty: bool = True
        self._note_prefix_sum: Dict[str, List[np.ndarray]] = {}
        self._note_prefix_count: Dict[str, List[int]] = {}

        self._load()
        self._repair_chunk_id_mapping()
        self._load_faiss()

        # If we loaded from a legacy location, persist into the default backend storage path.
        if metadata_path is None and self.metadata_path != str(default_metadata):
            try:
                self.metadata_path = str(default_metadata)
                self._save_metadata()
            except Exception:
                pass
        # FAISS index is persisted separately.

    def _load(self):
        try:
            if os.path.exists(self.metadata_path):
                with open(self.metadata_path, "r", encoding="utf-8") as f:
                    payload = json.load(f)
                self._chunk = payload.get("chunks", {}) or {}
                self._chunk_int = payload.get("chunk_id_to_int", {}) or {}
                self._int_chunk = payload.get("int_to_chunk_id", {}) or {}
                self._concept_label = payload.get("concept_label", {}) or {}
                print(f"Loaded context index metadata: {len(self._chunk)} chunks")
        except Exception as exc:
            print(f"ContextIndex: failed to load metadata: {exc}")
            self._chunk = {}
            self._chunk_int = {}
            self._int_chunk = {}
            self._concept_label = {}

        self._rebuild_derived()
        self._dense_dirty = True
        self._bm25_dirty = True
        self._faiss_dirty = True
        self._note_prefix_dirty = True

    def _rebuild_dense_cache(self):
        chunk_ids: List[str] = []
        note_ids: List[str] = []
        vectors: List[np.ndarray] = []
        dim: Optional[int] = None

        for chunk_id in sorted(self._chunk.keys()):
            meta = self._chunk.get(chunk_id) or {}
            dense = meta.get("dense")
            if not dense:
                continue
            vec = _normalize_dense(dense)
            if vec.size == 0:
                continue
            if dim is None:
                dim = int(vec.shape[0])
            if int(vec.shape[0]) != int(dim):
                continue
            chunk_ids.append(chunk_id)
            note_ids.append(str(meta.get("note_id") or ""))
            vectors.append(vec.astype(np.float32))

        self._dense_dim = dim
        self._dense_chunk_ids = chunk_ids
        self._dense_note_ids = note_ids
        self._dense_matrix = np.stack(vectors, axis=0) if vectors else None
        self._dense_dirty = False

    def _save_metadata(self):
        try:
            os.makedirs(os.path.dirname(self.metadata_path), exist_ok=True)
            payload = {
                "chunks": self._chunk,
                "chunk_id_to_int": self._chunk_int,
                "int_to_chunk_id": self._int_chunk,
                "concept_label": self._concept_label,
            }
            with open(self.metadata_path, "w", encoding="utf-8") as f:
                json.dump(payload, f)
        except Exception as exc:
            print(f"ContextIndex: failed to save metadata: {exc}")

    def _rebuild_derived(self):
        self._concept_chunks = {}
        self._concept_centroid = {}
        self._concept_dirty = set()
        self._sparse_postings = {}
        self._bm25_postings = {}
        self._bm25_doc_len = {}
        self._bm25_df = {}
        self._bm25_avgdl = 0.0
        self._bm25_dirty = True
        self._note_prefix_dirty = True

        for chunk_id, meta in self._chunk.items():
            for concept_id in meta.get("concepts", []) or []:
                self._concept_chunks.setdefault(concept_id, set()).add(chunk_id)
                self._concept_dirty.add(concept_id)
            # Legacy sparse postings are deprecated; use BM25 built from chunk text.
            for token, weight in (meta.get("sparse") or {}).items():
                postings = self._sparse_postings.setdefault(token, {})
                postings[chunk_id] = float(weight)

    def _repair_chunk_id_mapping(self):
        """Ensure FAISS-safe, collision-free int64 ids for all chunks."""
        min_i64 = -(2**63)
        max_i64 = 2**63 - 1

        used: Set[int] = set()
        new_chunk_int: Dict[str, int] = {}
        new_int_chunk: Dict[str, str] = {}

        for chunk_id in sorted(self._chunk.keys()):
            raw = self._chunk_int.get(chunk_id)
            try:
                existing = int(raw) if raw is not None else None
            except Exception:
                existing = None

            if (
                existing is not None
                and min_i64 <= existing <= max_i64
                and existing not in (-1, 0)
                and existing not in used
                and self._int_chunk.get(str(existing)) == chunk_id
            ):
                new_chunk_int[chunk_id] = existing
                new_int_chunk[str(existing)] = chunk_id
                used.add(existing)

        next_id = 1
        for chunk_id in sorted(self._chunk.keys()):
            if chunk_id in new_chunk_int:
                continue
            while next_id in used or next_id in (-1, 0):
                next_id += 1
            if next_id > max_i64:
                raise OverflowError("ContextIndex: ran out of FAISS int64 ids")
            new_chunk_int[chunk_id] = next_id
            new_int_chunk[str(next_id)] = chunk_id
            used.add(next_id)
            next_id += 1

        if new_chunk_int != self._chunk_int or new_int_chunk != self._int_chunk:
            self._chunk_int = new_chunk_int
            self._int_chunk = new_int_chunk
            self._save_metadata()
            self._dense_dirty = True

    def _ensure_chunk_int(self, chunk_id: str) -> int:
        value = self._chunk_int.get(chunk_id)
        if value is not None:
            return int(value)
        used = {int(v) for v in self._chunk_int.values() if str(v).lstrip("-").isdigit()}
        next_id = 1
        while next_id in used or next_id in (-1, 0):
            next_id += 1
        int_id = next_id
        self._chunk_int[chunk_id] = int_id
        self._int_chunk[str(int_id)] = chunk_id
        return int_id

    def update_note(self, note_id: str, chunks: List[Dict]):
        existing = [cid for cid, meta in self._chunk.items() if meta.get("note_id") == note_id]
        self._delete_chunks(existing)

        for meta in chunks:
            chunk_id = meta["chunk_id"]
            int_id = self._ensure_chunk_int(chunk_id)
            self._chunk[chunk_id] = meta

            for concept_id, label in (meta.get("concept_labels") or {}).items():
                self._concept_label.setdefault(concept_id, label)

            for concept_id in meta.get("concepts", []) or []:
                self._concept_chunks.setdefault(concept_id, set()).add(chunk_id)
                self._concept_dirty.add(concept_id)

            for token, weight in (meta.get("sparse") or {}).items():
                postings = self._sparse_postings.setdefault(token, {})
                postings[chunk_id] = float(weight)

        self._save_metadata()
        self._dense_dirty = True
        self._bm25_dirty = True
        self._faiss_dirty = True
        self._note_prefix_dirty = True

    def _delete_chunks(self, chunk_ids: Iterable[str]):
        chunk_ids = list(chunk_ids)
        if not chunk_ids:
            return

        for cid in chunk_ids:
            meta = self._chunk.pop(cid, None)
            if not meta:
                continue
            for concept_id in meta.get("concepts", []) or []:
                if concept_id in self._concept_chunks:
                    self._concept_chunks[concept_id].discard(cid)
                    self._concept_dirty.add(concept_id)
            for token in (meta.get("sparse") or {}).keys():
                postings = self._sparse_postings.get(token)
                if postings and cid in postings:
                    postings.pop(cid, None)
                    if not postings:
                        self._sparse_postings.pop(token, None)

        self._dense_dirty = True
        self._bm25_dirty = True
        self._faiss_dirty = True
        self._note_prefix_dirty = True
        self._save_metadata()

    def delete_notes(self, note_ids: Iterable[str]):
        for note_id in note_ids:
            existing = [cid for cid, meta in self._chunk.items() if meta.get("note_id") == note_id]
            self._delete_chunks(existing)

    def clear(self):
        self._chunk = {}
        self._chunk_int = {}
        self._int_chunk = {}
        self._concept_label = {}
        self._rebuild_derived()
        self._dense_matrix = None
        self._dense_chunk_ids = []
        self._dense_note_ids = []
        self._dense_dim = None
        self._dense_dirty = True
        self._bm25_dirty = True
        self._faiss_dirty = True
        self._faiss_index = None
        self._note_prefix_dirty = True
        self._note_prefix_sum = {}
        self._note_prefix_count = {}
        try:
            if os.path.exists(self.metadata_path):
                os.remove(self.metadata_path)
        except Exception:
            pass
        try:
            if os.path.exists(self.faiss_path):
                os.remove(self.faiss_path)
        except Exception:
            pass

    def _load_faiss(self):
        try:
            if not os.path.exists(self.faiss_path):
                return
            import faiss  # type: ignore

            self._faiss_index = faiss.read_index(self.faiss_path)
            self._faiss_dirty = False
        except Exception as exc:
            print(f"ContextIndex: failed to load FAISS index: {exc}")
            self._faiss_index = None
            self._faiss_dirty = True

    def _save_faiss(self):
        if self._faiss_index is None:
            return
        try:
            import faiss  # type: ignore

            os.makedirs(os.path.dirname(self.faiss_path), exist_ok=True)
            faiss.write_index(self._faiss_index, self.faiss_path)
        except Exception as exc:
            print(f"ContextIndex: failed to save FAISS index: {exc}")

    def _rebuild_faiss(self):
        try:
            import faiss  # type: ignore
        except Exception as exc:
            print(f"ContextIndex: faiss unavailable: {exc}")
            self._faiss_index = None
            self._faiss_dirty = False
            return

        if self._dense_dirty or self._dense_matrix is None:
            self._rebuild_dense_cache()

        mat = self._dense_matrix
        if mat is None or mat.size == 0:
            self._faiss_index = None
            self._faiss_dirty = False
            return

        d = int(mat.shape[1])
        m = int(os.environ.get("GRIMOIRE_FAISS_HNSW_M", "32"))
        efc = int(os.environ.get("GRIMOIRE_FAISS_EFCONSTRUCTION", "100"))
        efs = int(os.environ.get("GRIMOIRE_FAISS_EFSEARCH", "64"))

        base = faiss.IndexHNSWFlat(d, m, faiss.METRIC_INNER_PRODUCT)
        base.hnsw.efConstruction = efc
        base.hnsw.efSearch = efs
        index = faiss.IndexIDMap2(base)

        ids = np.array([self._ensure_chunk_int(cid) for cid in self._dense_chunk_ids], dtype=np.int64)
        index.add_with_ids(mat.astype(np.float32), ids)
        self._faiss_index = index
        self._faiss_dirty = False
        self._save_faiss()

    def _ensure_bm25(self):
        if not self._bm25_dirty:
            return
        self._bm25_postings = {}
        self._bm25_doc_len = {}
        self._bm25_df = {}

        total_len = 0
        doc_count = 0

        for chunk_id in sorted(self._chunk.keys()):
            meta = self._chunk.get(chunk_id) or {}
            text = str(meta.get("text") or "")
            tokens = _SparseTokenizer.tokenize(text)
            if not tokens:
                continue
            doc_count += 1
            total_len += len(tokens)
            self._bm25_doc_len[chunk_id] = len(tokens)
            tf: Dict[str, int] = {}
            for t in tokens:
                tf[t] = tf.get(t, 0) + 1
            for token, count in tf.items():
                self._bm25_postings.setdefault(token, []).append((chunk_id, count))
                self._bm25_df[token] = self._bm25_df.get(token, 0) + 1

        self._bm25_avgdl = (float(total_len) / float(doc_count)) if doc_count > 0 else 0.0
        for postings in self._bm25_postings.values():
            postings.sort(key=lambda t: t[0])
        self._bm25_dirty = False

    def bm25_search(self, query: str, exclude_note_id: str, top_k: int) -> List[Tuple[str, float]]:
        query = query.strip()
        if not query:
            return []
        self._ensure_bm25()
        if not self._bm25_postings:
            return []

        tokens = _SparseTokenizer.tokenize(query)
        if not tokens:
            return []

        qtf: Dict[str, int] = {}
        for t in tokens:
            qtf[t] = qtf.get(t, 0) + 1

        N = max(1, len(self._bm25_doc_len))
        avgdl = self._bm25_avgdl if self._bm25_avgdl > 0 else 1.0
        k1 = float(os.environ.get("GRIMOIRE_BM25_K1", "1.2"))
        b = float(os.environ.get("GRIMOIRE_BM25_B", "0.75"))

        scores: Dict[str, float] = {}
        for token, q_count in qtf.items():
            postings = self._bm25_postings.get(token)
            if not postings:
                continue
            df = float(self._bm25_df.get(token, 0))
            idf = math.log((N - df + 0.5) / (df + 0.5) + 1.0)
            for chunk_id, tf in postings:
                meta = self._chunk.get(chunk_id)
                if not meta or meta.get("note_id") == exclude_note_id:
                    continue
                dl = float(self._bm25_doc_len.get(chunk_id, 0) or 0)
                denom = float(tf) + k1 * (1.0 - b + b * (dl / avgdl))
                if denom <= 0:
                    continue
                part = idf * (float(tf) * (k1 + 1.0) / denom)
                scores[chunk_id] = scores.get(chunk_id, 0.0) + part * float(q_count)

        items = sorted(scores.items(), key=lambda kv: (-kv[1], kv[0]))
        return items[:top_k]

    def embedding_dim_guess(self) -> Optional[int]:
        """Best-effort embedding dimension detection for upgrade/migration safety."""
        if self._dense_dim is not None:
            return int(self._dense_dim)
        for meta in self._chunk.values():
            dense = meta.get("dense")
            if dense:
                try:
                    return int(len(dense))
                except Exception:
                    continue
        return None

    def dense_search(self, query_vec: np.ndarray, exclude_note_id: str, top_k: int) -> List[Tuple[str, float]]:
        query_vec = query_vec.astype(np.float32)
        results: List[Tuple[str, float]] = []

        # Prefer FAISS/HNSW when available.
        if self._faiss_dirty:
            self._rebuild_faiss()
        if self._faiss_index is not None:
            try:
                k = min(int(top_k) * 3, int(self._faiss_index.ntotal))  # type: ignore[attr-defined]
                if k <= 0:
                    return []
                q = query_vec.reshape(1, -1).astype(np.float32)
                scores, ids = self._faiss_index.search(q, k)  # type: ignore[union-attr]
                for score, int_id in zip(scores[0].tolist(), ids[0].tolist()):
                    if int_id == -1:
                        continue
                    chunk_id = self._int_chunk.get(str(int(int_id)))
                    if not chunk_id:
                        continue
                    meta = self._chunk.get(chunk_id)
                    if not meta or meta.get("note_id") == exclude_note_id:
                        continue
                    results.append((chunk_id, float(score)))
                    if len(results) >= top_k:
                        break
                return results
            except Exception as exc:
                print(f"ContextIndex: FAISS search failed, falling back: {exc}")

        if self._dense_dirty or self._dense_matrix is None:
            self._rebuild_dense_cache()

        # Fallback: brute force.
        mat = self._dense_matrix
        if mat is None or mat.size == 0:
            return []
        if int(mat.shape[1]) != int(query_vec.shape[0]):
            return []

        scores = mat @ query_vec  # (n,)
        if scores.size == 0:
            return []

        k = min(int(top_k) * 3, int(scores.shape[0]))
        if k <= 0:
            return []
        idx = np.argpartition(-scores, k - 1)[:k]
        idx = idx[np.argsort(-scores[idx], kind="stable")]

        for i in idx.tolist():
            if i < 0 or i >= len(self._dense_chunk_ids):
                continue
            if self._dense_note_ids[i] == exclude_note_id:
                continue
            results.append((self._dense_chunk_ids[i], float(scores[i])))
            if len(results) >= top_k:
                break
        return results

    def sparse_search(self, query_sparse: Dict[str, float], exclude_note_id: str, top_k: int) -> List[Tuple[str, float]]:
        if not query_sparse:
            return []
        scores: Dict[str, float] = {}
        for token, q_w in query_sparse.items():
            postings = self._sparse_postings.get(token)
            if not postings:
                continue
            for cid, c_w in postings.items():
                meta = self._chunk.get(cid)
                if not meta or meta.get("note_id") == exclude_note_id:
                    continue
                scores[cid] = scores.get(cid, 0.0) + float(q_w) * float(c_w)
        items = sorted(scores.items(), key=lambda kv: (-kv[1], kv[0]))
        return items[:top_k]

    def chunks_for_concepts(self, concept_ids: Iterable[str], exclude_note_id: str) -> Set[str]:
        out: Set[str] = set()
        for cid in concept_ids:
            for chunk_id in self._concept_chunks.get(cid, set()):
                meta = self._chunk.get(chunk_id)
                if meta and meta.get("note_id") != exclude_note_id:
                    out.add(chunk_id)
        return out

    def concept_label(self, concept_id: str) -> Optional[str]:
        return self._concept_label.get(concept_id)

    def get_chunk(self, chunk_id: str) -> Optional[Dict]:
        return self._chunk.get(chunk_id)

    def chunk_count(self) -> int:
        return len(self._chunk)

    def prefix_embedding(self, note_id: str, block_index: int) -> Optional[np.ndarray]:
        """Incremental prefix embedding e(P) without re-encoding full prefix.

        Uses the indexed per-block embeddings for the given note and returns
        a normalized sum of all blocks strictly before `block_index`.
        """
        if block_index <= 0:
            return None
        return self._prefix_embedding_from_cache(note_id, block_index)

    def _prefix_embedding_from_cache(self, note_id: str, block_index: int) -> Optional[np.ndarray]:
        if self._note_prefix_dirty:
            self._rebuild_note_prefix_cache()
        sums = self._note_prefix_sum.get(note_id)
        counts = self._note_prefix_count.get(note_id)
        if not sums or not counts:
            return None
        if block_index >= len(sums):
            block_index = len(sums) - 1
        if block_index <= 0:
            return None
        if counts[block_index] <= 0:
            return None
        return _normalize_dense(sums[block_index])

    def _rebuild_note_prefix_cache(self):
        self._note_prefix_sum = {}
        self._note_prefix_count = {}

        by_note: Dict[str, Dict[int, np.ndarray]] = {}
        for chunk_id, meta in self._chunk.items():
            note_id = str(meta.get("note_id") or "")
            dense = meta.get("dense")
            if not note_id or not dense:
                continue
            try:
                idx = int(str(chunk_id).split(":")[-1])
            except Exception:
                continue
            vec = _normalize_dense(dense)
            if vec.size == 0:
                continue
            by_note.setdefault(note_id, {})[idx] = vec.astype(np.float32)

        for note_id, vec_map in by_note.items():
            if not vec_map:
                continue
            max_idx = max(vec_map.keys())
            sums: List[np.ndarray] = []
            counts: List[int] = []
            running = None
            running_count = 0
            # sums[i] = sum of vectors for indices < i
            for i in range(0, max_idx + 2):
                if running is None:
                    # initialize based on any vector dim we have
                    sample = next(iter(vec_map.values()))
                    running = np.zeros_like(sample, dtype=np.float32)
                sums.append(running.copy())
                counts.append(int(running_count))
                vec = vec_map.get(i)
                if vec is not None:
                    running += vec
                    running_count += 1

            self._note_prefix_sum[note_id] = sums
            self._note_prefix_count[note_id] = counts

        self._note_prefix_dirty = False

    def concept_centroid(self, concept_id: str) -> Optional[np.ndarray]:
        if concept_id in self._concept_centroid and concept_id not in self._concept_dirty:
            return self._concept_centroid[concept_id]

        expected_dim = self.embedding_dim_guess()
        chunk_ids = sorted(self._concept_chunks.get(concept_id, set()))
        vecs: List[np.ndarray] = []
        for chunk_id in chunk_ids[:60]:
            meta = self._chunk.get(chunk_id)
            if not meta:
                continue
            vec = _normalize_dense(meta.get("dense") or [])
            if vec.size == 0:
                continue
            if expected_dim is not None and int(vec.shape[0]) != int(expected_dim):
                continue
            vecs.append(vec)

        if not vecs:
            self._concept_centroid[concept_id] = None
            self._concept_dirty.discard(concept_id)
            return None

        if len(vecs) <= 3:
            centroid = _normalize_dense(np.mean(np.stack(vecs, axis=0), axis=0))
            self._concept_centroid[concept_id] = centroid
            self._concept_dirty.discard(concept_id)
            return centroid

        # Densest-cluster approximation (deterministic):
        # pick a seed with highest average similarity, then average its nearest neighbors.
        mat = np.stack(vecs, axis=0).astype(np.float32)
        sims = mat @ mat.T
        avg = sims.mean(axis=1)
        seed_idx = int(np.argmax(avg))
        seed_sims = sims[seed_idx]
        neighbor_idx = np.argsort(-seed_sims)[: min(10, mat.shape[0])]
        centroid = _normalize_dense(np.mean(mat[neighbor_idx], axis=0))

        self._concept_centroid[concept_id] = centroid
        self._concept_dirty.discard(concept_id)
        return centroid


class ContextService:
    def __init__(
        self,
        embedder: Optional[ContextEmbedder] = None,
        index: Optional[ContextIndex] = None,
    ):
        model_name = os.environ.get("GRIMOIRE_BGE_EMBED_MODEL", "BAAI/bge-small-en-v1.5")
        self.embedder = embedder or ContextEmbedder(model_name=model_name)
        self.index = index or ContextIndex()
        reranker_model = os.environ.get("GRIMOIRE_BGE_RERANKER_MODEL", "BAAI/bge-reranker-base")
        self.reranker = ContextReranker(model_name=reranker_model)

        # Cache keyed by (note_id, block_index) to reduce cursor jitter cost.
        self._cache_key: Optional[Tuple[str, int, str]] = None
        self._cache_value: List[ContextSnippetPayload] = []
        self._autobuild_dim: Optional[int] = None
        self._current_dim: Optional[int] = None
        self._window_embed_cache: Dict[Tuple[str, int, str], Tuple[np.ndarray, str]] = {}

    def _current_embedding_dim(self) -> int:
        if self._current_dim is not None:
            return self._current_dim
        self._current_dim = int(self.embedder.embedding_dim())
        return self._current_dim

    def index_note(self, record: NoteRecord) -> int:
        if record.kind != NoteKind.NOTE:
            return 0
        current_dim = self._current_embedding_dim()
        existing_dim = self.index.embedding_dim_guess()
        if existing_dim is not None and existing_dim != current_dim:
            print(f"ContextService: stale context index dim {existing_dim} != {current_dim}; clearing")
            self.index.clear()

        cleaned = record.content
        cleaned = cleaned.replace("\n\n<!-- grimoire-chunk -->\n\n", "\n\n")
        cleaned = cleaned.replace("<!-- grimoire-chunk -->", "")
        cleaned = cleaned.replace("\r\n", "\n").replace("\r", "\n")
        if not cleaned.strip():
            self.index.delete_notes([record.id])
            return 0

        blocks = split_blocks(cleaned)
        metas: List[Dict] = []
        for idx, block in enumerate(blocks):
            if not block.text.strip():
                continue
            chunk_id = f"{record.id}:{block.start}:{block.end}:{idx}"
            dense = self.embedder.encode_dense(block.text)
            concepts = extract_concept_candidates(block.text)
            concept_ids: List[str] = []
            concept_labels: Dict[str, str] = {}
            for label in concepts:
                norm = _normalize_concept_label(label)
                if not norm:
                    continue
                concept_ids.append(norm)
                concept_labels.setdefault(norm, label)

            metas.append(
                {
                    "note_id": record.id,
                    "chunk_id": chunk_id,
                    "start": block.start,
                    "end": block.end,
                    "text": block.text,
                    "dense": dense.tolist(),
                    # Lexical retrieval is handled via BM25 built from chunk text.
                    # Keep the legacy field for backwards compatibility with older metadata.
                    "sparse": {},
                    "concepts": sorted(set(concept_ids)),
                    "concept_labels": concept_labels,
                }
            )

        self.index.update_note(record.id, metas)
        return len(metas)

    def delete_notes(self, note_ids: Iterable[str]):
        self.index.delete_notes(note_ids)

    def rebuild(self, records: Iterable[NoteRecord]) -> int:
        self.index.clear()
        processed = 0
        for record in records:
            if record.kind != NoteKind.NOTE:
                continue
            if not record.content.strip():
                continue
            self.index_note(record)
            processed += 1
        return processed

    def ensure_built(self, records: Iterable[NoteRecord]) -> bool:
        """Ensure the context index has data.

        This is a lazy bootstrap so existing note corpora work immediately
        without requiring each note to be re-saved after upgrades.
        """
        current_dim = self._current_embedding_dim()
        existing_dim = self.index.embedding_dim_guess()

        if self.index.chunk_count() > 0 and (existing_dim is None or existing_dim == current_dim):
            return True

        if self.index.chunk_count() > 0 and existing_dim is not None and existing_dim != current_dim:
            print(f"ContextService: rebuilding context index due to dim change {existing_dim}->{current_dim}")
            self.index.clear()

        if self._autobuild_dim == current_dim:
            return self.index.chunk_count() > 0
        self._autobuild_dim = current_dim
        try:
            self.rebuild(records)
        except Exception as exc:
            print(f"ContextService: autobuild failed: {exc}")
            return False
        return self.index.chunk_count() > 0

    def warmup(self, records: Iterable[NoteRecord], force_rebuild: bool = False) -> WarmupResponsePayload:
        self.embedder._load()
        if self.embedder._model is None:
            raise RuntimeError(
                f"Warmup failed: embedder model is unavailable: {self.embedder.model_name}. "
                "Ensure sentence-transformers is installed and the model is present in the local HF cache."
            )
        self._current_embedding_dim()
        if force_rebuild:
            self.rebuild(records)
        else:
            self.ensure_built(records)
        if self.reranker.enabled:
            self.reranker._load()
            if self.reranker._model is None:
                # Don't fail the entire app startup if only the optional reranker is missing.
                # The system remains fully local and deterministic without it.
                self.reranker.enabled = False
        # Ensure FAISS/BM25/prefix caches are ready for realtime queries.
        try:
            self.index._ensure_bm25()
        except Exception as exc:
            print(f"ContextService: BM25 warmup skipped: {exc}")
        try:
            self.index._rebuild_faiss()
        except Exception as exc:
            print(f"ContextService: FAISS warmup skipped: {exc}")
        try:
            self.index._rebuild_note_prefix_cache()
        except Exception as exc:
            print(f"ContextService: prefix-cache warmup skipped: {exc}")
        return WarmupResponsePayload(
            success=True,
            embedder_model=self.embedder.model_name,
            reranker_enabled=bool(self.reranker.enabled and self.reranker._model is not None),
            reranker_model=self.reranker.model_name if self.reranker.enabled else None,
            context_index_chunks=self.index.chunk_count(),
        )

    def _indexed_block_meta(self, note_id: str, block: Block, idx: int) -> Optional[Dict]:
        if not note_id:
            return None
        chunk_id = f"{note_id}:{block.start}:{block.end}:{idx}"
        meta = self.index.get_chunk(chunk_id)
        if not meta:
            return None
        if str(meta.get("note_id") or "") != note_id:
            return None
        # Only reuse embeddings if the block text matches the indexed block exactly.
        # This keeps edits consistent without forcing a reindex on every keystroke.
        indexed_text = str(meta.get("text") or "").strip()
        if indexed_text != block.text.strip():
            return None
        return meta

    def _combine_sparse(self, sparse_dicts: Sequence[Dict[str, float]], max_terms: int = 64) -> Dict[str, float]:
        merged: Dict[str, float] = {}
        for sd in sparse_dicts:
            for token, weight in (sd or {}).items():
                merged[token] = merged.get(token, 0.0) + float(weight)
        items = sorted(merged.items(), key=lambda kv: (-kv[1], kv[0]))[:max_terms]
        return {k: float(v) for k, v in items}

    def _clip_tokens_around_cursor(self, text: str, cursor_char: int, max_tokens: int = 450) -> str:
        tokens = re.findall(r"\S+", text)
        if len(tokens) <= max_tokens:
            return text
        # Approximate cursor token index by counting tokens in prefix substring.
        cursor_char = max(0, min(cursor_char, len(text)))
        prefix = text[:cursor_char]
        prefix_tokens = re.findall(r"\S+", prefix)
        cursor_tok = min(len(tokens), len(prefix_tokens))
        half = max_tokens // 2
        start = max(0, cursor_tok - half)
        end = min(len(tokens), start + max_tokens)
        start = max(0, end - max_tokens)
        clipped = " ".join(tokens[start:end])
        return clipped

    def _compute_window_embeddings(
        self,
        note_id: str,
        blocks: List[Block],
        start_i: int,
        end_i: int,
        window_text: str,
    ) -> Tuple[np.ndarray, Dict[str, float]]:
        # Fast-path: if the note text matches the indexed block exactly, reuse its chunk vector.
        if start_i + 1 == end_i and start_i >= 0 and start_i < len(blocks):
            meta = self._indexed_block_meta(note_id, blocks[start_i], start_i)
            if meta:
                vec = _normalize_dense(meta.get("dense") or [])
                return vec, {}

        # Fallback: encode dynamically (e.g., unsaved edits). Cache per paragraph hash.
        w_hash = hashlib.sha1(window_text.encode("utf-8")).hexdigest()[:12]
        key = (note_id, start_i, w_hash)
        cached = self._window_embed_cache.get(key)
        if cached is not None:
            return cached[0], {}
        vec = self.embedder.encode_dense(window_text)
        self._window_embed_cache[key] = (vec, window_text)
        return vec, {}

    def _compute_prefix_embedding(
        self,
        note_id: str,
        blocks: List[Block],
        block_index: int,
        prefix_tail: str,
    ) -> Optional[np.ndarray]:
        if block_index <= 0:
            return None

        # Cached/incremental prefix embedding from indexed blocks (full prefix).
        try:
            prefix_vec = self.index.prefix_embedding(note_id, block_index)
            if prefix_vec is not None:
                return prefix_vec
        except Exception:
            pass

        # Fallback: avoid expensive long-prefix encoding; only use a short tail.
        tail = prefix_tail[-800:]
        if not tail.strip():
            return None
        return self.embedder.encode_dense(tail)

    def _compute_suffix_embedding(
        self,
        note_id: str,
        blocks: List[Block],
        block_index: int,
        suffix_text: str,
    ) -> Optional[np.ndarray]:
        if block_index + 1 >= len(blocks):
            return None
        meta = self._indexed_block_meta(note_id, blocks[block_index + 1], block_index + 1)
        if meta:
            vec = _normalize_dense(meta.get("dense") or [])
            return vec if vec.size > 0 else None
        if not suffix_text.strip():
            return None
        return self.embedder.encode_dense(suffix_text[:600])

    def _apply_reranker(
        self, window: str, scored: List[Tuple[str, float, Dict]]
    ) -> List[Tuple[str, float, Dict]]:
        if not scored:
            return scored
        if not self.reranker.enabled:
            return scored

        try:
            top_k = int(os.environ.get("GRIMOIRE_RERANK_TOP_K", "50"))
        except Exception:
            top_k = 50
        try:
            weight = float(os.environ.get("GRIMOIRE_RERANK_WEIGHT", "0.35"))
        except Exception:
            weight = 0.35

        if top_k <= 0 or weight <= 0:
            return scored

        top = scored[: min(top_k, len(scored))]
        doc_ids: List[str] = []
        docs: List[str] = []
        for cid, _, _ in top:
            meta = self.index.get_chunk(cid)
            text = (meta or {}).get("text") if meta else None
            if text:
                doc_ids.append(cid)
                docs.append(str(text))

        rerank_scores = self.reranker.score(window, docs)
        if rerank_scores is None or len(rerank_scores) != len(doc_ids):
            return scored

        raw_by_id: Dict[str, float] = {cid: float(s) for cid, s in zip(doc_ids, rerank_scores)}
        raw_vals = list(raw_by_id.values())
        lo = min(raw_vals) if raw_vals else 0.0
        hi = max(raw_vals) if raw_vals else 0.0
        denom = (hi - lo) if (hi - lo) > 1e-9 else None

        def norm(v: float) -> float:
            if denom is None:
                return 0.0
            return float((v - lo) / denom)

        reranked: List[Tuple[str, float, Dict]] = []
        for cid, base, debug in scored:
            combined = float(base)
            if cid in raw_by_id:
                raw = raw_by_id[cid]
                n = norm(raw)
                combined = float(base) + weight * n
                debug = dict(debug)
                debug["reranker_raw"] = raw
                debug["reranker_norm"] = n
            debug = dict(debug)
            debug["combined"] = combined
            reranked.append((cid, combined, debug))

        reranked.sort(key=lambda t: (-t[1], t[0]))
        return reranked

    def context(self, request: ContextRequest) -> List[ContextSnippetPayload]:
        text = _clean_text(request.text or "")
        cursor = int(request.cursor_offset)
        cursor = max(0, min(cursor, len(text)))
        blocks = split_blocks(text)

        block_index = 0
        for i, block in enumerate(blocks):
            if block.start <= cursor <= block.end:
                block_index = i
                break
            if cursor > block.end:
                block_index = i

        # Cache at paragraph-level, invalidated when paragraph text changes.
        current_block = blocks[block_index]
        block_hash = hashlib.sha1((current_block.text or "").encode("utf-8")).hexdigest()[:12]
        cache_key = (request.note_id, block_index, block_hash)
        if self._cache_key == cache_key:
            return self._cache_value[: request.limit]

        prefix = text[:cursor]
        prefix_tail = prefix[-2500:]

        # Step 1: W = current paragraph (clip to <= 450 tokens).
        window_raw = current_block.text.strip()
        if not window_raw:
            self._cache_key = cache_key
            self._cache_value = []
            return []

        local_cursor = max(0, min(cursor - current_block.start, len(window_raw)))
        window = self._clip_tokens_around_cursor(window_raw, local_cursor, max_tokens=450).strip()

        # Step 2: embed W (cached).
        window_vec, _ = self._compute_window_embeddings(
            request.note_id,
            blocks,
            block_index,
            block_index + 1,
            window,
        )
        existing_dim = self.index.embedding_dim_guess()
        if existing_dim is not None and existing_dim != int(window_vec.shape[0]):
            self._cache_key = cache_key
            self._cache_value = []
            return []

        # Step 4: prefix penalty uses cached/incremental e(P) when available.
        prefix_vec = self._compute_prefix_embedding(request.note_id, blocks, block_index, prefix_tail)

        # Step 3: concepts in W.
        active_labels = extract_concept_candidates(window)
        active: List[Tuple[str, str]] = []
        for label in active_labels:
            norm = _normalize_concept_label(label)
            if norm:
                active.append((norm, label))

        # Grounding and gaps (reader-state).
        grounded: Set[str] = set()
        gaps: Set[str] = set()
        for concept_id, label in active:
            count = _count_occurrences(prefix, label)
            if count >= 2:
                grounded.add(concept_id)
                continue
            centroid = self.index.concept_centroid(concept_id)
            if centroid is not None and prefix_vec is not None:
                tau = float(os.environ.get("GRIMOIRE_GROUNDED_TAU", "0.35"))
                if _dot(prefix_vec, centroid) >= tau:
                    grounded.add(concept_id)
                    continue
            gaps.add(concept_id)

        # Step 3: candidate retrieval union.
        dense_top_n = int(os.environ.get("GRIMOIRE_DENSE_TOP_N", "200"))
        bm25_top_n = int(os.environ.get("GRIMOIRE_BM25_TOP_N", "200"))

        candidate_ids: Set[str] = set()
        concept_ids_in_w = sorted({cid for cid, _ in active})
        candidate_ids |= self.index.chunks_for_concepts(concept_ids_in_w, exclude_note_id=request.note_id)
        candidate_ids |= self.index.chunks_for_concepts(sorted(gaps), exclude_note_id=request.note_id)

        for cid, _ in self.index.dense_search(window_vec, exclude_note_id=request.note_id, top_k=dense_top_n):
            candidate_ids.add(cid)
            if len(candidate_ids) >= 800:
                break

        for cid, _ in self.index.bm25_search(window, exclude_note_id=request.note_id, top_k=bm25_top_n):
            candidate_ids.add(cid)
            if len(candidate_ids) >= 800:
                break

        # Step 4/5: cheap scoring + cap.
        beta = float(os.environ.get("GRIMOIRE_GAP_BETA", "0.55"))
        lambd = float(os.environ.get("GRIMOIRE_PREFIX_LAMBDA", "0.35"))
        mention_bonus = float(os.environ.get("GRIMOIRE_GAP_MENTION_BONUS", "0.12"))
        max_candidates = int(os.environ.get("GRIMOIRE_MAX_CANDIDATES", "500"))
        mu = float(os.environ.get("GRIMOIRE_MMR_MU", "0.35"))
        coverage_weight = float(os.environ.get("GRIMOIRE_COVERAGE_WEIGHT", "0.08"))

        scored: List[Tuple[str, float, Dict]] = []
        gap_list = sorted(gaps)
        for cid in sorted(candidate_ids):
            meta = self.index.get_chunk(cid)
            if not meta:
                continue
            vec = _normalize_dense(meta.get("dense") or [])
            if vec.size == 0 or int(vec.shape[0]) != int(window_vec.shape[0]):
                continue
            rel = _dot(vec, window_vec)

            gap_support = 0.0
            gap_best: Optional[str] = None
            mentions_gap = False
            meta_concepts = set(meta.get("concepts", []) or [])
            for gap_id in gap_list:
                if gap_id in meta_concepts:
                    mentions_gap = True
                centroid = self.index.concept_centroid(gap_id)
                if centroid is None:
                    continue
                val = _dot(vec, centroid)
                if val > gap_support:
                    gap_support = val
                    gap_best = gap_id

            redundancy = _dot(vec, prefix_vec) if prefix_vec is not None else 0.0
            base = rel - lambd * redundancy + beta * gap_support + (mention_bonus if mentions_gap else 0.0)
            debug = {
                "relevance": rel,
                "gap_support": gap_support,
                "redundancy": redundancy,
                "base": base,
                "gap_concept_id": gap_best,
                "mentions_gap": mentions_gap,
            }
            scored.append((cid, base, debug))

        scored.sort(key=lambda t: (-t[1], t[0]))
        if len(scored) > max_candidates:
            scored = scored[:max_candidates]

        # Step 6: rerank top-K (handled inside apply_reranker).
        scored = self._apply_reranker(window, scored)

        # Step 7: pick 5-7 with MMR + per-gap coverage.
        score_temp = float(os.environ.get("GRIMOIRE_CONTEXT_SCORE_TEMP", "2.0"))
        score_bias = float(os.environ.get("GRIMOIRE_CONTEXT_SCORE_BIAS", "0.0"))

        selected: List[ContextSnippetPayload] = []
        selected_vecs: List[np.ndarray] = []
        remaining = scored
        covered_gaps: Set[str] = set()

        while remaining and len(selected) < request.limit:
            best_idx = 0
            best_score = None
            for idx, (cid, base, debug) in enumerate(remaining[:250]):
                meta = self.index.get_chunk(cid)
                if not meta:
                    continue
                vec = _normalize_dense(meta.get("dense") or [])
                max_red = 0.0
                for svec in selected_vecs:
                    max_red = max(max_red, _dot(vec, svec))
                combined = float(debug.get("combined", base))
                candidate_concepts = set(meta.get("concepts", []) or [])
                newly_covered = len((candidate_concepts & gaps) - covered_gaps)
                cover_bonus = coverage_weight * float(newly_covered)
                mmr = combined + cover_bonus - mu * max_red
                if best_score is None or mmr > best_score:
                    best_score = mmr
                    best_idx = idx

            cid, base, debug = remaining.pop(best_idx)
            meta = self.index.get_chunk(cid)
            if not meta:
                continue

            vec = _normalize_dense(meta.get("dense") or [])
            selected_vecs.append(vec)
            covered_gaps |= (set(meta.get("concepts", []) or []) & gaps)

            concept_title = None
            gap_best = debug.get("gap_concept_id")
            if gap_best:
                concept_title = self.index.concept_label(gap_best) or gap_best

            # UI score should match the list ordering. Use the combined (cheap+rerank) score,
            # then normalize across the final selected set.
            raw_score = float(debug.get("combined", base))

            snippet = ContextSnippetPayload(
                note_id=meta["note_id"],
                chunk_id=meta["chunk_id"],
                text=_sentences_excerpt(meta.get("text") or ""),
                # Display score should reflect "how good" the item is for this cursor context,
                # without normalizing relative to the other returned items.
                score=float(
                    max(
                        0.0,
                        min(
                            1.0,
                            _sigmoid(score_temp * (raw_score - score_bias)),
                        ),
                    )
                ),
                concept=concept_title,
                debug=debug if request.include_debug else None,
            )
            selected.append(snippet)

        self._cache_key = cache_key
        self._cache_value = selected
        return selected
