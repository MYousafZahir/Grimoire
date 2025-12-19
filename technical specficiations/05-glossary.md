# Grimoire — Automated Glossary Technical Specification

This document specifies the automated glossary subsystem: a local, corpus-derived world-bible glossary that extracts terms from notes and selects verbatim definitions from within the corpus.

---

## Non-LLM Constraint

- No generative model is used.
- No external knowledge is used.
- All displayed definitions are verbatim excerpts from notes.

The glossary is a **selection problem**, not a generation problem.

---

## Models (Local)

1. **Embeddings**
   - `BAAI/bge-small-en-v1.5`
   - used for sentence/context embeddings and similarity scoring

2. **Reranker (optional but recommended)**
   - `BAAI/bge-reranker-base`
   - cross-encoder scoring for “definition-likelihood”

3. **Syntax/Mention Extraction (optional but preferred)**
   - `spaCy en_core_web_sm` (NER disabled)
   - provides noun chunks, POS tags, dependency roles

If spaCy is unavailable, a conservative fallback extractor is used.

---

## Data Model (Concepts/Entities)

Glossary entries are built from:

- **Sentence records** (with offsets into the note)
- **Mention records** (spans inside sentences)
- **Candidate keys** (canonicalized mention strings)
- **Entity clusters** (alias groups)

The stored glossary entry includes:

- a stable ID (`concept_id`)
- `display_name`
- `kind` (Person/Place/Thing/Unknown; conservative)
- definition excerpt (1–3 sentences, verbatim)
- source note ID
- supporting chunks (additional verbatim excerpts)

---

## Extraction Pipeline

### Step 1: Preprocessing

- Remove Grimoire chunk markers from note text (to keep offsets stable).
- Mask code fences (do not parse mentions inside code).
- Mask common Markdown syntax when running spaCy so headings/list markers do not become entities.

### Step 2: Sentence splitting

- Prefer spaCy sentence segmentation when available.
- Fall back to a conservative regex splitter when spaCy is unavailable.

Each sentence is embedded with `bge-small-en-v1.5`.

### Step 3: Mention extraction

When spaCy is available:

- Start from noun chunks + explicit PROPN spans.
- Apply strong filters to prevent junk:
  - reject spans crossing newlines
  - reject spans starting with Markdown markers
  - strip leading determiners/quantifiers/prepositions (“In Denmark” → “Denmark”)
  - trim punctuation wrappers (`(The Shadow)` → `The Shadow`)
  - expand “X of Y” patterns (“Essence of Dusk”, “Trading Guild of Yor”)

When spaCy is unavailable:

- Use conservative pattern extractors for:
  - multiword TitleCase phrases
  - `X of Y` TitleCase phrases
  - quoted terms (Unicode-friendly)
  - limited definitional templates

### Step 4: Termhood filtering

Candidates are aggregated across mentions and scored for “entity-worthiness” using features such as:

- referentiality ratio (dependency roles like subject/object/apposition)
- modifier-only ratio (amod/det/etc)
- heading hits
- definitional cues (“X is …”, “called an X”, etc.)
- capitalization away from sentence start
- repetition and context tightness

Only candidates above a threshold become entities.

### Step 5: Alias discovery (entity clustering)

Clusters are built via:

- high precision explicit alias patterns (aka, known as, parentheses)
- conservative similarity-based merging with safeguards
  - avoid merging headed phrases with their heads (e.g. “Essence of Dusk” ≠ “Dusk”)

### Step 6: Definition selection (verbatim)

For each entity cluster:

- score candidate sentences containing the entity name/aliases
- optionally rerank with the cross-encoder (`bge-reranker-base`)
- select 1–3 sentences with diversity/MMR
- concatenate sentences verbatim as `definition_excerpt`

---

## Rebuild & Incremental Updates

- The glossary is project-scoped and cached under `<Project>.grim/glossary/`.
- It can be rebuilt explicitly via `POST /admin/rebuild-glossary`.
- It can update incrementally on note saves (background thread).

Rebuild result reporting:

- The backend tracks how many notes used spaCy vs fallback extraction during the rebuild.
- The macOS app surfaces this to the user after rebuild (always, not only on fallback).

---

## Operational Safeguards

- Never fabricate definitions.
- Prefer skipping uncertain candidates to avoid junk glossary entries.
- Do not default Unknown → Person.
- Keep behavior deterministic and inspectable (all decisions trace to note sentences).

