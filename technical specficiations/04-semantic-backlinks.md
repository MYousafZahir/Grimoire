# Grimoire — Semantic Backlinks (Context Sidebar) Technical Specification

This document describes how “semantic backlinks” work: a cursor-conditioned retrieval system that returns short excerpts from other notes that help explain the current cursor context.

---

## Goals

- Local-only, deterministic retrieval (no generative output).
- Fast enough for interactive use on cursor movement.
- Works with invented / fictional terms (world-building).
- Outputs excerpts/snippets that are verbatim from notes.

---

## Data Model

**Note**
- A Markdown document stored in the project’s `notes/` directory.

**Chunk**
- An indexable block extracted from a note (paragraph/list block/heading block).
- Each chunk stores:
  - `text`
  - `note_id`
  - offsets (`start_char`, `end_char`) for navigation
  - dense embedding vector
  - optional concept labels/IDs

**Snippet**
- A UI rendering of a chunk excerpt:
  - title (derived from heading/concept match)
  - 1–3 sentence excerpt
  - source note reference

---

## Indexes (Per Project)

Context retrieval uses a hybrid approach:

1. **Dense retrieval** (primary high-recall):
   - FAISS index (HNSW) over chunk dense vectors
2. **Lexical retrieval** (optional/high precision):
   - BM25-like retrieval over chunk text
3. **Concept inverted index** (fast recall for named/internal terms):
   - concept → chunk IDs

On disk, these live under:

- `<Project>.grim/context/`

Implementation code:

- `backend/context_service.py` (`ContextIndex`, `ContextService`)

---

## Models (Local)

- Dense embedder: `BAAI/bge-small-en-v1.5`
- Cross-encoder reranker (optional): `BAAI/bge-reranker-base`

If the reranker cannot be loaded, the system falls back to embedding-based scoring.

---

## Runtime Triggering

The macOS app triggers context recomputation on:

- cursor click
- debounced cursor move
- text changes

To keep latency low, recomputation should only happen when:

- the cursor enters a new paragraph/segment, or
- the edited text changes the current segment

---

## Query Construction (Cursor-Conditioned)

At runtime, the backend receives:

- current note text
- cursor position and/or a cursor window

The backend constructs:

- `W`: the local window (typically the current paragraph, clipped to a max token budget)
- optionally `P`: a prefix representation used as a redundancy penalty (cached/incremental)

---

## Candidate Generation

Candidate chunks are a union of:

- top-N from dense retrieval using embedding(W)
- top-N from lexical retrieval using W terms (if enabled)
- all chunks mentioning detected concepts/entities in W (inverted index)

Candidates are deduplicated and capped before expensive scoring.

---

## Scoring & Ranking

The system ranks chunks to maximize usefulness:

- high similarity to `W` (relevance)
- support for “information gaps” (terms/entities present near cursor but not grounded earlier)
- avoid redundancy with prefix `P` and already-selected chunks

Reranking (optional):

- take top-K (e.g. 30–50) candidates by a cheap embedding score
- apply cross-encoder reranker with (W, chunk.text)
- combine with the cheap score for final ordering

Selection:

- choose up to 7 snippets
- apply diversity/MMR-style logic to avoid near-duplicates
- prefer coverage of distinct gap concepts/entities

---

## Output Constraints

- No summarization.
- No generation.
- Snippets are excerpts of existing chunks (1–3 sentences).
- Each snippet includes a source note reference and supports navigation.

---

## UI Integration

The macOS app:

- clears the panel and shows a centered spinner while a request is in flight
- renders snippet text as Markdown
- allows “Open” navigation that highlights the referenced excerpt until the user clicks away

