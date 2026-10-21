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

    def test_document_material_is_rejected_with_actionable_error(self) -> None:
        request = valid_request(available_renditions=[{"kind": "document"}])
        with self.assertRaisesRegex(
            ConversionError,
            "document material input is not supported; provide audio or video media",
        ):
            CapabilityRequest.from_document(request)

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
