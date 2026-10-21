from __future__ import annotations

import json
import hashlib
import os
import signal
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.package_v3 import sha256_of_bytes
from listen_gen.document import MAX_DOCUMENT_BYTES
from listen_gen.cli import _build_asr, parser
from listen_gen.package import ConversionError
from listen_gen.produce import ProductionFailure, _blob_source_bytes

FIXTURES = ROOT / "tests" / "fixtures"


def _env() -> dict[str, str]:
    env = dict(os.environ)
    env["PYTHONPATH"] = str(ROOT / "src")
    return env


def run_cli(argv: list[str], timeout: float = 60, env=None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "listen_gen", *argv],
        capture_output=True,
        text=True,
        env=env or _env(),
        timeout=timeout,
    )


def parse_events(stdout: str) -> list[dict[str, object]]:
    return [json.loads(line) for line in stdout.splitlines() if line]


def media_rendition() -> dict[str, object]:
    path = FIXTURES / "sample-media.wav"
    raw = path.read_bytes()
    digest = sha256_of_bytes(raw)
    return {
        "kind": "media",
        "rendition_id": digest,
        "media_kind": "audio",
        "media_type": "audio/wav",
        "media_id": "fixture-media",
        "fingerprint": digest,
        "blob": {"digest": digest, "size_bytes": len(raw), "path": str(path)},
    }


def request_media(
    capability: str = "read", *, attempt_id: str = "attempt-1", rendition: dict | None = None
) -> dict[str, object]:
    return {
        "schema": "listen_gen.capability-request.v2",
        "version": 2,
        "created_at_ms": 1,
        "attempt_id": attempt_id,
        "material": {
            "material_id": "fixture-material",
            "material_revision_id": "fixture-revision",
            "title": "Fixture Material",
        },
        "edition": {
            "edition_id": "fixture-edition",
            "title": "Fixture Edition",
            "target_language": "en-US",
            "support_languages": [],
        },
        "requested_capability": capability,
        "available_renditions": [rendition or media_rendition()],
        "extensions": {},
    }


def _core_id(namespace: str, fields: tuple[str, ...]) -> str:
    fingerprint = "".join(
        f"{len(value.encode('utf-8'))}:{value}" for value in fields
    )
    return hashlib.sha256(f"{namespace}:{fingerprint}".encode("utf-8")).hexdigest()


def request_document(
    path: Path,
    capability: str = "read",
    *,
    media_type: str = "text/plain",
    language: str | None = "en-US",
) -> dict[str, object]:
    raw = path.read_bytes()
    digest = hashlib.sha256(raw).hexdigest()
    source_asset_id = _core_id(
        "source-asset", (media_type, str(len(raw)), digest)
    )
    rendition_id = _core_id(
        "document-rendition", (media_type, language or "", digest)
    )
    return {
        "schema": "listen_gen.capability-request.v2",
        "version": 2,
        "created_at_ms": 1,
        "attempt_id": "attempt-document-1",
        "material": {
            "material_id": "fixture-document",
            "material_revision_id": "fixture-document-revision",
            "title": "Fixture Document",
        },
        "edition": {
            "edition_id": "fixture-document-edition",
            "title": "Fixture Document",
            "target_language": "en-US",
            "support_languages": [],
        },
        "requested_capability": capability,
        "available_renditions": [{
            "kind": "document",
            "rendition_id": f"sha256:{rendition_id}",
            "media_type": media_type,
            "language": language,
            "source_asset_id": source_asset_id,
            "blob": {
                "digest": f"sha256:{digest}",
                "size_bytes": len(raw),
                "path": str(path.resolve()),
            },
        }],
        "extensions": {},
    }


def release_from(path: Path) -> dict[str, object]:
    with zipfile.ZipFile(path) as archive:
        return json.loads(archive.read("release.json"))


def archive_bytes(path: Path) -> bytes:
    with zipfile.ZipFile(path) as archive:
        return b"".join(archive.read(name) for name in archive.namelist())


def blank_pdf() -> bytes:
    from pypdf import PdfWriter

    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    from io import BytesIO

    buffer = BytesIO()
    writer.write(buffer)
    return buffer.getvalue()


class ProduceCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="listen-gen-test-")
        self.directory = Path(self.tempdir.name)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def write_request(self, request: dict[str, object]) -> Path:
        path = self.directory / "request.json"
        path.write_text(json.dumps(request), encoding="utf-8")
        return path

    def test_oversized_document_is_rejected_before_reading_source_bytes(self) -> None:
        source = self.directory / "oversized.txt"
        with source.open("wb") as stream:
            stream.truncate(MAX_DOCUMENT_BYTES + 1)
        blob = type("Blob", (), {
            "path": source,
            "digest": "sha256:" + "0" * 64,
            "size_bytes": MAX_DOCUMENT_BYTES + 1,
        })()
        with patch.object(Path, "read_bytes", side_effect=AssertionError("should not read")):
            with self.assertRaises(ProductionFailure) as raised:
                _blob_source_bytes(blob, max_bytes=MAX_DOCUMENT_BYTES)
        self.assertEqual(raised.exception.code, "input_too_large")

    def produce_media(self, capability: str = "read", *, output: str = "package.zip"):
        request_path = self.write_request(request_media(capability))
        output_path = self.directory / output
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output_path),
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--machine-events",
        ])
        return result, output_path, parse_events(result.stdout)

    def test_media_read_produces_structured_reading_alignment_and_v3_release(self) -> None:
        result, output, events = self.produce_media()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(events[-1]["event"], "completed")
        kinds = [entry["kind"] for entry in events[-1]["resources"]]
        self.assertIn("structured_reading", kinds)
        self.assertIn("anchor_time_alignment", kinds)
        release = release_from(output)
        self.assertEqual(release["schema"], "listen.content-package.release.v3")
        self.assertEqual(release["document_renditions"], [])
        with zipfile.ZipFile(output) as archive:
            reading_entry = next(
                entry for entry in release["resources"]
                if entry["descriptor"]["kind"] == "structured_reading"
            )
            digest = reading_entry["descriptor"]["payload_blob"]["digest"]
            reading = json.loads(archive.read(f"blobs/sha256/{digest.removeprefix('sha256:')}"))
        self.assertEqual(reading["text"], "Listen, carefully!\nWords matter.")
        self.assertEqual(reading["document_mappings"], [])

    def test_synchronized_read_listen_uses_media_transcription(self) -> None:
        result, _, events = self.produce_media("synchronized_read_listen")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(events[-1]["event"], "completed")
        self.assertEqual(
            events[2]["plan"]["derivations"][0]["kind"],
            "media_to_structured_reading",
        )

    def test_document_read_emits_structured_reading_and_core_source_mapping(self) -> None:
        source = self.directory / "lesson.txt"
        source.write_text("Listen, carefully!\nWords matter.", encoding="utf-8")
        request = request_document(source)
        request_path = self.write_request(request)
        output = self.directory / "document-read.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        completed = parse_events(result.stdout)[-1]
        self.assertEqual(completed["event"], "completed")
        self.assertEqual(len(completed["document_renditions"]), 1)
        release = release_from(output)
        source_rendition = release["document_renditions"][0]
        expected_source_id = request["available_renditions"][0]["source_asset_id"]
        self.assertEqual(source_rendition["source_asset_id"], f"sha256:{expected_source_id}")
        self.assertFalse(source_rendition["text_blob"]["embedded"])
        with zipfile.ZipFile(output) as archive:
            self.assertNotIn(
                f"blobs/sha256/{source_rendition['text_blob']['digest'].removeprefix('sha256:')}",
                archive.namelist(),
            )
            reading_entry = next(
                entry for entry in release["resources"]
                if entry["descriptor"]["kind"] == "structured_reading"
            )
            digest = reading_entry["descriptor"]["payload_blob"]["digest"]
            reading = json.loads(archive.read(f"blobs/sha256/{digest.removeprefix('sha256:')}"))
        self.assertEqual(reading["text"], "Listen, carefully!\nWords matter.")
        self.assertTrue(reading["document_mappings"])
        self.assertNotIn(str(source).encode(), archive_bytes(output))

    def test_document_listen_without_tts_fails_before_writing_package(self) -> None:
        source = self.directory / "lesson.txt"
        source.write_text("A sentence.", encoding="utf-8")
        request_path = self.write_request(request_document(source, "listen"))
        output = self.directory / "document-listen-missing-tts.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 2)
        failed = parse_events(result.stdout)[-1]
        self.assertEqual(failed["code"], "provider_not_configured")
        self.assertIn("document listen requires a TTS provider", failed["message"])
        self.assertFalse(output.exists())

    def test_document_listen_emits_derived_audio_and_anchor_alignment(self) -> None:
        source = self.directory / "lesson.md"
        source.write_text("# Lesson\n\nListen carefully.\nSecond sentence!", encoding="utf-8")
        request_path = self.write_request(request_document(source, "listen", media_type="text/markdown"))
        output = self.directory / "document-listen.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--tts-provider", "fake", "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        events = parse_events(result.stdout)
        self.assertEqual(events[-1]["event"], "completed")
        self.assertEqual(len(events[-1]["document_renditions"]), 1)
        self.assertEqual(len(events[-1]["media_renditions"]), 1)
        self.assertEqual(events[-1]["media_renditions"][0]["origin"], "derived")
        release = release_from(output)
        audio = release["media_renditions"][0]
        self.assertEqual(audio["kind"], "audio")
        self.assertEqual(audio["origin"], "derived")
        self.assertTrue(audio["media_blob"]["embedded"])
        self.assertRegex(audio["producer"]["config_sha256"], r"^sha256:[0-9a-f]{64}$")
        kinds = {entry["descriptor"]["kind"] for entry in release["resources"]}
        self.assertEqual(kinds, {"structured_reading", "anchor_time_alignment"})
        with zipfile.ZipFile(output) as archive:
            alignment_entry = next(
                entry for entry in release["resources"]
                if entry["descriptor"]["kind"] == "anchor_time_alignment"
            )
            descriptor = alignment_entry["descriptor"]
            digest = descriptor["payload_blob"]["digest"]
            alignment = json.loads(archive.read(f"blobs/sha256/{digest.removeprefix('sha256:')}"))
            self.assertEqual(alignment["rendition_id"], audio["rendition_id"])
            self.assertEqual(descriptor["subject"]["rendition_ids"], [audio["rendition_id"]])
            self.assertNotIn(str(source).encode(), b"".join(archive.read(name) for name in archive.namelist()))

    def test_scanned_pdf_abstains_without_ocr_and_fixture_ocr_can_produce_reading(self) -> None:
        source = self.directory / "scanned.pdf"
        source.write_bytes(blank_pdf())
        request_path = self.write_request(
            request_document(source, "read", media_type="application/pdf")
        )
        missing_ocr_output = self.directory / "scanned-no-ocr.zip"
        no_ocr = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(missing_ocr_output), "--machine-events",
        ])
        self.assertEqual(no_ocr.returncode, 2)
        abstained = parse_events(no_ocr.stdout)[-1]
        self.assertEqual(abstained["code"], "document_text_unavailable")
        self.assertIn("configure --ocr-provider", abstained["message"])
        self.assertFalse(missing_ocr_output.exists())

        fixture = self.directory / "ocr.txt"
        fixture.write_text("Recognized scanned text.", encoding="utf-8")
        output = self.directory / "scanned-with-ocr.zip"
        recognized = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--ocr-provider", "fixture",
            "--ocr-fixture", str(fixture), "--machine-events",
        ])
        self.assertEqual(recognized.returncode, 0, recognized.stderr)
        self.assertEqual(parse_events(recognized.stdout)[-1]["event"], "completed")
        release = release_from(output)
        self.assertEqual(
            [resource["descriptor"]["kind"] for resource in release["resources"]],
            ["structured_reading"],
        )

    def test_cli_exposes_explicit_document_tts_and_ocr_provider_flags(self) -> None:
        result = run_cli(["package", "from-capability", "--help"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--tts-provider", result.stdout)
        self.assertIn("--ocr-provider", result.stdout)

    def test_source_only_asr_providers_explain_missing_released_sidecars(self) -> None:
        for provider, flag in (
            ("qwen3", "--qwen3-sidecar"),
            ("sensevoice", "--sensevoice-sidecar"),
        ):
            with self.subTest(provider=provider):
                with patch("listen_gen.cli._source_checkout_sidecar", return_value=None):
                    args = parser().parse_args([
                        "package", "from-capability", "request.json",
                        "--output", "out.zip", "--provider", provider,
                    ])
                self.assertIsNone(getattr(args, flag.removeprefix("--").replace("-", "_")))
                with self.assertRaisesRegex(ConversionError, "source-checkout-only"):
                    _build_asr(args)

    def test_listen_is_already_satisfied_by_source_media(self) -> None:
        request_path = self.write_request(request_media("listen"))
        output = self.directory / "already-listening.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        completed = parse_events(result.stdout)[-1]
        self.assertEqual(completed["event"], "completed")
        self.assertIsNone(completed["package_sha256"])
        self.assertFalse(output.exists())

    def test_video_only_listen_is_rejected_without_audio_conversion(self) -> None:
        request = request_media("listen")
        rendition = request["available_renditions"][0]
        rendition["media_kind"] = "video"
        rendition["media_type"] = "video/mp4"
        request_path = self.write_request(request)
        output = self.directory / "video-only-listen.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 2)
        failed = parse_events(result.stdout)[-1]
        self.assertEqual(failed["event"], "failed")
        self.assertEqual(failed["code"], "unsupported_capability")
        self.assertIn("listen requires an audio rendition", failed["message"])
        self.assertFalse(output.exists())

    def test_invalid_capability_fails_before_running(self) -> None:
        request_path = self.write_request(request_media("speak"))
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(self.directory / "invalid.zip"), "--machine-events",
        ])
        self.assertEqual(result.returncode, 2)
        events = parse_events(result.stdout)
        self.assertEqual(events[-1]["code"], "invalid_request")
        self.assertNotIn("accepted", [event["event"] for event in events])

    def test_generated_package_contains_no_local_paths(self) -> None:
        result, output, _ = self.produce_media(output="no-paths.zip")
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(output) as archive:
            content = b"".join(archive.read(name) for name in archive.namelist())
        for marker in (b"/Users/", b"/tmp/", b"listen-gen-test-"):
            self.assertNotIn(marker, content)

    def test_deterministic_fixture_production_repeats_identically(self) -> None:
        request_path = self.write_request(request_media("read"))
        outputs = (self.directory / "first.zip", self.directory / "second.zip")
        for output in outputs:
            result = run_cli([
                "package", "from-capability", str(request_path),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            ])
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(outputs[0].read_bytes(), outputs[1].read_bytes())

    def test_cancel_before_terminal_commit_leaves_no_artifact(self) -> None:
        request_path = self.write_request(request_media("read"))
        output = self.directory / "cancel.zip"
        marker = self.directory / "before-commit.marker"
        env = _env()
        env["LISTEN_GEN_TEST_PAUSE_BEFORE_TERMINAL_COMMIT"] = "1"
        env["LISTEN_GEN_TEST_BEFORE_COMMIT_MARKER"] = str(marker)
        process = subprocess.Popen(
            [sys.executable, "-m", "listen_gen", "package", "from-capability",
             str(request_path), "--output", str(output), "--provider", "fixture",
             "--fixture", str(FIXTURES / "sample.asr.json"), "--machine-events"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env,
        )
        for _ in range(200):
            if marker.exists():
                break
            import time
            time.sleep(0.05)
        self.assertTrue(marker.exists(), "production did not reach its terminal commit gate")
        process.send_signal(signal.SIGTERM)
        stdout, _ = process.communicate(timeout=30)
        self.assertEqual(process.returncode, 130)
        self.assertEqual(parse_events(stdout)[-1]["event"], "cancelled")
        self.assertFalse(output.exists())
        self.assertFalse(list(self.directory.glob(".*.machine.tmp")))

    def test_core_round_trip_when_example_is_built(self) -> None:
        core = Path(os.environ.get("LISTEN_CORE_CHECKOUT", ROOT.parent / "core"))
        target = Path(os.environ.get("CARGO_TARGET_DIR", core / "target"))
        example = target / "debug" / "examples" / "inspect-package"
        if not example.exists():
            self.skipTest("Core inspect-package example is not built")
        result, output, _ = self.produce_media(output="round-trip.zip")
        self.assertEqual(result.returncode, 0, result.stderr)
        check = subprocess.run(
            [str(example), str(output)], capture_output=True, text=True, timeout=60
        )
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertTrue(check.stdout.startswith("OK "))

    def test_core_document_package_validation_when_example_is_built(self) -> None:
        core = Path(os.environ.get("LISTEN_CORE_CHECKOUT", ROOT.parent / "core"))
        target = Path(os.environ.get("CARGO_TARGET_DIR", core / "target"))
        example = target / "debug" / "examples" / "inspect-package"
        if not example.exists():
            self.skipTest("Core inspect-package example is not built")
        source = self.directory / "core-document.txt"
        source.write_text("Core validates the generated source document.", encoding="utf-8")
        request_path = self.write_request(request_document(source))
        output = self.directory / "core-document.listenpkg"
        generated = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
        ])
        self.assertEqual(generated.returncode, 0, generated.stderr)
        checked = subprocess.run(
            [str(example), str(output)],
            capture_output=True,
            text=True,
            timeout=60,
        )
        self.assertEqual(checked.returncode, 0, checked.stderr)
        self.assertTrue(checked.stdout.startswith("OK "))


if __name__ == "__main__":
    unittest.main()
