"""Shared LLTimeline text/token helpers for local Python tooling."""

from __future__ import annotations

import re
import unicodedata
from typing import Any


WORD_RE = re.compile(r"['‘’]?[A-Za-z0-9]+(?:['‘’][A-Za-z0-9]+)*(?:['‘’])?")

_PUNCT_STRIP = ".,!?;:\"" + "“”‘’()'[]{}'"


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
            tokens.append(
                {
                    "index": index,
                    "kind": "word",
                    "text": ch,
                    "normalized": ch,
                    "start_char": cursor,
                    "end_char": cursor + 1,
                }
            )
            index += 1
            cursor += 1
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


def word_key(word: dict[str, Any]) -> tuple[str, int]:
    return (str(word["sentence_id"]), int(word["token_index"]))
