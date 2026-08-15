"""Built-in credential-free baseline producers for the rich stages (R4).

The fixture and command seams in :mod:`listen_gen.rich` are provider-neutral
but do not ship a producer: fixtures replay committed results and command
adapters run external tools. The three baselines in this module close that gap
with deterministic, in-process, credential-free adapters that sit behind the
exact same request / result boundaries and package operation:

* :class:`PunctuationSenseGroupBaseline` is a text-backed Sense Group producer.
  It fully partitions every emitted Subtitle token array using clause
  punctuation and a length limit, and records the exact rule evidence
  (``punctuation`` / ``length_limit`` / ``rule``) on every group.

* :class:`WavWordAcousticsBaseline` is an audio-backed Word Acoustics
  producer. It operates only on the normalized 16 kHz mono signed-16-bit PCM
  WAV, measures honest per-word RMS energy and duration with sentence-local
  baselines, leaves every pitch field and ``voiced_frame_ratio`` null because
  it does not measure them, validates audio coverage, and degrades with
  ``acoustics_failed`` when the audio is unreadable or does not cover the
  exact Word Timeline.

* :class:`AcousticProsodyBaseline` is an acoustic-rule Prosody producer. It
  consumes the exact Word Timeline plus the exact Word Acoustics and the
  optional Sense Group only as weak corroborating evidence; chunk boundaries
  are declared from actual timing/acoustic cues so semantic boundaries stay
  independent. Anchors are chosen conservatively (one nucleus per chunk), use
  only evidence actually present, and preserve ``unknown`` lexical stress.

None of these baselines run by default: the caller selects each one
explicitly with ``--sense-groups baseline``, ``--acoustics baseline``, or
``--prosody baseline``. They never contact a model, never execute a child
process, and carry stable provider and config identities so their output is
fully deterministic and reproducible.
"""

from __future__ import annotations

import hashlib
import json
import math
import struct
import sys
from array import array
from pathlib import Path
from typing import Any

from .rich import (
    RichStageFailure,
    AcousticMeasurement,
    AcousticsRequest,
    AcousticsResult,
    ProsodicChunk,
    ProsodyAnchor,
    ProsodyRequest,
    ProsodyResult,
    RichWord,
    SenseGroup,
    SenseGroupRequest,
    SenseGroupResult,
)

NORMALIZED_SAMPLE_RATE_HZ = 16000
NORMALIZED_CHANNELS = 1
NORMALIZED_SAMPLE_BITS = 16
NORMALIZED_SAMPLE_FORMAT = "pcm_s16le"

# ---------------------------------------------------------------------------
# Shared config identity
# ---------------------------------------------------------------------------


def _config_sha256(document: dict[str, Any]) -> str:
    """Canonical JSON config identity for one baseline adapter."""
    config_bytes = json.dumps(
        document,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return f"sha256:{hashlib.sha256(config_bytes).hexdigest()}"


def _fail(stage: str, code: str) -> RichStageFailure:
    return RichStageFailure(stage, code)


# ---------------------------------------------------------------------------
# Sense Group baseline
# ---------------------------------------------------------------------------

SENSE_GROUPS_CONFIG_SCHEMA = "listen_gen.sense-groups-baseline-config.v1"

# Clause punctuation that closes a sense group. The sentence-final mark is a
# clause boundary like any other, so the sentence-final group keeps
# ``punctuation`` evidence.
BREAK_PUNCTUATION = frozenset(
    {
        ",",
        ";",
        ":",
        "!",
        "?",
        ".",
        "\u2026",
        "\u2014",
        "(",
        ")",
        "[",
        "]",
        "{",
        "}",
        '"',
        "'",
        "\u201c",
        "\u201d",
        "\u2018",
        "\u2019",
        "\u00ab",
        "\u00bb",
        "\u2013",
    }
)
MAX_SENSE_GROUP_TOKENS = 8


def _sense_group_config() -> dict[str, Any]:
    return {
        "schema": SENSE_GROUPS_CONFIG_SCHEMA,
        "provider_id": "baseline-sense-groups",
        "rules": ["clause_punctuation", "length_limit", "sentence_boundary"],
        "break_punctuation": sorted(BREAK_PUNCTUATION),
        "max_group_tokens": MAX_SENSE_GROUP_TOKENS,
    }


class PunctuationSenseGroupBaseline:
    """Deterministic text-backed Sense Group producer.

    Every sentence token array is fully partitioned: a clause-punctuation
    token closes the current group (the punctuation token stays inside it),
    and a segment longer than :data:`MAX_SENSE_GROUP_TOKENS` is split by the
    length limit. The group that ends at the sentence boundary without an
    internal clause mark carries ``rule`` evidence. Each group records the
    rule that produced its boundary, so the evidence is exact and inspectable.
    """

    provider_id = "baseline-sense-groups"
    provider_version = "1"

    def __init__(self) -> None:
        self.config_sha256 = _config_sha256(_sense_group_config())

    def analyze(self, request: SenseGroupRequest) -> SenseGroupResult:
        groups: list[SenseGroup] = []
        for sentence in request.sentences:
            groups.extend(self._partition(sentence))
        return SenseGroupResult(
            groups=tuple(groups),
            provider_id=self.provider_id,
            provider_version=self.provider_version,
            config_sha256=self.config_sha256,
        )

    @staticmethod
    def _emit(
        groups: list[SenseGroup],
        sentence_index: int,
        tokens: Any,
        start: int,
        end: int,
        boundary_source: str,
    ) -> None:
        """Emit ``[start, end)`` split at most ``MAX_SENSE_GROUP_TOKENS``.

        Only the group that touches the ``end`` boundary carries the boundary
        source; earlier overlong pieces carry ``length_limit`` evidence.
        """
        cursor = start
        while True:
            remaining = end - cursor
            span_end = end if remaining <= MAX_SENSE_GROUP_TOKENS else cursor + MAX_SENSE_GROUP_TOKENS
            groups.append(
                SenseGroup(
                    sentence_index=sentence_index,
                    group_index=len(groups),
                    start_token_index=cursor,
                    end_token_index_exclusive=span_end,
                    confidence=1.0,
                    head_token_index=next(
                        (
                            token.index
                            for token in tokens[cursor:span_end]
                            if token.kind == "word"
                        ),
                        None,
                    ),
                    sources=(
                        (boundary_source,) if span_end == end else ("length_limit",)
                    ),
                )
            )
            if span_end == end:
                return
            cursor = span_end

    def _partition(self, sentence: Any) -> list[SenseGroup]:
        tokens = sentence.tokens
        groups: list[SenseGroup] = []
        segment_start = 0
        for index, token in enumerate(tokens):
            if token.kind == "punctuation" and token.text in BREAK_PUNCTUATION:
                self._emit(
                    groups,
                    sentence.index,
                    tokens,
                    segment_start,
                    index + 1,
                    "punctuation",
                )
                segment_start = index + 1
            elif index - segment_start + 1 > MAX_SENSE_GROUP_TOKENS:
                self._emit(
                    groups,
                    sentence.index,
                    tokens,
                    segment_start,
                    segment_start + MAX_SENSE_GROUP_TOKENS,
                    "length_limit",
                )
                segment_start += MAX_SENSE_GROUP_TOKENS
        if segment_start < len(tokens):
            self._emit(
                groups, sentence.index, tokens, segment_start, len(tokens), "rule"
            )
        return groups


# ---------------------------------------------------------------------------
# Word Acoustics baseline
# ---------------------------------------------------------------------------

ACOUSTICS_CONFIG_SCHEMA = "listen_gen.acoustics-baseline-config.v1"

# dBFS floor for a completely silent window: 16-bit PCM cannot resolve below
# one least-significant bit, so silence is reported as the 16-bit noise floor
# instead of an infinite ``-inf`` value.
RMS_DBFS_FLOOR = -96.0
# delta_db range (in dB) that maps linearly onto the ``[0, 1]`` prominence.
PROMINENCE_DELTA_DB_RANGE = 12.0


def _acoustics_config() -> dict[str, Any]:
    return {
        "schema": ACOUSTICS_CONFIG_SCHEMA,
        "provider_id": "baseline-acoustics",
        "input": {
            "container": "wav",
            "channels": NORMALIZED_CHANNELS,
            "sample_format": NORMALIZED_SAMPLE_FORMAT,
            "sample_rate_hz": NORMALIZED_SAMPLE_RATE_HZ,
        },
        "energy": {
            "baseline": "sentence_median_dbfs",
            "rms_dbfs_floor": RMS_DBFS_FLOOR,
            "prominence_mapping": "linear_delta_db",
            "prominence_delta_db_range": PROMINENCE_DELTA_DB_RANGE,
        },
        "duration": {"baseline": "sentence_median_ms"},
        "pitch": "not_measured",
        "voicing": "not_measured",
    }


class WavWordAcousticsBaseline:
    """Audio-backed Word Acoustics producer over the normalized WAV.

    Only a 16 kHz mono signed-16-bit PCM WAV is accepted; anything else
    (different container, format, channel count, or sample rate) degrades with
    ``acoustics_failed``. Each Word Timeline window is measured for RMS energy
    in dBFS (with the 16-bit noise floor) and its duration, then sentence-local
    baselines (the sentence median RMS and median duration) are computed from
    exactly those measurements. Pitch and voicing are never measured, so every
    pitch field and ``voiced_frame_ratio`` stay ``null`` honestly.
    """

    provider_id = "baseline-acoustics"
    provider_version = "1"

    def __init__(self) -> None:
        self.config_sha256 = _config_sha256(_acoustics_config())

    def measure(self, request: AcousticsRequest) -> AcousticsResult:
        try:
            sample_rate, samples = _read_normalized_wav(request.audio_path)
        except (OSError, ValueError) as error:
            raise _fail("acoustics", "failed") from error
        if sample_rate != NORMALIZED_SAMPLE_RATE_HZ:
            raise _fail("acoustics", "failed")
        # Validate audio coverage: every word window must start inside the
        # audio. A window whose end merely overruns the final boundary is
        # measured over the clamped window (audio edges are the norm for the
        # last word); a window that never touches the audio is a failure.
        if not request.words:
            raise _fail("acoustics", "failed")
        sample_count = len(samples)
        for word in request.words:
            if word.start_ms * NORMALIZED_SAMPLE_RATE_HZ // 1000 >= sample_count:
                raise _fail("acoustics", "failed")
        measurements = self._measure_words(request.words, samples)
        return AcousticsResult(
            sample_rate_hz=NORMALIZED_SAMPLE_RATE_HZ,
            measurements=tuple(measurements),
            provider_id=self.provider_id,
            provider_version=self.provider_version,
            config_sha256=self.config_sha256,
        )

    @staticmethod
    def _measure_words(
        words: tuple[RichWord, ...], samples: array
    ) -> list[AcousticMeasurement]:
        per_word: list[tuple[int, float, int]] = []
        for word in words:
            start_sample = word.start_ms * NORMALIZED_SAMPLE_RATE_HZ // 1000
            end_sample = word.end_ms * NORMALIZED_SAMPLE_RATE_HZ // 1000
            window = samples[start_sample:end_sample]
            rms = (
                math.sqrt(sum(sample * sample for sample in window) / len(window))
                if window
                else 0.0
            )
            rms_dbfs = _rms_dbfs(rms)
            duration_ms = word.end_ms - word.start_ms
            per_word.append((word.sentence_index, rms_dbfs, duration_ms))
        rms_by_sentence: dict[int, list[float]] = {}
        duration_by_sentence: dict[int, list[int]] = {}
        for sentence_index, rms_dbfs, duration_ms in per_word:
            rms_by_sentence.setdefault(sentence_index, []).append(rms_dbfs)
            duration_by_sentence.setdefault(sentence_index, []).append(duration_ms)
        baseline_by_sentence = {
            sentence_index: _median(values)
            for sentence_index, values in rms_by_sentence.items()
        }
        median_duration_by_sentence = {
            sentence_index: _median(duration_values)
            for sentence_index, duration_values in duration_by_sentence.items()
        }
        measurements: list[AcousticMeasurement] = []
        for word, (sentence_index, rms_dbfs, duration_ms) in zip(words, per_word):
            baseline = baseline_by_sentence[sentence_index]
            delta_db = rms_dbfs - baseline
            prominence = _clamp(0.5 + delta_db / PROMINENCE_DELTA_DB_RANGE, 0.0, 1.0)
            median_duration = median_duration_by_sentence[sentence_index]
            local_ratio = (
                duration_ms / median_duration if median_duration else 1.0
            )
            measurements.append(
                AcousticMeasurement(
                    sentence_index=word.sentence_index,
                    token_index=word.token_index,
                    energy={
                        "rms_dbfs": _round1(rms_dbfs),
                        "local_baseline_dbfs": _round1(baseline),
                        "delta_db": _round1(delta_db),
                        "prominence": _round3(prominence),
                    },
                    pitch={
                        "median_f0_hz": None,
                        "local_baseline_f0_hz": None,
                        "delta_semitones": None,
                        "range_semitones": None,
                        "prominence": None,
                        "reset_after": None,
                    },
                    duration={
                        "duration_ms": duration_ms,
                        "local_ratio": _round3(local_ratio),
                    },
                    voiced_frame_ratio=None,
                )
            )
        return measurements


def _rms_dbfs(rms: float) -> float:
    if rms <= 0.0:
        return RMS_DBFS_FLOOR
    dbfs = 20.0 * math.log10(rms / 32768.0)
    return RMS_DBFS_FLOOR if dbfs < RMS_DBFS_FLOOR else dbfs


def _clamp(value: float, low: float, high: float) -> float:
    return low if value < low else high if value > high else value


def _round1(value: float) -> float:
    return round(value, 1)


def _round3(value: float) -> float:
    return round(value, 3)


def _median(values: list) -> float:
    ordered = sorted(values)
    length = len(ordered)
    if length % 2 == 1:
        return float(ordered[length // 2])
    return (float(ordered[length // 2 - 1]) + float(ordered[length // 2])) / 2.0


def _read_normalized_wav(path: Path) -> tuple[int, array]:
    """Read and validate a 16 kHz mono s16le PCM WAV.

    Returns ``(sample_rate, samples)``. Raises ``ValueError`` for any file
    that is not a WAV with the exact normalized format.
    """
    with path.open("rb") as handle:
        data = handle.read()
    if len(data) < 12 or data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("audio is not a WAV file")
    fmt: tuple[int, int, int, int] | None = None
    samples_bytes: bytes | None = None
    offset = 12
    while offset + 8 <= len(data):
        chunk_id = data[offset : offset + 4]
        (chunk_size,) = struct.unpack_from("<I", data, offset + 4)
        chunk_start = offset + 8
        chunk_end = chunk_start + chunk_size
        if chunk_end > len(data):
            raise ValueError("WAV chunk is truncated")
        body = data[chunk_start:chunk_end]
        if chunk_id == b"fmt ":
            if len(body) < 16:
                raise ValueError("WAV fmt chunk is truncated")
            (
                audio_format,
                channels,
                sample_rate,
                _byte_rate,
                _block_align,
                bits_per_sample,
            ) = struct.unpack_from("<HHIIHH", body)
            fmt = (audio_format, channels, sample_rate, bits_per_sample)
        elif chunk_id == b"data":
            samples_bytes = body
        offset = chunk_start + chunk_size + (chunk_size & 1)
    if fmt is None or samples_bytes is None:
        raise ValueError("WAV is missing the fmt or data chunk")
    audio_format, channels, sample_rate, bits_per_sample = fmt
    if (
        audio_format != 1
        or channels != NORMALIZED_CHANNELS
        or sample_rate != NORMALIZED_SAMPLE_RATE_HZ
        or bits_per_sample != NORMALIZED_SAMPLE_BITS
    ):
        raise ValueError("audio is not normalized 16 kHz mono PCM")
    trimmed = samples_bytes[: len(samples_bytes) - len(samples_bytes) % 2]
    samples = array("h")
    samples.frombytes(trimmed)
    if sys.byteorder == "big":
        samples.byteswap()
    return sample_rate, samples


# ---------------------------------------------------------------------------
# Prosody baseline
# ---------------------------------------------------------------------------

PROSODY_CONFIG_SCHEMA = "listen_gen.prosody-baseline-config.v1"

# Timing/acoustic boundary cues. A pause at or above ``pause_ms`` is a strong
# boundary; a smaller but still substantial pause paired with a loud-to-quiet
# energy drop at or above ``energy_drop_db`` is a weak boundary. The weak cue
# deliberately requires a clear pause so ordinary word-to-word gaps never
# over-segment a sentence.
PROSODY_PAUSE_MS = 150
PROSODY_MIN_PAUSE_MS = 100
PROSODY_ENERGY_DROP_DB = 6.0
PROSODY_STRONG_CONFIDENCE = 0.8
PROSODY_WEAK_CONFIDENCE = 0.6
PROSODY_SENSE_GROUP_BOOST = 0.1
# Neutral realized prominence when a nucleus is chosen on duration evidence
# alone (energy was not present for that chunk).
PROSODY_DURATION_PROMINENCE = 0.5


def _prosody_config() -> dict[str, Any]:
    return {
        "schema": PROSODY_CONFIG_SCHEMA,
        "provider_id": "baseline-prosody",
        "boundaries": {
            "pause_ms": PROSODY_PAUSE_MS,
            "min_pause_ms": PROSODY_MIN_PAUSE_MS,
            "energy_drop_db": PROSODY_ENERGY_DROP_DB,
            "sources": ["pause", "energy_drop"],
        },
        "confidence": {
            "strong_boundary": PROSODY_STRONG_CONFIDENCE,
            "weak_boundary": PROSODY_WEAK_CONFIDENCE,
            "sense_group_weak_evidence_boost": PROSODY_SENSE_GROUP_BOOST,
        },
        "nucleus_selection": "max_energy_rms_dbfs_then_duration",
        "lexical_stress": "unknown",
        "semantic_boundaries": "independent",
        "uses_sense_groups": False,
    }


class AcousticProsodyBaseline:
    """Acoustic-rule Prosody producer over the exact Word Timeline + Acoustics.

    Chunk boundaries are declared from actual timing/acoustic cues only: a
    strong pause between consecutive Word Timeline windows, or a smaller pause
    combined with a loud-to-quiet RMS drop. The optional Sense Group is
    consumed only as weak corroborating evidence (a confidence boost when a
    chunk span coincides with a sense-group span); it never drives the
    boundary decisions, so semantic boundaries stay independent and
    ``uses_sense_groups`` is always ``false``.

    One nucleus anchor is emitted per chunk, chosen conservatively as the
    loudest measured word (falling back to the longest word only when no
    energy was measured in that chunk). Anchors use only evidence actually
    present (``energy`` or ``duration``), and lexical stress is preserved as
    ``unknown`` because it is never measured.
    """

    provider_id = "baseline-prosody"
    provider_version = "1"

    def __init__(self) -> None:
        self.config_sha256 = _config_sha256(_prosody_config())

    def analyze(self, request: ProsodyRequest) -> ProsodyResult:
        index_by_id = {sentence.id: sentence.index for sentence in request.sentences}
        sentence_by_index = {
            sentence.index: sentence for sentence in request.sentences
        }
        measurement_by_ref = {
            (
                index_by_id[measurement["word_ref"]["sentence_id"]],
                measurement["word_ref"]["token_index"],
            ): measurement
            for measurement in request.measurements
        }
        group_spans: set[tuple[int, int, int]] | None = None
        if request.groups is not None:
            group_spans = {
                (
                    index_by_id[group["sentence_id"]],
                    group["start_token_index"],
                    group["end_token_index_exclusive"],
                )
                for group in request.groups
            }
        words_by_sentence: dict[int, list[RichWord]] = {}
        for word in request.words:
            words_by_sentence.setdefault(word.sentence_index, []).append(word)
        anchors: list[ProsodyAnchor] = []
        chunks: list[ProsodicChunk] = []
        for sentence_index in sorted(sentence_by_index):
            sentence_words = words_by_sentence.get(sentence_index, [])
            for position, chunk in enumerate(
                self._chunk_spans(sentence_words, measurement_by_ref)
            ):
                start, end, strong = chunk
                confidence = (
                    PROSODY_STRONG_CONFIDENCE
                    if strong
                    else PROSODY_WEAK_CONFIDENCE
                )
                if group_spans is not None and (
                    sentence_index, start, end
                ) in group_spans:
                    confidence = min(
                        1.0, confidence + PROSODY_SENSE_GROUP_BOOST
                    )
                nucleus = self._choose_nucleus(
                    sentence_words, start, end, measurement_by_ref
                )
                chunks.append(
                    ProsodicChunk(
                        sentence_index=sentence_index,
                        chunk_index=position,
                        start_token_index=start,
                        end_token_index_exclusive=end,
                        confidence=_round3(confidence),
                        nucleus_token_index=(
                            nucleus[0].token_index if nucleus is not None else None
                        ),
                    )
                )
                if nucleus is not None:
                    word, cue, prominence = nucleus
                    anchors.append(
                        ProsodyAnchor(
                            sentence_index=sentence_index,
                            token_index=word.token_index,
                            lexical_stress="unknown",
                            realized_prominence=_round3(prominence),
                            utterance_role="nucleus",
                            evidence=(cue,),
                            confidence=_round3(prominence),
                        )
                    )
        return ProsodyResult(
            anchors=tuple(anchors),
            chunks=tuple(chunks),
            uses_sense_groups=False,
            provider_id=self.provider_id,
            provider_version=self.provider_version,
            config_sha256=self.config_sha256,
        )

    def _chunk_spans(
        self,
        words: list[RichWord],
        measurement_by_ref: dict[tuple[int, int], dict[str, Any]],
    ) -> list[tuple[int, int, bool]]:
        """Declare chunk spans from timing/acoustic cues.

        Returns ``(start_token_index, end_token_index_exclusive, strong)``
        chunks in token space: a chunk covers its first through last word
        tokens inclusive. ``strong`` records whether the chunk ends at a
        strong prosodic boundary (sentence-final or a strong pause).
        """
        if not words:
            return []
        boundaries = [0]
        for index in range(1, len(words)):
            pause = words[index].start_ms - words[index - 1].end_ms
            previous = measurement_by_ref.get(
                (words[index - 1].sentence_index, words[index - 1].token_index)
            )
            current = measurement_by_ref.get(
                (words[index].sentence_index, words[index].token_index)
            )
            energy_drop = None
            if previous is not None and current is not None:
                previous_rms = previous.get("energy", {}).get("rms_dbfs")
                current_rms = current.get("energy", {}).get("rms_dbfs")
                if previous_rms is not None and current_rms is not None:
                    energy_drop = previous_rms - current_rms
            if pause >= PROSODY_PAUSE_MS or (
                pause >= PROSODY_MIN_PAUSE_MS
                and energy_drop is not None
                and energy_drop >= PROSODY_ENERGY_DROP_DB
            ):
                boundaries.append(index)
        spans: list[tuple[int, int, bool]] = []
        for position, boundary in enumerate(boundaries):
            end = (
                boundaries[position + 1]
                if position + 1 < len(boundaries)
                else len(words)
            )
            chunk_words = words[boundary:end]
            start_token = chunk_words[0].token_index
            end_token = chunk_words[-1].token_index + 1
            strong = position == len(boundaries) - 1
            if not strong and end < len(words):
                gap = words[end].start_ms - words[end - 1].end_ms
                strong = gap >= PROSODY_PAUSE_MS
            spans.append((start_token, end_token, strong))
        return spans

    @staticmethod
    def _choose_nucleus(
        words: list[RichWord],
        start_token: int,
        end_token: int,
        measurement_by_ref: dict[tuple[int, int], dict[str, Any]],
    ) -> tuple[RichWord, str, float] | None:
        """Conservatively pick the nucleus word of one chunk span.

        Prefers the loudest word with measured energy; only when no word in
        the chunk has energy does it fall back to the longest duration. The
        cue that decided the choice is returned so the anchor can cite only
        evidence actually present.
        """
        chunk_words = [
            word
            for word in words
            if start_token <= word.token_index < end_token
        ]
        if not chunk_words:
            return None
        energy_candidates = []
        for word in chunk_words:
            measurement = measurement_by_ref.get(
                (word.sentence_index, word.token_index)
            )
            if measurement is None:
                continue
            energy = measurement.get("energy", {})
            rms = energy.get("rms_dbfs")
            if rms is not None:
                prominence = energy.get("prominence")
                if prominence is None:
                    delta = energy.get("delta_db")
                    prominence = (
                        _clamp(
                            0.5 + delta / PROMINENCE_DELTA_DB_RANGE, 0.0, 1.0
                        )
                        if delta is not None
                        else PROSODY_DURATION_PROMINENCE
                    )
                energy_candidates.append((word, float(rms), float(prominence)))
        if energy_candidates:
            nucleus = min(
                energy_candidates, key=lambda item: (-item[1], item[0].token_index)
            )
            return nucleus[0], "energy", nucleus[2]
        duration_candidates = []
        for word in chunk_words:
            measurement = measurement_by_ref.get(
                (word.sentence_index, word.token_index)
            )
            if measurement is None:
                continue
            duration_ms = measurement.get("duration", {}).get("duration_ms")
            if duration_ms is not None:
                duration_candidates.append((word, int(duration_ms)))
        if duration_candidates:
            nucleus = min(
                duration_candidates, key=lambda item: (-item[1], item[0].token_index)
            )
            return nucleus[0], "duration", PROSODY_DURATION_PROMINENCE
        return None
