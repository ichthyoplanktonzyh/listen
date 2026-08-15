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

from listen_gen.rich import AlignmentSentence, AlignmentToken
from listen_gen.rich import RichStageFailure
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

