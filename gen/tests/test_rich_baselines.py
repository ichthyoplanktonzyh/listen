from __future__ import annotations

import hashlib
import json
import math
import struct
import subprocess
import sys
import tempfile
import unittest
import wave
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
TERMINAL_EVENTS = {"completed", "failed", "cancelled"}

from listen_gen.alignment import AlignmentSentence, AlignmentToken
from listen_gen.protocol import RichStageFailure, protocol_capabilities
from listen_gen.rich import (
    AcousticsRequest,
    ProsodyRequest,
    RichWord,
    SenseGroupRequest,
)
from listen_gen.rich_baselines import (
    AcousticProsodyBaseline,
    PunctuationSenseGroupBaseline,
    WavWordAcousticsBaseline,
)

SR = 16000


def _env(**overrides: str) -> dict[str, str]:
    env = dict(__import__("os").environ)
    env["PYTHONPATH"] = str(ROOT / "src")
    env.update(overrides)
    return env


def run_cli(
    argv: list[str],
    env: dict[str, str] | None = None,
    timeout: float = 90,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "listen_gen", *argv],
        capture_output=True,
        text=True,
        env=_env() if env is None else env,
        timeout=timeout,
    )


def parse_events(stdout: str) -> list[dict[str, object]]:
    return [json.loads(line) for line in stdout.splitlines() if line]


def read_package(output: Path) -> dict[str, object]:
    with zipfile.ZipFile(output) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        documents = {
            entry["kind"]: json.loads(archive.read(entry["path"]))
            for entry in manifest["resources"]
        }
    return {"manifest": manifest, "documents": documents}


def _sha256_bytes(data: bytes) -> str:
    return f"sha256:{hashlib.sha256(data).hexdigest()}"


def _tokens(*texts: str) -> tuple[AlignmentToken, ...]:
    out: list[AlignmentToken] = []
    for index, text in enumerate(texts):
        if text.isalnum():
            kind, normalized = "word", text.casefold()
        elif text in ",.!?;:":
            kind, normalized = "punctuation", None
        else:
            kind, normalized = "whitespace", None
        out.append(
            AlignmentToken(index, kind, text, normalized, 0, len(text))
        )
    return tuple(out)


def fixture_sentences() -> tuple[AlignmentSentence, ...]:
    """The exact subtitle sentences of the committed ASR/alignment fixtures."""
    first = AlignmentSentence(
        "s0", 0, 100, 1200, "Listen, carefully!", "Listen, carefully!",
        _tokens("Listen", ",", " ", "carefully", "!"),
    )
    second = AlignmentSentence(
        "s1", 1, 1300, 2100, "Words matter.", "Words matter.",
        _tokens("Words", " ", "matter", "."),
    )
    return (first, second)


def fixture_words() -> tuple[RichWord, ...]:
    return (
        RichWord(0, 0, 110, 490),
        RichWord(0, 3, 570, 1100),
        RichWord(1, 0, 1310, 1600),
        RichWord(1, 2, 1660, 2030),
    )


def write_tone_wav(path: Path, *, duration_ms: int = 2200) -> Path:
    """Write a deterministic 16 kHz mono s16le PCM WAV.

    The amplitude windows follow the fixture Word Timeline so the loudest
    words are deterministic: ``Listen`` is loudest in sentence 0 and
    ``matter`` is loudest in sentence 1.
    """
    count = SR * duration_ms // 1000

    def amplitude(t_ms: int) -> float:
        if 110 <= t_ms < 490:
            return 0.6
        if 570 <= t_ms < 1100:
            return 0.2
        if 1310 <= t_ms < 1600:
            return 0.4
        if 1660 <= t_ms < 2030:
            return 0.5
        return 0.0

    samples = [
        int(amplitude(i * 1000 // SR) * 32767 * math.sin(2 * math.pi * 220 * i / SR))
        for i in range(count)
    ]
    with wave.open(str(path), "wb") as writer:
        writer.setnchannels(1)
        writer.setsampwidth(2)
        writer.setframerate(SR)
        writer.writeframes(b"".join(struct.pack("<h", sample) for sample in samples))
    return path


def _measurement_dicts(result, sentences) -> tuple[dict, ...]:
    return tuple(
        {
            "word_ref": {
                "sentence_id": next(
                    sentence.id
                    for sentence in sentences
                    if sentence.index == measurement.sentence_index
                ),
                "token_index": measurement.token_index,
            },
            "energy": measurement.energy,
            "pitch": measurement.pitch,
            "duration": measurement.duration,
            "voiced_frame_ratio": measurement.voiced_frame_ratio,
        }
        for measurement in result.measurements
    )


def _groups_for(*spans: tuple[int, int, int]) -> tuple[dict, ...]:
    groups = []
    for group_index, (sentence_index, start, end) in enumerate(spans):
        groups.append(
            {
                "sentence_id": "s0" if sentence_index == 0 else "s1",
                "group_index": group_index,
                "start_token_index": start,
                "end_token_index_exclusive": end,
                "confidence": 1.0,
                "label": None,
                "head_token_index": start,
                "sources": ["punctuation"],
            }
        )
    return tuple(groups)


class BaselineSenseGroupTests(unittest.TestCase):
    def test_partition_matches_punctuation_and_sentence_boundaries(self) -> None:
        result = PunctuationSenseGroupBaseline().analyze(
            SenseGroupRequest(language="en-US", sentences=fixture_sentences())
        )
        spans = [
            (group.sentence_index, group.start_token_index, group.end_token_index_exclusive)
            for group in result.groups
        ]
        self.assertEqual(spans, [(0, 0, 2), (0, 2, 5), (1, 0, 4)])
        self.assertEqual(
            [group.sources for group in result.groups],
            [("punctuation",), ("punctuation",), ("punctuation",)],
        )
        for group in result.groups:
            self.assertEqual(group.confidence, 1.0)
            self.assertIn(group.head_token_index, range(
                group.start_token_index, group.end_token_index_exclusive
            ))

    def test_full_partition_and_rule_evidence(self) -> None:
        sentence = AlignmentSentence(
            "s2", 2, 0, 1000, "one two three four five six seven eight nine",
            "one two three four five six seven eight nine",
            _tokens(*"one two three four five six seven eight nine".split()),
        )
        result = PunctuationSenseGroupBaseline().analyze(
            SenseGroupRequest(language="en-US", sentences=(sentence,))
        )
        self.assertEqual(
            [(group.start_token_index, group.end_token_index_exclusive)
             for group in result.groups],
            [(0, 8), (8, 9)],
        )
        self.assertEqual(
            [group.sources for group in result.groups],
            [("length_limit",), ("rule",)],
        )
        previous_end = 0
        for group in result.groups:
            self.assertEqual(group.start_token_index, previous_end)
            previous_end = group.end_token_index_exclusive
        self.assertEqual(previous_end, 9)

    def test_config_identity_is_stable(self) -> None:
        first = PunctuationSenseGroupBaseline()
        second = PunctuationSenseGroupBaseline()
        self.assertEqual(first.config_sha256, second.config_sha256)
        self.assertRegex(first.config_sha256, r"^sha256:[0-9a-f]{64}$")


class BaselineAcousticsTests(unittest.TestCase):
    def test_measures_honest_energy_and_duration_with_sentence_baselines(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            wav = write_tone_wav(Path(directory) / "tone.wav")
            result = WavWordAcousticsBaseline().measure(
                AcousticsRequest(
                    language="en-US",
                    sentences=fixture_sentences(),
                    words=fixture_words(),
                    audio_path=wav,
                )
            )
            self.assertEqual(result.provider_id, "baseline-acoustics")
            self.assertEqual(result.sample_rate_hz, 16000)
            by_ref = {
                (measurement.sentence_index, measurement.token_index): measurement
                for measurement in result.measurements
            }
            listen = by_ref[(0, 0)]
            carefully = by_ref[(0, 3)]
            # "Listen" is louder than "carefully" in the deterministic WAV.
            self.assertGreater(listen.energy["rms_dbfs"], carefully.energy["rms_dbfs"])
            self.assertGreater(listen.energy["prominence"], carefully.energy["prominence"])
            # Sentence-local baseline: both share the sentence median.
            self.assertEqual(
                listen.energy["local_baseline_dbfs"],
                carefully.energy["local_baseline_dbfs"],
            )
            self.assertEqual(listen.duration["duration_ms"], 380)
            self.assertEqual(carefully.duration["duration_ms"], 530)
            # Duration is relative to the sentence median duration.
            self.assertLess(listen.duration["local_ratio"], 1.0)
            self.assertGreater(carefully.duration["local_ratio"], 1.0)

    def test_unmeasured_pitch_and_voicing_stay_null(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            wav = write_tone_wav(Path(directory) / "tone.wav")
            result = WavWordAcousticsBaseline().measure(
                AcousticsRequest(
                    language="en-US",
                    sentences=fixture_sentences(),
                    words=fixture_words(),
                    audio_path=wav,
                )
            )
            for measurement in result.measurements:
                self.assertIsNone(measurement.voiced_frame_ratio)
                self.assertIsNone(measurement.pitch["median_f0_hz"])
                self.assertIsNone(measurement.pitch["local_baseline_f0_hz"])
                self.assertIsNone(measurement.pitch["delta_semitones"])
                self.assertIsNone(measurement.pitch["range_semitones"])
                self.assertIsNone(measurement.pitch["prominence"])
                self.assertIsNone(measurement.pitch["reset_after"])
                self.assertIsNotNone(measurement.energy["rms_dbfs"])
                self.assertIsNotNone(measurement.duration["duration_ms"])

    def test_measurements_exactly_cover_the_word_timeline(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            wav = write_tone_wav(Path(directory) / "tone.wav")
            result = WavWordAcousticsBaseline().measure(
                AcousticsRequest(
                    language="en-US",
                    sentences=fixture_sentences(),
                    words=fixture_words(),
                    audio_path=wav,
                )
            )
            self.assertEqual(
                [(m.sentence_index, m.token_index) for m in result.measurements],
                [(w.sentence_index, w.token_index) for w in fixture_words()],
            )

    def test_unreadable_audio_abstains_with_failed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            not_wav = root / "not-audio.wav"
            not_wav.write_bytes(b"offline fixture media bytes; not a WAV stream\n")
            with self.assertRaises(RichStageFailure) as caught:
                WavWordAcousticsBaseline().measure(
                    AcousticsRequest(
                        language="en-US",
                        sentences=fixture_sentences(),
                        words=fixture_words(),
                        audio_path=not_wav,
                    )
                )
            self.assertEqual(caught.exception.code, "acoustics_failed")

    def test_wrong_sample_rate_abstains(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "wrong-rate.wav"
            write_tone_wav(path)
            # Rewrite the fmt sample-rate field to 48000.
            data = bytearray(path.read_bytes())
            data[24:28] = struct.pack("<I", 48000)
            path.write_bytes(bytes(data))
            with self.assertRaises(RichStageFailure) as caught:
                WavWordAcousticsBaseline().measure(
                    AcousticsRequest(
                        language="en-US",
                        sentences=fixture_sentences(),
                        words=fixture_words(),
                        audio_path=path,
                    )
                )
            self.assertEqual(caught.exception.code, "acoustics_failed")

    def test_audio_that_does_not_cover_the_timeline_abstains(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            wav = write_tone_wav(Path(directory) / "short.wav", duration_ms=1500)
            with self.assertRaises(RichStageFailure) as caught:
                WavWordAcousticsBaseline().measure(
                    AcousticsRequest(
                        language="en-US",
                        sentences=fixture_sentences(),
                        words=fixture_words(),
                        audio_path=wav,
                    )
                )
            self.assertEqual(caught.exception.code, "acoustics_failed")


class BaselineProsodyTests(unittest.TestCase):
    def _request(self, wav: Path, groups=None) -> ProsodyRequest:
        acoustics = WavWordAcousticsBaseline().measure(
            AcousticsRequest(
                language="en-US",
                sentences=fixture_sentences(),
                words=fixture_words(),
                audio_path=wav,
            )
        )
        measurements = _measurement_dicts(acoustics, fixture_sentences())
        return ProsodyRequest(
            language="en-US",
            sentences=fixture_sentences(),
            words=fixture_words(),
            measurements=measurements,
            groups=groups,
        )

    def test_chunks_are_explicit_and_independent_of_sense_groups(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            wav = write_tone_wav(Path(directory) / "tone.wav")
            groups = _groups_for((0, 0, 2), (0, 2, 5), (1, 0, 4))
            result = AcousticProsodyBaseline().analyze(self._request(wav, groups))
            self.assertFalse(result.uses_sense_groups)
            spans = [
                (chunk.sentence_index, chunk.start_token_index, chunk.end_token_index_exclusive)
                for chunk in result.chunks
            ]
            # Chunk spans come from timing/acoustic cues, not the sense groups:
            # the baseline declares one chunk per sentence because the
            # 80 ms inter-word pause is below the boundary threshold.
            self.assertEqual(spans, [(0, 0, 4), (1, 0, 3)])
            self.assertNotEqual(spans, [(0, 0, 2), (0, 2, 5), (1, 0, 4)])

    def test_pause_declares_a_boundary(self) -> None:
        sentence = AlignmentSentence(
            "s2", 0, 0, 2000, "one two", "one two", _tokens("one", " ", "two")
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pause.wav"
            count = SR * 2000 // 1000
            samples = []
            for i in range(count):
                t_ms = i * 1000 // SR
                amplitude = 0.5 if t_ms < 400 or 600 <= t_ms < 1000 else 0.0
                samples.append(int(amplitude * 32767 * math.sin(2 * math.pi * 220 * i / SR)))
            with wave.open(str(path), "wb") as writer:
                writer.setnchannels(1)
                writer.setsampwidth(2)
                writer.setframerate(SR)
                writer.writeframes(b"".join(struct.pack("<h", s) for s in samples))
            words = (RichWord(0, 0, 0, 400), RichWord(0, 2, 600, 1000))
            acoustics = WavWordAcousticsBaseline().measure(
                AcousticsRequest("en-US", (sentence,), words, path)
            )
            measurements = _measurement_dicts(acoustics, (sentence,))
            result = AcousticProsodyBaseline().analyze(
                ProsodyRequest("en-US", (sentence,), words, measurements, None)
            )
            # A 200 ms pause splits the sentence into two explicit chunks.
            self.assertEqual(
                [(chunk.start_token_index, chunk.end_token_index_exclusive)
                 for chunk in result.chunks],
                [(0, 1), (2, 3)],
            )
            self.assertEqual(
                [chunk.nucleus_token_index for chunk in result.chunks], [0, 2]
            )

    def test_anchors_are_conservative_and_preserve_unknown_stress(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            wav = write_tone_wav(Path(directory) / "tone.wav")
            result = AcousticProsodyBaseline().analyze(self._request(wav))
            self.assertTrue(result.anchors)
            self.assertEqual(len(result.anchors), len(result.chunks))
            for anchor in result.anchors:
                self.assertEqual(anchor.lexical_stress, "unknown")
                self.assertEqual(anchor.utterance_role, "nucleus")
                self.assertIn(anchor.evidence, (("energy",), ("duration",)))
                self.assertTrue(0 <= anchor.realized_prominence <= 1)
                self.assertTrue(0 <= anchor.confidence <= 1)
            # The nucleus of each sentence is the loudest measured word.
            nuclei = {
                anchor.sentence_index: anchor.token_index for anchor in result.anchors
            }
            self.assertEqual(nuclei, {0: 0, 1: 2})

    def test_sense_group_is_weak_evidence_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            wav = write_tone_wav(Path(directory) / "tone.wav")
            without = AcousticProsodyBaseline().analyze(self._request(wav))
            # A sense group whose span exactly equals the acoustic chunk span
            # boosts only the confidence; the span itself is unchanged.
            matching = _groups_for((0, 0, 4), (1, 0, 3))
            with_boost = AcousticProsodyBaseline().analyze(
                self._request(wav, matching)
            )
            self.assertEqual(
                [(c.start_token_index, c.end_token_index_exclusive)
                 for c in without.chunks],
                [(c.start_token_index, c.end_token_index_exclusive)
                 for c in with_boost.chunks],
            )
            self.assertGreater(
                with_boost.chunks[0].confidence, without.chunks[0].confidence
            )
            self.assertFalse(with_boost.uses_sense_groups)


class BaselineRoundtripTests(unittest.TestCase):
    asr_fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
    alignment_fixture = ROOT / "tests" / "fixtures" / "alignment-result.json"

    def baseline_argv(self, output: Path, media: Path) -> list[str]:
        return [
            "package", "from-media", str(media),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(self.asr_fixture),
            "--aligner", "fixture", "--alignment-fixture", str(self.alignment_fixture),
            "--sense-groups", "baseline",
            "--acoustics", "baseline",
            "--prosody", "baseline",
            "--title", "Baseline lesson", "--media-kind", "audio",
            "--duration-ms", "2200", "--created-at-ms", "1786000000000",
        ]

    def test_app_fixture_roundtrip_with_normalized_audio(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            media = write_tone_wav(root / "media.wav")
            output = root / "baseline.listenpkg"
            completed = run_cli(self.baseline_argv(output, media))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = read_package(output)
            self.assertEqual(
                [entry["kind"] for entry in package["manifest"]["resources"]],
                [
                    "subtitle_text_track",
                    "word_timeline",
                    "sense_group_analysis",
                    "word_acoustics",
                    "prosody_analysis",
                ],
            )
            result = json.loads(completed.stdout)
            self.assertEqual(result["rich_resources"], {
                "sense_groups": {"status": "produced", "warnings": []},
                "acoustics": {"status": "produced", "warnings": []},
                "prosody": {"status": "produced", "warnings": []},
            })

    def test_exact_dependencies_and_provenance(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            media = write_tone_wav(root / "media.wav")
            output = root / "baseline.listenpkg"
            completed = run_cli(self.baseline_argv(output, media))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = read_package(output)
            documents = package["documents"]
            sense = documents["sense_group_analysis"]
            acoustics = documents["word_acoustics"]
            prosody = documents["prosody_analysis"]
            self.assertEqual(
                [item["kind"] for item in sense["dependencies"]],
                ["subtitle_text_track"],
            )
            self.assertEqual(
                [item["kind"] for item in acoustics["dependencies"]],
                ["word_timeline"],
            )
            self.assertEqual(
                [item["kind"] for item in prosody["dependencies"]],
                ["word_timeline", "word_acoustics"],
            )
            self.assertEqual(sense["provenance"]["provider"], {
                "id": "baseline-sense-groups", "version": "1",
            })
            self.assertEqual(acoustics["provenance"]["provider"], {
                "id": "baseline-acoustics", "version": "1",
            })
            self.assertEqual(prosody["provenance"]["provider"], {
                "id": "baseline-prosody", "version": "1",
            })
            for resource in (sense, acoustics, prosody):
                self.assertRegex(
                    resource["provenance"]["config_sha256"], r"^sha256:[0-9a-f]{64}$"
                )
            for forbidden in (
                str(self.asr_fixture), str(self.alignment_fixture), str(media),
            ):
                self.assertNotIn(forbidden.encode(), output.read_bytes())

    def test_baseline_package_is_deterministic_and_path_independent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            packages = []
            for index in (1, 2):
                run_dir = root / f"run-{index}"
                run_dir.mkdir()
                media = write_tone_wav(run_dir / "media.wav")
                output = run_dir / "baseline.listenpkg"
                completed = run_cli(self.baseline_argv(output, media))
                self.assertEqual(completed.returncode, 0, completed.stderr)
                packages.append(output.read_bytes())
            self.assertEqual(packages[0], packages[1])

    def test_baselines_are_never_the_default(self) -> None:
        from listen_gen.cli import parser

        root = parser()
        arguments = root.parse_args([
            "package", "from-media", "media.wav",
            "--output", "x.listenpkg", "--provider", "fixture",
            "--title", "t", "--media-kind", "audio",
            "--duration-ms", "2200", "--created-at-ms", "1",
        ])
        self.assertEqual(arguments.sense_groups, "none")
        self.assertEqual(arguments.acoustics, "none")
        self.assertEqual(arguments.prosody, "none")
        capabilities = protocol_capabilities()
        for stage in ("sense_groups", "acoustics", "prosody"):
            self.assertIn(
                "baseline", capabilities["rich_resources"][stage]["adapters"]
            )

    def test_core_inspector_accepts_baseline_package(self) -> None:
        checkout = __import__("os").environ.get("LISTEN_CORE_CHECKOUT")
        if checkout is None:
            self.skipTest("LISTEN_CORE_CHECKOUT is not set")
        core = Path(checkout)
        if not (core / "crates" / "content-package" / "Cargo.toml").is_file():
            self.fail("LISTEN_CORE_CHECKOUT does not contain crates/content-package")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            media = write_tone_wav(root / "media.wav")
            output = root / "baseline.listenpkg"
            completed = run_cli(self.baseline_argv(output, media))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            probe = root / "probe"
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

    def test_machine_events_for_baseline_stages(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            media = write_tone_wav(root / "media.wav")
            output = root / "baseline.listenpkg"
            argv = self.baseline_argv(output, media) + ["--machine-events"]
            completed = run_cli(argv)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            self.assertEqual(
                [event["phase"] for event in events if event["event"] == "phase"],
                [
                    "validating", "transcribing", "aligning",
                    "analyzing_sense_groups", "measuring_acoustics",
                    "analyzing_prosody", "building_package",
                ],
            )
            final = [e for e in events if e["event"] == "completed"][0]
            self.assertEqual(final["rich_resources"], {
                "sense_groups": {"status": "produced", "warnings": []},
                "acoustics": {"status": "produced", "warnings": []},
                "prosody": {"status": "produced", "warnings": []},
            })


class BaselineAbstentionTests(unittest.TestCase):
    asr_fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
    alignment_fixture = ROOT / "tests" / "fixtures" / "alignment-result.json"

    def test_unreadable_audio_degrades_acoustics_and_prosody(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            media = root / "media.wav"
            media.write_bytes(b"not a wav at all; baseline must abstain\n")
            output = root / "degraded.listenpkg"
            argv = [
                "package", "from-media", str(media),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(self.asr_fixture),
                "--aligner", "fixture", "--alignment-fixture", str(self.alignment_fixture),
                "--sense-groups", "baseline",
                "--acoustics", "baseline",
                "--prosody", "baseline",
                "--title", "Degraded baseline", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1786000000000",
                "--machine-events",
            ]
            completed = run_cli(argv)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            final = [e for e in events if e["event"] in TERMINAL_EVENTS][0]
            self.assertEqual(final["event"], "completed")
            self.assertEqual(
                final["rich_resources"]["sense_groups"]["status"], "produced"
            )
            self.assertEqual(
                final["rich_resources"]["acoustics"]["status"], "degraded"
            )
            self.assertEqual(
                final["rich_resources"]["acoustics"]["warnings"][0]["code"],
                "acoustics_failed",
            )
            self.assertEqual(
                final["rich_resources"]["prosody"]["status"], "degraded"
            )
            self.assertEqual(
                final["rich_resources"]["prosody"]["warnings"][0]["code"],
                "prosody_upstream_missing",
            )
            self.assertEqual(
                [entry["kind"] for entry in final["resources"]],
                ["subtitle_text_track", "word_timeline", "sense_group_analysis"],
            )
            self.assertNotIn(str(media), completed.stdout)


class RichParserRedactionTests(unittest.TestCase):
    """Every malformed normalized result degrades with the typed code."""

    media = ROOT / "tests" / "fixtures" / "sample-media.wav"
    asr_fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
    alignment_fixture = ROOT / "tests" / "fixtures" / "alignment-result.json"
    sense_fixture = ROOT / "tests" / "fixtures" / "sense-group-result.json"
    acoustics_fixture = ROOT / "tests" / "fixtures" / "acoustics-result.json"
    prosody_fixture = ROOT / "tests" / "fixtures" / "prosody-result.json"

    def _parse(self, stage: str, document: object) -> None:
        from listen_gen.rich import (
            _parse_acoustics_result,
            _parse_prosody_result,
            _parse_sense_group_result,
        )
        if stage == "sense_groups":
            _parse_sense_group_result(document, stage)
        elif stage == "acoustics":
            _parse_acoustics_result(document, stage)
        else:
            _parse_prosody_result(document, stage)

    def test_non_object_roots_redact(self) -> None:
        for stage in ("sense_groups", "acoustics", "prosody"):
            for root in ([1, 2, 3], "string", 42, None):
                with self.subTest(stage=stage, root=root):
                    with self.assertRaises(RichStageFailure) as caught:
                        self._parse(stage, root)
                    self.assertEqual(caught.exception.code, f"{stage}_output_invalid")

    def test_non_object_items_redact(self) -> None:
        cases = {
            "sense_groups": {
                "schema": "listen_gen.sense-group-result.v1",
                "provider": {"id": "p", "version": "1"},
                "groups": [[1, 2], "x"],
            },
            "acoustics": {
                "schema": "listen_gen.acoustics-result.v1",
                "provider": {"id": "p", "version": "1"},
                "sample_rate_hz": 16000,
                "measurements": [3.14, None],
            },
            "prosody": {
                "schema": "listen_gen.prosody-result.v1",
                "provider": {"id": "p", "version": "1"},
                "uses_sense_groups": False,
                "anchors": ["nope"],
                "chunks": [],
            },
        }
        for stage, document in cases.items():
            with self.subTest(stage=stage):
                with self.assertRaises(RichStageFailure) as caught:
                    self._parse(stage, document)
                self.assertEqual(caught.exception.code, f"{stage}_output_invalid")

    def test_non_object_provider_and_nested_objects_redact(self) -> None:
        sense = json.loads(self.sense_fixture.read_text(encoding="utf-8"))
        for mutate in (
            lambda value: value.update(provider="not-an-object"),
            lambda value: value["provider"].update(id=5),
            lambda value: value["groups"].append({"sentence_index": 0}),
        ):
            document = json.loads(json.dumps(sense))
            mutate(document)
            with self.assertRaises(RichStageFailure) as caught:
                self._parse("sense_groups", document)
            self.assertEqual(caught.exception.code, "sense_groups_output_invalid")
        acoustics = json.loads(self.acoustics_fixture.read_text(encoding="utf-8"))
        for mutate in (
            lambda value: value["measurements"][0].update(energy="nested"),
            lambda value: value["measurements"][0]["pitch"].update(median_f0_hz="x"),
            lambda value: value.update(sample_rate_hz=16000.5),
        ):
            document = json.loads(json.dumps(acoustics))
            mutate(document)
            with self.assertRaises(RichStageFailure) as caught:
                self._parse("acoustics", document)
            self.assertEqual(caught.exception.code, "acoustics_output_invalid")

    def test_uses_sense_groups_requires_a_boolean(self) -> None:
        prosody = json.loads(self.prosody_fixture.read_text(encoding="utf-8"))
        for bad in (1, 0, "true", None, [], {}):
            document = json.loads(json.dumps(prosody))
            document["uses_sense_groups"] = bad
            with self.assertRaises(RichStageFailure) as caught:
                self._parse("prosody", document)
            self.assertEqual(caught.exception.code, "prosody_output_invalid")

    def test_malformed_fixture_degrades_without_internal_error(self) -> None:
        cases = [
            ("sense_groups", "sense-group-result.json", "[1, 2, 3]",
             "sense_groups_output_invalid", []),
            ("acoustics", "acoustics-result.json", '"not an object"',
             "acoustics_output_invalid", []),
            ("prosody", "prosody-result.json", "42",
             "prosody_output_invalid", [
                 "--sense-groups", "fixture",
                 "--sense-groups-fixture", str(self.sense_fixture),
                 "--acoustics", "fixture",
                 "--acoustics-fixture", str(self.acoustics_fixture),
             ]),
        ]
        for stage, name, raw, expected, upstream in cases:
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fixture = root / name
                fixture.write_text(raw, encoding="utf-8")
                flag = {
                    "sense_groups": ("--sense-groups", "--sense-groups-fixture"),
                    "acoustics": ("--acoustics", "--acoustics-fixture"),
                    "prosody": ("--prosody", "--prosody-fixture"),
                }[stage]
                output = root / "degraded.listenpkg"
                argv = [
                    "package", "from-media", str(self.media),
                    "--output", str(output),
                    "--provider", "fixture", "--fixture", str(self.asr_fixture),
                    "--aligner", "fixture",
                    "--alignment-fixture", str(self.alignment_fixture),
                    *upstream,
                    flag[0], "fixture", flag[1], str(fixture),
                    "--title", "Degraded", "--media-kind", "audio",
                    "--duration-ms", "2200", "--created-at-ms", "1786000000000",
                    "--machine-events",
                ]
                completed = run_cli(argv)
                self.assertEqual(completed.returncode, 0, completed.stderr)
                events = parse_events(completed.stdout)
                terminal = [e for e in events if e["event"] in TERMINAL_EVENTS][0]
                self.assertEqual(terminal["event"], "completed")
                warnings = terminal["rich_resources"][stage]["warnings"]
                self.assertEqual(warnings[0]["code"], expected)
                self.assertNotIn("internal_error", completed.stdout)
                self.assertNotIn("must be an object", completed.stdout)
                self.assertNotIn("not an object", completed.stdout)


if __name__ == "__main__":
    unittest.main()
