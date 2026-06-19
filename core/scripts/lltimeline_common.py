"""Shared LLTimeline text/token helpers for local Python tooling."""

from __future__ import annotations

import re
from typing import Any


WORD_RE = re.compile(r"['’]?[A-Za-z0-9]+(?:['’][A-Za-z0-9]+)*(?:['’])?")


def normalize_word(value: str) -> str:
    return value.strip().strip(".,!?;:\"“”‘’()[]{}").replace("’", "'").lower()


def tokenize(text: str) -> list[dict[str, Any]]:
    tokens: list[dict[str, Any]] = []
    index = 0
    cursor = 0
    for match in WORD_RE.finditer(text):
        if match.start() > cursor:
            index = append_non_word_tokens(tokens, text[cursor:match.start()], cursor, index)
        value = match.group(0)
        tokens.append(
            {
                "index": index,
                "kind": "word",
                "text": value,
                "normalized": normalize_word(value),
                "start_char": match.start(),
                "end_char": match.end(),
            }
        )
        index += 1
        cursor = match.end()
    if cursor < len(text):
        append_non_word_tokens(tokens, text[cursor:], cursor, index)
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
