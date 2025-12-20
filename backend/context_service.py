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
from models import NoteKind, NoteRecord


def _resolve_hf_snapshot(model_name_or_path: str) -> str:
    """Resolve a HF model id to a local snapshot path (no network).

    If the model is not present locally, this raises.
    """
    name = (model_name_or_path or "").strip()
    if not name:
        raise ValueError("Model name is empty.")
    if os.path.exists(name):
        return name
    try:
        from huggingface_hub import snapshot_download  # type: ignore
    except Exception as exc:
        raise RuntimeError(f"huggingface_hub is required to load '{name}': {exc}") from exc
    try:
        return snapshot_download(repo_id=name, local_files_only=True)
    except Exception as exc:
        raise RuntimeError(
            f"Model '{name}' is not available in the local HF cache. "
            "Download it (with network access) before running."
        ) from exc


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


def _min_max_normalize(scores: Dict[str, float]) -> Dict[str, float]:
    if not scores:
        return {}
    values = list(scores.values())
    lo = min(values)
    hi = max(values)
    denom = hi - lo
    if denom <= 1e-9:
        return {k: 0.0 for k in scores}
    return {k: (v - lo) / denom for k, v in scores.items()}


def _stable_int_id(text: str) -> int:
    """Legacy deterministic id helper.

    Note: FAISS expects signed int64 ids. This helper now returns a signed int64
    value (and avoids -1), but ContextIndex prefers a persisted sequential id
    mapping to avoid collisions and overflow across upgrades.
    """
    digest = hashlib.sha1(text.encode("utf-8")).digest()[:8]
    value = int.from_bytes(digest, byteorder="big", signed=True)
    return -2 if value == -1 else value


def _chunk_block_index(chunk_id: str) -> Optional[int]:
    if not chunk_id:
        return None
    try:
        return int(str(chunk_id).rsplit(":", 1)[-1])
    except Exception:
        return None


def _clean_text(text: str) -> str:
    return text.replace("\r\n", "\n").replace("\r", "\n")


_BLANK_SPLIT_RE = re.compile(r"\n[ \t]*\n+")

_CHUNK_MARKER = "<!-- grimoire-chunk -->"
_CHUNK_MARKER_BLOCK = "\n\n<!-- grimoire-chunk -->\n\n"


def _normalize_note_text_and_cursor(text: str, cursor: int) -> Tuple[str, int]:
    """Apply the same chunk-marker normalization as indexing, with cursor remapping."""
    text = _clean_text(text or "")
    cursor = int(cursor)
    cursor = max(0, min(cursor, len(text)))

    out: List[str] = []
    out_len = 0
    cursor_out: Optional[int] = None

    i = 0
    while i < len(text):
        if cursor_out is None and i == cursor:
            cursor_out = out_len

        if text.startswith(_CHUNK_MARKER_BLOCK, i):
            end = i + len(_CHUNK_MARKER_BLOCK)
            if cursor_out is None and i <= cursor < end:
                # Keep the leading double-newline and drop the marker.
                cursor_out = out_len + min(cursor - i, 2)
            out.append("\n\n")
            out_len += 2
            i = end
            continue

        if text.startswith(_CHUNK_MARKER, i):
            end = i + len(_CHUNK_MARKER)
            if cursor_out is None and i <= cursor < end:
                cursor_out = out_len
            i = end
            continue

        ch = text[i]
        out.append(ch)
        out_len += 1
        i += 1

    if cursor_out is None:
        cursor_out = out_len

    return "".join(out), int(cursor_out)


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


def chunk_blocks(text: str) -> List[Block]:
    """Chunk markdown into higher-quality, section-aware blocks.

    This merges small heading/list blocks into larger semantic chunks to avoid
    low-value "just a header" or tiny list fragments dominating retrieval.
    """
    full_text = text
    base = split_blocks(full_text)
    if not base:
        return [Block(start=0, end=0, text="")]

    try:
        max_chars = int(os.environ.get("GRIMOIRE_CONTEXT_CHUNK_MAX_CHARS", "1600"))
    except Exception:
        max_chars = 1600
    max_chars = max(400, max_chars)

    def heading_level(block_text: str) -> Optional[int]:
        line = (block_text or "").lstrip().splitlines()[0] if (block_text or "").strip() else ""
        if not line.startswith("#"):
            return None
        return len(line) - len(line.lstrip("#"))

    def is_labelish(block_text: str) -> bool:
        lines = [ln.strip() for ln in (block_text or "").splitlines() if ln.strip()]
        if not lines:
            return False
        first = lines[0].strip()
        lowered = first.lower()
        if lowered.startswith("example:") or lowered.startswith("important:"):
            return True
        if first.endswith(":") and len(lines) <= 2:
            return True
        return False

    def is_listy(block_text: str) -> bool:
        lines = [ln.strip() for ln in (block_text or "").splitlines() if ln.strip()]
        if not lines:
            return False
        list_lines = sum(1 for ln in lines if _LIST_LINE_RE.match(ln))
        return (list_lines >= 2) or (list_lines == len(lines) and len(lines) >= 1)

    merged: List[Block] = []
    i = 0
    while i < len(base):
        block = base[i]
        if not (block.text or "").strip():
            i += 1
            continue

        level = heading_level(block.text)
        # Do not let top-level headings consume the entire note.
        if level is not None and level >= 2:
            start = block.start
            end = block.end
            j = i + 1
            while j < len(base):
                nxt = base[j]
                if not (nxt.text or "").strip():
                    j += 1
                    continue
                nxt_level = heading_level(nxt.text)
                if nxt_level is not None and nxt_level <= level:
                    break
                candidate_text = full_text[start : nxt.end].strip()
                if len(candidate_text) > max_chars:
                    break
                end = nxt.end
                j += 1
            merged.append(Block(start=start, end=end, text=full_text[start:end].strip()))
            i = j
            continue

        if is_labelish(block.text) or is_listy(block.text):
            start = block.start
            end = block.end
            j = i + 1
            while j < len(base):
                nxt = base[j]
                if not (nxt.text or "").strip():
                    j += 1
                    continue
                nxt_level = heading_level(nxt.text)
                if nxt_level is not None:
                    break
                if not (is_labelish(nxt.text) or is_listy(nxt.text)):
                    break
                candidate_text = full_text[start : nxt.end].strip()
                if len(candidate_text) > max_chars:
                    break
                end = nxt.end
                j += 1
            merged.append(Block(start=start, end=end, text=full_text[start:end].strip()))
            i = j
            continue

        merged.append(block)
        i += 1

    return merged or [Block(start=0, end=0, text="")]


_HEADING_RE = re.compile(r"(?m)^[ \t]{0,3}#{1,6}[ \t]+(.+?)\s*$")
_HEADING_ONLY_RE = re.compile(r"(?m)^[ \t]{0,3}#{1,6}[ \t]+(.+?)\s*$")
_CAP_PHRASE_RE = re.compile(r"\b(?:[A-Z][A-Za-z0-9'_-]*)(?:\s+[A-Z][A-Za-z0-9'_-]*){0,4}\b")
_LIST_LINE_RE = re.compile(r"^\s*(?:[-*+]\s+|\d+[.)]\s+)")


def _normalize_concept_label(label: str) -> str:
    label = label.strip()
    label = re.sub(r"`+", "", label)
    label = re.sub(r"[^\w\s-]", "", label)
    label = re.sub(r"\s+", " ", label)
    return label.lower().strip()


def extract_concept_candidates(text: str, *, min_single_occurrences: int = 1) -> List[str]:
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
        if norm in _CONCEPT_STOPLIST:
            continue
        parts = [p for p in norm.split() if p]
        if not parts:
            continue
        if min_single_occurrences > 1 and len(parts) == 1:
            if _count_occurrences(text, item) < int(min_single_occurrences):
                continue
        if len(parts) == 1 and parts[0] in _CAP_STOPWORDS:
            continue
        if all(part in _INFO_STOPWORDS or part in _CAP_STOPWORDS for part in parts):
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


def _is_heading_only(text: str) -> bool:
    stripped = (text or "").strip()
    if not stripped:
        return False
    if _HEADING_ONLY_RE.fullmatch(stripped) is None:
        return False
    tokens = _SparseTokenizer.tokenize(stripped)
    return len(tokens) <= 6


def _sentences_excerpt(text: str, max_sentences: int = 3, max_chars: int = 600) -> str:
    text = text.strip()
    if not text:
        return ""
    # Simple sentence splitter; deterministic and local.
    parts = re.split(r"(?<=[.!?])\s+", text)
    parts = [p.strip() for p in parts if p.strip()]
    # If the first "sentence" is just an ordered-list marker like "4.", merge it.
    if len(parts) >= 2 and re.fullmatch(r"\d+[.)]?", parts[0].strip()):
        parts[1] = f"{parts[0]} {parts[1]}".strip()
        parts = parts[1:]
    excerpt = " ".join(parts[:max_sentences]).strip()
    if len(excerpt) > max_chars:
        excerpt = excerpt[:max_chars].rstrip()
    return excerpt


def _query_aware_excerpt(
    text: str,
    query_lex_tokens: Set[str],
    *,
    max_units: int = 3,
    max_chars: int = 600,
    cursor_char: Optional[int] = None,
    avoid_radius: int = 0,
    hard_avoid: bool = False,
) -> str:
    text = (text or "").strip()
    if not text:
        return ""

    query_set = set(query_lex_tokens or set())

    units: List[Tuple[str, int]] = []
    pos = 0
    for raw_line in text.splitlines(True):
        stripped = raw_line.strip()
        if stripped:
            units.append((stripped, pos))
        pos += len(raw_line)

    if not units:
        return ""

    cursor = int(cursor_char) if cursor_char is not None else None
    avoid = max(0, int(avoid_radius))

    def is_tag_list_line(line: str) -> bool:
        if line.count(",") < 2:
            return False
        if re.search(r"[.!?]", line):
            return False
        tokens = _lexical_tokens(line)
        if len(tokens) > 12:
            return False
        parts = [p.strip() for p in line.split(",") if p.strip()]
        if len(parts) < 3:
            return False
        for p in parts:
            pt = _lexical_tokens(p)
            if not (1 <= len(pt) <= 4):
                return False
        return True

    def unit_score(unit: str, start: int) -> float:
        if _is_low_information_text(unit):
            return -1.0
        # Avoid "tag list" / header-list lines like "A, B, C, D".
        if is_tag_list_line(unit):
            return -1.0
        tokens = set(_lexical_tokens(unit))
        overlap = len(tokens & query_set) if query_set else 0
        q = _chunk_quality_score(unit)
        # Prefer lexical overlap; only fall back to intrinsic quality when no overlap exists.
        if query_set and overlap == 0:
            score = 0.05 * float(q)
        else:
            precision = float(overlap) / float(max(1, len(tokens))) if tokens else 0.0
            recall = float(overlap) / float(max(1, len(query_set))) if query_set else 0.0
            overlap_score = 0.7 * precision + 0.3 * recall
            score = 0.8 * overlap_score + 0.2 * float(q)
        if cursor is not None and avoid > 0:
            dist = abs(int(start) - int(cursor))
            if hard_avoid and dist < avoid:
                return -1.0
            away = float(min(1.0, float(dist) / float(avoid)))
            score *= 0.05 + 0.95 * away
        return score

    scored = [(i, unit_score(u, start), u) for i, (u, start) in enumerate(units)]
    scored.sort(key=lambda t: (-t[1], -len(_lexical_tokens(t[2])), t[0]))
    best_score = scored[0][1]
    # Prefer earlier units when multiple candidates are similarly good.
    tie_margin = float(os.environ.get("GRIMOIRE_EXCERPT_TIE_MARGIN", "0.04"))
    best_i = min(i for i, s, _ in scored if s >= best_score - tie_margin)

    chosen: List[str] = []
    best_unit = units[best_i][0].strip()

    def is_list_line(line: str) -> bool:
        return bool(_LIST_LINE_RE.match(line))

    # If the best unit is part of a list (or a list lead-in), include adjacent list items even
    # when they don't share lexical tokens with the cursor window. Otherwise, we often surface
    # a single bullet (low value) instead of a coherent multi-bullet excerpt.
    list_mode = False
    list_start = best_i
    list_end = best_i
    lead_in: Optional[str] = None
    if is_list_line(best_unit):
        list_mode = True
        while list_start - 1 >= 0 and is_list_line(units[list_start - 1][0]):
            list_start -= 1
        while list_end + 1 < len(units) and is_list_line(units[list_end + 1][0]):
            list_end += 1
        maybe_lead_i = list_start - 1
        if maybe_lead_i >= 0:
            maybe_lead = units[maybe_lead_i][0].strip()
            if (
                maybe_lead
                and not _is_low_information_text(maybe_lead)
                and not is_tag_list_line(maybe_lead)
                and not is_list_line(maybe_lead)
                and maybe_lead.endswith(":")
            ):
                lead_in = maybe_lead
    else:
        # Lead-in line directly followed by a list.
        if best_unit.endswith(":") and best_i + 1 < len(units) and is_list_line(units[best_i + 1][0]):
            list_mode = True
            lead_in = best_unit
            list_start = best_i + 1
            list_end = list_start
            while list_end + 1 < len(units) and is_list_line(units[list_end + 1][0]):
                list_end += 1

    if list_mode:
        if lead_in:
            chosen.append(lead_in)
        # Prefer forward list items for readability.
        for i in range(best_i if is_list_line(best_unit) else list_start, list_end + 1):
            unit = units[i][0].strip()
            if not unit:
                continue
            if _is_low_information_text(unit):
                continue
            if is_tag_list_line(unit):
                continue
            chosen.append(unit)
            if len(chosen) >= max_units:
                break
        # If we still have room, backfill earlier list items to complete the list excerpt.
        if len(chosen) < max_units and is_list_line(best_unit):
            for i in range(best_i - 1, list_start - 1, -1):
                unit = units[i][0].strip()
                if not unit:
                    continue
                if _is_low_information_text(unit):
                    continue
                if is_tag_list_line(unit):
                    continue
                chosen.insert(1 if lead_in else 0, unit)
                if len(chosen) >= max_units:
                    break
    else:
        best_is_heading = best_unit.lstrip().startswith("#")
        neighbor_min_quality = 0.55 if best_is_heading else 0.75
        for i in range(max(0, best_i - 1), min(len(units), best_i + 2)):
            unit = units[i][0].strip()
            if not unit:
                continue
            if _is_low_information_text(unit):
                continue
            if is_tag_list_line(unit):
                continue
            # Keep neighbors only if they add signal or are intrinsically strong.
            tokens = set(_lexical_tokens(unit))
            overlap = len(tokens & query_set) if query_set else 0
            if (
                i != best_i
                and query_set
                and overlap == 0
                and not is_list_line(unit)
                and _chunk_quality_score(unit) < neighbor_min_quality
            ):
                continue
            chosen.append(unit)
            if len(chosen) >= max_units:
                break

    excerpt = " ".join(chosen).strip()
    if len(excerpt) > max_chars:
        excerpt = excerpt[:max_chars].rstrip()
    return excerpt


def _excerpt_key(text: str) -> str:
    """Normalize excerpts for de-duplication in the UI selection step."""
    text = text.strip().lower()
    text = re.sub(r"\s+", " ", text)
    return text[:400]


_INFO_STOPWORDS: Set[str] = {
    "a",
    "an",
    "and",
    "are",
    "as",
    "at",
    "be",
    "but",
    "by",
    "for",
    "from",
    "has",
    "have",
    "if",
    "in",
    "into",
    "is",
    "it",
    "its",
    "of",
    "on",
    "or",
    "that",
    "the",
    "their",
    "then",
    "there",
    "these",
    "this",
    "to",
    "was",
    "were",
    "with",
}

_CONCEPT_STOPLIST: Set[str] = {
    "articles",
    "article",
    "background",
    "description",
    "glossary",
    "key point",
    "key points",
    "key operations",
    "location",
    "notes",
    "note",
    "open questions",
    "overview",
    "purpose",
    "rivalries",
    "summary",
    "trade and politics",
}

_CAP_STOPWORDS: Set[str] = {
    "a",
    "an",
    "any",
    "all",
    "each",
    "every",
    "here",
    "his",
    "her",
    "its",
    "my",
    "no",
    "none",
    "our",
    "some",
    "that",
    "the",
    "their",
    "them",
    "these",
    "they",
    "this",
    "those",
    "there",
    "your",
}


def _is_low_information_text(text: str) -> bool:
    """True for snippets unlikely to provide useful context."""
    raw = (text or "").strip()
    if not raw:
        return True

    # Markdown-ish markers / punctuation-only / digits-only.
    if re.fullmatch(r"[#>*_\-\s\[\]\(\)`~\.\,\:\;\!\?0-9]+", raw):
        return True

    lowered = raw.lower().strip()
    if lowered in {
        "key points",
        "key points.",
        "key point",
        "key point.",
        "summary",
        "summary.",
        "notes",
        "notes.",
        "todo",
        "todo.",
    }:
        return True

    alpha_chars = sum(1 for ch in raw if ch.isalpha())
    if alpha_chars < int(os.environ.get("GRIMOIRE_MIN_SNIPPET_ALPHA", "8")):
        return True

    tokens = re.findall(r"[A-Za-z][A-Za-z']*", raw)
    if len(tokens) < int(os.environ.get("GRIMOIRE_MIN_SNIPPET_TOKENS", "3")):
        return True

    content = [t.lower() for t in tokens if len(t) >= 3 and t.lower() not in _INFO_STOPWORDS]
    if len(content) < int(os.environ.get("GRIMOIRE_MIN_SNIPPET_CONTENT_TOKENS", "2")):
        return True

    return False


class _SparseTokenizer:
    @staticmethod
    def tokenize(text: str) -> List[str]:
        text = text.lower()
        return re.findall(r"[a-z0-9_'-]{2,}", text)


def _lexical_tokens(text: str) -> List[str]:
    tokens = _SparseTokenizer.tokenize(text)
    if not tokens:
        return []
    out = []
    for token in tokens:
        if len(token) < 3:
            continue
        if token in _INFO_STOPWORDS:
            continue
        out.append(token)
    return out


_CAP_ANCHOR_RE = re.compile(r"\b[A-Z][A-Za-z0-9'_-]{3,}\b")


def _strong_capitalized_anchors(text: str) -> Set[str]:
    """Extract "topic anchor" tokens from a cursor window (proper-noun-ish capitalized words)."""
    anchors: Set[str] = set()
    raw = text or ""
    for m in _CAP_ANCHOR_RE.finditer(raw):
        token = (m.group(0) or "").strip()
        if not token:
            continue
        lowered = token.lower()
        if lowered in _INFO_STOPWORDS or lowered in _CAP_STOPWORDS:
            continue
        # Skip tokens that are almost certainly sentence-initial function words ("When", "This", ...).
        start = int(m.start())
        j = start - 1
        while j >= 0 and raw[j] in " \t\r\n\"'“”‘’([{<*-#>":
            j -= 1
        if j >= 0 and raw[j] in ".!?":
            continue
        anchors.add(token)
    return anchors


def _chunk_quality_score(text: str) -> float:
    raw = (text or "").strip()
    if not raw:
        return 0.0
    if _is_heading_only(raw):
        return 0.05
    if _is_low_information_text(raw):
        return 0.05

    tokens = _lexical_tokens(raw)
    token_count = len(tokens)
    if token_count == 0:
        return 0.1
    unique_ratio = float(len(set(tokens))) / float(token_count)
    length_score = min(1.0, token_count / 50.0)

    sentences = [s for s in re.split(r"(?<=[.!?])\s+", raw) if s.strip()]
    sentence_score = min(1.0, len(sentences) / 3.0) if sentences else 0.0

    lines = [line.strip() for line in raw.splitlines() if line.strip()]
    list_lines = sum(1 for line in lines if _LIST_LINE_RE.match(line))
    list_ratio = float(list_lines) / float(max(1, len(lines)))
    # Penalize list-heavy blocks, but avoid harshly penalizing a single long, descriptive
    # numbered/list sentence (common in worldbuilding outlines).
    if len(lines) == 1 and list_lines == 1 and token_count >= 16:
        list_penalty = 0.05
    else:
        list_penalty = 0.35 * list_ratio
        # If the block is long and content-dense, the fact that it's list-structured is
        # less indicative of "low value" than it is for tiny bullet fragments.
        if token_count > 0:
            list_penalty *= float(min(1.0, 22.0 / float(token_count)))
        # Multi-line lists with meaningful lead-in tend to be useful context.
        if list_lines >= 3 and token_count >= 16:
            list_penalty *= 0.6

    short_sentence_penalty = 0.0
    if sentences:
        avg_len = float(token_count) / float(max(1, len(sentences)))
        if avg_len < 8.0:
            short_sentence_penalty = 0.12

    if len(sentences) <= 1 and token_count < 18:
        length_score *= 0.6

    quality = 0.2 + 0.45 * length_score + 0.2 * unique_ratio + 0.15 * sentence_score
    quality -= list_penalty
    quality -= short_sentence_penalty

    if raw.lstrip().startswith("#") and token_count < 25:
        quality -= 0.15

    if len(sentences) == 1 and token_count < 20:
        quality -= 0.12
    elif len(sentences) == 1 and token_count < 30:
        quality -= 0.08

    comma_ratio = float(raw.count(",")) / float(max(1, token_count))
    if comma_ratio > 0.18 and len(sentences) <= 1:
        quality -= 0.12

    if any(line.endswith(":") for line in lines) and len(lines) <= 3 and token_count < 30:
        # A trailing-colon lead-in is often a useful definition/transition in outlines.
        if re.search(r"(?i)\\b(can|must|cannot|is|are|was|were|has|have)\\b", raw) and token_count >= 7:
            quality -= 0.04
        else:
            quality -= 0.12

    if token_count < 12:
        quality = min(quality, 0.45)
    return float(max(0.0, min(1.0, quality)))


class ContextEmbedder:
    """Dense embedder wrapper for realtime semantic context.

    Default model is BAAI/bge-small-en-v1.5 (fast enough for CPU realtime).
    """

    def __init__(self, model_name: str = "BAAI/bge-small-en-v1.5"):
        self.model_name = model_name
        self._model = None
        self._dim: Optional[int] = None

    def _configure_torch_threads(self):
        _configure_torch_threads()

    def _load(self):
        if self._model is not None:
            return
        try:
            from sentence_transformers import SentenceTransformer  # type: ignore
        except Exception as exc:
            raise RuntimeError(
                "ContextEmbedder requires sentence-transformers. "
                f"Install it and ensure model '{self.model_name}' is available. "
                f"Reason: {exc}"
            ) from exc

        self._configure_torch_threads()
        try:
            resolved = _resolve_hf_snapshot(self.model_name)
            self._model = SentenceTransformer(resolved)
        except Exception as exc:
            raise RuntimeError(
                f"ContextEmbedder failed to load model '{self.model_name}': {exc}"
            ) from exc

        try:
            self._dim = int(self._model.get_sentence_embedding_dimension())
        except Exception:
            vec = self._model.encode(
                ["dim probe"],
                convert_to_numpy=True,
                normalize_embeddings=True,
                show_progress_bar=False,
            )[0]
            self._dim = int(vec.shape[0])

    def encode_dense(self, text: str) -> np.ndarray:
        text = text.strip()
        self._load()
        if self._model is None:
            raise RuntimeError("ContextEmbedder model is unavailable.")
        if not text:
            return _normalize_dense([0.0] * self.embedding_dim())
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
        except Exception as exc:
            raise RuntimeError(f"ContextEmbedder encoding failed: {exc}") from exc

    def embedding_dim(self) -> int:
        self._load()
        if self._dim is None:
            raise RuntimeError("ContextEmbedder embedding dimension is unavailable.")
        return int(self._dim)


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
        except Exception as exc:
            raise RuntimeError(
                "ContextReranker requires FlagEmbedding. "
                f"Install it and ensure model '{self.model_name}' is available. "
                f"Reason: {exc}"
            ) from exc

        _configure_torch_threads()
        try:
            resolved = _resolve_hf_snapshot(self.model_name)
            self._model = FlagReranker(resolved, use_fp16=False)
        except Exception as exc:
            raise RuntimeError(
                f"ContextReranker failed to load model '{self.model_name}': {exc}"
            ) from exc

    def score(self, query: str, documents: List[str]) -> Optional[List[float]]:
        query = query.strip()
        if not self.enabled or not query or not documents:
            return None
        self._load()
        if self._model is None:
            raise RuntimeError("ContextReranker model is unavailable.")

        pairs = [(query, d) for d in documents]
        try:
            scores = self._model.compute_score(sentence_pairs=pairs)  # type: ignore[arg-type]
        except TypeError:
            scores = self._model.compute_score(pairs)  # type: ignore[misc]
        except Exception as exc:
            raise RuntimeError(f"ContextReranker scoring failed: {exc}") from exc

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
        if os.path.exists(self.metadata_path):
            with open(self.metadata_path, "r", encoding="utf-8") as f:
                payload = json.load(f)
            self._chunk = payload.get("chunks", {}) or {}
            self._chunk_int = payload.get("chunk_id_to_int", {}) or {}
            self._int_chunk = payload.get("int_to_chunk_id", {}) or {}
            self._concept_label = payload.get("concept_label", {}) or {}
            print(f"Loaded context index metadata: {len(self._chunk)} chunks")

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
        os.makedirs(os.path.dirname(self.metadata_path), exist_ok=True)
        payload = {
            "chunks": self._chunk,
            "chunk_id_to_int": self._chunk_int,
            "int_to_chunk_id": self._int_chunk,
            "concept_label": self._concept_label,
        }
        with open(self.metadata_path, "w", encoding="utf-8") as f:
            json.dump(payload, f)

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
        if os.path.exists(self.metadata_path):
            os.remove(self.metadata_path)
        if os.path.exists(self.faiss_path):
            os.remove(self.faiss_path)

    def _load_faiss(self):
        if not os.path.exists(self.faiss_path):
            return
        try:
            import faiss  # type: ignore
        except Exception as exc:
            raise RuntimeError(f"FAISS is required for semantic context: {exc}") from exc

        try:
            self._faiss_index = faiss.read_index(self.faiss_path)
            self._faiss_dirty = False
        except Exception as exc:
            raise RuntimeError(f"Failed to load FAISS context index: {exc}") from exc

    def _save_faiss(self):
        if self._faiss_index is None:
            return
        try:
            import faiss  # type: ignore
        except Exception as exc:
            raise RuntimeError(f"FAISS is required for semantic context: {exc}") from exc

        try:
            os.makedirs(os.path.dirname(self.faiss_path), exist_ok=True)
            faiss.write_index(self._faiss_index, self.faiss_path)
        except Exception as exc:
            raise RuntimeError(f"Failed to save FAISS context index: {exc}") from exc

    def _rebuild_faiss(self):
        try:
            import faiss  # type: ignore
        except Exception as exc:
            raise RuntimeError(f"FAISS is required for semantic context: {exc}") from exc

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

    def bm25_search(
        self, query: str, exclude_note_id: Optional[str] = None, top_k: int = 20
    ) -> List[Tuple[str, float]]:
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
                if not meta:
                    continue
                if exclude_note_id and meta.get("note_id") == exclude_note_id:
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

    def dense_search(
        self, query_vec: np.ndarray, exclude_note_id: Optional[str] = None, top_k: int = 20
    ) -> List[Tuple[str, float]]:
        query_vec = query_vec.astype(np.float32)
        results: List[Tuple[str, float]] = []

        # Prefer FAISS/HNSW when available.
        if self._faiss_dirty:
            self._rebuild_faiss()
        if self._faiss_index is None:
            if self._dense_matrix is None or self._dense_matrix.size == 0:
                return []
            raise RuntimeError(
                "FAISS context index is unavailable. Rebuild the semantic context index."
            )

        try:
            k = min(int(top_k) * 3, int(self._faiss_index.ntotal))  # type: ignore[attr-defined]
            if k <= 0:
                return []
            q = query_vec.reshape(1, -1).astype(np.float32)
            scores, ids = self._faiss_index.search(q, k)  # type: ignore[union-attr]
        except Exception as exc:
            raise RuntimeError(f"FAISS context search failed: {exc}") from exc

        for score, int_id in zip(scores[0].tolist(), ids[0].tolist()):
            if int_id == -1:
                continue
            chunk_id = self._int_chunk.get(str(int(int_id)))
            if not chunk_id:
                continue
            meta = self._chunk.get(chunk_id)
            if not meta:
                continue
            if exclude_note_id and meta.get("note_id") == exclude_note_id:
                continue
            results.append((chunk_id, float(score)))
            if len(results) >= top_k:
                break
        return results

    def sparse_search(
        self, query_sparse: Dict[str, float], exclude_note_id: Optional[str] = None, top_k: int = 20
    ) -> List[Tuple[str, float]]:
        if not query_sparse:
            return []
        scores: Dict[str, float] = {}
        for token, q_w in query_sparse.items():
            postings = self._sparse_postings.get(token)
            if not postings:
                continue
            for cid, c_w in postings.items():
                meta = self._chunk.get(cid)
                if not meta:
                    continue
                if exclude_note_id and meta.get("note_id") == exclude_note_id:
                    continue
                scores[cid] = scores.get(cid, 0.0) + float(q_w) * float(c_w)
        items = sorted(scores.items(), key=lambda kv: (-kv[1], kv[0]))
        return items[:top_k]

    def chunks_for_concepts(
        self, concept_ids: Iterable[str], exclude_note_id: Optional[str] = None
    ) -> Set[str]:
        out: Set[str] = set()
        for cid in concept_ids:
            for chunk_id in self._concept_chunks.get(cid, set()):
                meta = self._chunk.get(chunk_id)
                if not meta:
                    continue
                if exclude_note_id and meta.get("note_id") == exclude_note_id:
                    continue
                out.add(chunk_id)
        return out

    def concept_label(self, concept_id: str) -> Optional[str]:
        return self._concept_label.get(concept_id)

    def get_chunk(self, chunk_id: str) -> Optional[Dict]:
        return self._chunk.get(chunk_id)

    def chunk_count(self) -> int:
        return len(self._chunk)

    def chunk_ids(self) -> List[str]:
        return sorted(self._chunk.keys())

    def note_ids(self) -> List[str]:
        out: Set[str] = set()
        for meta in self._chunk.values():
            nid = str(meta.get("note_id") or "")
            if nid:
                out.add(nid)
        return sorted(out)

    def chunks_for_note(self, note_id: str) -> List[Dict]:
        nid = str(note_id or "")
        if not nid:
            return []
        chunks: List[Dict] = []
        for meta in self._chunk.values():
            if str(meta.get("note_id") or "") == nid:
                chunks.append(meta)
        # stable order by chunk_id
        chunks.sort(key=lambda m: str(m.get("chunk_id") or ""))
        return chunks

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

        blocks = chunk_blocks(cleaned)
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
                    "quality": _chunk_quality_score(block.text),
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
        self.rebuild(records)
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
                raise RuntimeError(
                    f"Warmup failed: reranker model is unavailable: {self.reranker.model_name}."
                )
        # Ensure FAISS/BM25/prefix caches are ready for realtime queries.
        self.index._ensure_bm25()
        self.index._rebuild_faiss()
        self.index._rebuild_note_prefix_cache()
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
        prefix_vec = self.index.prefix_embedding(note_id, block_index)
        if prefix_vec is not None:
            return prefix_vec

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
        if rerank_scores is None:
            raise RuntimeError("Reranker returned no scores while enabled.")
        if len(rerank_scores) != len(doc_ids):
            raise RuntimeError("Reranker returned mismatched score count.")

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
        try:
            max_results = int(os.environ.get("GRIMOIRE_CONTEXT_MAX_RESULTS", "3"))
        except Exception:
            max_results = 3
        limit = max(1, min(int(request.limit), max_results))

        text, cursor = _normalize_note_text_and_cursor(request.text or "", int(request.cursor_offset))
        blocks = chunk_blocks(text)

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
            return self._cache_value[:limit]

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
        window_tokens = _SparseTokenizer.tokenize(window)
        window_token_count = len(window_tokens)
        window_lex_tokens = _lexical_tokens(window)
        window_lex_set = set(window_lex_tokens)
        strong_anchors = _strong_capitalized_anchors(window)

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
            raise RuntimeError(
                "Context index embedding dimension mismatch. Rebuild the semantic context index."
            )

        # Step 4: prefix penalty uses cached/incremental e(P) when available.
        prefix_vec = self._compute_prefix_embedding(request.note_id, blocks, block_index, prefix_tail)

        # Blend prefix into the query when the window is short to stabilize retrieval.
        query_vec = window_vec
        try:
            short_window_tokens = int(os.environ.get("GRIMOIRE_SHORT_WINDOW_TOKENS", "40"))
        except Exception:
            short_window_tokens = 40
        if window_token_count < short_window_tokens and prefix_vec is not None:
            try:
                mix = float(os.environ.get("GRIMOIRE_WINDOW_PREFIX_MIX", "0.18"))
            except Exception:
                mix = 0.18
            mix = max(0.0, min(0.5, mix))
            if mix > 0.0 and prefix_vec.size == window_vec.size:
                query_vec = _normalize_dense(window_vec * (1.0 - mix) + prefix_vec * mix)

        # Step 3: concepts in W.
        active_labels = extract_concept_candidates(window, min_single_occurrences=2)
        active: List[Tuple[str, str]] = []
        for label in active_labels:
            norm = _normalize_concept_label(label)
            if norm:
                active.append((norm, label))
        active_ids = {cid for cid, _ in active}
        active_label_list = [label for _, label in active]
        active_label_weights: Dict[str, int] = {}
        for label in active_label_list:
            norm = _normalize_concept_label(label)
            if not norm or len(norm) < 4:
                continue
            if norm in _INFO_STOPWORDS:
                continue
            if norm in _CONCEPT_STOPLIST:
                continue
            if norm in _CAP_STOPWORDS:
                continue
            freq = _count_occurrences(window, label)
            if freq <= 0:
                freq = 1
            active_label_weights[norm] = max(active_label_weights.get(norm, 0), freq)

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

        # Expand lexical query when the window is too short or concept-heavy.
        try:
            min_lex_tokens = int(os.environ.get("GRIMOIRE_MIN_LEX_WINDOW_TOKENS", "12"))
        except Exception:
            min_lex_tokens = 12
        lexical_query = window
        if window_token_count < min_lex_tokens:
            tail = prefix_tail[-1200:].strip()
            if tail:
                lexical_query = f"{tail}\n{window}".strip()
        if active_label_list:
            lexical_query = f"{lexical_query}\n{' '.join(active_label_list[:8])}".strip()

        # Step 3: candidate retrieval union.
        dense_top_n = int(os.environ.get("GRIMOIRE_DENSE_TOP_N", "200"))
        bm25_top_n = int(os.environ.get("GRIMOIRE_BM25_TOP_N", "200"))

        candidate_ids: Set[str] = set()
        concept_ids_in_w = sorted({cid for cid, _ in active})
        candidate_ids |= self.index.chunks_for_concepts(concept_ids_in_w)
        candidate_ids |= self.index.chunks_for_concepts(sorted(gaps))

        dense_hits = self.index.dense_search(query_vec, top_k=dense_top_n)
        for cid, _ in dense_hits:
            candidate_ids.add(cid)
            if len(candidate_ids) >= 800:
                break

        bm25_hits = self.index.bm25_search(lexical_query, top_k=bm25_top_n)
        bm25_scores = {cid: score for cid, score in bm25_hits}
        bm25_norms = _min_max_normalize(bm25_scores)
        for cid, _ in bm25_hits:
            candidate_ids.add(cid)
            if len(candidate_ids) >= 800:
                break

        # Step 4/5: cheap scoring + cap.
        beta = float(os.environ.get("GRIMOIRE_GAP_BETA", "0.55"))
        lambd = float(os.environ.get("GRIMOIRE_PREFIX_LAMBDA", "0.35"))
        mention_bonus = float(os.environ.get("GRIMOIRE_GAP_MENTION_BONUS", "0.12"))
        lex_weight = float(os.environ.get("GRIMOIRE_LEXICAL_WEIGHT", "0.18"))
        concept_weight = float(os.environ.get("GRIMOIRE_CONCEPT_OVERLAP_WEIGHT", "0.16"))
        gap_overlap_weight = float(os.environ.get("GRIMOIRE_GAP_OVERLAP_WEIGHT", "0.1"))
        active_mention_bonus = float(os.environ.get("GRIMOIRE_ACTIVE_MENTION_BONUS", "0.18"))
        active_miss_penalty = float(os.environ.get("GRIMOIRE_ACTIVE_MISS_PENALTY", "0.08"))
        heading_penalty = float(os.environ.get("GRIMOIRE_HEADING_PENALTY", "0.08"))
        quality_weight = float(os.environ.get("GRIMOIRE_QUALITY_WEIGHT", "0.25"))
        min_quality = float(os.environ.get("GRIMOIRE_MIN_CHUNK_QUALITY", "0.5"))
        same_note_distance_weight = float(os.environ.get("GRIMOIRE_SAME_NOTE_DISTANCE_WEIGHT", "0.6"))
        max_candidates = int(os.environ.get("GRIMOIRE_MAX_CANDIDATES", "500"))
        mu = float(os.environ.get("GRIMOIRE_MMR_MU", "0.0"))
        coverage_weight = float(os.environ.get("GRIMOIRE_COVERAGE_WEIGHT", "0.08"))
        note_repeat_penalty = float(os.environ.get("GRIMOIRE_NOTE_REPEAT_PENALTY", "0.0"))

        scored: List[Tuple[str, float, Dict]] = []
        current_chunk_id = f"{request.note_id}:{current_block.start}:{current_block.end}:{block_index}"
        gap_list = sorted(gaps)
        cross_note_penalty = float(os.environ.get("GRIMOIRE_CROSS_NOTE_PENALTY", "0.06"))
        for cid in sorted(candidate_ids):
            # Avoid echoing what the user is currently reading.
            if cid == current_chunk_id:
                continue
            meta = self.index.get_chunk(cid)
            if not meta:
                continue
            # Semantic backlinks should always point to other notes.
            note_id = str(meta.get("note_id") or "")
            if note_id == request.note_id:
                continue
            meta_text = str(meta.get("text") or "")
            if _is_low_information_text(meta_text):
                continue
            quality = meta.get("quality")
            if not isinstance(quality, (float, int)):
                raise RuntimeError(
                    "Context chunk quality is missing. Rebuild the semantic context index to populate it."
                )
            if min_quality and float(quality) < min_quality:
                continue
            vec = _normalize_dense(meta.get("dense") or [])
            if vec.size == 0 or int(vec.shape[0]) != int(window_vec.shape[0]):
                continue
            rel = _dot(vec, query_vec)

            gap_support = 0.0
            gap_best: Optional[str] = None
            meta_concepts = set(meta.get("concepts", []) or [])
            active_overlap = len(meta_concepts & active_ids)
            gap_overlap = len(meta_concepts & gaps)
            active_ratio = float(active_overlap) / float(max(1, len(active_ids))) if active_ids else 0.0
            gap_ratio = float(gap_overlap) / float(max(1, len(gaps))) if gaps else 0.0
            mentions_gap = gap_overlap > 0
            for gap_id in gap_list:
                centroid = self.index.concept_centroid(gap_id)
                if centroid is None:
                    continue
                val = _dot(vec, centroid)
                if val > gap_support:
                    gap_support = val
                    gap_best = gap_id

            bm25_norm = float(bm25_norms.get(cid, 0.0)) if bm25_norms else 0.0
            lex_overlap = 0.0
            if window_lex_set:
                chunk_tokens = _lexical_tokens(meta_text)
                if chunk_tokens:
                    overlap = len(window_lex_set.intersection(chunk_tokens))
                    lex_overlap = float(overlap) / float(max(1, len(window_lex_set)))
            lexical = max(bm25_norm, lex_overlap)

            active_label_hits = 0
            if active_label_weights:
                lower_text = meta_text.lower()
                for label, weight in active_label_weights.items():
                    if label in lower_text:
                        active_label_hits += weight

            # Cross-note gating: keep quality high, but avoid "no results" when a note has
            # strong semantic matches with weak lexical overlap (common in prose).
            if note_id and note_id != request.note_id:
                min_cross_lex = float(os.environ.get("GRIMOIRE_CROSS_NOTE_MIN_LEXICAL", "0.06"))
                min_cross_rel = float(os.environ.get("GRIMOIRE_CROSS_NOTE_MIN_RELEVANCE", "0.78"))
                has_concept_link = bool(active_overlap or gap_overlap)

                # If we have strong anchors (proper-noun-ish terms), require at least one match.
                if strong_anchors:
                    lowered_text = meta_text.lower()
                    if not any(anchor.lower() in lowered_text for anchor in strong_anchors):
                        # No anchor match: only allow if the dense similarity is extremely high.
                        if rel < (min_cross_rel + 0.06):
                            continue

                # Otherwise, accept cross-note candidates if they pass *any* strong signal gate.
                if not (
                    (min_cross_lex and lexical >= min_cross_lex)
                    or has_concept_link
                    or (active_label_hits > 0)
                    or (min_cross_rel and rel >= min_cross_rel)
                ):
                    continue
            redundancy = _dot(vec, prefix_vec) if prefix_vec is not None else 0.0
            redundancy_penalty = float(lambd) * float(redundancy)
            # If a candidate is lexically on-topic for the current cursor window,
            # prefer relevance over "don't repeat what the reader already saw".
            if lexical:
                redundancy_penalty *= float(max(0.0, 1.0 - 0.6 * float(min(1.0, lexical))))
            base = rel - redundancy_penalty + beta * gap_support + (mention_bonus if mentions_gap else 0.0)
            base += lex_weight * lexical + concept_weight * active_ratio + gap_overlap_weight * gap_ratio
            if active_label_hits:
                base += active_mention_bonus * float(active_label_hits)
            elif active_label_weights and active_miss_penalty:
                base -= active_miss_penalty
            if heading_penalty and _is_heading_only(meta_text):
                base -= heading_penalty
            if quality_weight:
                base += quality_weight * float(quality)

            same_note_dist = None
            same_note_bonus = 0.0
            if same_note_distance_weight and note_id == request.note_id:
                cand_idx = _chunk_block_index(str(meta.get("chunk_id") or ""))
                if cand_idx is not None:
                    same_note_dist = abs(int(cand_idx) - int(block_index))
                    same_note_bonus = float(same_note_distance_weight) / float(1.0 + same_note_dist)
                    base += same_note_bonus
            debug = {
                "relevance": rel,
                "gap_support": gap_support,
                "redundancy": redundancy,
                "redundancy_penalty": redundancy_penalty,
                "lexical": lexical,
                "bm25_norm": bm25_norm,
                "lex_overlap": lex_overlap,
                "active_label_hits": active_label_hits,
                "active_overlap": active_overlap,
                "gap_overlap": gap_overlap,
                "active_ratio": active_ratio,
                "gap_ratio": gap_ratio,
                "quality": quality,
                "same_note_dist": same_note_dist,
                "same_note_bonus": same_note_bonus,
                "current_chunk": cid == current_chunk_id,
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
        seen_excerpt_keys: Set[str] = set()
        selected_note_ids: Set[str] = set()

        while remaining and len(selected) < limit:
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
                note_id = str(meta.get("note_id") or "")
                note_penalty = note_repeat_penalty if note_id and note_id in selected_note_ids else 0.0
                cross_penalty = cross_note_penalty if note_id and note_id != request.note_id else 0.0
                mmr = combined + cover_bonus - mu * max_red - note_penalty - cross_penalty
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
            if meta.get("note_id"):
                selected_note_ids.add(str(meta.get("note_id")))

            concept_title = None
            gap_best = debug.get("gap_concept_id")
            if gap_best:
                concept_title = self.index.concept_label(gap_best) or gap_best

            # UI score should match the list ordering. Use the combined (cheap+rerank) score,
            # then normalize across the final selected set.
            raw_score = float(debug.get("combined", base))

            meta_text = str(meta.get("text") or "")
            if cid == current_chunk_id:
                excerpt = _query_aware_excerpt(
                    meta_text,
                    window_lex_set,
                    max_units=3,
                    max_chars=600,
                    cursor_char=local_cursor,
                    avoid_radius=int(os.environ.get("GRIMOIRE_EXCERPT_AVOID_RADIUS", "420")),
                    hard_avoid=True,
                )
            else:
                excerpt = _query_aware_excerpt(meta_text, window_lex_set, max_units=3, max_chars=600)
            if _is_low_information_text(excerpt):
                continue
            min_excerpt_quality = float(os.environ.get("GRIMOIRE_MIN_EXCERPT_QUALITY", "0.35"))
            excerpt_eval = excerpt
            if excerpt_eval.lstrip().startswith("#"):
                excerpt_eval = re.sub(r"(?m)^[ \t]{0,3}#{1,6}[ \t]+", "", excerpt_eval).strip()
            if min_excerpt_quality and _chunk_quality_score(excerpt_eval) < float(min_excerpt_quality):
                continue
            ex_key = _excerpt_key(excerpt)
            # Avoid showing multiple identical excerpts (often from short headings/boilerplate).
            if ex_key and ex_key in seen_excerpt_keys:
                continue
            if ex_key:
                seen_excerpt_keys.add(ex_key)

            snippet = ContextSnippetPayload(
                note_id=meta["note_id"],
                chunk_id=meta["chunk_id"],
                text=excerpt,
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
