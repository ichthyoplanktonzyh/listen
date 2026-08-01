from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.asr import CommandAsrAdapter, FixtureAsrAdapter, package_media
from listen_gen.cli import main
from listen_gen.package import ConversionError, package_from_lltimeline


class NativeAsrPackageTests(unittest.TestCase):
    media = ROOT / "tests" / "fixtures" / "sample-media.wav"
    fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"

    def build(self, output: Path) -> dict[str, object]:
        return package_media(
            self.media,
            output,
            FixtureAsrAdapter(self.fixture),
            title="Fixture lesson",
            media_kind="audio",
            duration_ms=2200,
            created_at_ms=1785542400000,
        )

    def test_native_build_is_deterministic_closed_and_redacted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.listenpkg"
            second = Path(directory) / "second.listenpkg"
            one, two = self.build(first), self.build(second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(one["package_sha256"], two["package_sha256"])
            package_bytes = first.read_bytes()
            self.assertNotIn(str(self.media).encode(), package_bytes)
            self.assertNotIn(str(self.fixture).encode(), package_bytes)
            self.assertNotIn(b"raw_response", package_bytes)

            with zipfile.ZipFile(first) as archive:
                self.assertEqual(
                    archive.namelist(),
                    ["manifest.json", "resources/subtitle-text-track.json", "resources/word-timeline.json"],
                )
                manifest = json.loads(archive.read("manifest.json"))
                self.assertEqual(
                    manifest["content_document"]["media_fingerprint"],
                    f"sha256:{hashlib.sha256(self.media.read_bytes()).hexdigest()}",
                )
                self.assertEqual([entry["kind"] for entry in manifest["resources"]], ["subtitle_text_track", "word_timeline"])
                subtitle_raw = archive.read("resources/subtitle-text-track.json")
                words_raw = archive.read("resources/word-timeline.json")
                subtitle = json.loads(subtitle_raw)
                words = json.loads(words_raw)
                self.assertEqual(words["dependencies"], [{
                    "kind": "subtitle_text_track",
                    "resource_id": f"sha256:{hashlib.sha256(subtitle_raw).hexdigest()}",
                }])
                self.assertEqual(subtitle["payload"]["source_kind"], "asr")
                self.assertEqual(
                    [token["kind"] for token in subtitle["payload"]["sentences"][0]["tokens"]],
                    ["word", "punctuation", "whitespace", "word", "punctuation"],
                )
                self.assertEqual([word["token_index"] for word in words["payload"]["words"]], [0, 3, 0, 2])

    def test_cli_runs_complete_offline_media_flow(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson.listenpkg"
            code = main([
                "package", "from-media", str(self.media), "--output", str(output),
                "--provider", "fixture", "--fixture", str(self.fixture),
                "--title", "Fixture lesson", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1785542400000",
            ])
            self.assertEqual(code, 0)
            self.assertTrue(output.is_file())

    def test_command_provider_receives_media_and_builds_package(self) -> None:
        helper = ROOT / "tests" / "fixtures" / "fake_asr_command.py"
        ffprobe = ROOT / "tests" / "fixtures" / "fake_ffprobe.py"
        ffmpeg = ROOT / "tests" / "fixtures" / "fake_ffmpeg.py"
        media = ROOT / "tests" / "fixtures" / "single-audio-media.json"
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "command.listenpkg"
            second_output = Path(directory) / "command-second.listenpkg"
            observed = Path(directory) / "observed.txt"
            arguments = [
                "package", "from-media", str(media), "--output", str(output),
                "--provider", "command", "--command", sys.executable,
                "--command-arg", str(helper), "--command-arg", "success",
                "--command-arg", "{media}", "--command-arg", str(self.fixture),
                "--command-arg", str(observed), "--command-timeout-seconds", "5",
                "--ffprobe-command", str(ffprobe), "--ffmpeg-command", str(ffmpeg),
                "--title", "Command lesson", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1785542400000",
            ]
            code = main(arguments)
            self.assertEqual(code, 0)
            normalized_path = Path(observed.read_text(encoding="utf-8"))
            self.assertEqual(normalized_path.name, "normalized.wav")
            self.assertFalse(normalized_path.exists())
            self.assertTrue(output.is_file())
            package_bytes = output.read_bytes()
            self.assertNotIn(str(media).encode(), package_bytes)
            self.assertNotIn(str(normalized_path).encode(), package_bytes)
            with zipfile.ZipFile(output) as archive:
                manifest = json.loads(archive.read("manifest.json"))
            self.assertEqual(
                manifest["content_document"]["media_fingerprint"],
                f"sha256:{hashlib.sha256(media.read_bytes()).hexdigest()}",
            )
            second_arguments = list(arguments)
            second_arguments[second_arguments.index(str(output))] = str(second_output)
            self.assertEqual(main(second_arguments), 0)
            self.assertEqual(output.read_bytes(), second_output.read_bytes())

    def test_selected_stream_changes_pipeline_config_identity(self) -> None:
        helper = ROOT / "tests" / "fixtures" / "fake_asr_command.py"
        ffprobe = ROOT / "tests" / "fixtures" / "fake_ffprobe.py"
        ffmpeg = ROOT / "tests" / "fixtures" / "fake_ffmpeg.py"
        media = ROOT / "tests" / "fixtures" / "multi-audio-media.json"
        with tempfile.TemporaryDirectory() as directory:
            identities = []
            for stream_index in (1, 3):
                output = Path(directory) / f"stream-{stream_index}.listenpkg"
                observed = Path(directory) / f"observed-{stream_index}.txt"
                code = main([
                    "package", "from-media", str(media), "--output", str(output),
                    "--provider", "command", "--command", sys.executable,
                    "--command-arg", str(helper), "--command-arg", "success",
                    "--command-arg", "{media}", "--command-arg", str(self.fixture),
                    "--command-arg", str(observed), "--audio-stream-index", str(stream_index),
                    "--ffprobe-command", str(ffprobe), "--ffmpeg-command", str(ffmpeg),
                    "--title", "Stream lesson", "--media-kind", "video",
                    "--duration-ms", "2200", "--created-at-ms", "1785542400000",
                ])
                self.assertEqual(code, 0)
                with zipfile.ZipFile(output) as archive:
                    subtitle = json.loads(
                        archive.read("resources/subtitle-text-track.json")
                    )
                identity = subtitle["provenance"]["config_sha256"]
                self.assertRegex(identity, r"^sha256:[0-9a-f]{64}$")
                identities.append(identity)
                self.assertNotIn(str(ffprobe), output.read_text("latin-1"))
                self.assertNotIn(str(ffmpeg), output.read_text("latin-1"))
            self.assertNotEqual(identities[0], identities[1])

    def test_command_provider_failure_does_not_expose_output(self) -> None:
        helper = ROOT / "tests" / "fixtures" / "fake_asr_command.py"
        with tempfile.TemporaryDirectory() as directory:
            observed = Path(directory) / "observed.txt"
            adapter = CommandAsrAdapter(
                sys.executable,
                [str(helper), "fail", "{media}", str(self.fixture), str(observed)],
                5,
            )
            with self.assertRaisesRegex(ConversionError, "exit status 23") as raised:
                adapter.transcribe(self.media)
            message = str(raised.exception)
            self.assertNotIn("provider-secret", message)
            self.assertNotIn("raw_response", message)
            self.assertNotIn("must-not-leak", message)

    def test_asr_failure_preserves_existing_package_output(self) -> None:
        helper = ROOT / "tests" / "fixtures" / "fake_asr_command.py"
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "existing.listenpkg"
            original = b"existing-package-must-survive"
            output.write_bytes(original)
            adapter = CommandAsrAdapter(
                sys.executable,
                [
                    str(helper), "fail", "{media}", str(self.fixture),
                    str(Path(directory) / "observed.txt"),
                ],
                5,
            )
            with self.assertRaisesRegex(ConversionError, "exit status 23"):
                package_media(
                    self.media,
                    output,
                    adapter,
                    title="Failure",
                    media_kind="audio",
                    duration_ms=2200,
                    created_at_ms=1785542400000,
                )
            self.assertEqual(output.read_bytes(), original)

    def test_media_change_during_transcription_preserves_existing_output(self) -> None:
        class MutatingAdapter:
            def transcribe(adapter_self, media_path: Path):
                transcript = FixtureAsrAdapter(self.fixture).transcribe(media_path)
                media_path.write_bytes(media_path.read_bytes() + b"changed")
                return transcript

        with tempfile.TemporaryDirectory() as directory:
            media = Path(directory) / "media.wav"
            media.write_bytes(self.media.read_bytes())
            output = Path(directory) / "existing.listenpkg"
            original = b"existing-package-must-survive"
            output.write_bytes(original)

            with self.assertRaisesRegex(ConversionError, "changed during processing"):
                package_media(
                    media,
                    output,
                    MutatingAdapter(),
                    title="Changed input",
                    media_kind="audio",
                    duration_ms=2200,
                    created_at_ms=1785542400000,
                )

            self.assertEqual(output.read_bytes(), original)

    def test_command_provider_timeout_is_safe(self) -> None:
        helper = ROOT / "tests" / "fixtures" / "fake_asr_command.py"
        with tempfile.TemporaryDirectory() as directory:
            adapter = CommandAsrAdapter(
                sys.executable,
                [str(helper), "sleep", "{media}", str(self.fixture), str(Path(directory) / "observed.txt")],
                0.05,
            )
            with self.assertRaisesRegex(ConversionError, "timed out") as raised:
                adapter.transcribe(self.media)
            self.assertNotIn(str(self.media), str(raised.exception))

    def test_command_provider_bounds_output_and_kills_descendants_on_timeout(self) -> None:
        helper = ROOT / "tests" / "fixtures" / "fake_asr_command.py"
        with tempfile.TemporaryDirectory() as directory:
            observed = Path(directory) / "observed.txt"
            flooded = CommandAsrAdapter(
                sys.executable,
                [str(helper), "flood", "{media}", str(self.fixture), str(observed)],
                5,
            )
            with self.assertRaisesRegex(ConversionError, "safety limit"):
                flooded.transcribe(self.media)

            descendant = CommandAsrAdapter(
                sys.executable,
                [
                    str(helper), "spawn-child", "{media}", str(self.fixture),
                    str(observed),
                ],
                0.05,
            )
            with self.assertRaisesRegex(ConversionError, "timed out"):
                descendant.transcribe(self.media)
            time.sleep(0.5)
            self.assertFalse(observed.with_suffix(".child").exists())

    def test_command_provider_requires_one_exact_media_placeholder(self) -> None:
        with self.assertRaisesRegex(ConversionError, "exactly one"):
            CommandAsrAdapter("provider", [], 1)
        with self.assertRaisesRegex(ConversionError, "exactly one"):
            CommandAsrAdapter("provider", ["{media}", "{media}"], 1)

    def test_word_must_match_lossless_subtitle_token(self) -> None:
        value = json.loads(self.fixture.read_text(encoding="utf-8"))
        value["segments"][0]["words"][0]["end_char"] = 7
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "bad.json"
            fixture.write_text(json.dumps(value), encoding="utf-8")
            with self.assertRaisesRegex(ConversionError, "exactly match a word token"):
                package_media(
                    self.media, Path(directory) / "bad.listenpkg",
                    FixtureAsrAdapter(fixture), title="Bad", media_kind="audio",
                    duration_ms=2200, created_at_ms=0,
                )

    def test_native_and_legacy_fixtures_preserve_subtitle_word_semantics(self) -> None:
        legacy_fixture = ROOT / "tests" / "fixtures" / "sample.lltimeline.json"
        native_fixture = ROOT / "tests" / "fixtures" / "migration-equivalent.asr.json"
        with tempfile.TemporaryDirectory() as directory:
            legacy_package = Path(directory) / "legacy.listenpkg"
            native_package = Path(directory) / "native.listenpkg"
            package_from_lltimeline(legacy_fixture, legacy_package)
            package_media(
                self.media, native_package, FixtureAsrAdapter(native_fixture),
                title="A small lesson", media_kind="video", duration_ms=2000,
                created_at_ms=1700000000000,
            )

            def semantics(path: Path) -> dict[str, object]:
                with zipfile.ZipFile(path) as archive:
                    subtitle = json.loads(archive.read("resources/subtitle-text-track.json"))["payload"]
                    words = json.loads(archive.read("resources/word-timeline.json"))["payload"]["words"]
                sentence_indexes = {
                    sentence["id"]: sentence["index"] for sentence in subtitle["sentences"]
                }
                return {
                    "language": subtitle["language"],
                    "sentences": [{
                        key: sentence[key]
                        for key in ("index", "start_ms", "end_ms", "original_text", "display_text", "tokens")
                    } for sentence in subtitle["sentences"]],
                    "words": [{
                        **{key: word[key] for key in ("token_index", "start_ms", "end_ms", "confidence", "timing_source")},
                        "sentence_index": sentence_indexes[word["sentence_id"]],
                    } for word in words],
                }

            self.assertEqual(semantics(native_package), semantics(legacy_package))

    def test_core_inspector_accepts_native_fixture(self) -> None:
        checkout = os.environ.get("LISTEN_CORE_CHECKOUT")
        if checkout is None:
            self.skipTest("LISTEN_CORE_CHECKOUT is not set")
        core = Path(checkout)
        if not (core / "crates" / "content-package" / "Cargo.toml").is_file():
            self.fail("LISTEN_CORE_CHECKOUT does not contain crates/content-package")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson.listenpkg"
            self.build(output)
            probe = Path(directory) / "probe"
            (probe / "src").mkdir(parents=True)
            (probe / "Cargo.toml").write_text(
                "[package]\nname = \"listen-gen-contract-probe\"\nversion = \"0.0.0\"\nedition = \"2024\"\n"
                f"[dependencies]\ncontent-package = {{ path = {json.dumps(str(core / 'crates' / 'content-package'))} }}\n",
                encoding="utf-8",
            )
            (probe / "src" / "main.rs").write_text(
                "fn main() { content_package::inspect_path(std::env::args_os().nth(1).unwrap()).unwrap(); }\n",
                encoding="utf-8",
            )
            subprocess.run(
                ["cargo", "run", "-q", "--manifest-path", str(probe / "Cargo.toml"), "--", str(output)],
                cwd=probe,
                check=True,
                capture_output=True,
                text=True,
            )


if __name__ == "__main__":
    unittest.main()
