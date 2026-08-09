from __future__ import annotations

import hashlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from contextlib import redirect_stderr
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.asr import FixtureAsrAdapter, package_media
from listen_gen.cli import main
from listen_gen.package import (
    RESOURCE_SCHEMAS,
    ConversionError,
    ResourceFile,
    package_from_lltimeline,
)
from listen_gen.package_v2 import (
    DELIVERY_SCHEMA,
    RELEASE_SCHEMA,
    ReleaseSpec,
    V2_RESOURCE_SCHEMAS,
    build_v2_carrier,
    write_v2_package,
)

MEDIA = ROOT / "tests" / "fixtures" / "sample-media.wav"
FIXTURE = ROOT / "tests" / "fixtures" / "sample.asr.json"
LEGACY_FIXTURE = ROOT / "tests" / "fixtures" / "sample.lltimeline.json"
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
MEDIA_SHA256 = f"sha256:{hashlib.sha256(MEDIA.read_bytes()).hexdigest()}"
SHA256_RE = r"sha256:[0-9a-f]{64}"


def canonical_v2(value: object) -> bytes:
    return json.dumps(
        value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False
    ).encode("utf-8")


def spec(**overrides: object) -> ReleaseSpec:
    values = dict(
        edition_id="edition-42",
        title="V2 fixture lesson",
        material_id="material-7",
        material_revision_id="rev-2026-08",
        target_language="en-US",
        media_type="audio/wav",
        support_languages=(),
        media_delivery="referenced",
    )
    values.update(overrides)
    return ReleaseSpec(**values)


def v1_envelope(
    *,
    kind: str,
    payload: dict[str, object],
    tool_version: str = "0.4.0",
    dependencies: tuple[ResourceFile, ...] = (),
) -> ResourceFile:
    """A direct v1 ResourceFile envelope for carrier-level tests."""
    document = {
        "schema": RESOURCE_SCHEMAS[kind],
        "kind": kind,
        "subject": {"media_fingerprint": MEDIA_SHA256},
        "dependencies": [
            {"resource_id": resource.resource_id, "kind": resource.kind}
            for resource in dependencies
        ],
        "provenance": {
            "created_at_ms": 1785542400000,
            "tool": {"id": "listen-gen.asr-package", "version": tool_version},
        },
        "quality": {"review_status": "machine_checked"},
        "payload": payload,
    }
    return ResourceFile(
        kind=kind,
        path=f"resources/{kind.replace('_', '-')}.json",
        body=canonical_v2(document),
        required=kind == "subtitle_text_track",
    )


def v1_pair(*, word_version: str = "0.4.1") -> list[ResourceFile]:
    """The canonical two-resource v1 fixture as direct envelopes.

    Both envelopes share byte-identical payload bytes (the subtitle payload)
    so the v2 carrier must deduplicate them by digest while keeping distinct
    resource identities from their different provenance.
    """
    payload: dict[str, object] = {
        "language": "en-US",
        "source_kind": "asr",
        "sentences": [{"id": "sentence.0", "index": 0, "start_ms": 0, "end_ms": 100}],
    }
    subtitle = v1_envelope(kind="subtitle_text_track", payload=payload)
    word = v1_envelope(
        kind="word_timeline",
        payload=payload,
        tool_version=word_version,
        dependencies=(subtitle,),
    )
    return [subtitle, word]


def build_v2(output: Path, **overrides: object) -> dict[str, object]:
    return package_media(
        MEDIA,
        output,
        FixtureAsrAdapter(FIXTURE),
        title="V2 fixture lesson",
        media_kind="audio",
        duration_ms=2200,
        created_at_ms=1785542400000,
        package_version=2,
        release_spec=spec(**overrides),
    )


def v2_argv(
    output: Path,
    *,
    media_delivery: str | None = None,
    target_language: str = "en-US",
    support_languages: tuple[str, ...] = (),
    media_type: str = "audio/wav",
    machine: bool = False,
) -> list[str]:
    argv = [
        "package", "from-media", str(MEDIA),
        "--output", str(output),
        "--provider", "fixture", "--fixture", str(FIXTURE),
        "--title", "V2 fixture lesson", "--media-kind", "audio",
        "--duration-ms", "2200", "--created-at-ms", "1785542400000",
        "--package-version", "2",
        "--edition-id", "edition-42",
        "--material-id", "material-7",
        "--material-revision-id", "rev-2026-08",
        "--target-language", target_language,
        "--media-type", media_type,
    ]
    for language in support_languages:
        argv += ["--support-language", language]
    if media_delivery is not None:
        argv += ["--media-delivery", media_delivery]
    if machine:
        argv.append("--machine-events")
    return argv


def drop_flag(argv: list[str], flag: str) -> list[str]:
    """Remove ``flag`` and its value from a generated argv."""
    position = argv.index(flag)
    return argv[:position] + argv[position + 2:]


def run_cli(argv: list[str]) -> subprocess.CompletedProcess[str]:
    env = dict(os.environ)
    env["PYTHONPATH"] = str(ROOT / "src")
    return subprocess.run(
        [sys.executable, "-m", "listen_gen", *argv],
        capture_output=True,
        text=True,
        env=env,
        timeout=60,
    )


def parse_events(stdout: str) -> list[dict[str, object]]:
    return [json.loads(line) for line in stdout.splitlines() if line]


class V2ReferencedCarrierTests(unittest.TestCase):
    def test_referenced_carrier_inventory_profile_and_identities(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson-v2.listenpkg"
            result = build_v2(output)
            self.assertEqual(result["package_version"], 2)
            self.assertEqual(result["delivery_profile"], "hybrid")
            self.assertRegex(result["release_id"], SHA256_RE)

            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
                self.assertNotIn("manifest.json", names)
                self.assertTrue(
                    all(not name.startswith("resources/") for name in names)
                )
                release_raw = archive.read("release.json")
                delivery_raw = archive.read("delivery.json")
                release = json.loads(release_raw)
                delivery = json.loads(delivery_raw)
                blob_names = sorted(
                    name for name in names if name.startswith("blobs/sha256/")
                )
                payload_digests = [
                    entry["descriptor"]["payload_blob"]["digest"]
                    for entry in release["resources"]
                ]
                # Referenced media is never shipped, so only the payload blobs
                # appear and the carrier is honestly hybrid.
                expected_blobs = sorted(
                    f"blobs/sha256/{digest.removeprefix('sha256:')}"
                    for digest in payload_digests
                )
                self.assertEqual(blob_names, expected_blobs)
                self.assertEqual(
                    names, ["release.json", "delivery.json"] + expected_blobs
                )
                for blob_name in blob_names:
                    self.assertRegex(blob_name, r"^blobs/sha256/[0-9a-f]{64}$")
                    digest = f"sha256:{blob_name.removeprefix('blobs/sha256/')}"
                    self.assertEqual(
                        digest,
                        f"sha256:{hashlib.sha256(archive.read(blob_name)).hexdigest()}",
                    )

            self.assertEqual(
                release_raw,
                canonical_v2(release),
                "release.json must be canonical identity JSON",
            )
            self.assertFalse(release_raw.endswith(b"\n"))
            self.assertFalse(delivery_raw.endswith(b"\n"))
            self.assertEqual(release["schema"], RELEASE_SCHEMA)
            self.assertEqual(delivery["schema"], DELIVERY_SCHEMA)
            self.assertEqual(
                delivery["release_id"],
                f"sha256:{hashlib.sha256(release_raw).hexdigest()}",
            )
            self.assertEqual(delivery["profile"], "hybrid")

    def test_release_document_structure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson-v2.listenpkg"
            build_v2(output)
            with zipfile.ZipFile(output) as archive:
                release = json.loads(archive.read("release.json"))
                delivery = json.loads(archive.read("delivery.json"))
            self.assertEqual(
                set(release),
                {
                    "schema", "created_at_ms", "edition", "material",
                    "entrypoints", "resources", "renditions", "extensions",
                },
            )
            self.assertEqual(
                set(release["edition"]),
                {"edition_id", "title", "target_language", "support_languages"},
            )
            self.assertEqual(release["edition"]["edition_id"], "edition-42")
            self.assertEqual(release["edition"]["target_language"], "en-US")
            self.assertEqual(release["edition"]["support_languages"], [])
            self.assertEqual(
                set(release["material"]),
                {"material_id", "material_revision_id", "title"},
            )
            self.assertEqual(release["material"]["material_revision_id"], "rev-2026-08")
            self.assertEqual(
                [entry["entrypoint_id"] for entry in release["entrypoints"]],
                ["rendition", "transcript"],
            )
            rendition = release["renditions"][0]
            self.assertRegex(rendition["rendition_id"], SHA256_RE)
            self.assertEqual(
                rendition["descriptor"]["schema"], "listen.rendition.audio.v1"
            )
            self.assertEqual(rendition["descriptor"]["kind"], "audio")
            self.assertEqual(rendition["descriptor"]["media_type"], "audio/wav")
            self.assertEqual(
                rendition["descriptor"]["media_blob"],
                {"digest": MEDIA_SHA256, "size_bytes": MEDIA.stat().st_size},
            )
            self.assertEqual(
                release["entrypoints"][0]["rendition_id"],
                rendition["rendition_id"],
            )
            # The primary transcript entrypoint names the required subtitle.
            subtitle = [
                entry for entry in release["resources"]
                if entry["descriptor"]["kind"] == "subtitle_text_track"
            ]
            self.assertEqual(len(subtitle), 1)
            self.assertTrue(subtitle[0]["required"])
            self.assertEqual(
                release["entrypoints"][1]["resource_id"], subtitle[0]["resource_id"]
            )
            self.assertRegex(delivery["release_id"], SHA256_RE)

    def test_resource_descriptors_are_strict_and_reference_declared_ids(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson-v2.listenpkg"
            build_v2(output)
            with zipfile.ZipFile(output) as archive:
                release = json.loads(archive.read("release.json"))
            resource_ids = {entry["resource_id"] for entry in release["resources"]}
            rendition_ids = {entry["rendition_id"] for entry in release["renditions"]}
            for entry in release["resources"]:
                descriptor = entry["descriptor"]
                self.assertEqual(
                    set(descriptor),
                    {
                        "schema", "kind", "role", "subject", "dependencies",
                        "provenance", "quality", "content_language",
                        "payload_blob", "extensions",
                    },
                )
                self.assertEqual(descriptor["role"], "base")
                self.assertEqual(
                    descriptor["schema"],
                    V2_RESOURCE_SCHEMAS[descriptor["kind"]],
                )
                self.assertEqual(descriptor["content_language"], "en-US")
                self.assertNotIn("support_languages", descriptor)
                subject = descriptor["subject"]
                self.assertEqual(subject["material_revision_id"], "rev-2026-08")
                self.assertEqual(set(subject["rendition_ids"]), rendition_ids)
                self.assertTrue(set(subject["anchor_resource_ids"]) <= resource_ids)
                for dependency in descriptor["dependencies"]:
                    self.assertEqual(set(dependency), {"resource_id"})
                    self.assertIn(dependency["resource_id"], resource_ids)
                provenance = descriptor["provenance"]
                self.assertEqual(
                    set(provenance),
                    {
                        "created_at_ms", "tool", "input_resource_ids",
                        "extensions", "provider", "model", "config_sha256",
                    },
                )
                self.assertTrue(set(provenance["input_resource_ids"]) <= resource_ids)
                self.assertEqual(
                    provenance["extensions"],
                    {"media_fingerprint": MEDIA_SHA256},
                )
                self.assertEqual(
                    set(provenance["tool"]), {"id", "version"}
                )
                quality = descriptor["quality"]
                self.assertEqual(
                    set(quality), {"review_status", "warnings", "extensions"}
                )
                payload_blob = descriptor["payload_blob"]
                self.assertRegex(payload_blob["digest"], SHA256_RE)
                self.assertIsInstance(payload_blob["size_bytes"], int)
                self.assertGreater(payload_blob["size_bytes"], 0)
            # Release order matches the v1 order and the v1 required policy.
            self.assertEqual(
                [entry["descriptor"]["kind"] for entry in release["resources"]],
                ["subtitle_text_track", "word_timeline"],
            )
            self.assertEqual(
                [entry["required"] for entry in release["resources"]],
                [True, False],
            )

    def test_dependency_edges_map_exactly_onto_v1_dependencies(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson-v2.listenpkg"
            build_v2(output)
            with zipfile.ZipFile(output) as archive:
                release = json.loads(archive.read("release.json"))
            by_kind = {
                entry["descriptor"]["kind"]: entry["resource_id"]
                for entry in release["resources"]
            }
            word = next(
                entry for entry in release["resources"]
                if entry["descriptor"]["kind"] == "word_timeline"
            )
            self.assertEqual(
                word["descriptor"]["dependencies"],
                [{"resource_id": by_kind["subtitle_text_track"]}],
            )
            self.assertEqual(
                word["descriptor"]["subject"]["anchor_resource_ids"],
                [by_kind["subtitle_text_track"]],
            )
            self.assertEqual(
                word["descriptor"]["provenance"]["input_resource_ids"],
                [by_kind["subtitle_text_track"]],
            )
            subtitle = next(
                entry for entry in release["resources"]
                if entry["descriptor"]["kind"] == "subtitle_text_track"
            )
            self.assertEqual(subtitle["descriptor"]["dependencies"], [])
            self.assertEqual(subtitle["descriptor"]["subject"]["anchor_resource_ids"], [])
            self.assertEqual(subtitle["descriptor"]["provenance"]["input_resource_ids"], [])


class V2EmbeddedCarrierTests(unittest.TestCase):
    def test_embedded_carrier_includes_exact_media_bytes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "embedded.listenpkg"
            result = build_v2(output, media_delivery="embedded")
            self.assertEqual(result["delivery_profile"], "embedded")
            with zipfile.ZipFile(output) as archive:
                release = json.loads(archive.read("release.json"))
                delivery = json.loads(archive.read("delivery.json"))
                media_blob_name = (
                    f"blobs/sha256/{MEDIA_SHA256.removeprefix('sha256:')}"
                )
                self.assertIn(media_blob_name, archive.namelist())
                self.assertEqual(archive.read(media_blob_name), MEDIA.read_bytes())
                blob_names = [
                    name for name in archive.namelist()
                    if name.startswith("blobs/sha256/")
                ]
                self.assertEqual(len(blob_names), 1 + len(release["resources"]))
                delivered_digests = {entry["digest"] for entry in delivery["blobs"]}
                self.assertIn(MEDIA_SHA256, delivered_digests)
                for entry in release["resources"]:
                    self.assertIn(
                        entry["descriptor"]["payload_blob"]["digest"],
                        delivered_digests,
                    )
                for entry in delivery["blobs"]:
                    self.assertEqual(entry["hints"], [])
                    self.assertIn(
                        f"blobs/sha256/{entry['digest'].removeprefix('sha256:')}",
                        archive.namelist(),
                    )

    def test_embedded_generation_never_reads_media_into_memory(self) -> None:
        media_bytes = MEDIA.read_bytes()
        original = Path.read_bytes
        seen: list[str] = []

        def guarded(path_self: Path, *args: object, **kwargs: object) -> bytes:
            seen.append(str(path_self))
            return original(path_self, *args, **kwargs)

        Path.read_bytes = guarded
        try:
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "embedded.listenpkg"
                result = build_v2(output, media_delivery="embedded")
                self.assertEqual(result["delivery_profile"], "embedded")
                media_blob_name = (
                    f"blobs/sha256/{MEDIA_SHA256.removeprefix('sha256:')}"
                )
                with zipfile.ZipFile(output) as archive:
                    self.assertEqual(archive.read(media_blob_name), media_bytes)
        finally:
            Path.read_bytes = original
        self.assertNotIn(str(MEDIA), seen)


class V2DeterminismTests(unittest.TestCase):
    def test_stable_bytes_and_identities(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.listenpkg"
            second = Path(directory) / "second.listenpkg"
            one, two = build_v2(first), build_v2(second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(one["package_sha256"], two["package_sha256"])
            self.assertEqual(one["release_id"], two["release_id"])
            with zipfile.ZipFile(first) as archive:
                release_raw = archive.read("release.json")
                release = json.loads(release_raw)
                for entry in release["resources"]:
                    self.assertEqual(
                        entry["resource_id"],
                        f"sha256:{hashlib.sha256(canonical_v2(entry['descriptor'])).hexdigest()}",
                    )
                for entry in release["renditions"]:
                    self.assertEqual(
                        entry["rendition_id"],
                        f"sha256:{hashlib.sha256(canonical_v2(entry['descriptor'])).hexdigest()}",
                    )
            self.assertEqual(
                one["release_id"],
                f"sha256:{hashlib.sha256(release_raw).hexdigest()}",
            )

    def test_embedded_bytes_are_deterministic(self) -> None:
        # The file-backed streaming writer must produce the same byte-identical
        # archive profile as the in-memory writestr path.
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.listenpkg"
            second = Path(directory) / "second.listenpkg"
            build_v2(first, media_delivery="embedded")
            build_v2(second, media_delivery="embedded")
            self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_v2_payloads_preserve_v1_payload_shapes_verbatim(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            v1_output = Path(directory) / "v1.listenpkg"
            v2_output = Path(directory) / "v2.listenpkg"
            package_media(
                MEDIA, v1_output, FixtureAsrAdapter(FIXTURE),
                title="V2 fixture lesson", media_kind="audio", duration_ms=2200,
                created_at_ms=1785542400000,
            )
            build_v2(v2_output)
            v1_payloads: dict[str, object] = {}
            with zipfile.ZipFile(v1_output) as archive:
                manifest = json.loads(archive.read("manifest.json"))
                for entry in manifest["resources"]:
                    envelope = json.loads(archive.read(entry["path"]))
                    v1_payloads[entry["kind"]] = envelope["payload"]
            v2_payloads: dict[str, object] = {}
            with zipfile.ZipFile(v2_output) as archive:
                release = json.loads(archive.read("release.json"))
                for entry in release["resources"]:
                    descriptor = entry["descriptor"]
                    blob_name = (
                        "blobs/sha256/"
                        + descriptor["payload_blob"]["digest"].removeprefix("sha256:")
                    )
                    v2_payloads[descriptor["kind"]] = json.loads(
                        archive.read(blob_name)
                    )
            self.assertEqual(v1_payloads, v2_payloads)


class V2ZipMetadataTests(unittest.TestCase):
    def test_exact_zip_profile_no_path_leak(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson-v2.listenpkg"
            build_v2(output, media_delivery="embedded")
            raw = output.read_bytes()
            self.assertNotIn(str(MEDIA).encode(), raw)
            self.assertNotIn(str(FIXTURE).encode(), raw)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(archive.comment, b"")
                names = archive.namelist()
                self.assertEqual(len(names), len(set(names)))
                for name in names:
                    self.assertNotIn("\\", name)
                    self.assertFalse(name.startswith("/"))
                    self.assertNotIn("..", name.split("/"))
                for info in archive.infolist():
                    self.assertFalse(info.is_dir())
                    self.assertEqual(info.date_time, ZIP_TIMESTAMP)
                    self.assertEqual(info.compress_type, zipfile.ZIP_STORED)
                    self.assertEqual(info.create_system, 3)
                    self.assertEqual(info.external_attr, 0o100644 << 16)
                    self.assertEqual(info.extra, b"")
                    # No data descriptors: sizes are known up front.
                    self.assertEqual(info.flag_bits & 0x0008, 0)


class V2WriterMutationTests(unittest.TestCase):
    def test_writer_mutation_preserves_preexisting_output_and_leaves_no_temp(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            media = root / "media.wav"
            media.write_bytes(MEDIA.read_bytes())
            fingerprint = f"sha256:{hashlib.sha256(media.read_bytes()).hexdigest()}"
            size = media.stat().st_size
            output = root / "existing.listenpkg"
            original = b"existing-package-must-survive"
            output.write_bytes(original)

            carrier = build_v2_carrier(
                resources=v1_pair(),
                media_sha256=fingerprint,
                media_size=size,
                media_kind="audio",
                media_source=media,
                spec=spec(media_delivery="embedded"),
                created_at_ms=1785542400000,
            )
            # The media changes after the carrier declares its identity; the
            # writer's streaming digest/size check is the final mutation gate.
            media.write_bytes(media.read_bytes() + b"changed")
            with self.assertRaisesRegex(
                ConversionError, "media input changed during processing"
            ):
                write_v2_package(output, carrier)

            self.assertEqual(output.read_bytes(), original)
            self.assertEqual(list(root.glob(f".{output.name}.*.tmp")), [])


class V2StreamedZip64Tests(unittest.TestCase):
    def test_streamed_media_declares_size_before_zip_open(self) -> None:
        """The file-backed ZipInfo must carry the declared media size when it
        reaches ``ZipFile.open`` so Python can select ZIP64 for media beyond
        the ZIP32 limit and knows the expected size before streaming.

        The probe is a narrow runtime spy on ``zipfile.ZipFile.open`` that
        records every ZipInfo as it is handed over for writing; it proves the
        declared size flows through without allocating a multi-GB fixture.
        """
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            media = root / "media.wav"
            media.write_bytes(MEDIA.read_bytes())
            carrier = build_v2_carrier(
                resources=v1_pair(),
                media_sha256=f"sha256:{hashlib.sha256(media.read_bytes()).hexdigest()}",
                media_size=media.stat().st_size,
                media_kind="audio",
                media_source=media,
                spec=spec(media_delivery="embedded"),
                created_at_ms=1785542400000,
            )
            streamed = next(
                entry for entry in carrier["entries"]
                if entry.source_path is not None
            )
            output = root / "streamed.listenpkg"

            original_open = zipfile.ZipFile.open
            declared: dict[str, int] = {}

            def spied_open(
                self: zipfile.ZipFile,
                name: object,
                mode: str = "r",
                pwd: object = None,
                *,
                force_zip64: bool = False,
            ) -> object:
                if mode == "w" and isinstance(name, zipfile.ZipInfo):
                    declared[name.filename] = name.file_size
                return original_open(self, name, mode, pwd, force_zip64=force_zip64)

            zipfile.ZipFile.open = spied_open
            try:
                write_v2_package(output, carrier)
            finally:
                zipfile.ZipFile.open = original_open

            self.assertIn(
                streamed.name, declared,
                "the file-backed media entry must be written through ZipFile.open",
            )
            self.assertEqual(
                declared[streamed.name], streamed.size_bytes,
                "the ZipInfo passed to ZipFile.open must declare the "
                "file-backed media size so ZIP64 selection sees it",
            )
            for entry in carrier["entries"]:
                self.assertIn(entry.name, declared)
                expected = len(entry.body) if entry.body is not None else entry.size_bytes
                self.assertEqual(
                    declared[entry.name], expected,
                    "every ZipInfo must reach ZipFile.open with its exact "
                    "declared size before any bytes are streamed",
                )
            # The spy changes no behavior: the archive stays byte-identical.
            rerun = root / "rerun.listenpkg"
            write_v2_package(rerun, carrier)
            self.assertEqual(output.read_bytes(), rerun.read_bytes())


class V2DeduplicationTests(unittest.TestCase):
    def test_duplicate_payloads_share_one_blob_and_keep_distinct_identities(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "dedup.listenpkg"
            carrier = build_v2_carrier(
                resources=v1_pair(word_version="0.4.2"),
                media_sha256=MEDIA_SHA256,
                media_size=MEDIA.stat().st_size,
                media_kind="audio",
                media_source=None,
                spec=spec(),
                created_at_ms=1785542400000,
            )
            release = carrier["release"]
            delivery = carrier["delivery"]
            self.assertEqual(len(release["resources"]), 2)
            resource_ids = {
                entry["resource_id"] for entry in release["resources"]
            }
            self.assertEqual(len(resource_ids), 2, "distinct resource identities")
            payload_digests = {
                entry["descriptor"]["payload_blob"]["digest"]
                for entry in release["resources"]
            }
            self.assertEqual(len(payload_digests), 1, "shared payload digest")
            (shared_digest,) = payload_digests
            delivered_digests = [entry["digest"] for entry in delivery["blobs"]]
            self.assertEqual(len(delivered_digests), 1)
            self.assertEqual(delivered_digests, [shared_digest])
            self.assertEqual(
                delivery["blobs"][0]["size_bytes"],
                release["resources"][0]["descriptor"]["payload_blob"]["size_bytes"],
            )

            write_v2_package(output, carrier)
            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
                blob_path = f"blobs/sha256/{shared_digest.removeprefix('sha256:')}"
                self.assertEqual(
                    [name for name in names if name.startswith("blobs/sha256/")],
                    [blob_path],
                )
                self.assertEqual(
                    json.loads(archive.read(blob_path)),
                    {"language": "en-US", "source_kind": "asr",
                     "sentences": [{"id": "sentence.0", "index": 0,
                                    "start_ms": 0, "end_ms": 100}]},
                )

    def test_same_digest_with_different_size_fails(self) -> None:
        payload: dict[str, object] = {
            "language": "en-US",
            "source_kind": "asr",
            "sentences": [],
        }
        subtitle = v1_envelope(kind="subtitle_text_track", payload=payload)
        payload_digest = f"sha256:{hashlib.sha256(canonical_v2(payload)).hexdigest()}"
        with tempfile.TemporaryDirectory() as directory:
            media = Path(directory) / "media.wav"
            media.write_bytes(canonical_v2(payload))
            with self.assertRaisesRegex(ConversionError, "different size"):
                build_v2_carrier(
                    resources=[subtitle],
                    media_sha256=payload_digest,
                    media_size=len(canonical_v2(payload)) + 1,
                    media_kind="audio",
                    media_source=media,
                    spec=spec(media_delivery="embedded"),
                    created_at_ms=1785542400000,
                )


class V2CarrierInvariantTests(unittest.TestCase):
    def test_embedded_requires_a_regular_media_source(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            missing = root / "missing.wav"
            with self.assertRaisesRegex(
                ConversionError, "requires the media source path"
            ):
                build_v2_carrier(
                    resources=v1_pair(),
                    media_sha256=MEDIA_SHA256,
                    media_size=1,
                    media_kind="audio",
                    media_source=None,
                    spec=spec(media_delivery="embedded"),
                    created_at_ms=1785542400000,
                )
            with self.assertRaisesRegex(
                ConversionError, "does not exist"
            ):
                build_v2_carrier(
                    resources=v1_pair(),
                    media_sha256=MEDIA_SHA256,
                    media_size=1,
                    media_kind="audio",
                    media_source=missing,
                    spec=spec(media_delivery="embedded"),
                    created_at_ms=1785542400000,
                )
            with self.assertRaisesRegex(
                ConversionError, "not a regular file"
            ):
                build_v2_carrier(
                    resources=v1_pair(),
                    media_sha256=MEDIA_SHA256,
                    media_size=1,
                    media_kind="audio",
                    media_source=root,
                    spec=spec(media_delivery="embedded"),
                    created_at_ms=1785542400000,
                )

    def test_referenced_mode_rejects_a_media_source(self) -> None:
        with self.assertRaisesRegex(
            ConversionError, "does not accept a media source path"
        ):
            build_v2_carrier(
                resources=v1_pair(),
                media_sha256=MEDIA_SHA256,
                media_size=MEDIA.stat().st_size,
                media_kind="audio",
                media_source=MEDIA,
                spec=spec(),
                created_at_ms=1785542400000,
            )

    def test_malformed_media_digest_is_rejected(self) -> None:
        cases = [
            None,
            123,
            "sha256:ABC",
            "sha256:ABCDEFGH",
            "sha256:" + "f" * 63,
            "sha256:" + "f" * 65,
            "sha256:" + "g" * 64,
            "sha256:" + "F" * 64,
            "f" * 64,
            "not-a-digest",
        ]
        for digest in cases:
            with self.assertRaisesRegex(
                ConversionError, "lowercase SHA-256"
            ):
                build_v2_carrier(
                    resources=v1_pair(),
                    media_sha256=digest,
                    media_size=MEDIA.stat().st_size,
                    media_kind="audio",
                    media_source=None,
                    spec=spec(),
                    created_at_ms=1785542400000,
                )


class V2MediaTypeValidationTests(unittest.TestCase):
    def test_invalid_media_type_forms_are_rejected(self) -> None:
        cases = [
            "audio",
            "/wav",
            "audio/",
            "audio/wav/extra",
            "audio /wav",
            "audio/wav;charset=binary",
            'audio/"wav"',
            "audio/wav,audio/mp3",
        ]
        for media_type in cases:
            with self.assertRaisesRegex(
                ConversionError, "parameter-free MIME type"
            ):
                spec(media_type=media_type)

    def test_mismatched_media_type_is_rejected_in_ordinary_mode(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "mismatch.listenpkg"
            argv = v2_argv(output, media_type="video/mp4")
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = main(argv)
            self.assertEqual(code, 2)
            self.assertIn("does not agree with media kind", stderr.getvalue())
            self.assertFalse(output.exists())

    def test_missing_media_type_machine_event_is_stable(self) -> None:
        # Matches the existing v2 spec-flag convention: a missing required
        # caller-owned value classifies as package_validation_failed.
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "no-media-type.listenpkg"
            completed = run_cli(
                drop_flag(v2_argv(output, machine=True), "--media-type")
            )
            self.assertEqual(completed.returncode, 2, completed.stderr)
            events = parse_events(completed.stdout)
            terminals = [
                event for event in events
                if event["event"] in {"completed", "failed", "cancelled"}
            ]
            self.assertEqual(len(terminals), 1)
            self.assertEqual(terminals[0]["event"], "failed")
            self.assertEqual(terminals[0]["code"], "package_validation_failed")
            self.assertNotIn("must-not-leak", completed.stdout)
            self.assertFalse(output.exists())

    def test_invalid_media_type_machine_event_is_stable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "bad-media-type.listenpkg"
            completed = run_cli(v2_argv(output, media_type="audio", machine=True))
            self.assertEqual(completed.returncode, 2, completed.stderr)
            events = parse_events(completed.stdout)
            terminals = [
                event for event in events
                if event["event"] in {"completed", "failed", "cancelled"}
            ]
            self.assertEqual(len(terminals), 1)
            self.assertEqual(terminals[0]["event"], "failed")
            self.assertEqual(terminals[0]["code"], "package_validation_failed")
            self.assertNotIn("must-not-leak", completed.stdout)
            self.assertFalse(output.exists())

    def test_mismatched_media_type_machine_event_is_stable(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "media-type-mismatch.listenpkg"
            completed = run_cli(
                v2_argv(output, media_type="video/mp4", machine=True)
            )
            self.assertEqual(completed.returncode, 2, completed.stderr)
            events = parse_events(completed.stdout)
            terminals = [
                event for event in events
                if event["event"] in {"completed", "failed", "cancelled"}
            ]
            self.assertEqual(len(terminals), 1)
            self.assertEqual(terminals[0]["event"], "failed")
            self.assertEqual(terminals[0]["code"], "package_validation_failed")
            self.assertNotIn("must-not-leak", completed.stdout)
            self.assertFalse(output.exists())


class V2RenditionKindTests(unittest.TestCase):
    def test_audio_rendition_declares_kind_audio(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "audio.listenpkg"
            build_v2(output)
            with zipfile.ZipFile(output) as archive:
                release = json.loads(archive.read("release.json"))
            descriptor = release["renditions"][0]["descriptor"]
            self.assertEqual(descriptor["kind"], "audio")
            self.assertEqual(descriptor["schema"], "listen.rendition.audio.v1")
            self.assertEqual(descriptor["media_type"], "audio/wav")

    def test_video_rendition_declares_kind_video(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "video.listenpkg"
            package_media(
                MEDIA, output, FixtureAsrAdapter(FIXTURE),
                title="V2 video lesson", media_kind="video", duration_ms=2200,
                created_at_ms=1785542400000,
                package_version=2,
                release_spec=spec(media_type="video/mp4"),
            )
            with zipfile.ZipFile(output) as archive:
                release = json.loads(archive.read("release.json"))
            descriptor = release["renditions"][0]["descriptor"]
            self.assertEqual(descriptor["kind"], "video")
            self.assertEqual(descriptor["schema"], "listen.rendition.video.v1")
            self.assertEqual(descriptor["media_type"], "video/mp4")


class V2SpecValidationTests(unittest.TestCase):
    def test_missing_required_ids_fail_in_ordinary_mode(self) -> None:
        cases = [
            ("--edition-id", "edition id must be a non-empty string"),
            ("--material-id", "material id must be a non-empty string"),
            ("--material-revision-id", "material revision id must be a non-empty string"),
            ("--target-language", "target language must be a valid BCP47 language tag"),
            ("--media-type", "media type must be a non-empty MIME type string"),
        ]
        for flag, message in cases:
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "lesson-v2.listenpkg"
                argv = drop_flag(v2_argv(output), flag)
                stderr = io.StringIO()
                with redirect_stderr(stderr):
                    code = main(argv)
                self.assertEqual(code, 2, flag)
                document = json.loads(stderr.getvalue())
                self.assertEqual(document["status"], "failed")
                self.assertIn(message, document["error"])

    def test_invalid_languages_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson-v2.listenpkg"
            argv = v2_argv(output, target_language="not a tag")
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = main(argv)
            self.assertEqual(code, 2)
            self.assertIn("target language must be a valid BCP47", stderr.getvalue())
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson-v2.listenpkg"
            argv = v2_argv(output, support_languages=("de-DE", "bad tag"))
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = main(argv)
            self.assertEqual(code, 2)
            self.assertIn("support language must be a valid BCP47", stderr.getvalue())
        with self.assertRaisesRegex(ConversionError, "BCP47"):
            spec(target_language="not a tag")
        with self.assertRaisesRegex(ConversionError, "BCP47"):
            spec(support_languages=("de-DE", "not a tag"))

    def test_support_languages_are_explicit_and_empty_is_valid(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson-v2.listenpkg"
            build_v2(output, support_languages=("de-DE", "fr"))
            with zipfile.ZipFile(output) as archive:
                release = json.loads(archive.read("release.json"))
            self.assertEqual(release["edition"]["support_languages"], ["de-DE", "fr"])

    def test_duplicate_support_languages_are_rejected_before_package_writing(self) -> None:
        with self.assertRaisesRegex(ConversionError, "support languages must be unique"):
            spec(support_languages=("de-DE", "de-DE"))

    def test_v1_default_is_unchanged(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson-v1.listenpkg"
            package_media(
                MEDIA, output, FixtureAsrAdapter(FIXTURE),
                title="V1 lesson", media_kind="audio", duration_ms=2200,
                created_at_ms=1785542400000,
            )
            with zipfile.ZipFile(output) as archive:
                self.assertIn("manifest.json", archive.namelist())
                self.assertNotIn("release.json", archive.namelist())
                self.assertNotIn("delivery.json", archive.namelist())
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "legacy.listenpkg"
            package_from_lltimeline(LEGACY_FIXTURE, output)
            with zipfile.ZipFile(output) as archive:
                self.assertIn("manifest.json", archive.namelist())
                self.assertNotIn("release.json", archive.namelist())

    def test_v1_rejects_v2_release_specification_flags(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson-v1.listenpkg"
            argv = v2_argv(output)
            argv[argv.index("--package-version") + 1] = "1"
            stderr = io.StringIO()
            with redirect_stderr(stderr):
                code = main(argv)
            self.assertEqual(code, 2)
            self.assertIn(
                "package version 1 does not accept v2 release specification flags",
                stderr.getvalue(),
            )


class V2LanguageAgreementTests(unittest.TestCase):
    def test_transcript_language_mismatch_fails_honestly(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "mismatch.listenpkg"
            with self.assertRaisesRegex(
                ConversionError, "does not agree with target-language"
            ) as caught:
                build_v2(output, target_language="fr-FR")
            self.assertNotIn(str(FIXTURE), str(caught.exception))

    def test_transcript_language_mismatch_machine_event(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "mismatch.listenpkg"
            completed = run_cli(v2_argv(output, target_language="fr-FR", machine=True))
            self.assertEqual(completed.returncode, 2, completed.stderr)
            events = parse_events(completed.stdout)
            terminals = [
                event for event in events
                if event["event"] in {"completed", "failed", "cancelled"}
            ]
            self.assertEqual(len(terminals), 1)
            self.assertEqual(terminals[0]["event"], "failed")
            self.assertEqual(terminals[0]["code"], "language_mismatch")
            self.assertNotIn("raw_response", completed.stdout)
            self.assertNotIn("must-not-leak", completed.stdout)
            self.assertFalse(output.exists())

    def test_target_language_is_case_insensitive(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "case.listenpkg"
            build_v2(output, target_language="en-us")
            with zipfile.ZipFile(output) as archive:
                release = json.loads(archive.read("release.json"))
            self.assertEqual(release["edition"]["target_language"], "en-us")


class V2MachineEventTests(unittest.TestCase):
    def test_completed_event_reads_v2_carrier(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "machine-v2.listenpkg"
            completed = run_cli(v2_argv(output, machine=True))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            self.assertEqual(
                [event["event"] for event in events],
                ["protocol", "started", "phase", "phase", "phase", "completed"],
            )
            self.assertEqual(
                [event["phase"] for event in events if event["event"] == "phase"],
                ["validating", "transcribing", "building_package"],
            )
            terminal = events[-1]
            self.assertEqual(terminal["event"], "completed")
            self.assertEqual(
                terminal["package_sha256"],
                f"sha256:{hashlib.sha256(output.read_bytes()).hexdigest()}",
            )
            self.assertEqual(terminal["media_fingerprint"], MEDIA_SHA256)
            self.assertEqual(terminal["package_version"], 2)
            self.assertEqual(terminal["delivery_profile"], "hybrid")
            with zipfile.ZipFile(output) as archive:
                release = json.loads(archive.read("release.json"))
                delivery = json.loads(archive.read("delivery.json"))
            self.assertEqual(terminal["release_id"], delivery["release_id"])
            expected_resources = [
                {
                    "resource_id": entry["resource_id"],
                    "kind": entry["descriptor"]["kind"],
                    "review_status": entry["descriptor"]["quality"]["review_status"],
                }
                for entry in release["resources"]
            ]
            self.assertEqual(terminal["resources"], expected_resources)
            self.assertEqual(
                [entry["kind"] for entry in terminal["resources"]],
                ["subtitle_text_track", "word_timeline"],
            )

    def test_embedded_machine_event_reports_embedded_profile(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "machine-embedded.listenpkg"
            completed = run_cli(
                v2_argv(output, media_delivery="embedded", machine=True)
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            terminal = [
                event for event in parse_events(completed.stdout)
                if event["event"] == "completed"
            ][0]
            self.assertEqual(terminal["delivery_profile"], "embedded")

    def test_default_v1_machine_completed_omits_v2_fields(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "machine-v1.listenpkg"
            completed = run_cli(
                [
                    "package", "from-media", str(MEDIA),
                    "--output", str(output),
                    "--provider", "fixture", "--fixture", str(FIXTURE),
                    "--title", "V1 machine", "--media-kind", "audio",
                    "--duration-ms", "2200", "--created-at-ms", "1786000000000",
                    "--machine-events",
                ]
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            self.assertEqual(events[-1]["event"], "completed")
            terminal = events[-1]
            self.assertNotIn("package_version", terminal)
            self.assertNotIn("release_id", terminal)
            self.assertNotIn("delivery_profile", terminal)
            self.assertEqual(
                terminal["package_sha256"],
                f"sha256:{hashlib.sha256(output.read_bytes()).hexdigest()}",
            )
            self.assertEqual(terminal["media_fingerprint"], MEDIA_SHA256)
            self.assertEqual(
                [entry["kind"] for entry in terminal["resources"]],
                ["subtitle_text_track", "word_timeline"],
            )


class V2CrossRepositoryCoreProbeTests(unittest.TestCase):
    """Real Core inspection gated on ``LISTEN_CORE_CHECKOUT``.

    Generates both real v2 delivery modes (referenced/hybrid and embedded)
    and compiles one small Rust probe against the canonical checkout. The
    probe calls the exact Core v2 API (``content_package::v2::inspect_v2_path``
    followed by ``content_package::v2::installation_plan(&inspection)``, which
    has no result to unwrap) and asserts the expected profile, resource
    dispositions, rendition availability, and missing-blob inventory per
    delivery mode. The compiled probe binary is then invoked once per package
    with the delivery mode as the first argument; only the package path is
    passed to the probe, and the expected media digest is embedded as a
    literal derived from the fixed fixture.
    """

    PROBE_SOURCE = """\
use content_package::v2::{DeliveryProfile, ResourceDisposition};

fn check(mode: &str, package_path: &std::ffi::OsStr) {
    let inspection = content_package::v2::inspect_v2_path(package_path).unwrap();
    assert_eq!(
        inspection.resources.len(),
        inspection.release.resources.len(),
        "every released resource must be inspected as a known payload"
    );
    assert!(inspection.opaque_resources.is_empty(), "no opaque resources");
    assert_eq!(inspection.renditions.len(), 1);
    assert_eq!(inspection.renditions[0].entry.descriptor.kind, "audio");
    assert_eq!(
        inspection.renditions[0].entry.descriptor.media_type, "audio/wav"
    );

    let plan = content_package::v2::installation_plan(&inspection);
    assert_eq!(plan.resources.len(), inspection.release.resources.len());
    for entry in &plan.resources {
        assert_eq!(entry.disposition, ResourceDisposition::Candidate);
    }
    assert_eq!(plan.renditions.len(), 1);
    assert_eq!(plan.renditions[0].kind, "audio");
    assert_eq!(plan.renditions[0].media_type, "audio/wav");

    match mode {
        "hybrid" => {
            assert_eq!(inspection.delivery_profile, DeliveryProfile::Hybrid);
            assert!(!inspection.renditions[0].media_present);
            assert_eq!(inspection.missing_blobs.len(), 1);
            assert_eq!(inspection.missing_blobs[0].digest, "{media_digest}");
            assert_eq!(plan.delivery_profile, DeliveryProfile::Hybrid);
            assert!(!plan.renditions[0].available);
            assert_eq!(plan.missing_blobs.len(), 1);
            assert_eq!(plan.missing_blobs[0].digest, "{media_digest}");
        }
        "embedded" => {
            assert_eq!(inspection.delivery_profile, DeliveryProfile::Embedded);
            assert!(inspection.renditions[0].media_present);
            assert!(inspection.missing_blobs.is_empty());
            assert_eq!(plan.delivery_profile, DeliveryProfile::Embedded);
            assert!(plan.renditions[0].available);
            assert!(plan.missing_blobs.is_empty());
        }
        other => panic!("unknown delivery mode: {other}"),
    }
}

fn main() {
    let mut args = std::env::args_os().skip(1);
    let mode = args.next().expect("mode argument");
    let package_path = args.next().expect("package path argument");
    check(&mode.to_string_lossy(), &package_path);
    println!("ok");
}
"""

    def test_core_v2_inspector_and_installation_plan_for_both_modes(self) -> None:
        checkout = os.environ.get("LISTEN_CORE_CHECKOUT")
        if checkout is None:
            self.skipTest("LISTEN_CORE_CHECKOUT is not set")
        core = Path(checkout)
        if not (core / "crates" / "content-package" / "Cargo.toml").is_file():
            self.fail("LISTEN_CORE_CHECKOUT does not contain crates/content-package")
        with tempfile.TemporaryDirectory() as directory:
            hybrid_output = Path(directory) / "hybrid-v2.listenpkg"
            embedded_output = Path(directory) / "embedded-v2.listenpkg"
            hybrid_result = build_v2(hybrid_output)
            embedded_result = build_v2(embedded_output, media_delivery="embedded")
            self.assertEqual(hybrid_result["delivery_profile"], "hybrid")
            self.assertEqual(embedded_result["delivery_profile"], "embedded")
            with zipfile.ZipFile(hybrid_output) as archive:
                hybrid_delivery = json.loads(archive.read("delivery.json"))
            with zipfile.ZipFile(embedded_output) as archive:
                embedded_delivery = json.loads(archive.read("delivery.json"))
            self.assertEqual(hybrid_delivery["profile"], "hybrid")
            self.assertEqual(embedded_delivery["profile"], "embedded")
            self.assertEqual(
                {entry["digest"] for entry in hybrid_delivery["blobs"]} & {MEDIA_SHA256},
                set(),
                "referenced media must not be carried in the archive",
            )
            self.assertIn(
                MEDIA_SHA256,
                {entry["digest"] for entry in embedded_delivery["blobs"]},
                "embedded media must be carried in the archive",
            )

            probe = Path(directory) / "probe"
            (probe / "src").mkdir(parents=True)
            (probe / "Cargo.toml").write_text(
                "[package]\n"
                'name = "listen-gen-contract-v2-probe"\n'
                'version = "0.0.0"\n'
                'edition = "2024"\n'
                "[dependencies]\n"
                "content-package = { path = "
                + json.dumps(str(core / "crates" / "content-package"))
                + " }\n",
                encoding="utf-8",
            )
            probe_source = self.PROBE_SOURCE.replace("{media_digest}", MEDIA_SHA256)
            (probe / "src" / "main.rs").write_text(probe_source, encoding="utf-8")
            build = subprocess.run(
                ["cargo", "build", "-q", "--manifest-path", str(probe / "Cargo.toml")],
                cwd=probe,
                capture_output=True,
                text=True,
                timeout=300,
            )
            self.assertEqual(
                build.returncode,
                0,
                "core v2 probe build failed:\n"
                f"stdout:\n{build.stdout}\n"
                f"stderr:\n{build.stderr}",
            )
            binary = probe / "target" / "debug" / "listen-gen-contract-v2-probe"
            for mode, package in (
                ("hybrid", hybrid_output),
                ("embedded", embedded_output),
            ):
                completed = subprocess.run(
                    [str(binary), mode, str(package)],
                    cwd=probe,
                    capture_output=True,
                    text=True,
                    timeout=120,
                )
                self.assertEqual(
                    completed.returncode,
                    0,
                    f"core v2 probe failed for {mode} delivery:\n"
                    f"stdout:\n{completed.stdout}\n"
                    f"stderr:\n{completed.stderr}",
                )
                self.assertIn("ok", completed.stdout)


if __name__ == "__main__":
    unittest.main()
