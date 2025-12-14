"""Automated glossary (local, non-LLM, corpus-derived).

Implements a selection-based glossary:
- Concepts are discovered from the corpus (shared with retrieval concepts).
- A glossary "definition" is a verbatim excerpt from the best-ranked chunk
  already present in the notes (no generation).

Models used (local):
- Embedder: BAAI/bge-small-en-v1.5 (via ContextEmbedder)
- Cross-encoder: BAAI/bge-reranker-base (via ContextReranker)
"""

from __future__ import annotations

import json
import os
import re
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Set, Tuple

import numpy as np

from context_service import ContextEmbedder, ContextIndex, ContextReranker, _sentences_excerpt, _dot, _normalize_dense


_GLOSSARY_NAMESPACE = uuid.UUID("9f5bca3a-73b8-4e70-b19d-8a7b7c7a81f5")


def _now() -> float:
    return time.time()


def _normalize_label(label: str) -> str:
    label = (label or "").strip()
    label = re.sub(r"`+", "", label)
    label = re.sub(r"[^\w\s-]", "", label)
    label = re.sub(r"\s+", " ", label)
    return label.lower().strip()


def _tokenize_words(text: str) -> List[str]:
    return re.findall(r"[A-Za-z0-9_'-]+", (text or "").lower())


_GENERIC_CONCEPT_BLACKLIST: Set[str] = {
    "key points",
    "key point",
    "summary",
    "notes",
    "todo",
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
    """Project-scoped glossary derived from the ContextIndex corpus."""

    def __init__(
        self,
        path: Path,
        index: ContextIndex,
        *,
        embedder: Optional[ContextEmbedder] = None,
        reranker: Optional[ContextReranker] = None,
    ):
        self.path = Path(path)
        self.index = index
        self.embedder = embedder
        self.reranker = reranker
        self.path.parent.mkdir(parents=True, exist_ok=True)

        self._note_concepts: Dict[str, Set[str]] = {}
        self._entries: Dict[str, GlossaryEntry] = {}
        self._merge_map: Dict[str, str] = {}
        self._name_vec_cache: Dict[str, np.ndarray] = {}
        self._load()

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------
    def ensure_built(self) -> None:
        # If we have no entries but we have chunks, build once.
        if self._entries:
            return
        self.rebuild()

    def list_entries(self) -> List[GlossaryEntry]:
        entries = list(self._entries.values())
        entries.sort(key=lambda e: (-len(e.chunk_ids), e.display_name.lower(), e.concept_id))
        return entries

    def entry(self, concept_id: str) -> Optional[GlossaryEntry]:
        return self._entries.get(concept_id)

    def update_for_note(self, note_id: str) -> None:
        """Incremental update after context index updated for a note."""
        concepts = self._discover_concepts()

        # Compute current concepts present in the note's indexed chunks.
        # Use raw concept keys first so we can merge newly-seen variants without
        # changing existing representatives (stable concept ids).
        raw_new = self._raw_concepts_for_note(note_id)
        if raw_new:
            self._extend_merge_map(concepts, raw_new)
        new_concepts = {self._merge_map.get(c, c) for c in raw_new}
        old_concepts = self._note_concepts.get(note_id, set())

        changed = set(old_concepts) | set(new_concepts)
        if not changed and note_id in self._note_concepts:
            return

        self._note_concepts[note_id] = set(new_concepts)

        # If the glossary wasn't built yet, do a full rebuild.
        if not self._entries:
            self.rebuild()
            return

        for concept_key in sorted(changed):
            concept_id = self._concept_uuid(concept_key)
            entry = self._build_entry_for_concept(concept_key, concepts=concepts, merge_map=self._merge_map)
            if entry is None:
                self._entries.pop(concept_id, None)
            else:
                self._entries[concept_id] = entry

        self._save()

    def delete_notes(self, note_ids: Iterable[str]) -> None:
        impacted: Set[str] = set()
        for note_id in note_ids:
            impacted |= set(self._note_concepts.pop(note_id, set()))

        if not impacted:
            return

        concepts = self._discover_concepts()
        for concept_key in sorted(impacted):
            concept_id = self._concept_uuid(concept_key)
            entry = self._build_entry_for_concept(concept_key, concepts=concepts, merge_map=self._merge_map)
            if entry is None:
                self._entries.pop(concept_id, None)
            else:
                self._entries[concept_id] = entry

        self._save()

    def rebuild(self) -> int:
        """Full rebuild from the current ContextIndex."""
        concepts = self._discover_concepts()
        merge_map = self._merge_variants(concepts, existing=self._merge_map)
        self._merge_map = merge_map

        # Recompute note->concepts based on merged concept ids.
        note_concepts: Dict[str, Set[str]] = {}
        for note_id in self.index.note_ids():
            base = self._concepts_for_note(note_id)
            note_concepts[note_id] = {merge_map.get(c, c) for c in base}
        self._note_concepts = note_concepts

        entries: Dict[str, GlossaryEntry] = {}
        for concept_key in sorted({merge_map.get(c, c) for c in concepts.keys()}):
            entry = self._build_entry_for_concept(concept_key, concepts=concepts, merge_map=merge_map)
            if entry is None:
                continue
            entries[entry.concept_id] = entry
        self._entries = entries
        self._save()
        return len(entries)

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
            if int(payload.get("version") or 0) != 2:
                return
            note_concepts = payload.get("note_concepts") or {}
            entries = payload.get("entries") or {}
            merge_map = payload.get("merge_map") or {}

            self._note_concepts = {k: set(v or []) for k, v in note_concepts.items()}
            self._merge_map = {str(k): str(v) for k, v in merge_map.items()}

            parsed: Dict[str, GlossaryEntry] = {}
            for concept_id, meta in entries.items():
                if not isinstance(meta, dict):
                    continue
                parsed[str(concept_id)] = GlossaryEntry(
                    concept_id=str(concept_id),
                    display_name=str(meta.get("display_name") or ""),
                    kind=str(meta.get("kind") or "thing"),
                    chunk_ids=list(meta.get("chunk_ids") or []),
                    surface_forms=list(meta.get("surface_forms") or []),
                    definition_chunk_id=meta.get("definition_chunk_id"),
                    definition_excerpt=str(meta.get("definition_excerpt") or ""),
                    source_note_id=meta.get("source_note_id"),
                    last_updated=float(meta.get("last_updated") or 0.0),
                    score=float(meta.get("score") or 0.0),
                    supporting=[tuple(x) for x in (meta.get("supporting") or []) if isinstance(x, (list, tuple)) and len(x) == 3],
                )
            self._entries = parsed
        except Exception:
            self._note_concepts = {}
            self._entries = {}
            self._merge_map = {}

    def _save(self) -> None:
        payload = {
            "version": 2,
            "updated_at": _now(),
            "merge_map": self._merge_map,
            "note_concepts": {k: sorted(v) for k, v in self._note_concepts.items()},
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
                for cid, e in self._entries.items()
            },
        }
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
