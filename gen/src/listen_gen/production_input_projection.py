"""Production Input Projection: provider-specific inputs from a Structured Reading.

A production input projection selects ordered spans of an exact Structured
Reading and renders them in a provider-specific form (plain text for TTS,
Markdown for text-model producers). Projections are internal to a Generation
Run: they are never persisted as a Rendition, Resource, or package authority,
and their identity (hash and configuration) flows into resource provenance so
the exact input a provider consumed stays reproducible.

The plain-text projection for speech synthesis is derived from the
Structured Reading's exact logical ``text`` in spine order — the same
ordered spans the reading anchors declare — so the TTS input never contains
markup markers or unselected content.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass

PROJECTION_SCHEMA = "listen_gen.production-input-projection.v1"


def _canonical_json(value: object) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


@dataclass(frozen=True)
class ProductionInputProjection:
    text: str
    config: dict[str, object]
    config_sha256: str


def sentences_from_structured_reading(
    structured_reading: dict[str, object],
) -> list[tuple[str, str]]:
    """Ordered ``(anchor_id, text)`` sentence spans of a Structured Reading.

    Sentence anchors are returned in anchor order (the reading's logical
    order); each text slice is the exact UTF-8 range into the payload text.
    """
    text = structured_reading["text"]
    text_bytes = text.encode("utf-8")
    anchors = structured_reading["anchors"]
    sentences: list[tuple[str, str]] = []
    for anchor in anchors:
        if anchor.get("kind") != "sentence":
            continue
        start = int(anchor["start_offset"])
        end = int(anchor["end_offset"])
        slice_text = text_bytes[start:end].decode("utf-8")
        sentences.append((str(anchor["anchor_id"]), slice_text))
    return sentences


def project_plain_text_for_speech(
    structured_reading: dict[str, object],
) -> ProductionInputProjection:
    """Project the exact logical text as plain speech input.

    Sentence spans are joined in spine order with a single space; trailing
    newlines carried by sentence units are stripped so the projection is
    clean continuous speech input. The projection configuration records the
    text hash and the projection schema so the TTS configuration can name
    exactly what it consumed.
    """
    sentences = sentences_from_structured_reading(structured_reading)
    text = " ".join(entry.strip() for _, entry in sentences)
    config: dict[str, object] = {
        "schema": PROJECTION_SCHEMA,
        "kind": "plain-text",
        "ordered_span_count": len(sentences),
        "text_sha256": "sha256:" + hashlib.sha256(text.encode("utf-8")).hexdigest(),
    }
    return ProductionInputProjection(
        text=text,
        config=config,
        config_sha256="sha256:"
        + hashlib.sha256(_canonical_json(config)).hexdigest(),
    )
