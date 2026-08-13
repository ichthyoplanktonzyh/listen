from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.package_v3 import (
    RELEASE_SCHEMA_V3,
    QualificationError,
    V3Release,
    blob_declaration,
    canonical_json,
    compatibility,
    identity_sha256,
    producer_declaration,
    provenance,
    quality,
    sha256_of_bytes,
    write_v3_package,
    PackageDocumentRendition,
    PackageMediaRendition,
    PackageResource,
)


def sample_release() -> V3Release:
    payload = json.dumps({"language": "en", "text": "Hello.", "segments": [
        {"id": "s0", "index": 0, "language": "en", "start_char": 0, "end_char": 6, "extensions": {}}
    ], "extensions": {}}, sort_keys=True, separators=(",", ":")).encode()
    payload_digest = sha256_of_bytes(payload)
    audio = b"FAKE-AUDIO"
    audio_digest = sha256_of_bytes(audio)
    subject = {
        "material_revision_id": "revision-1",
        "rendition_ids": [],
        "anchor_resource_ids": [],
    }
    source_document = PackageDocumentRendition(
        media_type="text/plain",
        language="en",
        text_blob=blob_declaration("sha256:" + "a" * 64, 10, False),
        origin="source",
        source_asset_id="sha256:" + "b" * 64,
    )
    audio_rendition = PackageMediaRendition(
        kind="audio",
        media_type="audio/wav",
        media_blob=blob_declaration(audio_digest, len(audio), True),
        fingerprint=audio_digest,
        origin="derived",
        producer=producer_declaration(1),
        compatibility=compatibility(
            ["provider:fake"],
            [{"rendition_id": source_document.rendition_id, "resource_id": None}],
        ),
    )
    reading = PackageResource(
        kind="structured_reading",
        schema="listen.payload.structured-reading.v1",
        role="base",
        content_language="en",
        payload_blob=blob_declaration(payload_digest, len(payload), True),
        subject=subject,
        provenance=provenance(1),
        quality=quality(),
    )
    return V3Release(
        created_at_ms=1,
        edition={
            "edition_id": "edition-1",
            "title": "Edition",
            "target_language": "en",
            "support_languages": [],
        },
        material={
            "material_id": "material-1",
            "material_revision_id": "revision-1",
            "title": "Material",
        },
        document_renditions=(source_document,),
        media_renditions=(audio_rendition,),
        resources=(reading,),
        payload_bytes={payload_digest: payload},
        embedded_bytes={audio_digest: audio},
    )


class CanonicalJsonTests(unittest.TestCase):
    def test_keys_are_byte_sorted_and_compact(self) -> None:
        raw = canonical_json({"b": 1, "a": [True, None, "x"]})
        self.assertEqual(raw, b'{"a":[true,null,"x"],"b":1}')

    def test_unicode_is_not_escaped(self) -> None:
        raw = canonical_json({"text": "大熊猫"})
        self.assertEqual(raw, '{"text":"大熊猫"}'.encode("utf-8"))


class IdentityTests(unittest.TestCase):
    def test_document_rendition_identity_uses_media_type_language_text_blob(self) -> None:
        rendition = PackageDocumentRendition(
            media_type="text/plain",
            language="en",
            text_blob=blob_declaration("sha256:" + "a" * 64, 10, False),
            origin="source",
            source_asset_id="sha256:" + "b" * 64,
        )
        expected = identity_sha256(
            {
                "media_type": "text/plain",
                "language": "en",
                "text_blob": {
                    "digest": "sha256:" + "a" * 64,
                    "size_bytes": 10,
                    "embedded": False,
                },
            }
        )
        self.assertEqual(rendition.rendition_id, expected)

    def test_language_none_serializes_as_null_in_identity(self) -> None:
        rendition = PackageDocumentRendition(
            media_type="text/plain",
            language=None,
            text_blob=blob_declaration("sha256:" + "a" * 64, 10, False),
            origin="source",
            source_asset_id="sha256:" + "b" * 64,
        )
        expected = identity_sha256(
            {
                "media_type": "text/plain",
                "language": None,
                "text_blob": {
                    "digest": "sha256:" + "a" * 64,
                    "size_bytes": 10,
                    "embedded": False,
                },
            }
        )
        self.assertEqual(rendition.rendition_id, expected)

    def test_resource_identity_is_descriptor_hash(self) -> None:
        resource = PackageResource(
            kind="structured_reading",
            schema="listen.payload.structured-reading.v1",
            role="base",
            content_language="en",
            payload_blob=blob_declaration("sha256:" + "c" * 64, 10, True),
            subject={"material_revision_id": "r", "rendition_ids": [], "anchor_resource_ids": []},
            provenance=provenance(1),
            quality=quality(),
        )
        self.assertEqual(resource.resource_id, identity_sha256(resource.descriptor()))


class AssistanceDescriptorTests(unittest.TestCase):
    def test_assistance_omits_content_language_entirely(self) -> None:
        resource = PackageResource(
            kind="translation",
            schema="listen.payload.translation.v1",
            role="assistance",
            support_languages=("zh-Hans",),
            content_language="en",
            payload_blob=blob_declaration("sha256:" + "c" * 64, 10, True),
            subject={"material_revision_id": "r", "rendition_ids": [], "anchor_resource_ids": []},
            provenance=provenance(1),
            quality=quality(),
        )
        descriptor = resource.descriptor()
        self.assertNotIn("content_language", descriptor)
        self.assertEqual(descriptor["support_languages"], ["zh-Hans"])

    def test_base_requires_content_language_in_qualification(self) -> None:
        resource = PackageResource(
            kind="structured_reading",
            schema="listen.payload.structured-reading.v1",
            role="base",
            content_language=None,
            payload_blob=blob_declaration("sha256:" + "c" * 64, 10, True),
            subject={"material_revision_id": "r", "rendition_ids": [], "anchor_resource_ids": []},
            provenance=provenance(1),
            quality=quality(),
        )
        with self.assertRaises(QualificationError):
            resource.qualify()


class QualificationTests(unittest.TestCase):
    def test_dependency_closure_checked(self) -> None:
        release = sample_release()
        resource = release.resources[0]
        broken = PackageResource(
            kind="anchor_time_alignment",
            schema="listen.payload.anchor-time-alignment.v1",
            role="base",
            content_language="en",
            dependencies=("sha256:" + "f" * 64,),
            payload_blob=resource.payload_blob,
            subject=resource.subject,
            provenance=provenance(1),
            quality=quality(),
        )
        broken_release = V3Release(
            created_at_ms=1,
            edition=release.edition,
            material=release.material,
            document_renditions=release.document_renditions,
            media_renditions=release.media_renditions,
            resources=(broken,),
            payload_bytes=release.payload_bytes,
            embedded_bytes=release.embedded_bytes,
        )
        with self.assertRaises(QualificationError):
            broken_release.qualify()

    def test_payload_hash_mismatch_rejected(self) -> None:
        release = sample_release()
        mismatched = V3Release(
            created_at_ms=1,
            edition=release.edition,
            material=release.material,
            document_renditions=release.document_renditions,
            media_renditions=release.media_renditions,
            resources=release.resources,
            payload_bytes={},
            embedded_bytes=release.embedded_bytes,
        )
        with self.assertRaises(QualificationError):
            mismatched.qualify()

    def test_derived_rendition_requires_producer_and_compatibility(self) -> None:
        release = sample_release()
        broken = PackageMediaRendition(
            kind="audio",
            media_type="audio/wav",
            media_blob=blob_declaration("sha256:" + "c" * 64, 10, True),
            fingerprint="fp",
            origin="derived",
        )
        with self.assertRaises(QualificationError):
            broken.qualify()

    def test_source_document_requires_source_asset_binding(self) -> None:
        rendition = PackageDocumentRendition(
            media_type="text/plain",
            language="en",
            text_blob=blob_declaration("sha256:" + "a" * 64, 10, False),
            origin="source",
        )
        with self.assertRaises(QualificationError):
            rendition.qualify()


class PackageWriteTests(unittest.TestCase):
    def test_release_is_canonical_and_carrier_is_minimal(self) -> None:
        release = sample_release()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "package.zip"
            package_sha256 = write_v3_package(release, output)
            self.assertEqual(package_sha256, hashlib.sha256(output.read_bytes()).hexdigest())
            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
                self.assertEqual(names[0], "release.json")
                self.assertTrue(all(
                    name == "release.json" or name.startswith("blobs/sha256/")
                    for name in names
                ))
                release_document = json.loads(archive.read("release.json"))
                canonical = canonical_json(release_document)
                self.assertEqual(canonical, archive.read("release.json"))
                self.assertEqual(release_document["schema"], RELEASE_SCHEMA_V3)

    def test_deterministic_bytes(self) -> None:
        release = sample_release()
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "a.zip"
            second = Path(directory) / "b.zip"
            write_v3_package(release, first)
            write_v3_package(release, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_no_local_paths_in_release(self) -> None:
        release = sample_release()
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "package.zip"
            write_v3_package(release, output)
            with zipfile.ZipFile(output) as archive:
                raw = archive.read("release.json")
        for marker in (b"/Users/", b"tmp", b"private", b"//"):
            self.assertNotIn(marker, raw)


if __name__ == "__main__":
    unittest.main()
