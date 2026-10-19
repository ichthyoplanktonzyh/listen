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
    Qwen3AsrAdapter,
    SenseVoiceAsrAdapter,
    _clean_sensevoice_text,
    _qwen_language_to_tag,
    _words_from_aligned_items,
)
from listen_gen.package import ConversionError
from listen_gen.sentence_assembly import assemble_asr_transcript
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
            model_id="ggml-large-v3-turbo.bin",
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
        self.assertEqual(transcript.model_id, "ggml-large-v3-turbo.bin")

    def test_word_timings_are_reported(self) -> None:
        transcript = self.make_adapter().transcribe(MEDIA)
        words = [word for segment in transcript.segments for word in segment.words]
        self.assertTrue(words)
        self.assertTrue(all(word.timing_source == "asr_reported" for word in words))

    def test_missing_model_rejected_at_construction(self) -> None:
        with self.assertRaises(ConversionError):
            self.make_adapter(model_path=Path("/does/not/exist.bin"))


# ---------------------------------------------------------------------------
# Neural sidecar adapters (Qwen3-ASR, SenseVoice) — the model is never loaded;
# a fake sidecar replays a canned core JSON so the pure adapter logic
# (language mapping, char-anchored word timing, absolute time, provenance,
# config hash, invalid-output handling) is exercised deterministically.
# ---------------------------------------------------------------------------


def _fake_sidecar(directory: Path, core: dict, argv_out: Path | None = None) -> Path:
    script = directory / "fake_sidecar.py"
    payload = json.dumps(core)
    lines = ["import sys, json"]
    if argv_out is not None:
        lines.append(f"open({str(argv_out)!r}, 'w').write(json.dumps(sys.argv))")
    lines.append(f"sys.stdout.write({payload!r})")
    script.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return script


def _qwen_core(**overrides) -> dict:
    core = {
        "schema": "listen_gen.qwen3-asr-core.v1",
        "runtime_version": "0.0.6-test",
        "language": "English",
        "text": "Hello world. How are you?",
        "duration_ms": 2000,
        "items": [
            {"text": "Hello", "start_ms": 0, "end_ms": 500},
            {"text": "world", "start_ms": 500, "end_ms": 1000},
            {"text": "How", "start_ms": 1200, "end_ms": 1400},
            {"text": "are", "start_ms": 1400, "end_ms": 1600},
            {"text": "you", "start_ms": 1600, "end_ms": 2000},
        ],
    }
    core.update(overrides)
    return core


class Qwen3AsrAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp(prefix="listen-gen-qwen-asr-"))

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.directory, ignore_errors=True)

    def make_adapter(self, core: dict, argv_out: Path | None = None, **kwargs) -> Qwen3AsrAdapter:
        sidecar = _fake_sidecar(self.directory, core, argv_out)
        defaults = dict(model_id="Qwen/Qwen3-ASR-0.6B", language="auto", timeout_seconds=30.0)
        defaults.update(kwargs)
        return Qwen3AsrAdapter(Path(sys.executable), sidecar, **defaults)

    def test_maps_language_segments_and_word_timing(self) -> None:
        transcript = self.make_adapter(_qwen_core()).transcribe(MEDIA)
        self.assertEqual(transcript.language, "en")
        self.assertEqual(transcript.provider_id, "qwen3-asr")
        self.assertEqual(transcript.model_id, "Qwen/Qwen3-ASR-0.6B")
        self.assertEqual(len(transcript.segments), 1)
        segment = transcript.segments[0]
        self.assertEqual(segment.text, "Hello world. How are you?")
        # word char spans line up with the reading tokens, timing is absolute
        self.assertEqual(
            [(w.start_char, w.end_char, w.start_ms, w.end_ms) for w in segment.words],
            [(0, 5, 0, 500), (6, 11, 500, 1000), (13, 16, 1200, 1400),
             (17, 20, 1400, 1600), (21, 24, 1600, 2000)],
        )
        self.assertEqual((segment.start_ms, segment.end_ms), (0, 2000))

    def test_two_sentence_fragment_splits_on_assembly(self) -> None:
        transcript = self.make_adapter(_qwen_core()).transcribe(MEDIA)
        assembled = assemble_asr_transcript(transcript)
        self.assertEqual(
            [s.text for s in assembled.segments],
            ["Hello world.", "How are you?"],
        )
        self.assertEqual(assembled.segments[0].start_ms, 0)
        self.assertEqual(assembled.segments[1].end_ms, 2000)

    def test_chinese_language_and_cjk_word_mapping(self) -> None:
        core = _qwen_core(
            language="Chinese",
            text="你好。世界。",
            duration_ms=1200,
            items=[
                {"text": "你", "start_ms": 0, "end_ms": 300},
                {"text": "好", "start_ms": 300, "end_ms": 600},
                {"text": "世", "start_ms": 700, "end_ms": 900},
                {"text": "界", "start_ms": 900, "end_ms": 1200},
            ],
        )
        transcript = self.make_adapter(core).transcribe(MEDIA)
        self.assertEqual(transcript.language, "zh")
        assembled = assemble_asr_transcript(transcript)
        self.assertEqual([s.text for s in assembled.segments], ["你好。", "世界。"])

    def test_merged_language_uses_first_tag(self) -> None:
        transcript = self.make_adapter(_qwen_core(language="Chinese,English")).transcribe(MEDIA)
        self.assertEqual(transcript.language, "zh")

    def test_unrecognized_language_is_a_provider_error(self) -> None:
        with self.assertRaises(ConversionError):
            self.make_adapter(_qwen_core(language="Klingon")).transcribe(MEDIA)

    def test_empty_transcript_is_rejected(self) -> None:
        with self.assertRaises(ConversionError):
            self.make_adapter(_qwen_core(text="   ", items=[])).transcribe(MEDIA)

    def test_no_timing_falls_back_to_duration_window(self) -> None:
        core = _qwen_core(text="Untimed speech.", items=[])
        transcript = self.make_adapter(core).transcribe(MEDIA)
        segment = transcript.segments[0]
        self.assertEqual(segment.words, ())
        self.assertEqual((segment.start_ms, segment.end_ms), (0, 2000))

    def test_invalid_schema_is_rejected(self) -> None:
        with self.assertRaises(ConversionError):
            self.make_adapter({"schema": "nope"}).transcribe(MEDIA)

    def test_argv_forwards_media_and_mapped_language(self) -> None:
        argv_out = self.directory / "argv.json"
        adapter = self.make_adapter(_qwen_core(), argv_out=argv_out, language="en")
        adapter.transcribe(MEDIA)
        argv = json.loads(argv_out.read_text())
        self.assertIn("--audio", argv)
        self.assertIn(str(MEDIA), argv)
        self.assertIn("--model-id", argv)
        self.assertIn("Qwen/Qwen3-ASR-0.6B", argv)
        # a concrete BCP-47 request is forced as the Qwen language name
        self.assertEqual(argv[argv.index("--language") + 1], "English")

    def test_config_hash_is_stable_and_model_sensitive(self) -> None:
        one = self.make_adapter(_qwen_core(), model_id="Qwen/Qwen3-ASR-0.6B").transcribe(MEDIA)
        two = self.make_adapter(_qwen_core(), model_id="Qwen/Qwen3-ASR-1.7B").transcribe(MEDIA)
        self.assertTrue(one.config_sha256.startswith("sha256:"))
        self.assertNotEqual(one.config_sha256, two.config_sha256)

    def test_missing_sidecar_rejected_at_construction(self) -> None:
        with self.assertRaises(ConversionError):
            Qwen3AsrAdapter(Path(sys.executable), self.directory / "nope.py")


def _sensevoice_core(**overrides) -> dict:
    core = {
        "schema": "listen_gen.sensevoice-asr-core.v1",
        "runtime_version": "1.1.0-test",
        "segments": [
            {"start_ms": 0, "end_ms": 2000, "text": "<|en|><|NEUTRAL|><|Speech|><|woitn|>Hello world."},
            {"start_ms": 2100, "end_ms": 4000, "text": "<|en|><|HAPPY|><|Speech|>How are you?"},
        ],
    }
    core.update(overrides)
    return core


class SenseVoiceAsrAdapterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.directory = Path(tempfile.mkdtemp(prefix="listen-gen-sensevoice-"))

    def tearDown(self) -> None:
        import shutil

        shutil.rmtree(self.directory, ignore_errors=True)

    def make_adapter(self, core: dict, **kwargs) -> SenseVoiceAsrAdapter:
        sidecar = _fake_sidecar(self.directory, core)
        defaults = dict(model_id="iic/SenseVoiceSmall", language="auto", timeout_seconds=30.0)
        defaults.update(kwargs)
        return SenseVoiceAsrAdapter(Path(sys.executable), sidecar, **defaults)

    def test_vad_fragments_and_meta_tag_cleanup(self) -> None:
        transcript = self.make_adapter(_sensevoice_core()).transcribe(MEDIA)
        self.assertEqual(transcript.language, "en")
        self.assertEqual(transcript.provider_id, "sensevoice")
        self.assertEqual(len(transcript.segments), 2)
        self.assertEqual(transcript.segments[0].text, "Hello world.")
        self.assertEqual(transcript.segments[1].text, "How are you?")
        for segment in transcript.segments:
            self.assertNotIn("<|", segment.text)
            self.assertEqual(segment.words, ())
        self.assertEqual(
            (transcript.segments[0].start_ms, transcript.segments[0].end_ms), (0, 2000)
        )

    def test_language_tag_maps(self) -> None:
        core = _sensevoice_core(
            segments=[{"start_ms": 0, "end_ms": 1500, "text": "<|zh|><|NEUTRAL|><|Speech|>你好世界。"}]
        )
        transcript = self.make_adapter(core).transcribe(MEDIA)
        self.assertEqual(transcript.language, "zh")
        self.assertEqual(transcript.segments[0].text, "你好世界。")

    def test_empty_regions_are_dropped(self) -> None:
        core = _sensevoice_core(
            segments=[
                {"start_ms": 0, "end_ms": 1000, "text": "<|en|><|NEUTRAL|><|Speech|>"},
                {"start_ms": 1000, "end_ms": 2000, "text": "<|en|><|NEUTRAL|><|Speech|>Real text."},
            ]
        )
        transcript = self.make_adapter(core).transcribe(MEDIA)
        self.assertEqual(len(transcript.segments), 1)
        self.assertEqual(transcript.segments[0].text, "Real text.")

    def test_no_language_tag_falls_back_to_configured(self) -> None:
        core = _sensevoice_core(
            segments=[{"start_ms": 0, "end_ms": 1000, "text": "no tags here"}]
        )
        transcript = self.make_adapter(core, language="ja").transcribe(MEDIA)
        self.assertEqual(transcript.language, "ja")

    def test_invalid_schema_is_rejected(self) -> None:
        with self.assertRaises(ConversionError):
            self.make_adapter({"schema": "nope", "segments": []}).transcribe(MEDIA)

    def test_config_hash_is_stable_and_model_sensitive(self) -> None:
        one = self.make_adapter(_sensevoice_core(), model_id="iic/SenseVoiceSmall").transcribe(MEDIA)
        two = self.make_adapter(_sensevoice_core(), model_id="other/model").transcribe(MEDIA)
        self.assertTrue(one.config_sha256.startswith("sha256:"))
        self.assertNotEqual(one.config_sha256, two.config_sha256)


class NeuralAsrHelperTests(unittest.TestCase):
    def test_qwen_language_mapping(self) -> None:
        self.assertEqual(_qwen_language_to_tag("English"), "en")
        self.assertEqual(_qwen_language_to_tag("Chinese"), "zh")
        self.assertEqual(_qwen_language_to_tag("Cantonese"), "yue")
        self.assertEqual(_qwen_language_to_tag("Chinese,English"), "zh")
        with self.assertRaises(ConversionError):
            _qwen_language_to_tag("")
        with self.assertRaises(ConversionError):
            _qwen_language_to_tag("Elvish")

    def test_words_anchor_reading_tokens_without_fabrication(self) -> None:
        text = "Listen carefully now."
        items = [("Listen", 100, 300), ("carefully", 350, 600)]  # provider dropped "now"
        words = _words_from_aligned_items(text, items)
        self.assertEqual(
            [(w["start_char"], w["end_char"], w["start_ms"], w["end_ms"]) for w in words],
            [(0, 6, 100, 300), (7, 16, 350, 600)],
        )
        # "now" had no provider item, so it simply carries no timing
        self.assertTrue(all(w["end_char"] <= len("Listen carefully") for w in words))

    def test_words_reconstruct_provider_subsplits(self) -> None:
        text = "don't stop"
        items = [("do", 0, 100), ("n't", 100, 200), ("stop", 250, 500)]
        words = _words_from_aligned_items(text, items)
        self.assertEqual(
            [(w["start_char"], w["end_char"], w["start_ms"], w["end_ms"]) for w in words],
            [(0, 5, 0, 200), (6, 10, 250, 500)],
        )

    def test_words_reconstruct_provider_merges_hyphenated(self) -> None:
        # The reading tokenizer splits on the hyphen ("red" + "eye"), but the
        # forced aligner emits one merged "redeye" item. The stream still stays
        # in sync (regression: this used to desync and drop every later word,
        # e.g. "flight"). The first sub-word takes the merged window; the
        # second cannot get a distinct monotonic window, so it honestly carries
        # no timing rather than a fabricated split.
        text = "your red-eye flight"
        items = [("your", 0, 200), ("redeye", 300, 900), ("flight", 950, 1300)]
        words = _words_from_aligned_items(text, items)
        self.assertEqual(
            [(text[w["start_char"]:w["end_char"]], w["start_ms"], w["end_ms"]) for w in words],
            [("your", 0, 200), ("red", 300, 900), ("flight", 950, 1300)],
        )

    def test_clean_sensevoice_text(self) -> None:
        language, text = _clean_sensevoice_text("<|en|><|NEUTRAL|><|Speech|><|woitn|>Hello there.")
        self.assertEqual(language, "en")
        self.assertEqual(text, "Hello there.")
        language, text = _clean_sensevoice_text("no meta tags")
        self.assertIsNone(language)
        self.assertEqual(text, "no meta tags")


if __name__ == "__main__":
    unittest.main()
