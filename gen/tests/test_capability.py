from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.capability import CapabilityRequest
from listen_gen.package import ConversionError


def media_rendition(**overrides) -> dict[str, object]:
    rendition: dict[str, object] = {
        "kind": "media",
        "rendition_id": "sha256:" + "1" * 64,
        "media_kind": "audio",
        "media_type": "audio/wav",
        "media_id": "media-1",
        "fingerprint": "fixture-fingerprint",
        "blob": {
            "digest": "sha256:" + "2" * 64,
            "size_bytes": 12,
            "path": "/tmp/media.wav",
        },
    }
    rendition.update(overrides)
    return rendition


def document_rendition(**overrides) -> dict[str, object]:
    rendition: dict[str, object] = {
        "kind": "document",
        "rendition_id": "sha256:" + "3" * 64,
        "media_type": "text/plain",
        "language": "en-US",
        "source_asset_id": "4" * 64,
        "blob": {
            "digest": "sha256:" + "5" * 64,
            "size_bytes": 12,
            "path": "/tmp/lesson.txt",
        },
    }
    rendition.update(overrides)
    return rendition


def valid_request(**overrides) -> dict[str, object]:
    document: dict[str, object] = {
        "schema": "listen_gen.capability-request.v2",
        "version": 2,
        "created_at_ms": 1,
        "attempt_id": "attempt-1",
        "material": {
            "material_id": "material-1",
            "material_revision_id": "revision-1",
            "title": "Test Material",
        },
        "edition": {
            "edition_id": "edition-1",
            "title": "Test Edition",
            "target_language": "en-US",
            "support_languages": ["zh-Hans"],
        },
        "requested_capability": "read",
        "available_renditions": [media_rendition()],
        "extensions": {},
    }
    document.update(overrides)
    return document


class CapabilityRequestTests(unittest.TestCase):
    def test_from_document_builds_media_only_request(self) -> None:
        request = CapabilityRequest.from_document(valid_request())
        self.assertEqual(request.requested_capability, "read")
        self.assertEqual(len(request.media_renditions), 1)
        self.assertEqual(request.media_renditions[0].media_kind, "audio")
        self.assertEqual(request.edition.target_language, "en-US")
        self.assertEqual(request.attempt_id, "attempt-1")

    def test_from_document_accepts_raw_core_source_asset_id(self) -> None:
        entry = document_rendition()
        request = CapabilityRequest.from_document(
            valid_request(available_renditions=[entry])
        )
        self.assertEqual(request.document_renditions[0].source_asset_id, "4" * 64)
        self.assertEqual(request.document_renditions[0].media_type, "text/plain")

    def test_document_source_id_must_be_raw_bare_core_id(self) -> None:
        with self.assertRaisesRegex(ConversionError, "without sha256"):
            CapabilityRequest.from_document(valid_request(available_renditions=[
                document_rendition(source_asset_id="sha256:" + "4" * 64)
            ]))

    def test_document_mime_must_be_a_supported_document_format(self) -> None:
        with self.assertRaisesRegex(ConversionError, "unsupported document media type"):
            CapabilityRequest.from_document(valid_request(available_renditions=[
                document_rendition(media_type="application/msword")
            ]))

    def test_invalid_schema_and_capability_are_rejected(self) -> None:
        with self.assertRaisesRegex(ConversionError, "unsupported capability request schema"):
            CapabilityRequest.from_document(valid_request(schema="listen_gen.capability-request.v1"))
        with self.assertRaisesRegex(ConversionError, "unsupported requested capability"):
            CapabilityRequest.from_document(valid_request(requested_capability="speak"))

    def test_invalid_media_shape_is_rejected(self) -> None:
        with self.assertRaisesRegex(ConversionError, "media_type must agree"):
            CapabilityRequest.from_document(
                valid_request(available_renditions=[media_rendition(media_type="video/mp4")])
            )
        with self.assertRaisesRegex(ConversionError, "blob path must be absolute"):
            CapabilityRequest.from_document(
                valid_request(
                    available_renditions=[
                        media_rendition(
                            blob={
                                "digest": "sha256:" + "2" * 64,
                                "size_bytes": 12,
                                "path": "media.wav",
                            }
                        )
                    ]
                )
            )

    def test_duplicate_media_ids_are_rejected(self) -> None:
        with self.assertRaisesRegex(ConversionError, "rendition ids must be unique"):
            CapabilityRequest.from_document(
                valid_request(available_renditions=[media_rendition(), media_rendition()])
            )

    def test_document_and_media_ids_share_one_unique_namespace(self) -> None:
        doc = document_rendition(rendition_id="sha256:" + "1" * 64)
        with self.assertRaisesRegex(ConversionError, "rendition ids must be unique"):
            CapabilityRequest.from_document(valid_request(
                available_renditions=[doc, media_rendition()]
            ))

    def test_from_json_file_reads_typed_media_request(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "request.json"
            path.write_text(json.dumps(valid_request()), encoding="utf-8")
            self.assertEqual(
                CapabilityRequest.from_json_file(path).material.material_id,
                "material-1",
            )


if __name__ == "__main__":
    unittest.main()
