from __future__ import annotations

import io
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.package_v3 import sha256_of_bytes

FIXTURES = ROOT / "tests" / "fixtures"
V2_SCHEMA = "listen_gen.machine-event.v2"
V2_VERSION = 2
TERMINAL_EVENTS = {"completed", "cancelled", "failed"}


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


def text_document(text: str, directory: Path) -> tuple[dict, dict]:
    path = directory / "document.txt"
    path.write_text(text, encoding="utf-8")
    raw = path.read_bytes()
    return {
        "kind": "document",
        "rendition_id": "sha256:" + "1" * 64,
        "media_type": "text/plain",
        "language": "en",
        "source_asset_id": "sha256:" + "2" * 64,
        "blob": {"digest": sha256_of_bytes(raw), "size_bytes": len(raw), "path": str(path)},
    }, {"digest": sha256_of_bytes(raw), "size_bytes": len(raw), "path": str(path)}


def media_rendition(directory: Path) -> dict:
    path = FIXTURES / "sample-media.wav"
    raw = path.read_bytes()
    return {
        "kind": "media",
        "media_kind": "audio",
        "rendition_id": "sha256:" + "3" * 64,
        "media_type": "audio/wav",
        "media_id": "media-1",
        "fingerprint": "fp-media-1",
        "blob": {"digest": sha256_of_bytes(raw), "size_bytes": len(raw), "path": str(path)},
    }


def request_document(
    directory: Path,
    capability: str = "read",
    text: str = "Hello world. This is a first test.\nSecond paragraph with a question!",
    attempt_id: str = "attempt-1",
    **extra,
) -> dict:
    rendition, _ = text_document(text, directory)
    document = {
        "schema": "listen_gen.capability-request.v2",
        "version": 2,
        "created_at_ms": 1,
        "attempt_id": attempt_id,
        "material": {
            "material_id": "material-1",
            "material_revision_id": "revision-1",
            "title": "Test Material",
        },
        "edition": {
            "edition_id": "edition-1",
            "title": "Test Edition",
            "target_language": "en",
            "support_languages": [],
        },
        "requested_capability": capability,
        "available_renditions": [rendition],
        "available_resources": [],
    }
    document.update(extra)
    return document


def make_epub_fixture(chapters: list[tuple[str, str]]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("mimetype", b"application/epub+zip")
        archive.writestr(
            "META-INF/container.xml",
            b'<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
        )
        manifest = "".join(
            f'<item id="c{i}" href="{href}" media-type="application/xhtml+xml"/>'
            for i, (href, _) in enumerate(chapters)
        )
        spine = "".join(
            f'<itemref idref="c{i}"/>' for i in range(len(chapters))
        )
        archive.writestr(
            "OEBPS/content.opf",
            f'<package><manifest>{manifest}</manifest><spine>{spine}</spine></package>'.encode(),
        )
        for href, content in chapters:
            archive.writestr(f"OEBPS/{href}", content.encode())
    return buffer.getvalue()


def make_text_pdf_fixture(text: str) -> bytes:
    from pypdf import PdfWriter
    from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject

    writer = PdfWriter()
    page = writer.add_blank_page(width=200, height=200)
    font = writer._add_object(
        DictionaryObject(
            {
                NameObject("/Type"): NameObject("/Font"),
                NameObject("/Subtype"): NameObject("/Type1"),
                NameObject("/BaseFont"): NameObject("/Helvetica"),
            }
        )
    )
    page[NameObject("/Resources")] = DictionaryObject(
        {
            NameObject("/Font"): DictionaryObject(
                {NameObject("/F1"): font}
            )
        }
    )
    stream = DecodedStreamObject()
    stream.set_data(f"BT /F1 12 Tf 72 700 Td ({text}) Tj ET".encode("latin-1"))
    page[NameObject("/Contents")] = writer._add_object(stream)
    buffer = io.BytesIO()
    writer.write(buffer)
    return buffer.getvalue()


def make_blank_pdf_fixture() -> bytes:
    from pypdf import PdfWriter

    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    buffer = io.BytesIO()
    writer.write(buffer)
    return buffer.getvalue()


def release_renditions(path: Path) -> list[dict]:
    with zipfile.ZipFile(path) as archive:
        release = json.loads(archive.read("release.json"))
    return [
        {"rendition_id": entry["rendition_id"], "origin": entry["origin"],
         "producer": entry.get("producer")}
        for entry in release["media_renditions"]
    ]


class ProduceCliTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp(prefix="listen-gen-test-"))

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.directory, ignore_errors=True)

    def write_request(self, request: dict) -> Path:
        path = self.directory / "request.json"
        path.write_text(json.dumps(request), encoding="utf-8")
        return path

    def event_sequence(self, events: list[dict]) -> list[str]:
        return [event["event"] for event in events]

    def test_read_from_document_completes_with_reading_resources(self) -> None:
        request_path = self.write_request(request_document(self.directory))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        events = parse_events(result.stdout)
        self.assertEqual(
            self.event_sequence(events),
            ["protocol", "accepted", "planned", "running", "completed"],
        )
        self.assertEqual(events[0]["schema"], V2_SCHEMA)
        self.assertEqual(events[0]["protocol_version"], V2_VERSION)
        self.assertEqual(events[1]["attempt_id"], "attempt-1")
        completed = events[-1]
        kinds = [entry["kind"] for entry in completed["resources"]]
        self.assertEqual(kinds, ["structured_reading"])
        self.assertNotIn("document_text", kinds)
        self.assertNotIn("anchor_time_alignment", kinds)
        self.assertTrue(output.exists())

    def test_planned_event_declares_the_derivation(self) -> None:
        request_path = self.write_request(request_document(self.directory))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        events = parse_events(result.stdout)
        planned = events[2]
        derivations = planned["plan"]["derivations"]
        self.assertEqual(derivations[0]["kind"], "document_to_structured_reading")

    def test_listen_produces_exact_alignment_with_say(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="synchronized_read_listen")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--tts-provider", "say",
            "--tts-say-executable", str(FIXTURES / "fake_say.py"),
            "--tts-afconvert-executable", str(FIXTURES / "fake_afconvert.py"),
            "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        events = parse_events(result.stdout)
        completed = events[-1]
        self.assertEqual(completed["event"], "completed")
        media_kinds = [entry["origin"] for entry in completed["media_renditions"]]
        self.assertIn("derived", media_kinds)
        self.assertEqual(completed["warnings"], [])
        resource_kinds = [entry["kind"] for entry in completed["resources"]]
        self.assertIn("anchor_time_alignment", resource_kinds)

    def test_listen_abstains_alignment_when_audio_cannot_be_measured(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="listen")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--tts-provider", "say",
            "--tts-say-executable", str(FIXTURES / "fake_say_garbage.py"),
            "--tts-afconvert-executable", str(FIXTURES / "fake_afconvert.py"),
            "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        events = parse_events(result.stdout)
        completed = events[-1]
        self.assertEqual(
            completed["warnings"],
            [{
                "code": "alignment_abstained",
                "message": "exact anchor timing could not be produced; audio is "
                "available but synchronized reading is not",
            }],
        )
        resource_kinds = [entry["kind"] for entry in completed["resources"]]
        self.assertNotIn("anchor_time_alignment", resource_kinds)

    def test_fake_tts_produces_exact_alignment(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="synchronized_read_listen")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--tts-provider", "fake", "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        events = parse_events(result.stdout)
        completed = events[-1]
        self.assertEqual(completed["warnings"], [])
        kinds = [entry["kind"] for entry in completed["resources"]]
        self.assertIn("anchor_time_alignment", kinds)
        with zipfile.ZipFile(output) as archive:
            release = json.loads(archive.read("release.json"))
            alignment = next(
                resource for resource in release["resources"]
                if resource["descriptor"]["kind"] == "anchor_time_alignment"
            )
            digest = alignment["descriptor"]["payload_blob"]["digest"]
            payload = json.loads(archive.read(
                f"blobs/sha256/{digest.removeprefix('sha256:')}"
            ))
        times = [entry["media_time_ms"] for entry in payload["alignments"]]
        self.assertEqual(times, sorted(times))

    def test_media_read_produces_reading_and_alignment(self) -> None:
        request_path = self.write_request({
            "schema": "listen_gen.capability-request.v2",
            "version": 2,
            "created_at_ms": 1,
            "attempt_id": "attempt-media",
            "material": {"material_id": "material-m", "material_revision_id": "revision-m", "title": "M"},
            "edition": {"edition_id": "edition-m", "title": "E", "target_language": "en-US", "support_languages": []},
            "requested_capability": "read",
            "available_renditions": [media_rendition(self.directory)],
            "available_resources": [],
        })
        output = self.directory / "media-package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(FIXTURES / "sample.asr.json"),
            "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        events = parse_events(result.stdout)
        completed = events[-1]
        kinds = [entry["kind"] for entry in completed["resources"]]
        self.assertIn("structured_reading", kinds)
        self.assertIn("anchor_time_alignment", kinds)

    def test_document_families_produce_qualified_reading(self) -> None:
        cases = [
            ("text/plain", b"Plain text content.\nSecond line!"),
            ("text/markdown", b"# Title\n\n**Bold** paragraph."),
            ("text/html", b"<html><body><h1>Title</h1><p>Body text.</p></body></html>"),
        ]
        epub = make_epub_fixture([("c1.xhtml", "<p>Chapter one.</p>")])
        cases.append(("application/epub+zip", epub))
        cases.append(("application/pdf", make_text_pdf_fixture("PDF text layer.")))
        for media_type, raw in cases:
            with self.subTest(media_type=media_type):
                path = self.directory / f"doc-{len(raw)}.bin"
                path.write_bytes(raw)
                request_path = self.write_request({
                    "schema": "listen_gen.capability-request.v2",
                    "version": 2,
                    "created_at_ms": 1,
                    "attempt_id": "attempt-family",
                    "material": {"material_id": "material-1", "material_revision_id": "revision-1", "title": "M"},
                    "edition": {"edition_id": "edition-1", "title": "E", "target_language": "en", "support_languages": []},
                    "requested_capability": "read",
                    "available_renditions": [{
                        "kind": "document",
                        "rendition_id": "sha256:" + "5" * 64,
                        "media_type": media_type,
                        "language": "en",
                        "source_asset_id": "sha256:" + "6" * 64,
                        "blob": {"digest": sha256_of_bytes(raw), "size_bytes": len(raw), "path": str(path)},
                    }],
                    "available_resources": [],
                })
                output = self.directory / f"family-{media_type.replace('/', '-')}.zip"
                result = run_cli([
                    "package", "from-capability", str(request_path),
                    "--output", str(output),
                ])
                self.assertEqual(result.returncode, 0, result.stderr)
                with zipfile.ZipFile(output) as archive:
                    release = json.loads(archive.read("release.json"))
                kinds = [
                    entry["descriptor"]["kind"]
                    for entry in release["resources"]
                ]
                self.assertEqual(kinds, ["structured_reading"])

    def test_scanned_pdf_ocr_states(self) -> None:
        blank = make_blank_pdf_fixture()
        path = self.directory / "scanned.pdf"
        path.write_bytes(blank)

        def request() -> dict:
            return {
                "schema": "listen_gen.capability-request.v2",
                "version": 2,
                "created_at_ms": 1,
                "attempt_id": "attempt-ocr",
                "material": {"material_id": "material-1", "material_revision_id": "revision-1", "title": "M"},
                "edition": {"edition_id": "edition-1", "title": "E", "target_language": "en", "support_languages": []},
                "requested_capability": "read",
                "available_renditions": [{
                    "kind": "document",
                    "rendition_id": "sha256:" + "7" * 64,
                    "media_type": "application/pdf",
                    "language": "en",
                    "source_asset_id": "sha256:" + "8" * 64,
                    "blob": {"digest": sha256_of_bytes(blank), "size_bytes": len(blank), "path": str(path)},
                }],
                "available_resources": [],
            }

        request_path = self.write_request(request())
        output = self.directory / "ocr-none.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
        ])
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("document_text_unavailable", result.stderr)

        ocr_fixture = self.directory / "ocr.txt"
        ocr_fixture.write_text("Recognized by OCR.", encoding="utf-8")
        request_path = self.write_request(request())
        output = self.directory / "ocr-ok.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--ocr-provider", "fixture", "--ocr-fixture", str(ocr_fixture),
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(output) as archive:
            release = json.loads(archive.read("release.json"))
        kinds = [entry["descriptor"]["kind"] for entry in release["resources"]]
        self.assertEqual(kinds, ["structured_reading"])
        source_rendition_id = release["document_renditions"][0]["rendition_id"]
        reading = next(
            entry["descriptor"] for entry in release["resources"]
            if entry["descriptor"]["kind"] == "structured_reading"
        )
        self.assertEqual(reading["provenance"]["input_rendition_ids"],
                         [source_rendition_id])
        self.assertEqual(reading["subject"]["rendition_ids"],
                         [source_rendition_id])

    def test_ocr_provider_failure_is_terminal(self) -> None:
        blank = make_blank_pdf_fixture()
        path = self.directory / "scanned.pdf"
        path.write_bytes(blank)
        request_path = self.write_request({
            "schema": "listen_gen.capability-request.v2",
            "version": 2,
            "created_at_ms": 1,
            "attempt_id": "attempt-ocr-fail",
            "material": {"material_id": "material-1", "material_revision_id": "revision-1", "title": "M"},
            "edition": {"edition_id": "edition-1", "title": "E", "target_language": "en", "support_languages": []},
            "requested_capability": "read",
            "available_renditions": [{
                "kind": "document",
                "rendition_id": "sha256:" + "7" * 64,
                "media_type": "application/pdf",
                "language": "en",
                "source_asset_id": "sha256:" + "8" * 64,
                "blob": {"digest": sha256_of_bytes(blank), "size_bytes": len(blank), "path": str(path)},
            }],
            "available_resources": [],
        })
        output = self.directory / "ocr-fail.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--ocr-provider", "fixture",
            "--ocr-fixture", str(self.directory / "missing-ocr.txt"),
        ])
        self.assertEqual(result.returncode, 2)

    def test_listen_reuses_available_structured_reading(self) -> None:
        reading_payload = {
            "language": "en",
            "text": "Hello world. This is a first test.",
            "anchors": [
                {"anchor_id": "sentence-0", "kind": "sentence", "start_offset": 0, "end_offset": 12},
                {"anchor_id": "sentence-1", "kind": "sentence", "start_offset": 12, "end_offset": 33},
            ],
            "blocks": [
                {"block_id": "block-root", "kind": "root", "order": 0,
                 "span_anchor_ids": ["sentence-0", "sentence-1"], "parent_block_id": None},
            ],
            "spans": [],
            "document_mappings": [],
            "extensions": {},
        }
        payload_bytes = json.dumps(
            reading_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
        ).encode("utf-8")
        resource_path = self.directory / "reading.json"
        resource_path.write_bytes(payload_bytes)
        resource_id = "sha256:" + "f" * 64
        request_path = self.write_request(
            request_document(
                self.directory,
                capability="listen",
                available_resources=[{
                    "resource_id": resource_id,
                    "kind": "structured_reading",
                    "schema": "listen.payload.structured-reading.v1",
                    "role": "base",
                    "content_language": "en",
                    "material_revision_id": "revision-1",
                    "blob": {
                        "digest": sha256_of_bytes(payload_bytes),
                        "size_bytes": len(payload_bytes),
                        "path": str(resource_path),
                    },
                }],
            )
        )
        output = self.directory / "reuse.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--tts-provider", "fake", "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(output) as archive:
            release = json.loads(archive.read("release.json"))
        kinds = [
            entry["descriptor"]["kind"]
            for entry in release["resources"]
        ]
        self.assertIn("structured_reading", kinds)
        self.assertIn("anchor_time_alignment", kinds)
        reading = next(
            entry for entry in release["resources"]
            if entry["descriptor"]["kind"] == "structured_reading"
        )
        descriptor = reading["descriptor"]
        self.assertEqual(
            descriptor["provenance"]["input_resource_ids"], [resource_id]
        )
        reading_digest = descriptor["payload_blob"]["digest"]
        with zipfile.ZipFile(output) as archive:
            embedded = json.loads(archive.read(
                f"blobs/sha256/{reading_digest.removeprefix('sha256:')}"
            ))
        self.assertEqual(embedded["text"], "Hello world. This is a first test.")
        alignment = next(
            entry for entry in release["resources"]
            if entry["descriptor"]["kind"] == "anchor_time_alignment"
        )
        alignment_descriptor = alignment["descriptor"]
        self.assertEqual(
            alignment_descriptor["dependencies"],
            [{"resource_id": reading["resource_id"]}],
        )
        self.assertEqual(
            alignment_descriptor["subject"]["anchor_resource_ids"],
            [reading["resource_id"]],
        )

    def test_provider_facts_never_leak_into_package(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="synchronized_read_listen")
        )
        output = self.directory / "facts.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--tts-provider", "fake", "--machine-events",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(output) as archive:
            raw_release = archive.read("release.json").decode("utf-8")
        audio = next(
            rendition for rendition in release_renditions(output)
            if rendition["origin"] == "derived"
        )
        producer = audio["producer"]
        self.assertEqual(producer["provider"], {"id": "fake", "version": "0.0.0"})
        self.assertIsNotNone(producer["config_sha256"])
        for private in ("/private/", "/Users/", self.directory.name, "tmp"):
            self.assertNotIn(private, raw_release)

    def test_no_paths_in_resource_payloads(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="read")
        )
        output = self.directory / "paths.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
        ])
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(output) as archive:
            for name in archive.namelist():
                if name.endswith(".json"):
                    content = archive.read(name).decode("utf-8")
                    self.assertNotIn(self.directory.name, content)
                    self.assertNotIn("/tmp", content)

    def test_already_satisfied_capability_completes_without_artifact(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="listen")
        )
        request = json.loads(request_path.read_text())
        request["available_renditions"] = [media_rendition(self.directory)]
        request_path.write_text(json.dumps(request))
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 0)
        events = parse_events(result.stdout)
        self.assertEqual(events[-1]["event"], "completed")
        self.assertIsNone(events[-1]["package_sha256"])
        self.assertFalse(output.exists())

    def test_unsupported_capability_fails_before_running(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="watch")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 2)
        events = parse_events(result.stdout)
        failed = events[-1]
        self.assertEqual(failed["event"], "failed")
        self.assertEqual(failed["code"], "unsupported_capability")
        self.assertFalse(output.exists())

    def test_invalid_request_fails_with_invalid_request(self) -> None:
        request_path = self.directory / "request.json"
        request_path.write_text(json.dumps({"schema": "wrong"}), encoding="utf-8")
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 2)
        events = parse_events(result.stdout)
        self.assertEqual(events[-1]["code"], "invalid_request")
        self.assertNotIn("accepted", self.event_sequence(events))

    def test_blank_document_abstains_honestly(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, text="   \n  ")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--machine-events",
        ])
        self.assertEqual(result.returncode, 2)
        events = parse_events(result.stdout)
        self.assertEqual(events[-1]["event"], "failed")
        self.assertEqual(events[-1]["code"], "document_text_unavailable")

    def test_missing_tts_provider_fails_honestly(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="listen")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output),
            "--tts-provider", "say",
            "--tts-voice", "x",
            "--machine-events",
        ])
        # The real `say` exists on macOS, so this only asserts the failure
        # shape when the tool is unavailable.
        if result.returncode == 2:
            events = parse_events(result.stdout)
            self.assertEqual(events[-1]["event"], "failed")
            self.assertEqual(events[-1]["code"], "tts_provider_failed")

    def test_deterministic_output_across_runs(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="synchronized_read_listen")
        )
        first = self.directory / "first.zip"
        second = self.directory / "second.zip"
        for output in (first, second):
            result = run_cli([
                "package", "from-capability", str(request_path),
                "--output", str(output), "--tts-provider", "fake",
            ])
            self.assertEqual(result.returncode, 0)
        self.assertEqual(first.read_bytes(), second.read_bytes())

    def test_retry_never_rewrites_the_old_attempt(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, attempt_id="attempt-a")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path), "--output", str(output),
        ])
        self.assertEqual(result.returncode, 0)
        first_bytes = output.read_bytes()
        time.sleep(0.05)
        result = run_cli([
            "package", "from-capability", str(request_path), "--output", str(output),
        ])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(first_bytes, output.read_bytes())
        self.assertEqual(sha256_of_bytes(first_bytes), sha256_of_bytes(output.read_bytes()))

    def test_package_contains_no_private_paths(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="listen")
        )
        output = self.directory / "package.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--tts-provider", "fake",
        ])
        self.assertEqual(result.returncode, 0)
        with zipfile.ZipFile(output) as archive:
            raw_release = archive.read("release.json")
            for blob in archive.namelist()[1:]:
                raw_release += archive.read(blob)
        for marker in (b"/Users/", b"/tmp/", b"tmp/", b"private"):
            self.assertNotIn(marker, raw_release)

    def test_cancellation_terminates_and_leaves_no_artifact(self) -> None:
        request_path = self.write_request(
            request_document(self.directory, capability="synchronized_read_listen")
        )
        output = self.directory / "cancel.zip"
        marker = self.directory / "before-commit.marker"
        env = _env()
        env["LISTEN_GEN_TEST_PAUSE_BEFORE_TERMINAL_COMMIT"] = "1"
        env["LISTEN_GEN_TEST_BEFORE_COMMIT_MARKER"] = str(marker)
        process = subprocess.Popen(
            [sys.executable, "-m", "listen_gen", "package", "from-capability",
             str(request_path), "--output", str(output), "--tts-provider", "fake",
             "--machine-events"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=env,
        )
        for _ in range(200):
            if marker.exists():
                break
            time.sleep(0.05)
        process.send_signal(signal.SIGTERM)
        stdout, _ = process.communicate(timeout=30)
        self.assertEqual(process.returncode, 130)
        events = parse_events(stdout)
        self.assertEqual(events[-1]["event"], "cancelled")
        self.assertFalse(output.exists())
        self.assertFalse(list(self.directory.glob(".*.machine.tmp")))

    def test_core_round_trip_when_checkout_is_configured(self) -> None:
        core = os.environ.get("LISTEN_CORE_CHECKOUT")
        if not core:
            self.skipTest("LISTEN_CORE_CHECKOUT is not set")
        example = Path(core) / "target" / "debug" / "examples" / "inspect-package"
        if not example.exists():
            self.skipTest("Core inspect-package example is not built")
        request_path = self.write_request(
            request_document(self.directory, capability="listen")
        )
        output = self.directory / "round-trip.zip"
        result = run_cli([
            "package", "from-capability", str(request_path),
            "--output", str(output), "--tts-provider", "fake",
        ])
        self.assertEqual(result.returncode, 0)
        check = subprocess.run(
            [str(example), str(output)], capture_output=True, text=True, timeout=60
        )
        self.assertEqual(check.returncode, 0, check.stderr)
        self.assertTrue(check.stdout.startswith("OK "))


if __name__ == "__main__":
    unittest.main()
