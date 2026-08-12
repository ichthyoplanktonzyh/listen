from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.capability import CapabilityRequest
from listen_gen.plan import (
    DerivationKind,
    ProductionPlan,
    UnsupportedCapability,
    plan,
)


def document_request(**overrides) -> CapabilityRequest:
    document = {
        "schema": "listen_gen.capability-request.v2",
        "version": 2,
        "created_at_ms": 1,
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
    return CapabilityRequest.from_document(document)


def media_request(**overrides) -> CapabilityRequest:
    document = {
        "schema": "listen_gen.capability-request.v2",
        "version": 2,
        "created_at_ms": 1,
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
                "kind": "media",
                "media_kind": "audio",
                "rendition_id": "sha256:" + "d" * 64,
                "media_type": "audio/wav",
                "media_id": "media-1",
                "fingerprint": "fp-1",
                "blob": {"digest": "sha256:" + "e" * 64, "size_bytes": 10, "path": "/tmp/x.wav"},
            }
        ],
        "available_resources": [],
    }
    document.update(overrides)
    return CapabilityRequest.from_document(document)


class PlanTests(unittest.TestCase):
    def test_read_from_document_plans_document_derivation(self) -> None:
        production_plan = plan(document_request())
        self.assertFalse(production_plan.empty)
        self.assertEqual(len(production_plan.derivations), 1)
        self.assertEqual(
            production_plan.derivations[0].kind, DerivationKind.DOCUMENT_READ
        )
        self.assertEqual(
            production_plan.derivations[0].input_rendition_ids,
            ("sha256:" + "a" * 64,),
        )

    def test_read_from_media_plans_media_derivation(self) -> None:
        production_plan = plan(media_request())
        self.assertEqual(len(production_plan.derivations), 1)
        self.assertEqual(
            production_plan.derivations[0].kind, DerivationKind.MEDIA_READ
        )

    def test_listen_from_document_plans_tts(self) -> None:
        production_plan = plan(document_request(requested_capability="listen"))
        self.assertEqual(len(production_plan.derivations), 1)
        self.assertEqual(
            production_plan.derivations[0].kind, DerivationKind.DOCUMENT_LISTEN
        )
        self.assertEqual(production_plan.derivations[0].provider, "tts")

    def test_listen_from_media_is_already_satisfied(self) -> None:
        production_plan = plan(media_request(requested_capability="listen"))
        self.assertTrue(production_plan.empty)

    def test_watch_from_document_is_unsupported(self) -> None:
        with self.assertRaises(UnsupportedCapability):
            plan(document_request(requested_capability="watch"))

    def test_watch_from_media_is_already_satisfied(self) -> None:
        production_plan = plan(media_request(requested_capability="watch"))
        self.assertTrue(production_plan.empty)

    def test_synchronized_from_document_plans_tts(self) -> None:
        production_plan = plan(
            document_request(requested_capability="synchronized_read_listen")
        )
        self.assertEqual(len(production_plan.derivations), 1)
        self.assertEqual(
            production_plan.derivations[0].kind, DerivationKind.DOCUMENT_LISTEN
        )

    def test_synchronized_from_media_plans_media_derivation(self) -> None:
        production_plan = plan(
            media_request(requested_capability="synchronized_read_listen")
        )
        self.assertEqual(len(production_plan.derivations), 1)
        self.assertEqual(
            production_plan.derivations[0].kind, DerivationKind.MEDIA_READ
        )

    def test_read_reuses_existing_structured_reading(self) -> None:
        resource = {
            "resource_id": "sha256:" + "f" * 64,
            "kind": "structured_reading",
            "schema": "listen.payload.structured-reading.v1",
            "role": "base",
            "blob": {"digest": "sha256:" + "9" * 64, "size_bytes": 10, "path": "/tmp/r.json"},
        }
        production_plan = plan(
            document_request(available_resources=[resource])
        )
        self.assertTrue(production_plan.empty)

    def test_empty_inputs_are_unsupported(self) -> None:
        with self.assertRaises(UnsupportedCapability):
            plan(document_request(available_renditions=[]))

    def test_plan_is_deterministic(self) -> None:
        first = plan(document_request()).describe()
        second = plan(document_request()).describe()
        self.assertEqual(first, second)


if __name__ == "__main__":
    unittest.main()
