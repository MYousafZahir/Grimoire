"""
Unit tests for glossary fallback mention extraction helpers.
"""

import os
import sys

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../../backend"))

from glossary_service import SentenceRecord, _add_fallback_mention, _maybe_singularize_phrase, _tokenize_words


@pytest.mark.unit
def test_add_fallback_mention_includes_acronym_blt():
    mentions = []
    seen = set()
    text = "The BLT is a common type of sandwich."
    sentence = SentenceRecord(sentence_id="s", note_id="n", start=0, end=len(text), text=text, dense=[], chunk_id="c")

    start = text.index("BLT")
    end = start + len("BLT")
    _add_fallback_mention(
        mentions=mentions,
        seen=seen,
        note_id="n",
        sentence=sentence,
        cleaned=text,
        start=start,
        end=end,
        surface="BLT",
        head_pos="PROPN",
    )

    assert len(mentions) == 1
    assert mentions[0].canonical_text == "BLT"
    assert mentions[0].head_lemma == "blt"


@pytest.mark.unit
def test_add_fallback_mention_includes_unicode_quoted_terms():
    mentions = []
    seen = set()
    text = 'In Denmark "smørrebrød" is an open sandwich.'
    sentence = SentenceRecord(sentence_id="s", note_id="n", start=0, end=len(text), text=text, dense=[], chunk_id="c")

    surface = "smørrebrød"
    start = text.index(surface)
    end = start + len(surface)
    _add_fallback_mention(
        mentions=mentions,
        seen=seen,
        note_id="n",
        sentence=sentence,
        cleaned=text,
        start=start,
        end=end,
        surface=surface,
        head_pos="PROPN",
    )

    assert len(mentions) == 1
    assert mentions[0].canonical_text == surface
    assert mentions[0].head_lemma == surface.lower()


@pytest.mark.unit
def test_maybe_singularize_phrase_handles_common_plural():
    assert _maybe_singularize_phrase("open sandwiches") == "open sandwich"
    # Keep proper multi-token names stable.
    assert _maybe_singularize_phrase("United States") == "United States"
    # Keep acronyms stable.
    assert _maybe_singularize_phrase("BLT") == "BLT"


@pytest.mark.unit
def test_tokenize_words_unicode():
    assert "smørrebrød" in _tokenize_words("smørrebrød is tasty")

