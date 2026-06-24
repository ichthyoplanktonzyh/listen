"""Shared LLTimeline text/token helpers for local Python tooling."""

from __future__ import annotations

import re
import unicodedata
from typing import Any


WORD_RE = re.compile(r"['‘’]?[A-Za-z0-9]+(?:['‘’][A-Za-z0-9]+)*(?:['‘’])?")

_PUNCT_STRIP = ".,!?;:\"" + "“”‘’()’[]{}’"

_jieba_loaded = False
_jieba_cut = None


def _ensure_jieba():
    global _jieba_loaded, _jieba_cut
    if _jieba_loaded:
        return
    _jieba_loaded = True
    try:
        import jieba
        jieba.setLogLevel(20)
        _jieba_cut = jieba.cut
    except ImportError:
        _jieba_cut = None


def _is_cjk(ch: str) -> bool:
    cp = ord(ch)
    return (
        0x4E00 <= cp <= 0x9FFF
        or 0x3400 <= cp <= 0x4DBF
        or 0x20000 <= cp <= 0x2A6DF
        or 0xF900 <= cp <= 0xFAFF
        or 0x3040 <= cp <= 0x309F  # hiragana
        or 0x30A0 <= cp <= 0x30FF  # katakana
        or 0x31F0 <= cp <= 0x31FF  # katakana extensions
        or 0xFF66 <= cp <= 0xFF9D  # half-width katakana
    )


def normalize_word(value: str) -> str:
    stripped = value.strip().strip(_PUNCT_STRIP).replace("’", "'")
    if any(_is_cjk(ch) for ch in stripped):
        return stripped
    return stripped.lower()


def _segment_cjk_run(text: str) -> list[str]:
    _ensure_jieba()
    if _jieba_cut is not None:
        return list(_jieba_cut(text))
    return list(text)


def tokenize(text: str) -> list[dict[str, Any]]:
    tokens: list[dict[str, Any]] = []
    index = 0
    cursor = 0

    while cursor < len(text):
        ascii_match = WORD_RE.match(text, cursor)
        if ascii_match and ascii_match.start() == cursor:
            if ascii_match.start() > cursor:
                index = append_non_word_tokens(tokens, text[cursor:ascii_match.start()], cursor, index)
            value = ascii_match.group(0)
            tokens.append(
                {
                    "index": index,
                    "kind": "word",
                    "text": value,
                    "normalized": normalize_word(value),
                    "start_char": ascii_match.start(),
                    "end_char": ascii_match.end(),
                }
            )
            index += 1
            cursor = ascii_match.end()
            continue

        ch = text[cursor]
        if _is_cjk(ch):
            cjk_start = cursor
            while cursor < len(text) and _is_cjk(text[cursor]):
                cursor += 1
            cjk_run = text[cjk_start:cursor]
            seg_words = _segment_cjk_run(cjk_run)
            pos = cjk_start
            for word in seg_words:
                tokens.append(
                    {
                        "index": index,
                        "kind": "word",
                        "text": word,
                        "normalized": word,
                        "start_char": pos,
                        "end_char": pos + len(word),
                    }
                )
                index += 1
                pos += len(word)
            continue

        start = cursor
        if ch.isspace():
            while cursor < len(text) and text[cursor].isspace():
                cursor += 1
            tokens.append(
                {
                    "index": index,
                    "kind": "whitespace",
                    "text": text[start:cursor],
                    "normalized": None,
                    "start_char": start,
                    "end_char": cursor,
                }
            )
        else:
            while cursor < len(text) and not text[cursor].isspace() and not _is_cjk(text[cursor]) and not WORD_RE.match(text, cursor):
                cursor += 1
            tokens.append(
                {
                    "index": index,
                    "kind": "punctuation",
                    "text": text[start:cursor],
                    "normalized": None,
                    "start_char": start,
                    "end_char": cursor,
                }
            )
        index += 1

    return tokens


def append_non_word_tokens(
    tokens: list[dict[str, Any]],
    text: str,
    absolute_start: int,
    index: int,
) -> int:
    cursor = 0
    while cursor < len(text):
        start = cursor
        is_space = text[cursor].isspace()
        while cursor < len(text) and text[cursor].isspace() == is_space:
            cursor += 1
        value = text[start:cursor]
        tokens.append(
            {
                "index": index,
                "kind": "whitespace" if is_space else "punctuation",
                "text": value,
                "normalized": None,
                "start_char": absolute_start + start,
                "end_char": absolute_start + cursor,
            }
        )
        index += 1
    return index


def word_token_indexes(tokens: list[dict[str, Any]]) -> list[int]:
    return [token["index"] for token in tokens if token["kind"] == "word"]


def align_asr_words_to_tokens(
    asr_words: list[dict[str, Any]],
    tokens: list[dict[str, Any]],
) -> list[dict[str, Any] | None]:
    word_tokens = [t for t in tokens if t["kind"] == "word"]
    if not asr_words or not word_tokens:
        return [None] * len(word_tokens)

    asr_chars: list[tuple[int, str]] = []
    for wi, w in enumerate(asr_words):
        for ch in str(w.get("word", "")).strip():
            asr_chars.append((wi, ch))

    tok_chars: list[tuple[int, dict]] = []
    for ti, t in enumerate(word_tokens):
        for ch in t["text"]:
            tok_chars.append((ti, t))

    asr_by_token: dict[int, list[int]] = {}
    ai = 0
    for ti_idx in range(len(tok_chars)):
        tok_ti, _ = tok_chars[ti_idx]
        if ai < len(asr_chars):
            asr_wi, _ = asr_chars[ai]
            asr_by_token.setdefault(tok_ti, []).append(asr_wi)
            ai += 1

    result: list[dict[str, Any] | None] = []
    for ti, t in enumerate(word_tokens):
        contributing = asr_by_token.get(ti, [])
        if not contributing:
            result.append(None)
            continue
        unique_wis = sorted(set(contributing))
        starts = [asr_words[wi].get("start") for wi in unique_wis if asr_words[wi].get("start") is not None]
        ends = [asr_words[wi].get("end") for wi in unique_wis if asr_words[wi].get("end") is not None]
        scores = [asr_words[wi].get("score", 0.0) for wi in unique_wis if asr_words[wi].get("score") is not None]
        if not starts or not ends:
            result.append(None)
            continue
        result.append({
            "start": min(starts),
            "end": max(ends),
            "score": sum(scores) / len(scores) if scores else 0.0,
            "word": t["text"],
        })
    return result


def word_key(word: dict[str, Any]) -> tuple[str, int]:
    return (str(word["sentence_id"]), int(word["token_index"]))
