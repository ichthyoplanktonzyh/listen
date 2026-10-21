from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.capability import CapabilityRequest
from listen_gen.plan import DerivationKind, UnsupportedCapability, plan


def media_request(capability: str = "read", *, media: bool = True) -> CapabilityRequest:
    renditions: list[dict[str, object]] = []
    if media:
        renditions.append({
            "kind": "media",
            "rendition_id": "sha256:" + "1" * 64,
            "media_kind": "audio",
            "media_type": "audio/wav",
            "media_id": "media-1",
            "fingerprint": "media-fingerprint",
            "blob": {
                "digest": "sha256:" + "2" * 64,
                "size_bytes": 10,
                "path": "/tmp/media.wav",
            },
        })
    return CapabilityRequest.from_document({
        "schema": "listen_gen.capability-request.v2",
        "version": 2,
        "created_at_ms": 1,
        "material": {
            "material_id": "material-1",
            "material_revision_id": "revision-1",
            "title": "Test",
        },
        "edition": {
            "edition_id": "edition-1",
            "title": "Test",
            "target_language": "en-US",
            "support_languages": [],
        },
        "requested_capability": capability,
        "available_renditions": renditions,
    })


class PlanTests(unittest.TestCase):
    def test_read_from_media_plans_transcription(self) -> None:
        production_plan = plan(media_request())
        self.assertEqual(len(production_plan.derivations), 1)
        derivation = production_plan.derivations[0]
        self.assertEqual(derivation.kind, DerivationKind.MEDIA_READ)
        self.assertEqual(derivation.provider, "asr")

    def test_synchronized_listen_from_media_uses_the_same_asr_derivation(self) -> None:
        production_plan = plan(media_request("synchronized_read_listen"))
        self.assertEqual(
            [entry.kind for entry in production_plan.derivations],
            [DerivationKind.MEDIA_READ],
        )

    def test_listen_and_watch_are_satisfied_by_source_media(self) -> None:
        for capability in ("listen", "watch"):
            with self.subTest(capability=capability):
                self.assertTrue(plan(media_request(capability)).empty)

    def test_capability_without_media_is_unsupported(self) -> None:
        for capability in ("read", "listen", "watch", "synchronized_read_listen"):
            with self.subTest(capability=capability):
                with self.assertRaises(UnsupportedCapability):
                    plan(media_request(capability, media=False))

    def test_plan_description_is_stable(self) -> None:
        request = media_request()
        self.assertEqual(plan(request).describe(), plan(request).describe())


if __name__ == "__main__":
    unittest.main()
