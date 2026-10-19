#!/usr/bin/env python3
"""Regenerate the committed Content Package v3 example carriers.

The examples are golden carriers: canonical `release.json`, payload blobs at
`blobs/sha256/<hex>`, and `release.json` identity invariants recomputed from
real bytes. Run after any v3 model or payload shape change, then re-run
`validate_content_package_schemas.py` and the Rust v3 suite.

Usage: regenerate_v3_examples.py [contracts/content-package/v3]
"""

from __future__ import annotations

import hashlib
import json
import shutil
import sys
from pathlib import Path


V3_ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "contracts" / "content-package" / "v3"
EXAMPLES_ROOT = V3_ROOT / "examples"

TEXT = "Pandas eat bamboo. They live in China."
DERIVED_TEXT = "Pandas eat bamboo. They live in China. (derived)"


def sha256_id(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def canonical_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def pretty_bytes(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8")


def blob_path(digest: str) -> str:
    return f"blobs/sha256/{digest.removeprefix('sha256:')}"


def sentence_ranges(text: str) -> list[tuple[int, int]]:
    ranges: list[tuple[int, int]] = []
    start = 0
    index = 0
    while index < len(text):
        if text[index] in ".!?":
            end = index + 1
            while end < len(text) and text[end] == " ":
                end += 1
            if start < end:
                ranges.append((start, end))
            start = end
            index = end
        else:
            index += 1
    if start < len(text):
        ranges.append((start, len(text)))
    return ranges


def structured_payload(text: str, rendition_id: str | None) -> tuple[dict, bytes]:
    ranges = sentence_ranges(text)
    anchors = [
        {
            "anchor_id": f"anchor-{i + 1}",
            "kind": "sentence",
            "start_offset": start,
            "end_offset": end,
        }
        for i, (start, end) in enumerate(ranges)
    ]
    blocks = [
        {
            "block_id": "block-root",
            "kind": "root",
            "order": 0,
            "span_anchor_ids": [f"anchor-{i + 1}" for i in range(len(ranges))],
            "parent_block_id": None,
        }
    ]
    if len(ranges) > 1:
        blocks.append(
            {
                "block_id": "block-section",
                "kind": "section",
                "order": 0,
                "span_anchor_ids": [f"anchor-{len(ranges)}"],
                "parent_block_id": "block-root",
            }
        )
    document_mappings = []
    if rendition_id is not None:
        document_mappings.append(
            {
                "anchor_id": "anchor-1",
                "rendition_id": rendition_id,
                "locator": {
                    "kind": "character_range",
                    "value": f"0:{ranges[0][1]}",
                },
            }
        )
    payload = {
        "language": "en",
        "text": text,
        "anchors": anchors,
        "blocks": blocks,
        "spans": [],
        "document_mappings": document_mappings,
        "extensions": {},
    }
    return payload, pretty_bytes(payload)


def alignment_payload(anchor_resource_id: str, rendition_id: str) -> tuple[dict, bytes]:
    payload = {
        "anchor_resource_id": anchor_resource_id,
        "rendition_id": rendition_id,
        "alignments": [
            {"anchor_id": "anchor-1", "media_time_ms": 0},
            {"anchor_id": "anchor-2", "media_time_ms": 1200},
        ],
        "extensions": {},
    }
    return payload, pretty_bytes(payload)


def blob_declaration(digest: str, size: int, embedded: bool) -> dict:
    return {"digest": digest, "size_bytes": size, "embedded": embedded}


def producer_value() -> dict:
    return {
        "created_at_ms": 1,
        "tool": {"id": "listen-gen", "version": "0.4.0"},
        "provider": None,
        "model": None,
        "config_sha256": None,
    }


def compatibility_value(rendition_id: str | None) -> dict:
    inputs = (
        [{"rendition_id": rendition_id, "resource_id": None}]
        if rendition_id is not None
        else []
    )
    return {"verified_inputs": inputs, "checks": ["exact_text_match"]}


def document_rendition(
    media_type: str,
    language: str | None,
    text_blob: dict,
    origin: str,
    source_asset_id: str | None,
    producer: dict | None,
    compatibility: dict | None,
) -> dict:
    identity = {"media_type": media_type, "language": language, "text_blob": text_blob}
    rendition_id = sha256_id(canonical_bytes(identity))
    return {
        "rendition_id": rendition_id,
        "origin": origin,
        "media_type": media_type,
        "language": language,
        "text_blob": text_blob,
        "source_asset_id": source_asset_id,
        "producer": producer,
        "compatibility": compatibility,
        "extensions": {},
    }


def media_rendition(
    kind: str,
    media_type: str,
    media_blob: dict,
    origin: str,
    media_id: str | None,
    fingerprint: str,
    producer: dict | None,
    compatibility: dict | None,
) -> dict:
    identity = {
        "kind": kind,
        "media_type": media_type,
        "media_blob": media_blob,
        "media_id": media_id,
        "fingerprint": fingerprint,
    }
    rendition_id = sha256_id(canonical_bytes(identity))
    return {
        "rendition_id": rendition_id,
        "origin": origin,
        "kind": kind,
        "media_type": media_type,
        "media_blob": media_blob,
        "media_id": media_id,
        "fingerprint": fingerprint,
        "producer": producer,
        "compatibility": compatibility,
        "extensions": {},
    }


def base_descriptor(
    kind: str,
    schema: str,
    dependencies: list[str],
    digest: str,
    size: int,
    revision_id: str,
    provenance: dict,
    review_status: str = "human_reviewed",
) -> dict:
    return {
        "schema": schema,
        "kind": kind,
        "role": "base",
        "content_language": "en",
        "support_languages": [],
        "subject": {
            "material_revision_id": revision_id,
            "rendition_ids": [],
            "anchor_resource_ids": [],
        },
        "dependencies": [{"resource_id": dep} for dep in dependencies],
        "provenance": provenance,
        "quality": {
            "review_status": review_status,
            "warnings": [],
            "extensions": {},
        },
        "payload_blob": blob_declaration(digest, size, True),
        "extensions": {},
    }


def assistance_descriptor(
    schema: str,
    support_languages: list[str],
    dependencies: list[str],
    digest: str,
    size: int,
    revision_id: str,
    provenance: dict,
) -> dict:
    return {
        "schema": schema,
        "kind": "translation",
        "role": "assistance",
        "support_languages": support_languages,
        "subject": {
            "material_revision_id": revision_id,
            "rendition_ids": [],
            "anchor_resource_ids": [],
        },
        "dependencies": [{"resource_id": dep} for dep in dependencies],
        "provenance": provenance,
        "quality": {
            "review_status": "machine_checked",
            "warnings": [],
            "extensions": {},
        },
        "payload_blob": blob_declaration(digest, size, True),
        "extensions": {},
    }


def resource_entry(descriptor: dict, required: bool) -> dict:
    return {
        "resource_id": sha256_id(canonical_bytes(descriptor)),
        "required": required,
        "descriptor": descriptor,
    }


def provenance(created_at_ms: int = 1) -> dict:
    return {
        "created_at_ms": created_at_ms,
        "tool": {"id": "listen-gen", "version": "0.4.0"},
        "provider": None,
        "model": None,
        "config_sha256": None,
        "input_rendition_ids": [],
        "input_resource_ids": [],
        "extensions": {},
    }


def write_example(name: str, release: dict, blobs: list[tuple[str, bytes]]) -> None:
    target = EXAMPLES_ROOT / name
    if target.exists():
        shutil.rmtree(target)
    for path, data in blobs:
        destination = target / blob_path(path)
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    (target / "release.json").write_bytes(canonical_bytes(release))


def build_document_source() -> None:
    revision = "revision-fixture-v1"
    text_bytes = TEXT.encode("utf-8")
    text_digest = sha256_id(text_bytes)
    text_blob = blob_declaration(text_digest, len(text_bytes), True)
    document = document_rendition(
        "text/plain",
        "en",
        text_blob,
        "source",
        "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        None,
        None,
    )
    structured, structured_bytes = structured_payload(TEXT, document["rendition_id"])
    structured_digest = sha256_id(structured_bytes)
    descriptor = base_descriptor(
        "structured_reading",
        "listen.payload.structured-reading.v1",
        [],
        structured_digest,
        len(structured_bytes),
        revision,
        provenance(),
    )
    resource = resource_entry(descriptor, True)
    release = {
        "schema": "listen.content-package.release.v3",
        "created_at_ms": 1,
        "edition": {
            "edition_id": "edition-fixture-v1",
            "title": "Fixture Edition",
            "target_language": "en",
            "support_languages": [],
        },
        "material": {
            "material_id": "material-fixture-v1",
            "material_revision_id": revision,
            "title": "Fixture Material",
        },
        "document_renditions": [document],
        "media_renditions": [],
        "resources": [resource],
        "extensions": {},
    }
    write_example(
        "document-source",
        release,
        [
            (text_digest, text_bytes),
            (structured_digest, structured_bytes),
        ],
    )


def build_media_only() -> None:
    revision = "revision-fixture-v1"
    embedded_bytes = b"listen fixture derived audio"
    embedded_digest = sha256_id(embedded_bytes)
    embedded_blob = blob_declaration(embedded_digest, len(embedded_bytes), True)
    derived = media_rendition(
        "audio",
        "audio/mpeg",
        embedded_blob,
        "derived",
        None,
        "fp-derived-1",
        producer_value(),
        compatibility_value(None),
    )
    referenced_digest = "sha256:" + "c" * 64
    referenced_blob = blob_declaration(referenced_digest, 100, False)
    source = media_rendition(
        "audio",
        "audio/mpeg",
        referenced_blob,
        "source",
        "media-1",
        "fp-source-1",
        None,
        None,
    )
    structured, structured_bytes = structured_payload(TEXT, None)
    structured_digest = sha256_id(structured_bytes)
    descriptor = base_descriptor(
        "structured_reading",
        "listen.payload.structured-reading.v1",
        [],
        structured_digest,
        len(structured_bytes),
        revision,
        provenance(),
    )
    structured_resource = resource_entry(descriptor, False)
    alignment, alignment_bytes = alignment_payload(
        structured_resource["resource_id"], source["rendition_id"]
    )
    alignment_digest = sha256_id(alignment_bytes)
    alignment_descriptor = base_descriptor(
        "anchor_time_alignment",
        "listen.payload.anchor-time-alignment.v1",
        [],
        alignment_digest,
        len(alignment_bytes),
        revision,
        provenance(),
    )
    alignment_resource = resource_entry(alignment_descriptor, False)
    release = {
        "schema": "listen.content-package.release.v3",
        "created_at_ms": 1,
        "edition": {
            "edition_id": "edition-fixture-v1",
            "title": "Fixture Edition",
            "target_language": "en",
            "support_languages": [],
        },
        "material": {
            "material_id": "material-fixture-v1",
            "material_revision_id": revision,
            "title": "Fixture Material",
        },
        "document_renditions": [],
        "media_renditions": [derived, source],
        "resources": [structured_resource, alignment_resource],
        "extensions": {},
    }
    write_example(
        "media-only",
        release,
        [
            (embedded_digest, embedded_bytes),
            (structured_digest, structured_bytes),
            (alignment_digest, alignment_bytes),
        ],
    )


def build_composed() -> None:
    revision = "revision-composed-v1"
    text_bytes = TEXT.encode("utf-8")
    text_digest = sha256_id(text_bytes)
    text_blob = blob_declaration(text_digest, len(text_bytes), True)
    document = document_rendition(
        "text/plain",
        "en",
        text_blob,
        "source",
        "sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
        None,
        None,
    )
    derived_text_bytes = DERIVED_TEXT.encode("utf-8")
    derived_digest = sha256_id(derived_text_bytes)
    derived_blob = blob_declaration(derived_digest, len(derived_text_bytes), False)
    derived_document = document_rendition(
        "text/plain",
        "en",
        derived_blob,
        "derived",
        None,
        producer_value(),
        compatibility_value(document["rendition_id"]),
    )
    embedded_media = b"listen fixture composed media"
    embedded_media_digest = sha256_id(embedded_media)
    embedded_media_blob = blob_declaration(embedded_media_digest, len(embedded_media), True)
    source_media = media_rendition(
        "audio",
        "audio/mpeg",
        embedded_media_blob,
        "source",
        "media-1",
        "fp-source-composed",
        None,
        None,
    )
    referenced_media_digest = "sha256:" + "e" * 64
    referenced_media_blob = blob_declaration(referenced_media_digest, 200, False)
    derived_media = media_rendition(
        "audio",
        "audio/mpeg",
        referenced_media_blob,
        "derived",
        None,
        "fp-derived-composed",
        producer_value(),
        compatibility_value(document["rendition_id"]),
    )
    structured, structured_bytes = structured_payload(TEXT, document["rendition_id"])
    structured_digest = sha256_id(structured_bytes)
    structured_descriptor = base_descriptor(
        "structured_reading",
        "listen.payload.structured-reading.v1",
        [],
        structured_digest,
        len(structured_bytes),
        revision,
        provenance(),
    )
    structured_resource = resource_entry(structured_descriptor, True)
    alignment, alignment_bytes = alignment_payload(
        structured_resource["resource_id"], source_media["rendition_id"]
    )
    alignment_digest = sha256_id(alignment_bytes)
    alignment_descriptor = base_descriptor(
        "anchor_time_alignment",
        "listen.payload.anchor-time-alignment.v1",
        [],
        alignment_digest,
        len(alignment_bytes),
        revision,
        provenance(),
    )
    alignment_resource = resource_entry(alignment_descriptor, True)
    translation = {
        "support_language": "zh-Hans",
        "base_resource_id": structured_resource["resource_id"],
        "segments": [
            {
                "id": "tr-1",
                "index": 0,
                "text": "大熊猫吃竹子。",
                "source_segment_id": "anchor-1",
                "extensions": {},
            },
            {
                "id": "tr-2",
                "index": 1,
                "text": "它们住在中国。",
                "source_segment_id": "anchor-2",
                "extensions": {},
            },
        ],
        "extensions": {},
    }
    translation_bytes = pretty_bytes(translation)
    translation_digest = sha256_id(translation_bytes)
    translation_descriptor = assistance_descriptor(
        "listen.payload.translation.v1",
        ["zh-Hans"],
        [structured_resource["resource_id"]],
        translation_digest,
        len(translation_bytes),
        revision,
        provenance(),
    )
    translation_resource = resource_entry(translation_descriptor, False)
    release = {
        "schema": "listen.content-package.release.v3",
        "created_at_ms": 1,
        "edition": {
            "edition_id": "edition-composed-v1",
            "title": "Composed Example Edition",
            "target_language": "en",
            "support_languages": ["zh-Hans"],
        },
        "material": {
            "material_id": "material-composed-v1",
            "material_revision_id": revision,
            "title": "Composed Example Material",
        },
        "document_renditions": [document, derived_document],
        "media_renditions": [source_media, derived_media],
        "resources": [
            structured_resource,
            alignment_resource,
            translation_resource,
        ],
        "extensions": {},
    }
    write_example(
        "composed",
        release,
        [
            (text_digest, text_bytes),
            (embedded_media_digest, embedded_media),
            (structured_digest, structured_bytes),
            (alignment_digest, alignment_bytes),
            (translation_digest, translation_bytes),
        ],
    )


def main() -> int:
    if not EXAMPLES_ROOT.is_dir():
        print(f"examples root missing: {EXAMPLES_ROOT}", file=sys.stderr)
        return 1
    build_document_source()
    build_media_only()
    build_composed()
    print("Regenerated Content Package v3 examples.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
