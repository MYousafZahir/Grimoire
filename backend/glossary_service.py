"""Automated glossary (local, non-LLM, corpus-derived).

UPDATED (entity/mention-based):
- Operates on *entity mentions*, not raw strings.
- Uses spaCy parses (en_core_web_sm) to extract noun-phrase/proper-noun mentions.
- Filters candidates via termhood scoring to avoid junk entries (e.g. "Many", "In Denmark").
- Discovers aliases via conservative clustering + explicit alias patterns ("aka", "(Y)", "known as").
- Selects verbatim definition *sentences* (1–3) from the corpus (no generation).

Models used (local):
- Dense embeddings: BAAI/bge-small-en-v1.5 (via ContextEmbedder)
- Cross-encoder scorer: BAAI/bge-reranker-base (via ContextReranker)
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import threading
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

import numpy as np

from context_service import (
    Block,
    ContextEmbedder,
    ContextIndex,
    ContextReranker,
    _dot,
    _normalize_dense,
    _sentences_excerpt,
    split_blocks,
)
from models import NoteKind
from storage import NoteStorage


_GLOSSARY_NAMESPACE = uuid.UUID("9f5bca3a-73b8-4e70-b19d-8a7b7c7a81f5")
_GLOSSARY_STORAGE_VERSION = 5


def _now() -> float:
    return time.time()


def _normalize_label(label: str) -> str:
    label = (label or "").strip()
    label = re.sub(r"`+", "", label)
    label = re.sub(r"[^\w\s-]", "", label)
    label = re.sub(r"\s+", " ", label)
    return label.lower().strip()


def _clean_note_text(text: str) -> str:
    """Match ContextService cleaning so offsets align with context chunk ids."""
    cleaned = (text or "")
    cleaned = cleaned.replace("\n\n<!-- grimoire-chunk -->\n\n", "\n\n")
    cleaned = cleaned.replace("<!-- grimoire-chunk -->", "")
    cleaned = cleaned.replace("\r\n", "\n").replace("\r", "\n")
    return cleaned


def _sha1(text: str) -> str:
    return hashlib.sha1((text or "").encode("utf-8")).hexdigest()


_CODE_FENCE_RE = re.compile(r"(?s)```.*?```")


def _code_fence_ranges(text: str) -> List[Tuple[int, int]]:
    return [(m.start(), m.end()) for m in _CODE_FENCE_RE.finditer(text or "")]


def _is_inside_ranges(start: int, end: int, ranges: Sequence[Tuple[int, int]]) -> bool:
    for a, b in ranges:
        if start >= a and end <= b:
            return True
    return False


def _mask_code_blocks_keep_offsets(text: str, ranges: Sequence[Tuple[int, int]]) -> str:
    if not ranges:
        return text
    chars = list(text)
    for a, b in ranges:
        a = max(0, min(len(chars), int(a)))
        b = max(0, min(len(chars), int(b)))
        for i in range(a, b):
            if chars[i] != "\n":
                chars[i] = " "
    return "".join(chars)


_MD_HEADING_PREFIX_RE = re.compile(r"(?m)^[ \t]{0,3}#{1,6}[ \t]+")
_MD_UNORDERED_PREFIX_RE = re.compile(r"(?m)^[ \t]*[-*+][ \t]+")
_MD_ORDERED_PREFIX_RE = re.compile(r"(?m)^[ \t]*\d+[.)][ \t]+")
_MD_BLOCKQUOTE_PREFIX_RE = re.compile(r"(?m)^[ \t]*>[ \t]?")
_MD_HRULE_LINE_RE = re.compile(r"(?m)^[ \t]*[-—_⸻]{3,}[ \t]*$")
_MD_FIELD_LABEL_RE = re.compile(r"(?mi)^(name|purpose|description|location)[ \t]*:[ \t]*")


def _mask_markdown_for_spacy_keep_offsets(text: str) -> str:
    """Mask common markdown syntax with spaces while preserving offsets."""
    if not text:
        return text
    chars = list(text)

    def mask_span(a: int, b: int):
        a = max(0, int(a))
        b = min(len(chars), int(b))
        for i in range(a, b):
            if chars[i] != "\n":
                chars[i] = " "

    for pat in (
        _MD_HEADING_PREFIX_RE,
        _MD_UNORDERED_PREFIX_RE,
        _MD_ORDERED_PREFIX_RE,
        _MD_BLOCKQUOTE_PREFIX_RE,
        _MD_FIELD_LABEL_RE,
    ):
        for m in pat.finditer(text):
            mask_span(m.start(), m.end())

    for m in _MD_HRULE_LINE_RE.finditer(text):
        mask_span(m.start(), m.end())

    # Inline markdown markers.
    for i, ch in enumerate(chars):
        if ch in {"*", "_", "`"}:
            chars[i] = " "

    return "".join(chars)


_QUANTIFIER_LEMMAS: Set[str] = {
    "many",
    "some",
    "most",
    "few",
    "several",
    "various",
    "all",
    "each",
    "every",
    "either",
    "neither",
    "any",
    "much",
    "more",
    "less",
}


def _canonicalize_span_tokens(tokens: List[object]) -> List[object]:
    """Strip leading determiners/quantifiers/prepositions without destroying PROPN spans."""
    i = 0
    while i < len(tokens):
        t = tokens[i]
        pos = getattr(t, "pos_", "")
        lemma = (getattr(t, "lemma_", "") or "").lower()
        if pos in {"DET", "ADP", "PRON", "ADV", "CCONJ", "SCONJ", "PART"}:
            i += 1
            continue
        if lemma in _QUANTIFIER_LEMMAS:
            i += 1
            continue
        break
    return tokens[i:]


def _normalize_for_key(text: str) -> str:
    t = (text or "").strip()
    t = re.sub(r"`+", "", t)
    t = re.sub(r"[^\w\s'-]", "", t)
    t = re.sub(r"\s+", " ", t)
    return t.lower().strip()


def _token_count(text: str) -> int:
    return len(re.findall(r"\S+", (text or "").strip()))


def _entity_kind_label(kind: str) -> str:
    kind = (kind or "").strip().lower()
    if kind in {"person", "place", "thing"}:
        return kind
    return "unknown"


def _bounded_edit_distance(a: str, b: str, max_dist: int = 2) -> int:
    # Small bounded Levenshtein; deterministic.
    a = a or ""
    b = b or ""
    if a == b:
        return 0
    if abs(len(a) - len(b)) > max_dist:
        return max_dist + 1
    if not a or not b:
        return max_dist + 1
    if len(a) > len(b):
        a, b = b, a
    prev = list(range(len(a) + 1))
    for i, cb in enumerate(b, start=1):
        cur = [i]
        min_row = i
        for j, ca in enumerate(a, start=1):
            cost = 0 if ca == cb else 1
            val = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            cur.append(val)
            min_row = min(min_row, val)
        prev = cur
        if min_row > max_dist:
            return max_dist + 1
    return prev[-1]


@dataclass
class SentenceRecord:
    sentence_id: str
    note_id: str
    start: int
    end: int
    text: str
    dense: List[float]
    chunk_id: str
    heading: Optional[str] = None


@dataclass
class MentionRecord:
    mention_id: str
    note_id: str
    sentence_id: str
    start: int
    end: int
    surface_text: str
    canonical_text: str
    head_lemma: str
    head_pos: str
    dep_role: str
    context_dense: List[float]


@dataclass
class NoteExtract:
    note_id: str
    text_hash: str
    sentences: List[SentenceRecord]
    mentions: List[MentionRecord]


@dataclass
class EntityRecord:
    entity_id: str
    canonical_name: str
    kind: str
    aliases: List[str]
    mention_ids: List[str]
    chunk_ids: List[str]
    definition_sentence_ids: List[str]
    definition_excerpt: str
    definition_chunk_id: Optional[str]
    source_note_id: Optional[str]
    score: float
    supporting: List[Tuple[str, str, str]]


_SPACY_NLP = None
_SPACY_LOCK = threading.Lock()


def _load_spacy() -> object:
    """Load spaCy model lazily. Raises if unavailable."""
    global _SPACY_NLP
    with _SPACY_LOCK:
        if _SPACY_NLP is not None:
            return _SPACY_NLP
        try:
            import spacy  # type: ignore
        except ImportError as exc:
            raise RuntimeError(
                "spaCy is required for glossary extraction. Install it and the model to proceed."
            ) from exc

        model_name = os.environ.get("GRIMOIRE_SPACY_MODEL", "en_core_web_sm").strip() or "en_core_web_sm"

        def load_model() -> object:
            try:
                return spacy.load(model_name, exclude=["ner"])
            except TypeError:
                # Older spaCy versions don't support `exclude`.
                return spacy.load(model_name)

        try:
            _SPACY_NLP = load_model()
        except OSError as exc:
            raise RuntimeError(
                f"spaCy model '{model_name}' is unavailable. Install it to use the glossary."
            ) from exc

        try:
            _SPACY_NLP.max_length = max(int(getattr(_SPACY_NLP, "max_length", 1_000_000)), 5_000_000)
        except Exception:
            pass
        return _SPACY_NLP


_HEADING_LINE_RE = re.compile(r"(?m)^[ \t]{0,3}#{1,6}[ \t]+(.+?)\s*$")


def _extract_headings(cleaned: str) -> List[Tuple[int, str]]:
    headings: List[Tuple[int, str]] = []
    for m in _HEADING_LINE_RE.finditer(cleaned or ""):
        title = (m.group(1) or "").strip()
        if title:
            headings.append((m.start(), title))
    headings.sort(key=lambda t: t[0])
    return headings


def _heading_for_offset(headings: Sequence[Tuple[int, str]], offset: int) -> Optional[str]:
    if not headings:
        return None
    best: Optional[str] = None
    for start, title in headings:
        if start <= offset:
            best = title
        else:
            break
    return best


def _blocks_with_ids(note_id: str, cleaned: str) -> List[Tuple[Block, str]]:
    blocks = split_blocks(cleaned)
    out: List[Tuple[Block, str]] = []
    for idx, block in enumerate(blocks):
        if not block.text.strip():
            continue
        chunk_id = f"{note_id}:{block.start}:{block.end}:{idx}"
        out.append((block, chunk_id))
    return out


def _chunk_id_for_offset(blocks_with_ids: Sequence[Tuple[Block, str]], offset: int) -> Optional[str]:
    if not blocks_with_ids:
        return None
    for block, cid in blocks_with_ids:
        if int(block.start) <= int(offset) <= int(block.end):
            return cid
    # Fallback: nearest block by start.
    best = min(blocks_with_ids, key=lambda b: abs(int(b[0].start) - int(offset)))
    return best[1]


_FALLBACK_SENT_SPLIT_RE = re.compile(r"(?<=[.!?])\s+|\n{2,}")


def _fallback_sentences_with_offsets(span_text: str, span_start: int) -> List[Tuple[int, int, str]]:
    """Best-effort sentence splitting with offsets for when spaCy isn't available."""
    if not span_text:
        return []
    sentences: List[Tuple[int, int, str]] = []
    cursor = 0
    for m in _FALLBACK_SENT_SPLIT_RE.finditer(span_text):
        raw = span_text[cursor : m.start()]
        if raw.strip():
            leading = len(raw) - len(raw.lstrip())
            trailing = len(raw) - len(raw.rstrip())
            start = span_start + cursor + leading
            end = span_start + m.start() - trailing
            if end > start:
                sentences.append((start, end, span_text[start - span_start : end - span_start].strip()))
        cursor = m.end()
    tail = span_text[cursor:]
    if tail.strip():
        leading = len(tail) - len(tail.lstrip())
        trailing = len(tail) - len(tail.rstrip())
        start = span_start + cursor + leading
        end = span_start + len(span_text) - trailing
        if end > start:
            sentences.append((start, end, span_text[start - span_start : end - span_start].strip()))
    return sentences


_FALLBACK_QUOTE_RE = re.compile(r"(?:(?:\"|“)([^\"\n]{2,60})(?:\"|”))")


def _maybe_singularize_phrase(phrase: str) -> str:
    phrase = (phrase or "").strip()
    if not phrase:
        return phrase
    parts = phrase.split()
    if not parts:
        return phrase
    last = parts[-1]
    low = last.lower()
    # Avoid mangling reflexive/relative pronouns that commonly appear in sentence-start fragments.
    if low in {
        "itself",
        "themselves",
        "himself",
        "herself",
        "yourself",
        "yourselves",
        "myself",
        "ourselves",
        "which",
        "that",
        "who",
        "whom",
        "whose",
        "where",
        "when",
    }:
        return phrase
    # Don't try to singularize acronyms like "BLT".
    if last.isupper():
        return phrase
    # Don't try to singularize likely multi-token proper names like "United States".
    if len(parts) >= 2 and all(p[:1].isupper() for p in parts):
        return phrase
    if low.endswith("ss"):
        return phrase
    if low.endswith("ies") and len(low) >= 5:
        parts[-1] = last[:-3] + "y"
        return " ".join(parts).strip()
    if low.endswith("es") and len(low) >= 5:
        # Strip "es" only for common plural forms where it's actually an "es" suffix,
        # not just an "s" plural (e.g. "olives" -> "olive", not "oliv").
        if low.endswith(("ses", "xes", "zes", "ches", "shes", "oes")):
            parts[-1] = last[:-2]
            return " ".join(parts).strip()
    if low.endswith("s") and len(low) >= 4:
        parts[-1] = last[:-1]
        return " ".join(parts).strip()
    return phrase


def _add_fallback_mention(
    *,
    mentions: List[MentionRecord],
    seen: Set[Tuple[int, int]],
    note_id: str,
    sentence: SentenceRecord,
    cleaned: str,
    start: int,
    end: int,
    surface: str,
    head_pos: str = "PROPN",
) -> None:
    if end <= start:
        return
    if (start, end) in seen:
        return
    surface = (surface or "").strip()
    if not surface:
        return
    canonical = surface
    # Normalize simple plural forms for better clustering in fallback mode.
    # Avoid singularizing likely proper nouns ("The Ratways") where the plural is part of the name.
    if head_pos != "PROPN":
        canonical = _maybe_singularize_phrase(canonical)

    # Unicode-friendly tokenization so quoted fictional terms (e.g. "smørrebrød") work.
    words = [w for w in re.findall(r"[\w'-]+", canonical, flags=re.UNICODE) if w]
    if not words:
        return
    # Strip trailing reflexives/relatives that appear in sentence fragments (e.g. "geometry itself").
    while words and words[-1].lower() in {"itself", "themselves", "himself", "herself", "which", "that", "who", "whom"}:
        words = words[:-1]
    if not words:
        return
    canonical = " ".join(words).strip()
    # Reject spans that accidentally include relative pronouns (e.g. "olives which").
    if words and words[-1].lower() in {"which", "that", "who", "whom", "whose", "where", "when"}:
        return
    # Reject common junk leads.
    w0 = words[0].lower()
    if w0 in _FUNCTION_WORD_CANDIDATES or w0 in _GENERIC_NOUN_CANDIDATES or w0 in _GENERIC_CONCEPT_BLACKLIST:
        return
    if w0 in _QUANTIFIER_LEMMAS:
        return
    if all(w.lower() in _GLOSSARY_STOPWORDS for w in words):
        return

    canonical_key = _normalize_for_key(canonical)
    if not canonical_key or len(canonical_key) < 3:
        return
    if canonical_key in _FUNCTION_WORD_CANDIDATES or canonical_key in _GENERIC_NOUN_CANDIDATES or canonical_key in _GENERIC_CONCEPT_BLACKLIST:
        return

    mid = str(uuid.uuid5(_GLOSSARY_NAMESPACE, f"{note_id}:m:{start}:{end}:{canonical_key}"))
    mentions.append(
        MentionRecord(
            mention_id=mid,
            note_id=note_id,
            sentence_id=sentence.sentence_id,
            start=start,
            end=end,
            surface_text=canonical,
            canonical_text=canonical,
            head_lemma=canonical_key,
            head_pos=head_pos,
            dep_role="",
            context_dense=list(sentence.dense),
        )
    )
    seen.add((start, end))

# Roles that tend to indicate a span is being used referentially ("X does Y", "about X", "X, a Y, ...").
# Include `oprd` for patterns like "called an X" / "named X", which are common definitional cues.
_REF_ROLES: Set[str] = {"nsubj", "nsubjpass", "dobj", "iobj", "obj", "pobj", "appos", "attr", "oprd"}
_MOD_ROLES: Set[str] = {"amod", "advmod", "det"}


def _explicit_alias_edges(
    sentence_text: str, sentence_start: int, mentions_in_sentence: List[MentionRecord]
) -> Set[Tuple[str, str]]:
    """Return canonical-key pairs that should be considered aliases from explicit patterns."""
    text = (sentence_text or "").lower()
    if not mentions_in_sentence or len(mentions_in_sentence) < 2:
        return set()

    patterns = (" aka ", " known as ", " also known as ", " called ")
    if not any(p in text for p in patterns) and "(" not in text:
        return set()

    # Conservative: only connect mentions that appear near each other in text.
    by_start = sorted(mentions_in_sentence, key=lambda m: (m.start, m.end))
    edges: Set[Tuple[str, str]] = set()
    for a, b in zip(by_start, by_start[1:]):
        a0 = max(0, int(a.start) - int(sentence_start))
        a1 = max(0, int(a.end) - int(sentence_start))
        b0 = max(0, int(b.start) - int(sentence_start))
        b1 = max(0, int(b.end) - int(sentence_start))
        if a1 > len(sentence_text) or b0 > len(sentence_text):
            continue
        gap = sentence_text[a1:b0]
        gap_lower = gap.lower()
        if any(p.strip() in gap_lower for p in patterns):
            ka = _normalize_for_key(a.canonical_text)
            kb = _normalize_for_key(b.canonical_text)
            if ka and kb and ka != kb:
                edges.add(tuple(sorted((ka, kb))))
        # Parenthetical alias: "X (Y)"
        if "(" in gap and ")" in sentence_text[b1 : min(len(sentence_text), b1 + 6)]:
            ka = _normalize_for_key(a.canonical_text)
            kb = _normalize_for_key(b.canonical_text)
            if ka and kb and ka != kb:
                edges.add(tuple(sorted((ka, kb))))
    return edges

def _tokenize_words(text: str) -> List[str]:
    return re.findall(r"[\w'-]+", (text or "").lower(), flags=re.UNICODE)


def _fallback_head_pos(surface: str, *, sentence_start: bool = False) -> str:
    """Best-effort POS for fallback mentions (no spaCy).

    We intentionally default to NOUN to avoid treating sentence-start words like "Above" or "During"
    as proper nouns; proper nouns are still captured via multiword TitleCase, acronyms, or repetition.
    """
    surface = (surface or "").strip()
    if not surface:
        return "NOUN"
    words = [w for w in re.findall(r"[\w'-]+", surface, flags=re.UNICODE) if w]
    if not words:
        return "NOUN"
    if any(w.isupper() and len(w) >= 2 for w in words):
        return "PROPN"
    if any(not w.isascii() for w in words):
        return "PROPN"
    if any(any(ch.isupper() for ch in w[1:]) for w in words):
        return "PROPN"
    initial_uppers = sum(1 for w in words if w[:1].isupper())
    if len(words) >= 2 and initial_uppers >= 2:
        return "PROPN"
    if (
        len(words) == 1
        and words[0][:1].isupper()
        and words[0][1:].islower()
        and len(words[0]) >= 4
        and not sentence_start
        and words[0].lower() not in _FUNCTION_WORD_CANDIDATES
        and words[0].lower() not in _GENERIC_NOUN_CANDIDATES
        and words[0].lower() not in _QUANTIFIER_LEMMAS
    ):
        return "PROPN"
    return "NOUN"


_GENERIC_CONCEPT_BLACKLIST: Set[str] = {
    "key points",
    "key point",
    "summary",
    "notes",
    "todo",
    "name",
    "purpose",
    "description",
    "location",
    # Common document-structure headings that shouldn't become glossary entries by themselves.
    "overview",
    "introduction",
    "background",
    "history",
    "origin",
    "timeline",
    "conclusion",
    "appendix",
    "start writing",
    "start writing here",
}


_GLOSSARY_STOPWORDS: Set[str] = {
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

_FUNCTION_WORD_CANDIDATES: Set[str] = set(_GLOSSARY_STOPWORDS) | {
    # Pronouns / determiners / deictics.
    "i",
    "me",
    "my",
    "mine",
    "we",
    "us",
    "our",
    "ours",
    "you",
    "your",
    "yours",
    "he",
    "him",
    "his",
    "she",
    "her",
    "hers",
    "they",
    "them",
    "their",
    "theirs",
    "it",
    "its",
    "this",
    "that",
    "these",
    "those",
    "there",
    "here",
    # Common sentence-initial adverbs/conjuncts that become junk in fallback extraction.
    "again",
    "another",
    "around",
    "even",
    "later",
    "then",
    "also",
    "generally",
    "usually",
    "often",
    "sometimes",
    "mostly",
    "however",
    "therefore",
    "meanwhile",
    "first",
    "second",
    "third",
    "finally",
    # Misc.
    "for",
    "from",
    "with",
    "without",
    # Common prepositions/conjunctions that often appear capitalized at sentence start in notes.
    "above",
    "across",
    "after",
    "along",
    "around",
    "as",
    "because",
    "before",
    "below",
    "beneath",
    "between",
    "beyond",
    "despite",
    "during",
    "inside",
    "near",
    "onto",
    "over",
    "since",
    "through",
    "though",
    "toward",
    "towards",
    "under",
    "until",
    "upon",
    "where",
    "when",
    "while",
    # Direction words (often sentence-start and not entities).
    "north",
    "south",
    "east",
    "west",
    "northward",
    "southward",
    "eastward",
    "westward",
}

_GENERIC_NOUN_CANDIDATES: Set[str] = {
    "people",
    "person",
    "persons",
    "thing",
    "things",
    "type",
    "types",
    "definition",
    "example",
    "examples",
    "artifact",
    "artifacts",
    "district",
    "districts",
    # Common colors.
    "black",
}


def _is_low_information_text(text: str) -> bool:
    """True if a chunk is unlikely to be a useful glossary definition."""
    raw = (text or "").strip()
    if not raw:
        return True

    # Mostly punctuation/markdown markers/digits.
    # Put '-' at the end to avoid "bad character range" errors in the character class.
    if re.fullmatch(r"[#>*_\s\[\]\(\)`~\.,:;!?0-9-]+", raw):
        return True

    lowered = raw.lower().strip()
    if lowered.rstrip(".") in _GENERIC_CONCEPT_BLACKLIST:
        return True

    alpha_chars = sum(1 for ch in raw if ch.isalpha())
    if alpha_chars < int(os.environ.get("GRIMOIRE_GLOSSARY_MIN_ALPHA", "8")):
        return True

    tokens = re.findall(r"[A-Za-z][A-Za-z']*", raw)
    if len(tokens) < int(os.environ.get("GRIMOIRE_GLOSSARY_MIN_TOKENS", "3")):
        return True

    content = [t.lower() for t in tokens if len(t) >= 3 and t.lower() not in _GLOSSARY_STOPWORDS]
    if len(content) < int(os.environ.get("GRIMOIRE_GLOSSARY_MIN_CONTENT_TOKENS", "2")):
        return True

    return False


def _is_bullet_heavy(text: str) -> bool:
    lines = [ln.strip() for ln in (text or "").splitlines() if ln.strip()]
    if len(lines) < 3:
        return False
    bullet = 0
    for ln in lines:
        if re.match(r"^([-*+]|(\d+[\.\)]))\s+", ln):
            bullet += 1
    return (bullet / max(1, len(lines))) >= 0.6


def _early_position_bonus(text: str, surface_forms: Sequence[str], token_limit: int = 30) -> float:
    tokens = re.findall(r"\S+", (text or ""))
    if not tokens:
        return 0.0
    hay = (text or "")
    best = None
    for form in surface_forms:
        if not form:
            continue
        m = re.search(rf"(?i)(?<!\w){re.escape(form)}(?!\w)", hay)
        if not m:
            continue
        prefix = hay[: m.start()]
        idx = len(re.findall(r"\S+", prefix))
        if best is None or idx < best:
            best = idx
    if best is None:
        return 0.0
    if best <= token_limit:
        return 1.0
    if best <= token_limit * 2:
        return 0.4
    return 0.0


def _heading_match_bonus(text: str, surface_forms: Sequence[str]) -> float:
    first = (text or "").strip().splitlines()[:1]
    if not first:
        return 0.0
    line = first[0].strip()
    if not line.startswith("#"):
        return 0.0
    for form in surface_forms:
        if form and re.search(rf"(?i)\b{re.escape(form)}\b", line):
            return 1.0
    return 0.0


def _fragment_penalty(text: str) -> float:
    tokens = re.findall(r"\S+", (text or "").strip())
    if len(tokens) < 10:
        return 1.0
    if len(tokens) < 16:
        return 0.4
    return 0.0


def _classify(surface: str) -> str:
    surface = (surface or "").strip()
    if not surface:
        return "thing"

    place_suffixes = (
        " City",
        " Town",
        " Village",
        " Kingdom",
        " Empire",
        " Realm",
        " Forest",
        " Woods",
        " Mountain",
        " Mountains",
        " River",
        " Lake",
        " Sea",
        " Desert",
        " Valley",
        " Keep",
        " Castle",
        " Citadel",
        " Temple",
    )
    for suf in place_suffixes:
        if surface.endswith(suf):
            return "place"

    words = surface.split()
    if len(words) >= 2 and all(w[:1].isupper() for w in words if w):
        return "person"

    return "thing"


def _levenshtein(a: str, b: str, max_dist: int = 3) -> int:
    """Bounded Levenshtein for deterministic variant merging."""
    a = a or ""
    b = b or ""
    if a == b:
        return 0
    if abs(len(a) - len(b)) > max_dist:
        return max_dist + 1
    if not a or not b:
        return max_dist + 1

    # Ensure a is shorter.
    if len(a) > len(b):
        a, b = b, a

    prev = list(range(len(a) + 1))
    for i, ch_b in enumerate(b, start=1):
        cur = [i]
        min_row = i
        for j, ch_a in enumerate(a, start=1):
            cost = 0 if ch_a == ch_b else 1
            val = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            cur.append(val)
            min_row = min(min_row, val)
        prev = cur
        if min_row > max_dist:
            return max_dist + 1
    return prev[-1]


@dataclass(frozen=True)
class GlossaryEntry:
    concept_id: str
    display_name: str
    kind: str
    chunk_ids: List[str]
    surface_forms: List[str]
    definition_chunk_id: Optional[str]
    definition_excerpt: str
    source_note_id: Optional[str]
    last_updated: float
    score: float
    supporting: List[Tuple[str, str, str]]  # (chunk_id, note_id, excerpt)


class GlossaryService:
    """Project-scoped entity glossary derived from notes.

    - Mention extraction uses spaCy parses over cleaned note text.
    - Definitions are verbatim sentences selected from the corpus (no generation).
    - Updates run in a background thread on-save.
    """

    def __init__(
        self,
        path: Path,
        index: ContextIndex,
        storage: NoteStorage,
        *,
        embedder: Optional[ContextEmbedder] = None,
        reranker: Optional[ContextReranker] = None,
    ):
        self.path = Path(path)
        self.index = index
        self.storage = storage
        self.embedder = embedder
        self.reranker = reranker
        self.path.parent.mkdir(parents=True, exist_ok=True)

        self._lock = threading.RLock()
        self._update_thread: Optional[threading.Thread] = None
        self._pending_note_updates: Set[str] = set()

        # Legacy fields kept for backwards compatibility with older serialized payloads.
        self._note_concepts: Dict[str, Set[str]] = {}
        self._merge_map: Dict[str, str] = {}

        # New state (entity/mention based).
        self._notes: Dict[str, NoteExtract] = {}
        self._entities: Dict[str, EntityRecord] = {}
        self._entries: Dict[str, GlossaryEntry] = {}
        self._name_vec_cache: Dict[str, np.ndarray] = {}
        self._last_extract_used_spacy: bool = False
        self._last_extract_spacy_available: bool = False
        self.last_build_spacy_notes: int = 0
        self.last_build_fallback_notes: int = 0
        self._load()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------
    def ensure_built(self) -> None:
        with self._lock:
            if self._entries:
                return
        self.rebuild()

    def list_entries(self) -> List[GlossaryEntry]:
        with self._lock:
            entries = list(self._entries.values())
        entries.sort(key=lambda e: (-len(e.chunk_ids), e.display_name.lower(), e.concept_id))
        return entries

    def entry(self, concept_id: str) -> Optional[GlossaryEntry]:
        with self._lock:
            return self._entries.get(concept_id)

    def update_for_note(self, note_id: str) -> None:
        """Schedule an on-save glossary update in the background."""
        with self._lock:
            self._pending_note_updates.add(str(note_id))
            if self._update_thread is not None and self._update_thread.is_alive():
                return
            self._update_thread = threading.Thread(
                target=self._run_pending_updates, name="glossary-update", daemon=True
            )
            self._update_thread.start()

    def delete_notes(self, note_ids: Iterable[str]) -> None:
        with self._lock:
            removed = False
            for note_id in note_ids:
                if str(note_id) in self._notes:
                    self._notes.pop(str(note_id), None)
                    removed = True
        if removed:
            self._recompute_entities_and_entries()
            self._save()

    def rebuild(self) -> int:
        """Full rebuild from current project notes."""
        records = self.storage.list_records().values()
        next_notes: Dict[str, NoteExtract] = {}
        self.last_build_spacy_notes = 0
        self.last_build_fallback_notes = 0
        for record in records:
            if record.kind != NoteKind.NOTE:
                continue
            cleaned = _clean_note_text(record.content)
            if not cleaned.strip():
                continue
            note_hash = _sha1(cleaned)
            extracted = self._extract_note(record.id, cleaned, note_hash)
            if extracted is not None:
                next_notes[record.id] = extracted
                if self._last_extract_used_spacy:
                    self.last_build_spacy_notes += 1
                else:
                    self.last_build_fallback_notes += 1

        with self._lock:
            self._notes = next_notes

        self._recompute_entities_and_entries()
        self._save()
        with self._lock:
            return len(self._entries)

    # ------------------------------------------------------------------
    # Entity glossary internals (new pipeline)
    # ------------------------------------------------------------------
    def _run_pending_updates(self) -> None:
        # Consume queued note ids; collapse multiple updates into one recompute.
        while True:
            with self._lock:
                pending = sorted(self._pending_note_updates)
                self._pending_note_updates.clear()
            if not pending:
                return

            changed = False
            for note_id in pending:
                try:
                    record = self.storage.get_note(note_id)
                except Exception:
                    with self._lock:
                        if note_id in self._notes:
                            self._notes.pop(note_id, None)
                            changed = True
                    continue

                if getattr(record, "kind", None) != NoteKind.NOTE:
                    with self._lock:
                        if note_id in self._notes:
                            self._notes.pop(note_id, None)
                            changed = True
                    continue

                cleaned = _clean_note_text(getattr(record, "content", "") or "")
                if not cleaned.strip():
                    with self._lock:
                        if note_id in self._notes:
                            self._notes.pop(note_id, None)
                            changed = True
                    continue

                note_hash = _sha1(cleaned)
                with self._lock:
                    existing = self._notes.get(note_id)
                if existing is not None and existing.text_hash == note_hash:
                    continue

                extracted = self._extract_note(note_id, cleaned, note_hash)
                if extracted is None:
                    continue
                with self._lock:
                    self._notes[note_id] = extracted
                changed = True

            if changed:
                self._recompute_entities_and_entries()
                self._save()

    def _extract_note(self, note_id: str, cleaned: str, note_hash: str) -> Optional[NoteExtract]:
        embedder = self.embedder or ContextEmbedder("BAAI/bge-small-en-v1.5")
        nlp = _load_spacy()
        self._last_extract_spacy_available = True
        used_spacy = True

        code_ranges = _code_fence_ranges(cleaned)
        masked = _mask_code_blocks_keep_offsets(cleaned, code_ranges)
        parse_text = _mask_markdown_for_spacy_keep_offsets(masked)
        headings = _extract_headings(cleaned)
        blocks_with_ids = _blocks_with_ids(note_id, cleaned)

        if not blocks_with_ids:
            return None

        sentences: List[SentenceRecord] = []
        sentence_by_range: List[Tuple[int, int, str, List[float], str, Optional[str]]] = []

        try:
            doc = nlp(parse_text)
        except Exception as exc:
            raise RuntimeError(f"Glossary: spaCy parse failed: {exc}") from exc

        for sent in getattr(doc, "sents", []):
            start = int(getattr(sent, "start_char", 0))
            end = int(getattr(sent, "end_char", 0))
            if end <= start:
                continue
            if _is_inside_ranges(start, end, code_ranges):
                continue
            raw = (cleaned[start:end] or "").strip()
            if not raw:
                continue
            chunk_id = _chunk_id_for_offset(blocks_with_ids, start)
            if chunk_id is None:
                continue
            heading = _heading_for_offset(headings, start)
            dense = embedder.encode_dense(raw).tolist()
            sid = str(uuid.uuid5(_GLOSSARY_NAMESPACE, f"{note_id}:sent:{start}:{end}"))
            sentences.append(
                SentenceRecord(
                    sentence_id=sid,
                    note_id=note_id,
                    start=start,
                    end=end,
                    text=raw,
                    dense=dense,
                    chunk_id=chunk_id,
                    heading=heading,
                )
            )
            sentence_by_range.append((start, end, sid, dense, raw, heading))

        if not sentences:
            self._last_extract_used_spacy = False
            return None

        mentions: List[MentionRecord] = []

        try:
            doc = nlp(parse_text)
        except Exception as exc:
            raise RuntimeError(f"Glossary: spaCy parse failed: {exc}") from exc

        if doc is not None:
            # Build fast lookup of sentence spans for assigning mentions.
            spans = [(a, b, sid, dense) for (a, b, sid, dense, _, _) in sentence_by_range]
            spans.sort(key=lambda x: x[0])

            def find_sentence(start: int, end: int) -> Optional[Tuple[str, List[float]]]:
                for a, b, sid, dense in spans:
                    if start >= a and end <= b:
                        return sid, dense
                return None

            seen_ranges: Set[Tuple[int, int]] = set()

            # Noun chunks.
            try:
                noun_chunks = list(getattr(doc, "noun_chunks", []))
            except Exception:
                noun_chunks = []

            candidate_spans = list(noun_chunks)

            # PROPN spans not captured by noun_chunks.
            try:
                tokens = list(doc)
                for tok in tokens:
                    if getattr(tok, "pos_", "") != "PROPN":
                        continue
                    sent = getattr(tok, "sent", None)
                    if sent is None:
                        continue
                    # Expand to contiguous PROPN tokens in the sentence.
                    i = int(getattr(tok, "i", 0))
                    start_i = i
                    end_i = i + 1
                    while start_i - 1 >= int(getattr(sent, "start", 0)):
                        prev = doc[start_i - 1]
                        if getattr(prev, "pos_", "") == "PROPN":
                            start_i -= 1
                            continue
                        break
                    while end_i < int(getattr(sent, "end", 0)):
                        nxt = doc[end_i]
                        if getattr(nxt, "pos_", "") == "PROPN":
                            end_i += 1
                            continue
                        break
                    span = doc[start_i:end_i]
                    candidate_spans.append(span)
            except Exception:
                pass

            # Expand common "X of Y" structures where spaCy's `noun_chunks` only returns the base NP.
            # This is critical for worldbuilding terms like "Trading Guild of Yor" or "Essence of Dusk".
            try:
                for base in noun_chunks:
                    root = getattr(base, "root", None)
                    if root is None:
                        continue
                    for prep in getattr(root, "children", []):
                        if getattr(prep, "dep_", "") != "prep":
                            continue
                        if (getattr(prep, "lemma_", "") or "").lower() != "of":
                            continue
                        pobj = None
                        for child in getattr(prep, "children", []):
                            if getattr(child, "dep_", "") == "pobj":
                                pobj = child
                                break
                        if pobj is None:
                            continue
                        subtree = list(getattr(pobj, "subtree", []))
                        if not subtree:
                            continue
                        end_tok = max(subtree, key=lambda t: int(getattr(t, "i", 0)))
                        end_i = int(getattr(end_tok, "i", 0)) + 1
                        if end_i <= int(getattr(base, "start", 0)):
                            continue
                        expanded = doc[int(getattr(base, "start", 0)) : end_i]
                        candidate_spans.append(expanded)
            except Exception:
                pass

            for span in candidate_spans:
                try:
                    start = int(getattr(span, "start_char", 0))
                    end = int(getattr(span, "end_char", 0))
                except Exception:
                    continue
                if end <= start:
                    continue
                if _is_inside_ranges(start, end, code_ranges):
                    continue
                if (start, end) in seen_ranges:
                    continue

                tokens = [t for t in span if not getattr(t, "is_space", False)]
                # Skip spans that include verbs in a non-modifier role; these are usually
                # sentence-fragment artifacts (e.g. "balconies jut", "smoke curls") rather than mentions.
                # Allow gerund/participle modifiers ("Singing Tree") where the VERB token is acting as `amod/compound`.
                bad_verb = False
                for t in tokens:
                    if getattr(t, "pos_", "") not in {"VERB", "AUX"}:
                        continue
                    if getattr(t, "dep_", "") in {"amod", "compound"}:
                        continue
                    bad_verb = True
                    break
                if bad_verb:
                    continue
                tokens = _canonicalize_span_tokens(tokens)
                if not tokens:
                    continue
                # Trim leading/trailing punctuation tokens so quoted/parenthesized terms
                # ("smørrebrød", (The Shadow)) normalize cleanly.
                while tokens and (
                    getattr(tokens[0], "pos_", "") == "PUNCT" or getattr(tokens[0], "text", "") in {"“", "”", "\"", "'", "(", ")", "[", "]"}
                ):
                    tokens = tokens[1:]
                while tokens and (
                    getattr(tokens[-1], "pos_", "") == "PUNCT" or getattr(tokens[-1], "text", "") in {"“", "”", "\"", "'", "(", ")", "[", "]"}
                ):
                    tokens = tokens[:-1]
                if not tokens:
                    continue
                # Drop determiners immediately after "of" ("X of the Y" -> "X of Y") to keep canonical keys stable.
                filtered: List[object] = []
                prev_lemma = ""
                for t in tokens:
                    lemma = (getattr(t, "lemma_", "") or "").lower()
                    if prev_lemma == "of" and getattr(t, "pos_", "") == "DET" and lemma in {"the", "a", "an"}:
                        prev_lemma = lemma
                        continue
                    filtered.append(t)
                    prev_lemma = lemma
                tokens = filtered
                if not tokens:
                    continue
                span_start = int(getattr(tokens[0], "idx", start))
                last = tokens[-1]
                span_end = int(getattr(last, "idx", end) + len(getattr(last, "text", "")))
                if span_end <= span_start:
                    continue

                head = getattr(span, "root", None) or last
                head_pos = getattr(head, "pos_", "")
                if head_pos not in {"NOUN", "PROPN"}:
                    continue
                surface = (cleaned[span_start:span_end] or "").strip()
                if not surface:
                    continue
                # Reject spans that include newlines or are polluted by markdown structure.
                if "\n" in surface:
                    continue
                if surface.lstrip().startswith(("#", "-", "*", ">", "`")):
                    continue
                if re.match(r"^\d+(\.\d+)*\b", surface.strip()):
                    continue
                canonical = surface if head_pos == "PROPN" else surface.lower()
                canonical_key = _normalize_for_key(canonical)
                if not canonical_key:
                    continue
                if canonical_key[:1].isdigit():
                    continue
                if len(canonical_key) < 3 and head_pos != "PROPN":
                    continue

                # Reject if the first token is still a function word after canonicalization.
                first_token_pos = getattr(tokens[0], "pos_", "")
                if first_token_pos in {"DET", "ADP", "PRON", "ADV", "CCONJ", "SCONJ", "PART"}:
                    continue

                sentence_info = find_sentence(span_start, span_end)
                if sentence_info is None:
                    continue
                sentence_id, sent_dense = sentence_info

                dep_role = str(getattr(head, "dep_", "") or "")
                head_lemma = str(getattr(head, "lemma_", "") or canonical_key)
                mid = str(uuid.uuid5(_GLOSSARY_NAMESPACE, f"{note_id}:m:{span_start}:{span_end}:{canonical_key}"))
                mentions.append(
                    MentionRecord(
                        mention_id=mid,
                        note_id=note_id,
                        sentence_id=sentence_id,
                        start=span_start,
                        end=span_end,
                        surface_text=surface,
                        canonical_text=canonical,
                        head_lemma=head_lemma,
                        head_pos=head_pos,
                        dep_role=dep_role,
                        context_dense=list(sent_dense),
                    )
                )
                seen_ranges.add((start, end))

        if doc is None:
            raise RuntimeError("Glossary: spaCy returned no Doc; fallbacks are disabled.")
            # Fallback mention extraction (no spaCy): conservative phrase extraction.
            # Use spaces/tabs only between tokens to avoid crossing newlines/headings.
            cap_re = re.compile(r"\b(?:[A-Z][A-Za-z0-9'_-]*)(?:[ \t]+[A-Z][A-Za-z0-9'_-]*){0,4}\b")
            # Latin binomials: "Olea europaea"
            binomial_re = re.compile(r"\b[A-Z][a-z]{2,}[ \t]+[a-z]{2,}\b")
            # TitleCase "X of Y" phrases (common in worldbuilding: "Trading Guild of Yor", "Essence of Dusk").
            of_title_re = re.compile(
                r"\b([A-Z][A-Za-z0-9'_-]*(?:[ \t]+[A-Z][A-Za-z0-9'_-]*){0,3}[ \t]+of[ \t]+(?:the[ \t]+)?[A-Z][A-Za-z0-9'_-]*(?:[ \t]+[A-Z][A-Za-z0-9'_-]*){0,3})\b"
            )
            # Definitional subjects and named subtypes in plain text.
            subj_det_re = re.compile(
                r"(?i)^(?:the|a|an)\s+"
                r"([A-Za-z0-9][A-Za-z0-9_'-]*(?:\s+[A-Za-z0-9][A-Za-z0-9_'-]*){0,6})"
                r"(?:\s*(?:\([^)\n]{1,50}\)|,\s*[^,\n]{1,50},)\s*)?"
                r"\s+(?:is|are|was|were|would|can|will)\b"
            )
            called_re = re.compile(
                # Require an explicit article to avoid false positives like "called because …".
                r"(?i)\b(?:called|known as|referred to as)\s+(?:the|an|a)\s+([A-Za-z0-9][A-Za-z0-9_'-]*(?:\s+[A-Za-z0-9][A-Za-z0-9_'-]*){0,6})"
            )

            seen: Set[Tuple[int, int]] = set()
            leading_drop = {
                "in",
                "at",
                "on",
                "of",
                "for",
                "to",
                "from",
                "with",
                "by",
                "into",
                "over",
                "under",
                "within",
            }

            for s in sentences:
                # Add binomial mentions first.
                for m in binomial_re.finditer(s.text or ""):
                    rel_start, rel_end = m.start(), m.end()
                    if rel_end <= rel_start:
                        continue
                    start = int(s.start) + int(rel_start)
                    end = int(s.start) + int(rel_end)
                    if (start, end) in seen:
                        continue
                    surface = (cleaned[start:end] or "").strip()
                    if not surface:
                        continue
                    parts = [p for p in re.findall(r"[A-Za-z0-9'_-]+", surface) if p]
                    if len(parts) != 2:
                        continue
                    a, b = parts[0], parts[1]
                    a0 = a.lower()
                    b0 = b.lower()
                    # Reject trivial sentence-start patterns like "Breakfast is", "People around", "Dinners are".
                    if a0 in _FUNCTION_WORD_CANDIDATES or a0 in _GENERIC_NOUN_CANDIDATES or a0 in _QUANTIFIER_LEMMAS:
                        continue
                    if b0 in _FUNCTION_WORD_CANDIDATES or b0 in _GENERIC_NOUN_CANDIDATES or b0 in _QUANTIFIER_LEMMAS:
                        continue
                    # Avoid capturing ordinary sentence starts like "Sandwiches can", "Meals have".
                    # Latin genus names are rarely plural.
                    if a0.endswith("s") and not a0.endswith("us"):
                        continue
                    # Require a likely Latin-ish/descriptor second token (letters only, not tiny).
                    if len(b0) < 5 or not re.fullmatch(r"[a-z]+", b0):
                        continue
                    # Require common Latin epithet endings to avoid capturing ordinary phrases like
                    # "Ibnasi itself" or "Essence behaves".
                    if not re.search(r"(a|ae|um|us|is|ii|ensis)$", b0):
                        continue
                    canonical_key = _normalize_for_key(surface)
                    if not canonical_key or len(canonical_key) < 3:
                        continue
                    mid = str(uuid.uuid5(_GLOSSARY_NAMESPACE, f"{note_id}:m:{start}:{end}:{canonical_key}"))
                    mentions.append(
                        MentionRecord(
                            mention_id=mid,
                            note_id=note_id,
                            sentence_id=s.sentence_id,
                            start=start,
                            end=end,
                            surface_text=surface,
                            canonical_text=surface,
                            head_lemma=canonical_key,
                            head_pos="PROPN",
                            dep_role="",
                            context_dense=list(s.dense),
                        )
                    )
                    seen.add((start, end))

                # Quoted terms (supports fictional/non-English like “smørrebrød”).
                for qm in _FALLBACK_QUOTE_RE.finditer(s.text or ""):
                    rel_start = qm.start(1)
                    rel_end = qm.end(1)
                    if rel_end <= rel_start:
                        continue
                    start = int(s.start) + int(rel_start)
                    end = int(s.start) + int(rel_end)
                    surface = (cleaned[start:end] or "").strip()
                    _add_fallback_mention(
                        mentions=mentions,
                        seen=seen,
                        note_id=note_id,
                        sentence=s,
                        cleaned=cleaned,
                        start=start,
                        end=end,
                        surface=surface,
                        head_pos=_fallback_head_pos(surface),
                    )

                # Definitional subject patterns (captures lowercase multiword terms like "club sandwich").
                sm = subj_det_re.search(s.text or "")
                if sm:
                    rel_start = sm.start(1)
                    rel_end = sm.end(1)
                    start = int(s.start) + int(rel_start)
                    end = int(s.start) + int(rel_end)
                    surface = (cleaned[start:end] or "").strip()
                    if surface:
                        _add_fallback_mention(
                            mentions=mentions,
                            seen=seen,
                            note_id=note_id,
                            sentence=s,
                            cleaned=cleaned,
                            start=start,
                            end=end,
                            surface=surface,
                            head_pos=_fallback_head_pos(surface, sentence_start=True),
                        )

                # TitleCase "X of Y" mentions anywhere in the sentence.
                for om in of_title_re.finditer(s.text or ""):
                    rel_start, rel_end = om.start(1), om.end(1)
                    if rel_end <= rel_start:
                        continue
                    start = int(s.start) + int(rel_start)
                    end = int(s.start) + int(rel_end)
                    surface = (cleaned[start:end] or "").strip()
                    if surface:
                        _add_fallback_mention(
                            mentions=mentions,
                            seen=seen,
                            note_id=note_id,
                            sentence=s,
                            cleaned=cleaned,
                            start=start,
                            end=end,
                            surface=surface,
                            head_pos="PROPN",
                        )

                # "called/known as/referred to as <term>"
                for cm in called_re.finditer(s.text or ""):
                    rel_start = cm.start(1)
                    rel_end = cm.end(1)
                    start = int(s.start) + int(rel_start)
                    end = int(s.start) + int(rel_end)
                    surface = (cleaned[start:end] or "").strip()
                    _add_fallback_mention(
                        mentions=mentions,
                        seen=seen,
                        note_id=note_id,
                        sentence=s,
                        cleaned=cleaned,
                        start=start,
                        end=end,
                        surface=surface,
                        head_pos=_fallback_head_pos(surface),
                    )

                for m in cap_re.finditer(s.text or ""):
                    rel_start, rel_end = m.start(), m.end()
                    if rel_end <= rel_start:
                        continue
                    start = int(s.start) + int(rel_start)
                    end = int(s.start) + int(rel_end)
                    if (start, end) in seen:
                        continue
                    surface = (cleaned[start:end] or "").strip()
                    if not surface:
                        continue
                    words = [w for w in re.findall(r"[A-Za-z0-9'_-]+", surface) if w]
                    if not words:
                        continue
                    w0 = words[0].lower()
                    if w0 in _QUANTIFIER_LEMMAS and len(words) == 1:
                        continue
                    if (w0 in leading_drop or w0 in _QUANTIFIER_LEMMAS or w0 in {"the", "a", "an"}) and len(words) >= 2:
                        surface = " ".join(words[1:]).strip()
                        if not surface:
                            continue
                        words = [w for w in re.findall(r"[A-Za-z0-9'_-]+", surface) if w]
                        if not words:
                            continue
                        w0 = words[0].lower()
                    if w0 in _FUNCTION_WORD_CANDIDATES or w0 in _GENERIC_NOUN_CANDIDATES:
                        continue
                    canonical_key = _normalize_for_key(surface)
                    if not canonical_key or len(canonical_key) < 3:
                        continue
                    if canonical_key in _FUNCTION_WORD_CANDIDATES or canonical_key in _GENERIC_NOUN_CANDIDATES:
                        continue
                    sentence_start = not any(ch.isalpha() for ch in (s.text or "")[: int(rel_start)])
                    _add_fallback_mention(
                        mentions=mentions,
                        seen=seen,
                        note_id=note_id,
                        sentence=s,
                        cleaned=cleaned,
                        start=start,
                        end=end,
                        surface=surface,
                        head_pos=_fallback_head_pos(surface, sentence_start=sentence_start),
                    )

        self._last_extract_used_spacy = bool(used_spacy)
        return NoteExtract(note_id=note_id, text_hash=note_hash, sentences=sentences, mentions=mentions)

    def _recompute_entities_and_entries(self) -> None:
        embedder = self.embedder or ContextEmbedder("BAAI/bge-small-en-v1.5")
        reranker = self.reranker

        with self._lock:
            extracts = list(self._notes.values())
        total_notes = max(1, len({ex.note_id for ex in extracts}))

        # Group mentions by canonical candidate key.
        candidates: Dict[str, Dict] = {}
        sentence_lookup: Dict[str, SentenceRecord] = {}
        for ex in extracts:
            for sent in ex.sentences:
                sentence_lookup[sent.sentence_id] = sent
            for m in ex.mentions:
                key = _normalize_for_key(m.canonical_text)
                if not key:
                    continue
                if key in _FUNCTION_WORD_CANDIDATES or key in _GENERIC_NOUN_CANDIDATES or key in _GENERIC_CONCEPT_BLACKLIST:
                    continue
                # Reject candidates that are all stopwords.
                toks = [t for t in key.split() if t]
                if toks and all(t in _GLOSSARY_STOPWORDS for t in toks):
                    continue
                entry = candidates.setdefault(
                    key,
                    {
                        "mentions": [],
                        "surface_counts": {},
                        "has_propn": False,
                        "ref": 0,
                        "mod": 0,
                        "heading_hits": 0,
                        "sent_start": 0,
                        "def_hits": 0,
                        "cap_total": 0,
                        "cap_nonstart": 0,
                        "note_ids": set(),
                    },
                )
                entry["mentions"].append(m)
                entry["surface_counts"][m.surface_text] = int(entry["surface_counts"].get(m.surface_text, 0) + 1)
                if m.head_pos == "PROPN":
                    entry["has_propn"] = True
                if m.dep_role in _REF_ROLES:
                    entry["ref"] += 1
                if m.dep_role in _MOD_ROLES:
                    entry["mod"] += 1
                entry["note_ids"].add(m.note_id)
                sent = sentence_lookup.get(m.sentence_id)
                if sent is not None:
                    if abs(int(m.start) - int(sent.start)) <= 1:
                        entry["sent_start"] += 1
                    if sent.heading and re.search(rf"(?i)\\b{re.escape(key)}\\b", sent.heading):
                        entry["heading_hits"] += 1
                    if (m.surface_text or "")[:1].isupper():
                        entry["cap_total"] += 1
                        # Capitalization away from sentence start is a stronger signal of a named entity/term.
                        if int(m.start) > int(sent.start) + 1:
                            entry["cap_nonstart"] += 1
                    # Definitional cue: mention followed by a copula/modal ("X is …", "X, for example, is …").
                    try:
                        rel_end = int(m.end) - int(sent.start)
                        if 0 <= rel_end <= len(sent.text or ""):
                            tail = (sent.text or "")[rel_end : rel_end + 80]
                            if re.match(
                                r"(?is)^\s*(?:[\"”'’)\]]\s*)*(?:,?\s*(?:for example|e\.g\.)\s*,)?\s*(?:is|are|was|were|can be|means|refers to)\b",
                                tail,
                            ):
                                entry["def_hits"] += 1
                    except Exception:
                        pass
                    # Definitional cue: mention introduced after "called/known as/referred to as"
                    # (e.g. "… called an open sandwich", where the mention is at sentence end).
                    try:
                        rel_start = int(m.start) - int(sent.start)
                        if 0 <= rel_start <= len(sent.text or ""):
                            prefix = (sent.text or "")[max(0, rel_start - 80) : rel_start]
                            if re.search(
                                r"(?is)\b(?:called|known as|referred to as)\s+(?:the|a|an)\s*$",
                                prefix,
                            ):
                                entry["def_hits"] += 1
                    except Exception:
                        pass

        # Termhood filter.
        try:
            thresh = float(os.environ.get("GRIMOIRE_GLOSSARY_TERMHOOD_THRESH", "0.65"))
        except Exception:
            thresh = 0.65

        # Type word lexicons (editable).
        person_words = (
            set((os.environ.get("GRIMOIRE_GLOSSARY_PERSON_WORDS") or "").split(","))
            if os.environ.get("GRIMOIRE_GLOSSARY_PERSON_WORDS")
            else {"king", "queen", "knight", "witch", "merchant", "child", "priest", "soldier", "wizard"}
        )
        place_words = (
            set((os.environ.get("GRIMOIRE_GLOSSARY_PLACE_WORDS") or "").split(","))
            if os.environ.get("GRIMOIRE_GLOSSARY_PLACE_WORDS")
            else {
                "city",
                "kingdom",
                "empire",
                "realm",
                "forest",
                "mountain",
                "river",
                "lake",
                "sea",
                "desert",
                "valley",
                "castle",
                "temple",
            }
        )
        thing_words = (
            set((os.environ.get("GRIMOIRE_GLOSSARY_THING_WORDS") or "").split(","))
            if os.environ.get("GRIMOIRE_GLOSSARY_THING_WORDS")
            else {"sword", "relic", "artifact", "treaty", "disease", "spell", "book", "ring", "map"}
        )
        type_words = set(w.strip().lower() for w in (person_words | place_words | thing_words) if w.strip())

        accepted: Dict[str, Dict] = {}
        for key, meta in candidates.items():
            mentions = meta["mentions"]
            total = len(mentions)
            if total <= 0:
                continue

            if key in _FUNCTION_WORD_CANDIDATES or key in _GENERIC_NOUN_CANDIDATES or key in _GENERIC_CONCEPT_BLACKLIST:
                continue
            words = key.split()

            # Context tightness: mean cosine similarity to centroid.
            # NOTE: With only 1 mention, this would trivially be 1.0; treat as unknown (0.0).
            vecs = [_normalize_dense(m.context_dense) for m in mentions if m.context_dense]
            tight = 0.0
            if len(vecs) >= 2:
                centroid = _normalize_dense(np.mean(np.stack(vecs), axis=0))
                sims = [float(_dot(centroid, v)) for v in vecs]
                tight = float(np.mean(sims)) if sims else 0.0

            # Suppress generic type nouns unless they're being used as a named entity.
            # This prevents glossary entries like "city" / "spells" while still allowing specific names
            # like "Lantern Quarter" (multiword) or "The Institute" (capitalized mid-sentence).
            key_singular = _maybe_singularize_phrase(key) if len(words) == 1 else key
            if key_singular in type_words and len(words) == 1 and int(meta.get("heading_hits") or 0) == 0:
                # If it isn't an acronym or consistently capitalized away from sentence-start, treat it as generic.
                if not any(str(s).isupper() and len(str(s)) >= 2 for s in (meta.get("surface_counts") or {}).keys()):
                    cap_nonstart = int(meta.get("cap_nonstart") or 0)
                    if cap_nonstart < 2:
                        continue

            has_syntax = (int(meta.get("ref") or 0) + int(meta.get("mod") or 0)) > 0

            f_ref = float(meta["ref"]) / float(total)
            f_mod = float(meta["mod"]) / float(total)
            surface_counts: Dict[str, int] = meta.get("surface_counts") or {}
            is_acronym = any(str(s).isupper() and len(str(s)) >= 2 for s in surface_counts.keys())
            df_ratio = float(len(meta.get("note_ids") or set())) / float(total_notes)
            f_sent_start = float(meta.get("sent_start") or 0) / float(total)
            f_heading = 1.0 if int(meta.get("heading_hits") or 0) > 0 else 0.0
            f_def = float(meta.get("def_hits") or 0) / float(total)
            f_cap_nonstart = float(meta.get("cap_nonstart") or 0) / float(total)
            # Repetition helps common-noun multiword terms (e.g. "open sandwich") without requiring
            # capitalization or an explicit "X is ..." pattern.
            f_repeat = float(min(1.0, float(np.log(float(total) + 1.0)) / float(np.log(6.0))))
            # "Effective" PROPN: require capitalization away from sentence start (or acronym) so generic nouns
            # capitalized at headings/sentence starts don't become entities.
            has_propn_effective = bool(meta.get("has_propn") and (is_acronym or f_cap_nonstart >= 0.20))
            is_propn = 1.0 if has_propn_effective else 0.0

            # For non-PROPN candidates, require repeated mention / heading hit, OR a definitional cue.
            # This allows domain terms like "club sandwich" that appear once in a definitional sentence.
            if not has_propn_effective and total < 2 and f_heading < 1.0:
                allow_definitional = len(words) >= 2 and f_def >= 0.8 and f_ref >= 0.6
                # Also allow singleton multiword titlecase terms (e.g. "Essence of Dawn") which often
                # appear only once in a corpus but are still core glossary entities.
                allow_titlecase = False
                if len(words) >= 2:
                    best_title = 0
                    for s in surface_counts.keys():
                        s = str(s or "").strip()
                        if not s:
                            continue
                        toks = [t for t in re.findall(r"[A-Za-z][A-Za-z'_-]*", s) if t]
                        if not toks:
                            continue
                        title = sum(1 for t in toks if t[:1].isupper())
                        best_title = max(best_title, title)
                    allow_titlecase = best_title >= 2
                # Avoid ordinal-ish adjective leads ("first day") in the single-mention definitional exception.
                if allow_definitional and words and words[0] in _FUNCTION_WORD_CANDIDATES:
                    allow_definitional = False
                if not allow_definitional and not allow_titlecase:
                    continue
            # Additional filter for spaCy noun phrases: keep single-word common nouns out unless strongly term-like.
            if not has_propn_effective:
                if len(words) == 1:
                    # Keep if it's in a heading, used as a proper-ish capitalized term mid-sentence, or appears
                    # in an explicit definitional pattern.
                    cap_nonstart = int(meta.get("cap_nonstart") or 0)
                    # Or: appears repeatedly in a tight, consistent context (helps domain terms like "lich").
                    min_count = int(os.environ.get("GRIMOIRE_GLOSSARY_SINGLE_NOUN_MIN_COUNT", "6"))
                    min_tight = float(os.environ.get("GRIMOIRE_GLOSSARY_SINGLE_NOUN_MIN_TIGHT", "0.88"))
                    if f_heading < 1.0 and cap_nonstart < 2 and f_def < 0.6 and not (total >= min_count and tight >= min_tight and f_ref >= 0.4):
                        continue
                else:
                    # Multiword lowercase noun phrases can be descriptive junk ("clear water") unless repeated
                    # or introduced definitionally.
                    if f_heading < 1.0 and int(meta.get("cap_nonstart") or 0) == 0 and f_def < 0.6 and total < 2:
                        continue
                    # If the phrase only appears twice and has no definitional/heading/caps signal, require
                    # a tight context so we don't promote generic descriptive phrases.
                    if f_heading < 1.0 and int(meta.get("cap_nonstart") or 0) == 0 and f_def < 0.6 and total == 2 and tight < float(
                        os.environ.get("GRIMOIRE_GLOSSARY_MULTI_NOUN_MIN_TIGHT", "0.90")
                    ):
                        continue

            # Unithood: encourage stable multiword expressions.
            unithood = 0.0
            if len(words) >= 2 and total >= 2:
                unithood = min(1.0, float(np.log(total + 1.0)) / 2.0)
            elif len(words) >= 2 and total == 1:
                unithood = 0.25

            # Fallback-specific: suppress singleton single-word candidates unless strong evidence.
            if (
                not has_syntax
                and total == 1
                and len(words) == 1
                and not is_acronym
                and f_heading < 1.0
                and f_def < 0.8
            ):
                continue

            if has_syntax:
                # Full scoring when spaCy roles are available.
                score = (
                    1.2 * f_ref
                    - 1.0 * f_mod
                    + 0.7 * is_propn
                    + 0.6 * tight
                    + 0.35 * unithood
                    + 0.25 * f_repeat
                    + (0.12 if len(words) >= 2 else 0.0)
                    + 0.25 * f_heading
                    + 0.55 * f_def
                    - 0.45 * df_ratio
                    - 0.35 * f_sent_start * (1.0 - min(1.0, f_def))
                )
            else:
                # Fallback scoring (no spaCy): rely on repetition + PROPN + tightness.
                score = (
                    0.9 * is_propn
                    + 0.7 * tight
                    + 0.35 * unithood
                    + 0.25 * f_repeat
                    + (0.12 if len(words) >= 2 else 0.0)
                    + 0.35 * f_heading
                    + 0.55 * f_def
                    - 0.25 * df_ratio
            )

            # Conservative fallback: allow proper nouns that appear referentially.
            if has_propn_effective and (has_syntax and f_ref >= 0.2):
                accepted[key] = {**meta, "termhood": float(score)}
                continue
            # No-syntax fallback: accept repeated/heading/acronym/multiword proper nouns.
            if has_propn_effective and (not has_syntax) and (total >= 2 or f_heading >= 1.0 or is_acronym or len(words) >= 2):
                accepted[key] = {**meta, "termhood": float(score)}
                continue
            if score >= thresh:
                accepted[key] = {**meta, "termhood": float(score)}

        if not accepted:
            with self._lock:
                self._entities = {}
                self._entries = {}
            return

        # Build per-sentence mention lists for alias edges + co-occurrence.
        mentions_by_sentence: Dict[str, List[MentionRecord]] = {}
        for key, meta in accepted.items():
            for m in meta["mentions"]:
                mentions_by_sentence.setdefault(m.sentence_id, []).append(m)

        alias_edges: Set[Tuple[str, str]] = set()
        for sid, ms in mentions_by_sentence.items():
            sent = sentence_lookup.get(sid)
            if sent is None:
                continue
            alias_edges |= _explicit_alias_edges(sent.text, sent.start, ms)

        # Candidate centroid embeddings.
        centroids: Dict[str, np.ndarray] = {}
        for key, meta in accepted.items():
            vecs = [_normalize_dense(m.context_dense) for m in meta["mentions"] if m.context_dense]
            if not vecs:
                continue
            centroids[key] = _normalize_dense(np.mean(np.stack(vecs), axis=0))

        # Build token -> candidate ids for limited pair comparisons.
        token_df: Dict[str, int] = {}
        for key in accepted.keys():
            toks = {t for t in key.split() if len(t) >= 4}
            for t in toks:
                token_df[t] = int(token_df.get(t, 0) + 1)

        try:
            max_df_ratio = float(os.environ.get("GRIMOIRE_GLOSSARY_ALIAS_TOKEN_MAX_DF_RATIO", "0.35"))
        except Exception:
            max_df_ratio = 0.35
        max_df = max(1, int(round(max_df_ratio * float(max(1, len(accepted))))))

        token_to_keys: Dict[str, Set[str]] = {}
        for key in accepted.keys():
            for tok in key.split():
                if len(tok) < 4:
                    continue
                # Ignore very common tokens (e.g. shared heads like "sandwich") to avoid over-merging.
                if int(token_df.get(tok, 0)) > max_df:
                    continue
                token_to_keys.setdefault(tok, set()).add(key)

        def alias_token_set(key: str) -> Set[str]:
            toks = [t for t in key.split() if t]
            out = set()
            for t in toks:
                if t in _GLOSSARY_STOPWORDS:
                    continue
                if len(t) < 3:
                    continue
                out.add(t)
            return out

        # Union-find clustering.
        parent: Dict[str, str] = {k: k for k in accepted.keys()}

        def find(x: str) -> str:
            while parent.get(x, x) != x:
                parent[x] = parent[parent[x]]
                x = parent[x]
            return x

        def union(a: str, b: str):
            ra = find(a)
            rb = find(b)
            if ra == rb:
                return
            # Deterministic: keep lexicographically smaller rep.
            if ra < rb:
                parent[rb] = ra
            else:
                parent[ra] = rb

        # Apply explicit alias edges first.
        for a, b in sorted(alias_edges):
            if a in accepted and b in accepted:
                union(a, b)

        # Similarity-based merges (conservative).
        try:
            sim_tau = float(os.environ.get("GRIMOIRE_GLOSSARY_ALIAS_SIM_TAU", "0.90"))
        except Exception:
            sim_tau = 0.90

        compared: Set[Tuple[str, str]] = set()
        for tok, keys in token_to_keys.items():
            keys_list = sorted(keys)
            for i in range(len(keys_list)):
                for j in range(i + 1, len(keys_list)):
                    a = keys_list[i]
                    b = keys_list[j]
                    pair = (a, b)
                    if pair in compared:
                        continue
                    compared.add(pair)
                    va = centroids.get(a)
                    vb = centroids.get(b)
                    if va is None or vb is None:
                        continue
                    # Avoid merging headed phrases with their heads/components via pure similarity.
                    # "Essence of Dusk" should not become an alias of "Dusk".
                    ta = alias_token_set(a)
                    tb = alias_token_set(b)
                    if ta and tb and (ta.issubset(tb) or tb.issubset(ta)) and abs(len(ta) - len(tb)) >= 1:
                        continue
                    sim = float(_dot(va, vb))
                    if sim >= sim_tau:
                        union(a, b)
                        continue
                    if _bounded_edit_distance(a, b, max_dist=2) <= 2 and sim >= 0.75:
                        union(a, b)

        clusters: Dict[str, List[str]] = {}
        for key in accepted.keys():
            clusters.setdefault(find(key), []).append(key)
        for rep in clusters:
            clusters[rep] = sorted(clusters[rep])

        # Build entities + entries.
        entities: Dict[str, EntityRecord] = {}
        entries: Dict[str, GlossaryEntry] = {}

        def infer_kind(sentence_texts: List[str], headings: List[Optional[str]]) -> str:
            votes = {"person": 0.0, "place": 0.0, "thing": 0.0}
            for h in headings:
                if not h:
                    continue
                hl = h.lower()
                if any(k in hl for k in ("characters", "people", "persons", "cast")):
                    votes["person"] += 0.75
                if any(k in hl for k in ("places", "locations", "setting")):
                    votes["place"] += 0.75
                if any(k in hl for k in ("items", "artifacts", "things")):
                    votes["thing"] += 0.75
            for t in sentence_texts:
                low = t.lower()
                # Copula/apposition-like signals: "X is a <typeword>"
                m = re.search(r"\bis a[n]?\s+([a-z][a-z-]{2,})", low)
                if m:
                    w = m.group(1)
                    if w in person_words:
                        votes["person"] += 1.0
                    if w in place_words:
                        votes["place"] += 1.0
                    if w in thing_words:
                        votes["thing"] += 1.0
            best = max(votes.items(), key=lambda kv: kv[1])
            if best[1] >= 1.25:
                return best[0]
            return "unknown"

        def pick_canonical(surface_counts: Dict[str, int], sentence_headings: List[Optional[str]]) -> str:
            # Prefer a surface form that appears in a heading.
            heading_text = " ".join([h for h in sentence_headings if h])
            for name, _ in sorted(surface_counts.items(), key=lambda kv: (-kv[1], -len(kv[0]), kv[0].lower())):
                if name and heading_text and re.search(rf"(?i)\\b{re.escape(name)}\\b", heading_text):
                    return name
            # Otherwise most frequent.
            items = sorted(surface_counts.items(), key=lambda kv: (-kv[1], -len(kv[0]), kv[0].lower()))
            if not items:
                return ""
            chosen = items[0][0]

            # Prefer singular surface forms when a close singular alternative exists.
            # This keeps entries like "Essence of Dusk" instead of "Essences of Dusk" when both occur.
            parts = [p for p in str(chosen).split() if p]
            if len(parts) >= 1:
                first_singular = _maybe_singularize_phrase(parts[0])
                last_singular = _maybe_singularize_phrase(parts[-1])
                variants: List[List[str]] = []
                if first_singular and first_singular != parts[0]:
                    variants.append([first_singular] + parts[1:])
                if last_singular and last_singular != parts[-1]:
                    variants.append(parts[:-1] + [last_singular])
                if first_singular and last_singular and (first_singular != parts[0] or last_singular != parts[-1]):
                    variants.append([first_singular] + parts[1:-1] + [last_singular] if len(parts) >= 2 else [first_singular])

                lowered = {k.lower(): k for k, _ in items}
                for v in variants:
                    cand = " ".join(v).strip()
                    if cand.lower() in lowered:
                        chosen = lowered[cand.lower()]
                        break

            return chosen

        for rep, keys in sorted(clusters.items(), key=lambda kv: kv[0]):
            # Stable entity id from cluster membership.
            cluster_key = "|".join(keys)
            entity_id = str(uuid.uuid5(_GLOSSARY_NAMESPACE, f"entity:{cluster_key}"))

            merged_surface: Dict[str, int] = {}
            merged_mentions: List[MentionRecord] = []
            for k in keys:
                meta = accepted.get(k) or {}
                merged_mentions.extend(meta.get("mentions") or [])
                for s, c in (meta.get("surface_counts") or {}).items():
                    merged_surface[s] = int(merged_surface.get(s, 0) + int(c))

            merged_mentions.sort(key=lambda m: (m.note_id, m.start, m.end))
            mention_ids = [m.mention_id for m in merged_mentions]
            chunk_ids = sorted({sentence_lookup.get(m.sentence_id).chunk_id for m in merged_mentions if sentence_lookup.get(m.sentence_id) is not None})

            sentence_ids = sorted({m.sentence_id for m in merged_mentions})
            candidate_sents = [sentence_lookup[sid] for sid in sentence_ids if sid in sentence_lookup]

            # Definition selection (verbatim sentences).
            scored_sentences: List[Tuple[float, SentenceRecord]] = []
            canonical_name = pick_canonical(merged_surface, [s.heading for s in candidate_sents])
            if not canonical_name:
                continue

            docs = [s.text for s in candidate_sents]
            ce_scores = reranker.score(canonical_name, docs) if reranker is not None else None
            ce_norm = [0.0] * len(candidate_sents)
            if ce_scores:
                lo = min(ce_scores)
                hi = max(ce_scores)
                denom = (hi - lo) if (hi - lo) > 1e-9 else None
                for i, v in enumerate(ce_scores):
                    ce_norm[i] = float((v - lo) / denom) if denom is not None else 0.0

            for i, s in enumerate(candidate_sents):
                if _is_low_information_text(s.text):
                    continue
                soft = 0.0
                low = s.text.lower()
                if re.search(rf"(?i)\\b{re.escape(canonical_name)}\\b\\s+is\\b", s.text):
                    soft += 0.3
                if _token_count(s.text) < 6:
                    soft -= 0.2
                if _token_count(s.text) > 80:
                    soft -= 0.2
                if re.match(r"^\\s*([-*+]|(\\d+[\\.)]))\\s+", s.text):
                    soft -= 0.2
                score = 1.0 * ce_norm[i] + 0.25 * soft
                scored_sentences.append((score, s))

            if not scored_sentences:
                continue
            scored_sentences.sort(key=lambda t: (-t[0], t[1].sentence_id))

            # MMR-like diversity selection (avoid near-duplicates).
            chosen: List[SentenceRecord] = []
            chosen_ids: List[str] = []
            for score, s in scored_sentences:
                if len(chosen) >= 3:
                    break
                if not chosen:
                    chosen.append(s)
                    chosen_ids.append(s.sentence_id)
                    continue
                s_vec = _normalize_dense(s.dense)
                too_similar = False
                for prev in chosen:
                    pv = _normalize_dense(prev.dense)
                    if pv.size and s_vec.size and float(_dot(pv, s_vec)) >= 0.92:
                        too_similar = True
                        break
                if not too_similar:
                    chosen.append(s)
                    chosen_ids.append(s.sentence_id)

            definition_excerpt = " ".join([c.text.strip() for c in chosen]).strip()
            definition_excerpt = _sentences_excerpt(definition_excerpt, max_sentences=3, max_chars=700)
            source_note_id = chosen[0].note_id if chosen else None
            definition_chunk_id = chosen[0].chunk_id if chosen else None

            kind = infer_kind([s.text for s in candidate_sents], [s.heading for s in candidate_sents])
            kind = _entity_kind_label(kind)

            # Supporting passages: next best chunks (up to 2).
            supporting: List[Tuple[str, str, str]] = []
            for _, s in scored_sentences:
                if len(supporting) >= 3:
                    break
                if s.sentence_id in chosen_ids:
                    continue
                excerpt = _sentences_excerpt(s.text, max_sentences=2, max_chars=320)
                key = (s.chunk_id, s.note_id)
                if any(cid == key[0] for cid, _, _ in supporting):
                    continue
                supporting.append((s.chunk_id, s.note_id, excerpt))

            aliases = [k for k, _ in sorted(merged_surface.items(), key=lambda kv: (-kv[1], -len(kv[0]), kv[0].lower()))]
            aliases = aliases[:24]

            entities[entity_id] = EntityRecord(
                entity_id=entity_id,
                canonical_name=canonical_name,
                kind=kind,
                aliases=aliases,
                mention_ids=mention_ids,
                chunk_ids=chunk_ids,
                definition_sentence_ids=chosen_ids,
                definition_excerpt=definition_excerpt,
                definition_chunk_id=definition_chunk_id,
                source_note_id=source_note_id,
                score=float(scored_sentences[0][0]),
                supporting=supporting,
            )

            entries[entity_id] = GlossaryEntry(
                concept_id=entity_id,
                display_name=canonical_name,
                kind=kind,
                chunk_ids=chunk_ids,
                surface_forms=aliases[:12],
                definition_chunk_id=definition_chunk_id,
                definition_excerpt=definition_excerpt,
                source_note_id=source_note_id,
                last_updated=_now(),
                score=float(scored_sentences[0][0]),
                supporting=supporting,
            )

        with self._lock:
            self._entities = entities
            self._entries = entries

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------
    def _concept_uuid(self, concept_key: str) -> str:
        # Deterministic UUIDv5 derived from normalized concept key.
        return str(uuid.uuid5(_GLOSSARY_NAMESPACE, concept_key))

    def _concepts_for_note(self, note_id: str) -> Set[str]:
        raw = self._raw_concepts_for_note(note_id)
        if not raw:
            return set()
        if self._merge_map:
            return {self._merge_map.get(c, c) for c in raw}
        return raw

    def _raw_concepts_for_note(self, note_id: str) -> Set[str]:
        out: Set[str] = set()
        for meta in self.index.chunks_for_note(note_id):
            for cid in meta.get("concepts", []) or []:
                norm = _normalize_label(str(cid))
                if norm:
                    out.add(norm)
        return out

    def _concept_name_embedding(self, name: str) -> Optional[np.ndarray]:
        if not name:
            return None
        key = name.strip().lower()
        if key in self._name_vec_cache:
            return self._name_vec_cache[key]
        if self.embedder is None:
            return None
        vec = self.embedder.encode_dense(name)
        self._name_vec_cache[key] = vec
        return vec

    def _discover_concepts(self) -> Dict[str, Dict]:
        """Discover corpus concepts from indexed chunks (shared with retrieval)."""
        concepts: Dict[str, Dict] = {}
        for chunk_id in self.index.chunk_ids():
            meta = self.index.get_chunk(chunk_id)
            if not meta:
                continue
            labels_by_id = meta.get("concept_labels") or {}
            for concept_key in meta.get("concepts", []) or []:
                concept_key = _normalize_label(str(concept_key))
                if not concept_key or len(concept_key) < 3:
                    continue
                if concept_key in _GENERIC_CONCEPT_BLACKLIST:
                    continue
                entry = concepts.setdefault(
                    concept_key,
                    {"surface_forms": {}, "chunk_ids": set()},
                )
                label = labels_by_id.get(concept_key) or self.index.concept_label(concept_key) or concept_key
                label = str(label).strip() or concept_key
                entry["surface_forms"][label] = int(entry["surface_forms"].get(label, 0) + 1)
                entry["chunk_ids"].add(chunk_id)

        # Also include repeated n-grams (corpus-derived, no external knowledge).
        # Conservative defaults to avoid noise.
        try:
            min_ngram_count = int(os.environ.get("GRIMOIRE_GLOSSARY_NGRAM_MIN_COUNT", "4"))
        except Exception:
            min_ngram_count = 4
        max_ngram = int(os.environ.get("GRIMOIRE_GLOSSARY_NGRAM_MAX_N", "3") or 3)
        max_ngram = max(1, min(3, max_ngram))
        ngram_counts: Dict[str, int] = {}
        ngram_chunks: Dict[str, Set[str]] = {}
        ngram_label: Dict[str, str] = {}

        for chunk_id in self.index.chunk_ids():
            meta = self.index.get_chunk(chunk_id)
            if not meta:
                continue
            text = str(meta.get("text") or "")
            words = _tokenize_words(text)
            words = [w for w in words if len(w) >= 4 and w not in _GLOSSARY_STOPWORDS and not w.isdigit()]
            if not words:
                continue
            for n in range(1, max_ngram + 1):
                if len(words) < n:
                    continue
                for i in range(0, len(words) - n + 1):
                    gram_words = words[i : i + n]
                    if any(w in _GLOSSARY_STOPWORDS for w in gram_words):
                        continue
                    gram = " ".join(gram_words).strip()
                    if not gram:
                        continue
                    ngram_counts[gram] = int(ngram_counts.get(gram, 0) + 1)
                    ngram_chunks.setdefault(gram, set()).add(chunk_id)
                    ngram_label.setdefault(gram, gram)

        for gram, count in sorted(ngram_counts.items(), key=lambda kv: (-kv[1], kv[0])):
            if count < min_ngram_count:
                continue
            concept_key = _normalize_label(gram)
            if not concept_key or len(concept_key) < 3:
                continue
            if concept_key in _GENERIC_CONCEPT_BLACKLIST:
                continue
            if concept_key in concepts:
                continue
            concepts[concept_key] = {
                "surface_forms": {ngram_label.get(gram, gram): int(count)},
                "chunk_ids": set(ngram_chunks.get(gram, set())),
            }
        return concepts

    def _merge_variants(self, concepts: Dict[str, Dict], *, existing: Optional[Dict[str, str]] = None) -> Dict[str, str]:
        """Merge concept variants by edit distance and optional embedding similarity.

        Deterministic: compares in sorted order and always merges into the earliest representative.
        """
        keys = sorted(concepts.keys())
        rep: Dict[str, str] = {}

        try:
            max_edit = int(os.environ.get("GRIMOIRE_GLOSSARY_MERGE_EDIT_MAX", "2"))
        except Exception:
            max_edit = 2

        try:
            emb_tau = float(os.environ.get("GRIMOIRE_GLOSSARY_MERGE_EMB_TAU", "0.90"))
        except Exception:
            emb_tau = 0.90
        if self.embedder is None:
            emb_tau = 0.0

        reps: List[str] = []
        if existing:
            # Keep existing representatives to avoid concept-id churn.
            for k, v in (existing or {}).items():
                if k in concepts and v in concepts:
                    rep[str(k)] = str(v)

            # Collapse any chains deterministically.
            def resolve(x: str) -> str:
                seen: Set[str] = set()
                cur = x
                while cur in rep and rep[cur] != cur:
                    if cur in seen:
                        break
                    seen.add(cur)
                    cur = rep[cur]
                return cur if cur in concepts else x

            for k in list(rep.keys()):
                rep[k] = resolve(rep[k])
            reps = sorted({k for k, v in rep.items() if k == v and k in concepts})

        # Cache canonical names per concept key for stable comparisons.
        def canonical_name(key: str) -> str:
            forms = concepts.get(key, {}).get("surface_forms") or {}
            if forms:
                items = sorted(forms.items(), key=lambda kv: (-int(kv[1]), -len(str(kv[0])), str(kv[0]).lower()))
                return str(items[0][0])
            return self.index.concept_label(key) or key

        for key in keys:
            # Preserve an existing assignment (or rep) if present.
            if key in rep and rep.get(key) in concepts:
                if rep[key] not in reps:
                    reps.append(rep[key])
                continue

            merged_to: Optional[str] = None
            for r in reps:
                d = _levenshtein(key, r, max_dist=max_edit)
                if d <= max_edit:
                    merged_to = r
                    break
                if emb_tau > 0.0:
                    a = self._concept_name_embedding(canonical_name(key))
                    b = self._concept_name_embedding(canonical_name(r))
                    if a is None or b is None:
                        continue
                    if int(a.shape[0]) != int(b.shape[0]) or a.size == 0:
                        continue
                    sim = float(_dot(_normalize_dense(a), _normalize_dense(b)))
                    if sim >= emb_tau:
                        merged_to = r
                        break
            if merged_to is None:
                reps.append(key)
                rep[key] = key
            else:
                rep[key] = merged_to
        return rep

    def _extend_merge_map(self, concepts: Dict[str, Dict], raw_concepts: Set[str]) -> None:
        """Incrementally merge newly-seen concepts into the existing merge map."""
        if not raw_concepts:
            return
        if self._merge_map is None:
            self._merge_map = {}

        unknown = {c for c in raw_concepts if c not in self._merge_map}
        if not unknown:
            return

        updated = self._merge_variants(concepts, existing=self._merge_map)
        for key in unknown:
            if key in updated:
                self._merge_map[key] = updated[key]

    def _canonical_surface_forms(self, concept_key: str, concepts: Dict[str, Dict], merge_map: Dict[str, str]) -> List[str]:
        forms: Dict[str, int] = {}
        for key, meta in concepts.items():
            if merge_map.get(key, key) != concept_key:
                continue
            for label, count in (meta.get("surface_forms") or {}).items():
                forms[str(label)] = int(forms.get(str(label), 0) + int(count))
        items = sorted(forms.items(), key=lambda kv: (-kv[1], -len(kv[0]), kv[0].lower()))
        return [k for k, _ in items]

    def _build_entry_for_concept(
        self,
        concept_key: str,
        *,
        concepts: Optional[Dict[str, Dict]] = None,
        merge_map: Optional[Dict[str, str]] = None,
    ) -> Optional[GlossaryEntry]:
        concepts = concepts or self._discover_concepts()
        merge_map = merge_map or self._merge_map or {k: k for k in concepts.keys()}

        # Gather chunk ids across merged variants.
        chunk_ids: Set[str] = set()
        for key, meta in concepts.items():
            if merge_map.get(key, key) != concept_key:
                continue
            chunk_ids |= set(meta.get("chunk_ids") or set())
        if not chunk_ids:
            return None

        surface_forms = self._canonical_surface_forms(concept_key, concepts, merge_map)
        display_name = surface_forms[0] if surface_forms else (self.index.concept_label(concept_key) or concept_key)
        kind = _classify(display_name)

        definition = self._select_definition(concept_key, display_name, surface_forms, sorted(chunk_ids))
        concept_id = self._concept_uuid(concept_key)
        if definition is None:
            return GlossaryEntry(
                concept_id=concept_id,
                display_name=display_name,
                kind=kind,
                chunk_ids=sorted(chunk_ids),
                surface_forms=surface_forms[:12],
                definition_chunk_id=None,
                definition_excerpt="",
                source_note_id=None,
                last_updated=_now(),
                score=0.0,
                supporting=[],
            )

        def_chunk_id, def_note_id, def_excerpt, def_score, supporting = definition
        return GlossaryEntry(
            concept_id=concept_id,
            display_name=display_name,
            kind=kind,
            chunk_ids=sorted(chunk_ids),
            surface_forms=surface_forms[:12],
            definition_chunk_id=def_chunk_id,
            definition_excerpt=def_excerpt,
            source_note_id=def_note_id,
            last_updated=_now(),
            score=float(def_score),
            supporting=supporting,
        )

    def _select_definition(
        self,
        concept_key: str,
        display_name: str,
        surface_forms: Sequence[str],
        chunk_ids: Sequence[str],
    ) -> Optional[Tuple[str, str, str, float, List[Tuple[str, str, str]]]]:
        # Candidate chunks are all chunks mentioning the concept (high recall).
        metas: List[Tuple[str, Dict]] = []
        for cid in chunk_ids:
            meta = self.index.get_chunk(cid)
            if meta and meta.get("text"):
                metas.append((cid, meta))
        if not metas:
            return None

        # Scoring weights.
        alpha = float(os.environ.get("GRIMOIRE_GLOSSARY_ALPHA", "0.70"))
        beta = float(os.environ.get("GRIMOIRE_GLOSSARY_BETA", "0.25"))
        gamma = float(os.environ.get("GRIMOIRE_GLOSSARY_GAMMA", "0.20"))

        # Soft feature weights (not rules).
        early_w = float(os.environ.get("GRIMOIRE_GLOSSARY_EARLY_W", "0.08"))
        heading_w = float(os.environ.get("GRIMOIRE_GLOSSARY_HEADING_W", "0.06"))
        list_w = float(os.environ.get("GRIMOIRE_GLOSSARY_LIST_W", "0.10"))
        fragment_w = float(os.environ.get("GRIMOIRE_GLOSSARY_FRAGMENT_W", "0.12"))

        # Support centroid from retrieval stack (optional).
        centroid = self.index.concept_centroid(concept_key)

        # Cross-encoder scores.
        ce_scores: Optional[List[float]] = None
        if self.reranker is not None and getattr(self.reranker, "enabled", False):
            docs = [str(m.get("text") or "") for _, m in metas]
            ce_scores = self.reranker.score(display_name, docs)
            if ce_scores is not None and len(ce_scores) != len(metas):
                ce_scores = None

        # Normalize CE scores to 0..1 (per-concept).
        ce_norm: List[float] = [0.0] * len(metas)
        if ce_scores is not None and ce_scores:
            lo = min(ce_scores)
            hi = max(ce_scores)
            denom = (hi - lo) if (hi - lo) > 1e-9 else None
            for i, v in enumerate(ce_scores):
                ce_norm[i] = float((v - lo) / denom) if denom is not None else 0.0

        scored: List[Tuple[float, str, str, str]] = []  # (score, chunk_id, note_id, excerpt)
        for i, (chunk_id, meta) in enumerate(metas):
            text = str(meta.get("text") or "").strip()
            if not text:
                continue
            if _is_low_information_text(text):
                continue

            # Embedding similarity to support centroid.
            emb = 0.0
            if centroid is not None:
                vec = _normalize_dense(meta.get("dense") or [])
                if vec.size > 0 and int(vec.shape[0]) == int(centroid.shape[0]):
                    emb = float(_dot(vec, centroid))

            soft = 0.0
            soft += early_w * _early_position_bonus(text, surface_forms)
            soft += heading_w * _heading_match_bonus(text, surface_forms)
            if _is_bullet_heavy(text):
                soft -= list_w
            soft -= fragment_w * _fragment_penalty(text)

            total = alpha * float(ce_norm[i]) + beta * emb + gamma * soft
            excerpt = _sentences_excerpt(text, max_sentences=int(os.environ.get("GRIMOIRE_GLOSSARY_EXCERPT_SENTENCES", "3")))
            note_id = str(meta.get("note_id") or "")
            scored.append((total, chunk_id, note_id, excerpt))

        if not scored:
            return None

        scored.sort(key=lambda t: (-t[0], t[1]))
        best_score, best_chunk, best_note, best_excerpt = scored[0]

        supporting: List[Tuple[str, str, str]] = []
        for s, cid, nid, ex in scored[1:3]:
            if cid == best_chunk:
                continue
            supporting.append((cid, nid, ex))

        return best_chunk, best_note, best_excerpt, float(best_score), supporting

    def _load(self) -> None:
        try:
            if not self.path.exists():
                return
            payload = json.loads(self.path.read_text(encoding="utf-8"))
            version = int(payload.get("version") or 0)

            if version != _GLOSSARY_STORAGE_VERSION:
                # Stale payload from an older glossary build/version; force a rebuild.
                self._note_concepts = {}
                self._merge_map = {}
                self._notes = {}
                self._entities = {}
                self._entries = {}
                return

            if version == _GLOSSARY_STORAGE_VERSION:
                notes_payload = payload.get("notes") or {}
                parsed_notes: Dict[str, NoteExtract] = {}
                for note_id, meta in notes_payload.items():
                    if not isinstance(meta, dict):
                        continue
                    text_hash = str(meta.get("text_hash") or "")
                    sentences: List[SentenceRecord] = []
                    for s in meta.get("sentences") or []:
                        if not isinstance(s, dict):
                            continue
                        sentences.append(
                            SentenceRecord(
                                sentence_id=str(s.get("sentence_id") or ""),
                                note_id=str(s.get("note_id") or note_id),
                                start=int(s.get("start") or 0),
                                end=int(s.get("end") or 0),
                                text=str(s.get("text") or ""),
                                dense=list(s.get("dense") or []),
                                chunk_id=str(s.get("chunk_id") or ""),
                                heading=s.get("heading"),
                            )
                        )
                    mentions: List[MentionRecord] = []
                    for m in meta.get("mentions") or []:
                        if not isinstance(m, dict):
                            continue
                        mentions.append(
                            MentionRecord(
                                mention_id=str(m.get("mention_id") or ""),
                                note_id=str(m.get("note_id") or note_id),
                                sentence_id=str(m.get("sentence_id") or ""),
                                start=int(m.get("start") or 0),
                                end=int(m.get("end") or 0),
                                surface_text=str(m.get("surface_text") or ""),
                                canonical_text=str(m.get("canonical_text") or ""),
                                head_lemma=str(m.get("head_lemma") or ""),
                                head_pos=str(m.get("head_pos") or ""),
                                dep_role=str(m.get("dep_role") or ""),
                                context_dense=list(m.get("context_dense") or []),
                            )
                        )
                    if sentences:
                        parsed_notes[str(note_id)] = NoteExtract(
                            note_id=str(note_id),
                            text_hash=text_hash,
                            sentences=sentences,
                            mentions=mentions,
                        )
                self._notes = parsed_notes

                entries = payload.get("entries") or {}
                parsed_entries: Dict[str, GlossaryEntry] = {}
                for concept_id, meta in entries.items():
                    if not isinstance(meta, dict):
                        continue
                    parsed_entries[str(concept_id)] = GlossaryEntry(
                        concept_id=str(concept_id),
                        display_name=str(meta.get("display_name") or ""),
                        kind=_entity_kind_label(str(meta.get("kind") or "unknown")),
                        chunk_ids=list(meta.get("chunk_ids") or []),
                        surface_forms=list(meta.get("surface_forms") or []),
                        definition_chunk_id=meta.get("definition_chunk_id"),
                        definition_excerpt=str(meta.get("definition_excerpt") or ""),
                        source_note_id=meta.get("source_note_id"),
                        last_updated=float(meta.get("last_updated") or 0.0),
                        score=float(meta.get("score") or 0.0),
                        supporting=[
                            tuple(x)
                            for x in (meta.get("supporting") or [])
                            if isinstance(x, (list, tuple)) and len(x) == 3
                        ],
                    )
                self._entries = parsed_entries
                return

            # v2 (legacy concept glossary) is considered stale for the mention-based pipeline.
            # Leave empty so `ensure_built()` triggers a rebuild.
            self._note_concepts = {}
            self._merge_map = {}
            self._notes = {}
            self._entities = {}
            self._entries = {}
        except Exception:
            self._note_concepts = {}
            self._entries = {}
            self._merge_map = {}
            self._notes = {}
            self._entities = {}

    def _save(self) -> None:
        with self._lock:
            notes = self._notes
            entries = self._entries

        payload = {
            "version": _GLOSSARY_STORAGE_VERSION,
            "updated_at": _now(),
            "notes": {
                note_id: {
                    "text_hash": ex.text_hash,
                    "sentences": [
                        {
                            "sentence_id": s.sentence_id,
                            "note_id": s.note_id,
                            "start": int(s.start),
                            "end": int(s.end),
                            "text": s.text,
                            "dense": s.dense,
                            "chunk_id": s.chunk_id,
                            "heading": s.heading,
                        }
                        for s in ex.sentences
                    ],
                    "mentions": [
                        {
                            "mention_id": m.mention_id,
                            "note_id": m.note_id,
                            "sentence_id": m.sentence_id,
                            "start": int(m.start),
                            "end": int(m.end),
                            "surface_text": m.surface_text,
                            "canonical_text": m.canonical_text,
                            "head_lemma": m.head_lemma,
                            "head_pos": m.head_pos,
                            "dep_role": m.dep_role,
                            "context_dense": m.context_dense,
                        }
                        for m in ex.mentions
                    ],
                }
                for note_id, ex in notes.items()
            },
            "entries": {
                cid: {
                    "display_name": e.display_name,
                    "kind": e.kind,
                    "chunk_ids": e.chunk_ids,
                    "surface_forms": e.surface_forms,
                    "definition_chunk_id": e.definition_chunk_id,
                    "definition_excerpt": e.definition_excerpt,
                    "source_note_id": e.source_note_id,
                    "last_updated": e.last_updated,
                    "score": e.score,
                    "supporting": list(e.supporting),
                }
                for cid, e in entries.items()
            },
        }
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
