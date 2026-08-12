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


def valid_request(**overrides) -> dict:
    document = {
        "schema": "listen_gen.capability-request.v2",
        "version": 2,
        "created_at_ms": 1,
        "attempt_id": "attempt-1",
        "material": {
            "material_id": "material-1",
            "material_revision_id": "revision-1",
            "title": "Material",
        },
        "edition": {
            "edition_id": "edition-1",
            "title": "Edition",
            "target_language": "en",
            "support_languages": [],
        },
        "requested_capability": "read",
        "available_renditions": [
            {
                "kind": "document",
                "rendition_id": "sha256:" + "a" * 64,
                "media_type": "text/plain",
                "language": "en",
                "source_asset_id": "sha256:" + "b" * 64,
                "blob": {"digest": "sha256:" + "c" * 64, "size_bytes": 10, "path": "/tmp/x.txt"},
            }
        ],
        "available_resources": [],
    }
    document.update(overrides)
    return document


class CapabilityRequestTests(unittest.TestCase):
    def test_valid_request_parses(self) -> None:
        request = CapabilityRequest.from_document(valid_request())
        self.assertEqual(request.schema, "listen_gen.capability-request.v2")
        self.assertEqual(request.version, 2)
        self.assertEqual(request.requested_capability, "read")
        self.assertEqual(request.attempt_id, "attempt-1")
        self.assertEqual(len(request.document_renditions), 1)
        self.assertEqual(request.media_renditions, ())
        self.assertEqual(request.resources, ())

    def test_media_rendition_requires_media_kind(self) -> None:
        document = valid_request(available_renditions=[
            {
                "kind": "media",
                "rendition_id": "sha256:" + "a" * 64,
                "media_type": "audio/wav",
                "media_id": "media-1",
                "fingerprint": "fp",
                "blob": {"digest": "sha256:" + "c" * 64, "size_bytes": 10, "path": "/tmp/x.wav"},
            }
        ])
        with self.assertRaises(ConversionError):
            CapabilityRequest.from_document(document)

    def test_media_kind_must_agree_with_media_type(self) -> None:
        document = valid_request(available_renditions=[
            {
                "kind": "media",
                "media_kind": "audio",
                "rendition_id": "sha256:" + "a" * 64,
                "media_type": "video/mp4",
                "media_id": "media-1",
                "fingerprint": "fp",
                "blob": {"digest": "sha256:" + "c" * 64, "size_bytes": 10, "path": "/tmp/x.mp4"},
            }
        ])
        with self.assertRaises(ConversionError):
            CapabilityRequest.from_document(document)

    def test_unknown_schema_rejected(self) -> None:
        with self.assertRaises(ConversionError):
            CapabilityRequest.from_document(valid_request(schema="listen_gen.capability-request.v1"))

    def test_unsupported_capability_rejected(self) -> None:
        with self.assertRaises(ConversionError):
            CapabilityRequest.from_document(valid_request(requested_capability="fly"))

    def test_duplicate_rendition_ids_rejected(self) -> None:
        rendition = {
            "kind": "document",
            "rendition_id": "sha256:" + "a" * 64,
            "media_type": "text/plain",
            "language": "en",
            "source_asset_id": "sha256:" + "b" * 64,
            "blob": {"digest": "sha256:" + "c" * 64, "size_bytes": 10, "path": "/tmp/x.txt"},
        }
        with self.assertRaises(ConversionError):
            CapabilityRequest.from_document(
                valid_request(available_renditions=[rendition, rendition])
            )

    def test_non_absolute_blob_path_rejected(self) -> None:
        document = valid_request()
        document["available_renditions"][0]["blob"]["path"] = "relative.txt"
        with self.assertRaises(ConversionError):
            CapabilityRequest.from_document(document)

    def test_support_languages_must_be_unique(self) -> None:
        with self.assertRaises(ConversionError):
            CapabilityRequest.from_document(
                valid_request(**{
                    "edition": {
                        "edition_id": "e",
                        "title": "E",
                        "target_language": "en",
                        "support_languages": ["zh-Hans", "zh-Hans"],
                    }
                })
            )

    def test_attempt_id_optional(self) -> None:
        request = CapabilityRequest.from_document(valid_request(**{"attempt_id": None}))
        self.assertIsNone(request.attempt_id)

    def test_from_json_file_reads_typed_document(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "request.json"
            path.write_text(json.dumps(valid_request()), encoding="utf-8")
            request = CapabilityRequest.from_json_file(path)
            self.assertEqual(request.requested_capability, "read")


if __name__ == "__main__":
    unittest.main()
