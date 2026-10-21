from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.capability import CapabilityRequest
from listen_gen.plan import DerivationKind, UnsupportedCapability, plan
from listen_gen.package_v3 import sha256_of_bytes


def media_request(
    capability: str = "read", *, media: bool = True, media_kind: str = "audio"
) -> CapabilityRequest:
    renditions: list[dict[str, object]] = []
    if media:
        renditions.append({
            "kind": "media",
            "rendition_id": "sha256:" + "1" * 64,
            "media_kind": media_kind,
            "media_type": "audio/wav" if media_kind == "audio" else "video/mp4",
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

    def test_subtitle_input_is_explicit_in_the_plan_without_a_local_path(self) -> None:
        digest = sha256_of_bytes(b"subtitle bytes")
        first = plan(media_request(), subtitle_sha256=digest)
        changed = plan(media_request(), subtitle_sha256=sha256_of_bytes(b"other bytes"))
        derivation = first.derivations[0].describe()
        self.assertEqual(derivation["provider"], "subtitle")
        self.assertIn("SRT/VTT", derivation["label"])
        self.assertEqual(derivation["subtitle_sha256"], digest)
        self.assertNotIn("path", derivation)
        self.assertNotEqual(first.describe(), changed.describe())
        self.assertNotIn("subtitle_sha256", plan(media_request()).derivations[0].describe())

    def test_subtitle_input_identity_must_be_a_canonical_sha256(self) -> None:
        with self.assertRaisesRegex(ValueError, "subtitle_sha256"):
            plan(media_request(), subtitle_sha256="/private/local/path.srt")

    def test_listen_is_satisfied_by_audio_or_video_source(self) -> None:
        for media_kind in ("audio", "video"):
            with self.subTest(media_kind=media_kind):
                self.assertTrue(plan(media_request("listen", media_kind=media_kind)).empty)

    def test_watch_is_satisfied_only_by_video_source(self) -> None:
        self.assertTrue(plan(media_request("watch", media_kind="video")).empty)
        with self.assertRaisesRegex(UnsupportedCapability, "watch requires video media"):
            plan(media_request("watch", media_kind="audio"))

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
