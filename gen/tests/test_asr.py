from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.asr import (
    CommandAsrAdapter,
    FixtureAsrAdapter,
    PreprocessingAsrAdapter,
)
from listen_gen.package import ConversionError
from listen_gen.whisper_cpp import WhisperCppAsrAdapter

FIXTURES = ROOT / "tests" / "fixtures"
MEDIA = FIXTURES / "sample-media.wav"
TRANSCRIPT = FIXTURES / "sample.asr.json"


class FixtureAsrAdapterTests(unittest.TestCase):
    def test_parses_valid_transcript(self) -> None:
        adapter = FixtureAsrAdapter(TRANSCRIPT)
        transcript = adapter.transcribe(MEDIA)
        self.assertEqual(transcript.language, "en-US")
        self.assertEqual(len(transcript.segments), 2)
        self.assertEqual(transcript.segments[0].text, "Listen, carefully!")
        self.assertEqual(transcript.segments[0].start_ms, 100)
        self.assertEqual(transcript.provider_id, "fixture-asr")

    def test_invalid_schema_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "bad.json"
            fixture.write_text(json.dumps({"schema": "other"}), encoding="utf-8")
            adapter = FixtureAsrAdapter(fixture)
            with self.assertRaises(ConversionError):
                adapter.transcribe(MEDIA)

    def test_non_contiguous_word_spans_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / "bad.json"
            document = json.loads(TRANSCRIPT.read_text())
            document["segments"][0]["words"][1]["start_char"] = 2
            fixture.write_text(json.dumps(document), encoding="utf-8")
            adapter = FixtureAsrAdapter(fixture)
            with self.assertRaises(ConversionError):
                adapter.transcribe(MEDIA)

    def test_missing_media_rejected(self) -> None:
        adapter = FixtureAsrAdapter(TRANSCRIPT)
        with self.assertRaises(ConversionError):
            adapter.transcribe(Path("/does/not/exist.wav"))


class CommandAsrAdapterTests(unittest.TestCase):
    def test_receives_media_placeholder_and_parses(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            script = _echo_transcript_script(Path(directory))
            adapter = CommandAsrAdapter(
                str(script),
                ["{media}"],
                30.0,
            )
            transcript = adapter.transcribe(MEDIA)
            self.assertGreaterEqual(len(transcript.segments), 1)
            self.assertEqual(transcript.provider_id, "fixture-asr")

    def test_requires_exactly_one_placeholder(self) -> None:
        with self.assertRaises(ValueError):
            CommandAsrAdapter("x", [], 30.0)
        with self.assertRaises(ValueError):
            CommandAsrAdapter("x", ["{media}", "{media}"], 30.0)

    def test_failure_does_not_expose_raw_output(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "fail.py"
            script.write_text(
                "#!/usr/bin/env python3\nimport sys\nprint('secret detail')\nsys.exit(3)\n",
                encoding="utf-8",
            )
            script.chmod(0o755)
            adapter = CommandAsrAdapter(str(script), ["{media}"], 30.0)
            with self.assertRaises(ConversionError) as caught:
                adapter.transcribe(MEDIA)
            self.assertNotIn("secret", str(caught.exception))

    def test_timeout_is_safe(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            script = Path(directory) / "sleep.py"
            script.write_text(
                "#!/usr/bin/env python3\nimport time\ntime.sleep(10)\n",
                encoding="utf-8",
            )
            script.chmod(0o755)
            adapter = CommandAsrAdapter(str(script), ["{media}"], 0.2)
            with self.assertRaises(ConversionError):
                adapter.transcribe(MEDIA)


def _echo_transcript_script(directory: Path) -> Path:
    script = directory / "echo_transcript.py"
    script.write_text(
        "#!/usr/bin/env python3\nimport sys\n"
        "from pathlib import Path\n"
        f"print(Path({str(TRANSCRIPT)!r}).read_text(), end='')\n",
        encoding="utf-8",
    )
    script.chmod(0o755)
    return script


class WhisperCppAsrAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp(prefix="listen-gen-whisper-"))
        self.model = self.directory / "model.bin"
        self.model.write_bytes(b"FAKE-WHISPER-MODEL")

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.directory, ignore_errors=True)

    def make_adapter(self, **overrides) -> WhisperCppAsrAdapter:
        defaults = dict(
            executable=str(FIXTURES / "fake_whisper_cli.py"),
            model_path=self.model,
            model_id="fake-whisper",
            language="en",
            translate_to_english=False,
            timeout_seconds=30.0,
        )
        defaults.update(overrides)
        return WhisperCppAsrAdapter(**defaults)

    def test_transcribes_with_fake_whisper_cli(self) -> None:
        transcript = self.make_adapter().transcribe(MEDIA)
        self.assertGreaterEqual(len(transcript.segments), 1)
        self.assertEqual(transcript.provider_id, "whisper.cpp")

    def test_model_identity_flows_into_transcript(self) -> None:
        transcript = self.make_adapter().transcribe(MEDIA)
        self.assertEqual(transcript.model_id, "fake-whisper")

    def test_missing_model_rejected_at_construction(self) -> None:
        with self.assertRaises(ConversionError):
            self.make_adapter(model_path=Path("/does/not/exist.bin"))


if __name__ == "__main__":
    unittest.main()
