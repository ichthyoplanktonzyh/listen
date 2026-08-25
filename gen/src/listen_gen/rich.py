"""Provider-neutral sense-group, word-acoustics, and prosody stages.

The three optional rich stages (R4) sit behind the same
media -> machine events -> deterministic ``.listenpkg`` interface as the ASR
and alignment stages, in strict dependency order:

* ``sense_group_analysis`` is derived from the exact Subtitle Text Track that
  was emitted into the package;
* ``word_acoustics`` is derived from the exact Word Timeline resource plus the
  normalized audio window that produced it;
* ``prosody_analysis`` is derived from the exact Word Timeline, the exact Word
  Acoustics resource, and optionally the exact Sense Group evidence, and
  declares explicit Prosodic Chunk token spans per the Core v1 schema.

Adapters in this module are provider-neutral over immutable request / result
boundaries:

* fixture adapters replay committed ``listen_gen.*-result.v1`` documents
  without any model or network;
* command adapters run an external tool as a direct argv subprocess with a
  stable normalized protocol and reuse :func:`listen_gen.process.run_argv` for
  bounded output, positive timeouts, and process-group reaping.

Degradable failures raise :class:`RichStageFailure`, a typed exception
carrying the stable machine-protocol warning code. Stage runners convert them
into a degraded outcome that preserves every already-qualified upstream
resource. Cancellation and media-change failures are never treated as
degradation.

Audio-backed Phone Timeline production is implemented separately in
:mod:`listen_gen.phone`. It follows these same process and degradation rules
and never derives observed phone evidence from text.
"""

from __future__ import annotations

import hashlib
import json
import re
import tempfile
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Callable, Protocol

from . import __version__ as TOOL_VERSION
from .command_identity import command_identity_sha256, compose_config_sha256
from .media import AudioPreprocessor
from .package import ConversionError
from .package_v3 import (
    PackageResource,
    blob_declaration,
    canonical_json,
    producer_declaration,
    provenance,
    quality,
    sha256_of_bytes,
)
from .process import ProcessOutputTooLarge, ProcessTimedOut, run_argv

SENSE_GROUP_RESULT_SCHEMA = "listen_gen.sense-group-result.v1"
ACOUSTICS_RESULT_SCHEMA = "listen_gen.acoustics-result.v1"
PROSODY_RESULT_SCHEMA = "listen_gen.prosody-result.v1"
ACOUSTIC_TRACK_RESULT_SCHEMA = "listen_gen.acoustic-track-result.v1"
SPEECH_ACTIVITY_RESULT_SCHEMA = "listen_gen.speech-activity-result.v1"
SENSE_GROUP_SCHEMA = "listen.payload.sense-group-analysis.v1"
ACOUSTICS_SCHEMA = "listen.payload.word-acoustics.v1"
PROSODY_SCHEMA = "listen.payload.prosody-analysis.v1"
# Frame-level acoustic evidence and speech/non-speech evidence are audio-only
# measurement resources. Core has no payload family for them yet, so they enter
# the package as opaque optional resources (never depended on by a required
# resource); their schema ids stay in the ``listen.payload.*`` namespace so a
# future Core payload family can adopt them without a rename.
ACOUSTIC_TRACK_SCHEMA = "listen.payload.acoustic-track.v1"
SPEECH_ACTIVITY_SCHEMA = "listen.payload.speech-activity.v1"
ACOUSTIC_TRACK_RESOURCE_KIND = "acoustic_track"
SPEECH_ACTIVITY_RESOURCE_KIND = "speech_activity"
ACOUSTICS_PIPELINE_CONFIG_SCHEMA = "listen_gen.acoustics-pipeline-config.v1"
RICH_STDOUT_LIMIT_BYTES = 16 * 1024 * 1024
NORMALIZED_SAMPLE_RATE_HZ = 16000

# Optional rich stages are provider-neutral: every failure preserves the
# already-qualified upstream resources and is reported as a stable typed
# warning code with a safe human message. Cancellation and media-change
# failures are never treated as degradation.
RICH_STAGE_TITLES: dict[str, str] = {
    "sense_groups": "Sense-group",
    "acoustics": "Acoustics",
    "prosody": "Prosody",
    "phone": "Phone",
    "acoustic_track": "Acoustic-track",
    "speech_activity": "Speech-activity",
}
RICH_WARNING_TAILS: dict[str, str] = {
    "start_failed": "provider could not be started",
    "timeout": "provider timed out",
    "failed": "provider failed",
    "output_invalid": "provider returned an invalid result",
    "output_too_large": "provider produced too much output",
    "qualification_failed": "result did not qualify",
    "upstream_missing": "required upstream resource was not produced",
}
RICH_WARNING_MESSAGES: dict[str, str] = {
    f"{stage}_{code}": (
        f"The {RICH_STAGE_TITLES[stage]} {tail}; "
        "already-qualified resources were preserved."
    )
    for stage in RICH_STAGE_TITLES
    for code, tail in RICH_WARNING_TAILS.items()
}


class RichStageFailure(ConversionError):
    """A degradable rich-stage failure carrying a stable typed warning code."""

    def __init__(self, stage: str, code: str):
        if stage not in RICH_STAGE_TITLES:
            raise ValueError(f"unknown rich stage: {stage!r}")
        if code not in RICH_WARNING_TAILS:
            raise ValueError(f"unknown rich warning code: {code!r}")
        self.stage = stage
        self.code = f"{stage}_{code}"
        super().__init__(RICH_WARNING_MESSAGES[self.code])


def rich_warning(error: BaseException, stage: str) -> tuple[str, str]:
    """Map a degradable rich-stage error to a stable typed warning."""
    if isinstance(error, RichStageFailure):
        return error.code, RICH_WARNING_MESSAGES[error.code]
    message = str(error).lower()
    if "timed out" in message:
        code = "timeout"
    elif "safety limit" in message:
        code = "output_too_large"
    elif "could not be started" in message:
        code = "start_failed"
    else:
        code = "failed"
    full = f"{stage}_{code}"
    return full, RICH_WARNING_MESSAGES[full]


@dataclass(frozen=True)
class AlignmentToken:
    index: int
    kind: str
    text: str
    normalized: str | None
    start_char: int
    end_char: int


@dataclass(frozen=True)
class AlignmentSentence:
    id: str
    index: int
    start_ms: int
    end_ms: int
    original_text: str
    display_text: str
    tokens: tuple[AlignmentToken, ...]


@dataclass(frozen=True)
class RichContext:
    """The v3 package context a rich stage derives into.

    ``anchor_resource_id`` names the Structured Reading resource the stage is
    anchored to; ``rendition_id`` names the media rendition the timing refers
    to. Every rich resource depends on the anchor resource and the stage
    inputs.
    """

    language: str
    subject: dict[str, object]
    anchor_resource_id: str
    rendition_id: str
    created_at_ms: int

SHA256_RE = re.compile(r"sha256:[0-9a-f]{64}")

# Closed vocabulary of Gen's normalized provider-result protocols. Core remains
# the package-schema authority; these sets validate provider I/O before Gen
# projects it into a package and are not a local schema copy.
NORMALIZED_SENSE_GROUP_SOURCES = frozenset(
    {
        "dependency_parse",
        "phrase_structure",
        "language_model",
        "punctuation",
        "length_limit",
        "rule",
        "user",
    }
)
NORMALIZED_LEXICAL_STRESS = frozenset({"primary", "secondary", "unstressed", "unknown"})
NORMALIZED_UTTERANCE_ROLES = frozenset(
    {"nucleus", "prenuclear", "postnuclear", "unmarked", "unknown"}
)
NORMALIZED_PROSODY_EVIDENCE = frozenset(
    {"energy", "pitch", "duration", "lexical_stress", "context"}
)


def _failure(stage: str, code: str) -> RichStageFailure:
    return RichStageFailure(stage, code)


def _parse_failure(stage: str, error: ValueError) -> RichStageFailure:
    """Convert a parser-internal ``ValueError`` to the redacted stage warning.

    Every malformed normalized result document degrades with the same
    stage-specific ``output_invalid`` code and never lets raw details escape.
    Failures already typed as :class:`RichStageFailure` are returned unchanged.
    """
    if isinstance(error, RichStageFailure):
        return error
    return _failure(stage, "output_invalid")


def _object(value: Any, location: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError(f"{location} must be an object")
    return value


def _number(value: Any, location: str, *, minimum: float | None = None) -> float:
    if (
        not isinstance(value, (int, float))
        or isinstance(value, bool)
        or (minimum is not None and value < minimum)
    ):
        raise ValueError(f"{location} must be a number >= {minimum}")
    number = float(value)
    if not _finite(number):
        raise ValueError(f"{location} must be finite")
    return number


def _confidence(value: Any, location: str) -> float | None:
    if value is None:
        return None
    number = _number(value, location, minimum=0.0)
    if number > 1.0:
        raise ValueError(f"{location} must be between zero and one")
    return number


def _nullable_number(value: Any, location: str, *, minimum: float | None = None) -> float | None:
    if value is None:
        return None
    return _number(value, location, minimum=minimum)


def _integer(value: Any, location: str, minimum: int = 0) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < minimum:
        raise ValueError(f"{location} must be an integer >= {minimum}")
    return value


def _positive_integer(value: Any, location: str) -> int:
    if not isinstance(value, int) or isinstance(value, bool) or value < 1:
        raise ValueError(f"{location} must be a positive integer")
    return value


def _enum(value: Any, allowed: frozenset[str], location: str, default: str | None = None) -> str:
    candidate = default if value is None else value
    if not isinstance(candidate, str) or candidate not in allowed:
        raise ValueError(f"{location} is unsupported")
    return candidate


def _finite(number: float) -> bool:
    return number == number and number not in (float("inf"), float("-inf"))


def _provider(value: Any, stage: str) -> tuple[str, str, str | None, str | None, str | None]:
    """Parse the provider/model/config provenance of a normalized result."""
    document = _object(value, "/")
    if not document:
        raise _failure(stage, "output_invalid")
    provider = _object(document.get("provider"), "/provider")
    provider_id = provider.get("id")
    provider_version = provider.get("version")
    if not all(
        isinstance(item, str) and item.strip()
        for item in (provider_id, provider_version)
    ):
        raise _failure(stage, "output_invalid")
    model = document.get("model")
    model_id = model_version = None
    if model is not None:
        model = _object(model, "/model")
        model_id, model_version = model.get("id"), model.get("version")
        if not all(
            isinstance(item, str) and item.strip()
            for item in (model_id, model_version)
        ):
            raise _failure(stage, "output_invalid")
    config_sha256 = document.get("config_sha256")
    if config_sha256 is not None and (
        not isinstance(config_sha256, str) or not SHA256_RE.fullmatch(config_sha256)
    ):
        raise _failure(stage, "output_invalid")
    return (
        str(provider_id),
        str(provider_version),
        str(model_id) if model_id is not None else None,
        str(model_version) if model_version is not None else None,
        config_sha256,
    )


# ---------------------------------------------------------------------------
# Immutable request / result types
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class SenseGroupRequest:
    """The exact emitted Subtitle Text Track tokenization."""

    language: str
    sentences: tuple[AlignmentSentence, ...]


@dataclass(frozen=True)
class SenseGroup:
    sentence_index: int
    group_index: int
    start_token_index: int
    end_token_index_exclusive: int
    confidence: float
    label: str | None = None
    head_token_index: int | None = None
    sources: tuple[str, ...] = ("rule",)


@dataclass(frozen=True)
class SenseGroupResult:
    groups: tuple[SenseGroup, ...]
    provider_id: str
    provider_version: str
    model_id: str | None = None
    model_version: str | None = None
    config_sha256: str | None = None


@dataclass(frozen=True)
class RichWord:
    """One exact word-timeline entry addressed by subtitle coordinates."""

    sentence_index: int
    token_index: int
    start_ms: int
    end_ms: int
    sentence_id: str = ""


@dataclass(frozen=True)
class AcousticsRequest:
    """The exact Word Timeline plus the normalized audio window."""

    language: str
    sentences: tuple[AlignmentSentence, ...]
    words: tuple[RichWord, ...]
    audio_path: Path


@dataclass(frozen=True)
class AcousticMeasurement:
    sentence_index: int
    token_index: int
    energy: dict[str, float | None]
    pitch: dict[str, float | None]
    duration: dict[str, float | None]
    voiced_frame_ratio: float | None


@dataclass(frozen=True)
class AcousticsResult:
    sample_rate_hz: int
    measurements: tuple[AcousticMeasurement, ...]
    provider_id: str
    provider_version: str
    model_id: str | None = None
    model_version: str | None = None
    config_sha256: str | None = None


@dataclass(frozen=True)
class AcousticTrackRequest:
    """The normalized audio window, addressed on its own timeline.

    Frame-level acoustic evidence is a fact about the audio rendition, not
    about any word. The request therefore carries only the normalized audio
    path — no words, no sentences, no sense groups — so the measurement stays
    decoupled from text segmentation and language-independent.
    """

    audio_path: Path


@dataclass(frozen=True)
class AcousticFrame:
    """One fixed-hop acoustic measurement at ``time_ms`` (absolute media time).

    Every field is a raw measurement, never an interpretation: ``energy_rel_db``
    and ``f0_rel_st`` are relative to the recording's own median so different
    recordings are comparable, but Gen never labels a frame prominent, an
    anchor, weak, or a boundary. ``f0_hz``/``f0_rel_st`` are ``None`` on an
    unvoiced frame; ``voiced`` is ``None`` when voicing was not measured (for
    example when no pitch tracker is available and only energy was extracted).
    """

    time_ms: int
    energy_dbfs: float
    energy_rel_db: float
    f0_hz: float | None
    f0_rel_st: float | None
    voiced: bool | None


@dataclass(frozen=True)
class AcousticTrackResult:
    sample_rate_hz: int
    frame_step_ms: int
    energy_baseline: str
    pitch_baseline: str
    frames: tuple[AcousticFrame, ...]
    provider_id: str
    provider_version: str
    model_id: str | None = None
    model_version: str | None = None
    config_sha256: str | None = None


@dataclass(frozen=True)
class SpeechActivityRequest:
    """The normalized audio window for speech/non-speech measurement.

    Like the acoustic track, this is an audio-only fact: it carries no words
    or sentences and never interprets a silence as a sentence, prosodic, or
    audible boundary. That interpretation is left to Core.
    """

    audio_path: Path


@dataclass(frozen=True)
class SpeechSpan:
    start_ms: int
    end_ms: int
    activity: str  # "speech" | "silence"


@dataclass(frozen=True)
class SpeechActivityResult:
    spans: tuple[SpeechSpan, ...]
    provider_id: str
    provider_version: str
    model_id: str | None = None
    model_version: str | None = None
    config_sha256: str | None = None


@dataclass(frozen=True)
class ProsodyRequest:
    """Exact Word Timeline, exact Word Acoustics, and optional Sense Groups.

    ``measurements`` and ``groups`` carry the exact resolved evidence produced
    by the earlier stages; sentence references use the emitted sentence ids so
    the provider can be given an exact image of the package.
    """

    language: str
    sentences: tuple[AlignmentSentence, ...]
    words: tuple[RichWord, ...]
    measurements: tuple[dict[str, Any], ...]
    groups: tuple[dict[str, Any], ...] | None


@dataclass(frozen=True)
class ProsodyAnchor:
    sentence_index: int
    token_index: int
    lexical_stress: str
    realized_prominence: float
    utterance_role: str
    evidence: tuple[str, ...]
    confidence: float
    syllable_index: int | None = None


@dataclass(frozen=True)
class ProsodicChunk:
    sentence_index: int
    chunk_index: int
    start_token_index: int
    end_token_index_exclusive: int
    confidence: float
    nucleus_token_index: int | None = None


@dataclass(frozen=True)
class ProsodyResult:
    anchors: tuple[ProsodyAnchor, ...]
    chunks: tuple[ProsodicChunk, ...]
    uses_sense_groups: bool
    provider_id: str
    provider_version: str
    model_id: str | None = None
    model_version: str | None = None
    config_sha256: str | None = None


class SenseGroupAnalyzer(Protocol):
    """Provider-neutral seam for expensive sense-group analysis."""

    def analyze(self, request: SenseGroupRequest) -> SenseGroupResult: ...


class AcousticsExtractor(Protocol):
    """Provider-neutral seam for expensive word-acoustic measurement."""

    def measure(self, request: AcousticsRequest) -> AcousticsResult: ...


class AcousticTrackExtractor(Protocol):
    """Provider-neutral seam for frame-level acoustic measurement."""

    def measure(self, request: AcousticTrackRequest) -> AcousticTrackResult: ...


class SpeechActivityDetector(Protocol):
    """Provider-neutral seam for speech/non-speech measurement."""

    def measure(self, request: SpeechActivityRequest) -> SpeechActivityResult: ...


class ProsodyAnalyzer(Protocol):
    """Provider-neutral seam for expensive prosody analysis."""

    def analyze(self, request: ProsodyRequest) -> ProsodyResult: ...


# ---------------------------------------------------------------------------
# Normalized result parsing
# ---------------------------------------------------------------------------


def _parse_sense_group_result(raw: Any, stage: str) -> SenseGroupResult:
    try:
        document = _object(raw, "/")
        if document.get("schema") != SENSE_GROUP_RESULT_SCHEMA:
            raise _failure(stage, "output_invalid")
        provider = _provider(document, stage)
        raw_groups = document.get("groups")
        if not isinstance(raw_groups, list) or not raw_groups:
            raise _failure(stage, "output_invalid")
        groups: list[SenseGroup] = []
        for index, raw_group in enumerate(raw_groups):
            location = f"/groups/{index}"
            group = _object(raw_group, location)
            start = _integer(group.get("start_token_index"), f"{location}/start_token_index")
            end = _positive_integer(
                group.get("end_token_index_exclusive"),
                f"{location}/end_token_index_exclusive",
            )
            confidence = _number(group.get("confidence"), f"{location}/confidence", minimum=0.0)
            if confidence > 1.0:
                raise ValueError(f"{location}/confidence must be between zero and one")
            sources_value = group.get("sources") or ()
            if not isinstance(sources_value, (list, tuple)) or not sources_value:
                raise ValueError(f"{location}/sources must be a non-empty array")
            sources = tuple(
                _enum(source, NORMALIZED_SENSE_GROUP_SOURCES, f"{location}/sources", None)
                for source in sources_value
            )
            head = group.get("head_token_index")
            if head is not None:
                head = _integer(head, f"{location}/head_token_index")
            label = group.get("label")
            if label is not None and not isinstance(label, str):
                raise ValueError(f"{location}/label must be a string or null")
            if end <= start:
                raise ValueError(f"{location} must be a non-empty half-open span")
            groups.append(
                SenseGroup(
                    sentence_index=_integer(
                        group.get("sentence_index"), f"{location}/sentence_index"
                    ),
                    group_index=_integer(
                        group.get("group_index"), f"{location}/group_index"
                    ),
                    start_token_index=start,
                    end_token_index_exclusive=end,
                    confidence=confidence,
                    label=label,
                    head_token_index=head,
                    sources=sources,
                )
            )
        return SenseGroupResult(
            tuple(groups), provider[0], provider[1], provider[2], provider[3], provider[4]
        )
    except ValueError as error:
        raise _parse_failure(stage, error) from error


def _parse_acoustics_result(raw: Any, stage: str) -> AcousticsResult:
    try:
        document = _object(raw, "/")
        if document.get("schema") != ACOUSTICS_RESULT_SCHEMA:
            raise _failure(stage, "output_invalid")
        provider = _provider(document, stage)
        sample_rate_hz = _positive_integer(
            document.get("sample_rate_hz"), "/sample_rate_hz"
        )
        raw_measurements = document.get("measurements")
        if not isinstance(raw_measurements, list) or not raw_measurements:
            raise _failure(stage, "output_invalid")
        measurements: list[AcousticMeasurement] = []
        for index, raw_measurement in enumerate(raw_measurements):
            location = f"/measurements/{index}"
            measurement = _object(raw_measurement, location)
            energy = _object(measurement.get("energy"), f"{location}/energy")
            pitch = _object(measurement.get("pitch"), f"{location}/pitch")
            duration = _object(measurement.get("duration"), f"{location}/duration")
            voiced = _confidence(
                measurement.get("voiced_frame_ratio"),
                f"{location}/voiced_frame_ratio",
            )
            energy_value = {
                "rms_dbfs": _nullable_number(energy.get("rms_dbfs"), f"{location}/energy/rms_dbfs"),
                "local_baseline_dbfs": _nullable_number(
                    energy.get("local_baseline_dbfs"), f"{location}/energy/local_baseline_dbfs"
                ),
                "delta_db": _nullable_number(energy.get("delta_db"), f"{location}/energy/delta_db"),
                "prominence": _confidence(
                    energy.get("prominence"), f"{location}/energy/prominence"
                ),
            }
            median_f0 = _nullable_number(
                pitch.get("median_f0_hz"), f"{location}/pitch/median_f0_hz", minimum=0.0
            )
            baseline_f0 = _nullable_number(
                pitch.get("local_baseline_f0_hz"),
                f"{location}/pitch/local_baseline_f0_hz",
                minimum=0.0,
            )
            if median_f0 == 0.0 or baseline_f0 == 0.0:
                raise ValueError("pitch baselines must be positive when present")
            local_ratio = _nullable_number(
                duration.get("local_ratio"), f"{location}/duration/local_ratio", minimum=0.0
            )
            if local_ratio == 0.0:
                raise ValueError("duration local ratio must be positive when present")
            duration_ms = _positive_integer(
                duration.get("duration_ms"), f"{location}/duration/duration_ms"
            )
            pitch_value = {
                "median_f0_hz": median_f0,
                "local_baseline_f0_hz": baseline_f0,
                "delta_semitones": _nullable_number(
                    pitch.get("delta_semitones"), f"{location}/pitch/delta_semitones"
                ),
                "range_semitones": _nullable_number(
                    pitch.get("range_semitones"),
                    f"{location}/pitch/range_semitones",
                    minimum=0.0,
                ),
                "prominence": _confidence(
                    pitch.get("prominence"), f"{location}/pitch/prominence"
                ),
                "reset_after": _confidence(
                    pitch.get("reset_after"), f"{location}/pitch/reset_after"
                ),
            }
            duration_value = {"duration_ms": duration_ms, "local_ratio": local_ratio}
            measurements.append(
                AcousticMeasurement(
                    sentence_index=_integer(
                        measurement.get("sentence_index"), f"{location}/sentence_index"
                    ),
                    token_index=_integer(
                        measurement.get("token_index"), f"{location}/token_index"
                    ),
                    energy=energy_value,
                    pitch=pitch_value,
                    duration=duration_value,
                    voiced_frame_ratio=voiced,
                )
            )
        return AcousticsResult(
            sample_rate_hz,
            tuple(measurements),
            provider[0], provider[1], provider[2], provider[3], provider[4],
        )
    except ValueError as error:
        raise _parse_failure(stage, error) from error


def _parse_prosody_result(raw: Any, stage: str) -> ProsodyResult:
    try:
        document = _object(raw, "/")
        if document.get("schema") != PROSODY_RESULT_SCHEMA:
            raise _failure(stage, "output_invalid")
        provider = _provider(document, stage)
        uses_sense_groups = document.get("uses_sense_groups")
        if not isinstance(uses_sense_groups, bool):
            raise _failure(stage, "output_invalid")
        raw_anchors = document.get("anchors")
        if not isinstance(raw_anchors, list) or not raw_anchors:
            raise _failure(stage, "output_invalid")
        anchors: list[ProsodyAnchor] = []
        for index, raw_anchor in enumerate(raw_anchors):
            location = f"/anchors/{index}"
            anchor = _object(raw_anchor, location)
            evidence_value = anchor.get("evidence") or ()
            if not isinstance(evidence_value, (list, tuple)) or not evidence_value:
                raise ValueError(f"{location}/evidence must be a non-empty array")
            if len(set(evidence_value)) != len(evidence_value):
                raise ValueError(f"{location}/evidence must be unique")
            evidence = tuple(
                _enum(item, NORMALIZED_PROSODY_EVIDENCE, f"{location}/evidence", None)
                for item in evidence_value
            )
            syllable_index = anchor.get("syllable_index")
            if syllable_index is not None:
                syllable_index = _integer(
                    syllable_index, f"{location}/syllable_index"
                )
            anchors.append(
                ProsodyAnchor(
                    sentence_index=_integer(
                        anchor.get("sentence_index"), f"{location}/sentence_index"
                    ),
                    token_index=_integer(
                        anchor.get("token_index"), f"{location}/token_index"
                    ),
                    lexical_stress=_enum(
                        anchor.get("lexical_stress"), NORMALIZED_LEXICAL_STRESS, f"{location}/lexical_stress"
                    ),
                    realized_prominence=_number(
                        anchor.get("realized_prominence"),
                        f"{location}/realized_prominence",
                        minimum=0.0,
                    ),
                    utterance_role=_enum(
                        anchor.get("utterance_role"), NORMALIZED_UTTERANCE_ROLES, f"{location}/utterance_role"
                    ),
                    evidence=evidence,
                    confidence=_number(
                        anchor.get("confidence"), f"{location}/confidence", minimum=0.0
                    ),
                    syllable_index=syllable_index,
                )
            )
        for anchor in anchors:
            if anchor.realized_prominence > 1.0 or anchor.confidence > 1.0:
                raise _failure(stage, "output_invalid")
        raw_chunks = document.get("chunks")
        if not isinstance(raw_chunks, list) or not raw_chunks:
            raise _failure(stage, "output_invalid")
        chunks: list[ProsodicChunk] = []
        for index, raw_chunk in enumerate(raw_chunks):
            location = f"/chunks/{index}"
            chunk = _object(raw_chunk, location)
            start = _integer(chunk.get("start_token_index"), f"{location}/start_token_index")
            end = _positive_integer(
                chunk.get("end_token_index_exclusive"), f"{location}/end_token_index_exclusive"
            )
            if end <= start:
                raise ValueError(f"{location} must be a non-empty half-open span")
            confidence = _number(chunk.get("confidence"), f"{location}/confidence", minimum=0.0)
            if confidence > 1.0:
                raise ValueError(f"{location}/confidence must be between zero and one")
            nucleus = chunk.get("nucleus_token_index")
            if nucleus is not None:
                nucleus = _integer(nucleus, f"{location}/nucleus_token_index")
            chunks.append(
                ProsodicChunk(
                    sentence_index=_integer(
                        chunk.get("sentence_index"), f"{location}/sentence_index"
                    ),
                    chunk_index=_integer(chunk.get("chunk_index"), f"{location}/chunk_index"),
                    start_token_index=start,
                    end_token_index_exclusive=end,
                    confidence=confidence,
                    nucleus_token_index=nucleus,
                )
            )
        return ProsodyResult(
            tuple(anchors),
            tuple(chunks),
            uses_sense_groups,
            provider[0], provider[1], provider[2], provider[3], provider[4],
        )
    except ValueError as error:
        raise _parse_failure(stage, error) from error


def _parse_acoustic_track_result(raw: Any, stage: str) -> AcousticTrackResult:
    try:
        document = _object(raw, "/")
        if document.get("schema") != ACOUSTIC_TRACK_RESULT_SCHEMA:
            raise _failure(stage, "output_invalid")
        provider = _provider(document, stage)
        sample_rate_hz = _positive_integer(
            document.get("sample_rate_hz"), "/sample_rate_hz"
        )
        frame_step_ms = _positive_integer(
            document.get("frame_step_ms"), "/frame_step_ms"
        )
        energy_baseline = document.get("energy_baseline")
        pitch_baseline = document.get("pitch_baseline")
        if not isinstance(energy_baseline, str) or not energy_baseline.strip():
            raise ValueError("/energy_baseline must be a non-empty string")
        if not isinstance(pitch_baseline, str) or not pitch_baseline.strip():
            raise ValueError("/pitch_baseline must be a non-empty string")
        raw_frames = document.get("frames")
        if not isinstance(raw_frames, list) or not raw_frames:
            raise _failure(stage, "output_invalid")
        frames: list[AcousticFrame] = []
        previous_time: int | None = None
        for index, raw_frame in enumerate(raw_frames):
            location = f"/frames/{index}"
            frame = _object(raw_frame, location)
            time_ms = _integer(frame.get("time_ms"), f"{location}/time_ms")
            if previous_time is not None and time_ms <= previous_time:
                raise ValueError(f"{location}/time_ms must strictly increase")
            previous_time = time_ms
            energy_dbfs = _number(frame.get("energy_dbfs"), f"{location}/energy_dbfs")
            energy_rel_db = _number(
                frame.get("energy_rel_db"), f"{location}/energy_rel_db"
            )
            f0_hz = _nullable_number(
                frame.get("f0_hz"), f"{location}/f0_hz", minimum=0.0
            )
            if f0_hz == 0.0:
                raise ValueError(f"{location}/f0_hz must be positive when present")
            f0_rel_st = _nullable_number(frame.get("f0_rel_st"), f"{location}/f0_rel_st")
            # An unvoiced frame carries no pitch: never fabricate a relative
            # semitone value where no F0 was measured.
            if f0_hz is None and f0_rel_st is not None:
                raise ValueError(
                    f"{location}/f0_rel_st must be null when f0_hz is null"
                )
            voiced = frame.get("voiced")
            if voiced is not None and not isinstance(voiced, bool):
                raise ValueError(f"{location}/voiced must be a boolean or null")
            frames.append(
                AcousticFrame(
                    time_ms=time_ms,
                    energy_dbfs=energy_dbfs,
                    energy_rel_db=energy_rel_db,
                    f0_hz=f0_hz,
                    f0_rel_st=f0_rel_st,
                    voiced=voiced,
                )
            )
        return AcousticTrackResult(
            sample_rate_hz=sample_rate_hz,
            frame_step_ms=frame_step_ms,
            energy_baseline=energy_baseline,
            pitch_baseline=pitch_baseline,
            frames=tuple(frames),
            provider_id=provider[0],
            provider_version=provider[1],
            model_id=provider[2],
            model_version=provider[3],
            config_sha256=provider[4],
        )
    except ValueError as error:
        raise _parse_failure(stage, error) from error


def _parse_speech_activity_result(raw: Any, stage: str) -> SpeechActivityResult:
    try:
        document = _object(raw, "/")
        if document.get("schema") != SPEECH_ACTIVITY_RESULT_SCHEMA:
            raise _failure(stage, "output_invalid")
        provider = _provider(document, stage)
        raw_spans = document.get("spans")
        if not isinstance(raw_spans, list) or not raw_spans:
            raise _failure(stage, "output_invalid")
        spans: list[SpeechSpan] = []
        previous_end: int | None = None
        for index, raw_span in enumerate(raw_spans):
            location = f"/spans/{index}"
            span = _object(raw_span, location)
            start_ms = _integer(span.get("start_ms"), f"{location}/start_ms")
            end_ms = _positive_integer(span.get("end_ms"), f"{location}/end_ms")
            if end_ms <= start_ms:
                raise ValueError(f"{location} must be a non-empty half-open span")
            if previous_end is not None and start_ms < previous_end:
                raise ValueError(f"{location} spans must not overlap")
            previous_end = end_ms
            activity = _enum(
                span.get("activity"),
                frozenset({"speech", "silence"}),
                f"{location}/activity",
            )
            spans.append(SpeechSpan(start_ms=start_ms, end_ms=end_ms, activity=activity))
        return SpeechActivityResult(
            spans=tuple(spans),
            provider_id=provider[0],
            provider_version=provider[1],
            model_id=provider[2],
            model_version=provider[3],
            config_sha256=provider[4],
        )
    except ValueError as error:
        raise _parse_failure(stage, error) from error


# ---------------------------------------------------------------------------
# Adapters
# ---------------------------------------------------------------------------


class FixtureSenseGroupAdapter:
    """Offline sense-group adapter that replays a committed result fixture."""

    def __init__(self, fixture_path: Path):
        if not isinstance(fixture_path, Path) or not fixture_path.is_file():
            raise ConversionError("sense group fixture must be a regular file")
        self.fixture_path = fixture_path

    def analyze(self, request: SenseGroupRequest) -> SenseGroupResult:
        try:
            raw = json.loads(self.fixture_path.read_text(encoding="utf-8"))
        except OSError as error:
            raise _failure("sense_groups", "failed") from error
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("sense_groups", "output_invalid") from error
        return _parse_sense_group_result(raw, "sense_groups")


class FixtureAcousticsAdapter:
    """Offline word-acoustics adapter that replays a committed result fixture."""

    def __init__(self, fixture_path: Path):
        if not isinstance(fixture_path, Path) or not fixture_path.is_file():
            raise ConversionError("acoustics fixture must be a regular file")
        self.fixture_path = fixture_path

    def measure(self, request: AcousticsRequest) -> AcousticsResult:
        try:
            raw = json.loads(self.fixture_path.read_text(encoding="utf-8"))
        except OSError as error:
            raise _failure("acoustics", "failed") from error
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("acoustics", "output_invalid") from error
        return _parse_acoustics_result(raw, "acoustics")


class FixtureProsodyAdapter:
    """Offline prosody adapter that replays a committed result fixture."""

    def __init__(self, fixture_path: Path):
        if not isinstance(fixture_path, Path) or not fixture_path.is_file():
            raise ConversionError("prosody fixture must be a regular file")
        self.fixture_path = fixture_path

    def analyze(self, request: ProsodyRequest) -> ProsodyResult:
        try:
            raw = json.loads(self.fixture_path.read_text(encoding="utf-8"))
        except OSError as error:
            raise _failure("prosody", "failed") from error
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("prosody", "output_invalid") from error
        return _parse_prosody_result(raw, "prosody")


class FixtureAcousticTrackAdapter:
    """Offline acoustic-track adapter that replays a committed result fixture."""

    def __init__(self, fixture_path: Path):
        if not isinstance(fixture_path, Path) or not fixture_path.is_file():
            raise ConversionError("acoustic track fixture must be a regular file")
        self.fixture_path = fixture_path

    def measure(self, request: AcousticTrackRequest) -> AcousticTrackResult:
        try:
            raw = json.loads(self.fixture_path.read_text(encoding="utf-8"))
        except OSError as error:
            raise _failure("acoustic_track", "failed") from error
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("acoustic_track", "output_invalid") from error
        return _parse_acoustic_track_result(raw, "acoustic_track")


class FixtureSpeechActivityAdapter:
    """Offline speech-activity adapter that replays a committed result fixture."""

    def __init__(self, fixture_path: Path):
        if not isinstance(fixture_path, Path) or not fixture_path.is_file():
            raise ConversionError("speech activity fixture must be a regular file")
        self.fixture_path = fixture_path

    def measure(self, request: SpeechActivityRequest) -> SpeechActivityResult:
        try:
            raw = json.loads(self.fixture_path.read_text(encoding="utf-8"))
        except OSError as error:
            raise _failure("speech_activity", "failed") from error
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("speech_activity", "output_invalid") from error
        return _parse_speech_activity_result(raw, "speech_activity")


def _subtitle_input_document(request: SenseGroupRequest) -> bytes:
    """Serialize the exact emitted Subtitle Text Track payload."""
    document = {
        "schema": SENSE_GROUP_INPUT_SCHEMA,
        "language": request.language,
        "sentences": [
            {
                "id": sentence.id,
                "index": sentence.index,
                "start_ms": sentence.start_ms,
                "end_ms": sentence.end_ms,
                "original_text": sentence.original_text,
                "display_text": sentence.display_text,
                "tokens": [
                    {
                        "index": token.index,
                        "kind": token.kind,
                        "text": token.text,
                        "normalized": token.normalized,
                        "start_char": token.start_char,
                        "end_char": token.end_char,
                    }
                    for token in sentence.tokens
                ],
            }
            for sentence in request.sentences
        ],
    }
    return (
        json.dumps(
            document,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


def _acoustics_input_document(request: AcousticsRequest) -> bytes:
    """Serialize the exact Word Timeline payload for the acoustics extractor."""
    document = {
        "schema": ACOUSTICS_INPUT_SCHEMA,
        "language": request.language,
        "sample_rate_hz": NORMALIZED_SAMPLE_RATE_HZ,
        "words": [
            {
                "sentence_index": word.sentence_index,
                "token_index": word.token_index,
                "start_ms": word.start_ms,
                "end_ms": word.end_ms,
            }
            for word in request.words
        ],
    }
    return (
        json.dumps(
            document,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


def _prosody_input_document(request: ProsodyRequest) -> bytes:
    """Serialize the exact Word Timeline, Acoustics, and Sense Group payload."""
    index_by_id = {sentence.id: sentence.index for sentence in request.sentences}
    document = {
        "schema": PROSODY_INPUT_SCHEMA,
        "language": request.language,
        "sentences": [
            {
                "index": sentence.index,
                "start_ms": sentence.start_ms,
                "end_ms": sentence.end_ms,
                "original_text": sentence.original_text,
                "tokens": [
                    {
                        "index": token.index,
                        "kind": token.kind,
                        "text": token.text,
                        "normalized": token.normalized,
                        "start_char": token.start_char,
                        "end_char": token.end_char,
                    }
                    for token in sentence.tokens
                ],
            }
            for sentence in request.sentences
        ],
        "words": [
            {
                "sentence_index": word.sentence_index,
                "token_index": word.token_index,
                "start_ms": word.start_ms,
                "end_ms": word.end_ms,
            }
            for word in request.words
        ],
        "measurements": [
            {
                "sentence_index": index_by_id[measurement["word_ref"]["sentence_id"]],
                "token_index": measurement["word_ref"]["token_index"],
                "energy": measurement["energy"],
                "pitch": measurement["pitch"],
                "duration": measurement["duration"],
                "voiced_frame_ratio": measurement["voiced_frame_ratio"],
            }
            for measurement in request.measurements
        ],
        "groups": (
            [
                {
                    "sentence_index": index_by_id[group["sentence_id"]],
                    "group_index": group["group_index"],
                    "start_token_index": group["start_token_index"],
                    "end_token_index_exclusive": group["end_token_index_exclusive"],
                    "confidence": group["confidence"],
                    "label": group.get("label"),
                    "head_token_index": group.get("head_token_index"),
                    "sources": group["sources"],
                }
                for group in request.groups
            ]
            if request.groups is not None
            else []
        ),
    }
    return (
        json.dumps(
            document,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n"
    ).encode("utf-8")


def _run_result_command(
    argv: list[str],
    timeout_seconds: float,
    stage: str,
) -> bytes:
    """Run one rich-stage command with the shared process-safety rules."""
    try:
        completed = run_argv(
            argv,
            timeout_seconds=timeout_seconds,
            stdout_limit_bytes=RICH_STDOUT_LIMIT_BYTES,
        )
    except ProcessTimedOut as error:
        raise _failure(stage, "timeout") from error
    except ProcessOutputTooLarge as error:
        raise _failure(stage, "output_too_large") from error
    except OSError as error:
        raise _failure(stage, "start_failed") from error
    if completed.returncode != 0:
        raise _failure(stage, "failed")
    return completed.stdout


def _run_bound_result_command(
    *, executable: str, arguments: tuple[str, ...], argv: list[str],
    placeholders: frozenset[str], timeout_seconds: float, stage: str,
) -> tuple[bytes, str]:
    """Run a command and bind its observed bytes/config into provenance."""
    try:
        before = command_identity_sha256(
            executable, arguments, placeholders, timeout_seconds
        )
    except OSError as error:
        raise _failure(stage, "start_failed") from error
    stdout = _run_result_command(argv, timeout_seconds, stage)
    try:
        after = command_identity_sha256(
            executable, arguments, placeholders, timeout_seconds
        )
    except OSError as error:
        raise _failure(stage, "failed") from error
    if after != before:
        raise _failure(stage, "failed")
    return stdout, before


class CommandSenseGroupAdapter:
    """Run an external sense-group analyzer as an argv-only subprocess.

    The analyzer receives the exact emitted subtitle payload at the exact
    ``{input}`` placeholder and must write one
    ``listen_gen.sense-group-result.v1`` document to stdout.
    """

    def __init__(
        self,
        executable: str,
        arguments: list[str],
        timeout_seconds: float,
        *,
        progress: Callable[[str], None] | None = None,
    ):
        if not executable:
            raise ConversionError("sense group command executable must be non-empty")
        if arguments.count("{input}") != 1:
            raise ConversionError(
                "sense group command arguments must contain exactly one "
                "{input} placeholder"
            )
        if timeout_seconds <= 0:
            raise ConversionError("sense group command timeout must be positive")
        self.executable = executable
        self.arguments = tuple(arguments)
        self.timeout_seconds = timeout_seconds
        self.progress = progress

    def analyze(self, request: SenseGroupRequest) -> SenseGroupResult:
        with tempfile.TemporaryDirectory(prefix="listen-gen-sense-groups-") as directory:
            input_path = Path(directory) / "subtitle-input.json"
            try:
                input_path.write_bytes(_subtitle_input_document(request))
            except OSError as error:
                raise _failure("sense_groups", "failed") from error
            argv = [
                self.executable,
                *(
                    str(input_path)
                    if argument == "{input}"
                    else argument
                    for argument in self.arguments
                ),
            ]
            stdout, command_identity = _run_bound_result_command(
                executable=self.executable,
                arguments=self.arguments,
                argv=argv,
                placeholders=frozenset({"{input}"}),
                timeout_seconds=self.timeout_seconds,
                stage="sense_groups",
            )
        try:
            raw = json.loads(stdout)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("sense_groups", "output_invalid") from error
        result = _parse_sense_group_result(raw, "sense_groups")
        return replace(
            result,
            config_sha256=compose_config_sha256(
                result.config_sha256, command_identity
            ),
        )


class CommandAcousticsAdapter:
    """Run an external acoustics extractor as an argv-only subprocess.

    The extractor receives the normalized WAV at the exact ``{media}``
    placeholder and the exact Word Timeline payload at the exact
    ``{timeline}`` placeholder, and must write one
    ``listen_gen.acoustics-result.v1`` document to stdout.
    """

    def __init__(
        self,
        executable: str,
        arguments: list[str],
        timeout_seconds: float,
        *,
        progress: Callable[[str], None] | None = None,
    ):
        if not executable:
            raise ConversionError("acoustics command executable must be non-empty")
        if arguments.count("{media}") != 1 or arguments.count("{timeline}") != 1:
            raise ConversionError(
                "acoustics command arguments must contain exactly one "
                "{media} and one {timeline} placeholder"
            )
        if timeout_seconds <= 0:
            raise ConversionError("acoustics command timeout must be positive")
        self.executable = executable
        self.arguments = tuple(arguments)
        self.timeout_seconds = timeout_seconds
        self.progress = progress

    def measure(self, request: AcousticsRequest) -> AcousticsResult:
        if not request.audio_path.is_file():
            raise ConversionError("media input is not a regular file")
        with tempfile.TemporaryDirectory(prefix="listen-gen-acoustics-") as directory:
            timeline_path = Path(directory) / "acoustics-input.json"
            try:
                timeline_path.write_bytes(_acoustics_input_document(request))
            except OSError as error:
                raise _failure("acoustics", "failed") from error
            argv = [
                self.executable,
                *(
                    str(request.audio_path)
                    if argument == "{media}"
                    else (
                        str(timeline_path)
                        if argument == "{timeline}"
                        else argument
                    )
                    for argument in self.arguments
                ),
            ]
            stdout, command_identity = _run_bound_result_command(
                executable=self.executable,
                arguments=self.arguments,
                argv=argv,
                placeholders=frozenset({"{media}", "{timeline}"}),
                timeout_seconds=self.timeout_seconds,
                stage="acoustics",
            )
        try:
            raw = json.loads(stdout)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("acoustics", "output_invalid") from error
        result = _parse_acoustics_result(raw, "acoustics")
        return replace(
            result,
            config_sha256=compose_config_sha256(
                result.config_sha256, command_identity
            ),
        )


class CommandProsodyAdapter:
    """Run an external prosody analyzer as an argv-only subprocess.

    The analyzer receives the exact Word Timeline, Word Acoustics, and optional
    Sense Group payload at the exact ``{input}`` placeholder and must write one
    ``listen_gen.prosody-result.v1`` document to stdout.
    """

    def __init__(
        self,
        executable: str,
        arguments: list[str],
        timeout_seconds: float,
        *,
        progress: Callable[[str], None] | None = None,
    ):
        if not executable:
            raise ConversionError("prosody command executable must be non-empty")
        if arguments.count("{input}") != 1:
            raise ConversionError(
                "prosody command arguments must contain exactly one "
                "{input} placeholder"
            )
        if timeout_seconds <= 0:
            raise ConversionError("prosody command timeout must be positive")
        self.executable = executable
        self.arguments = tuple(arguments)
        self.timeout_seconds = timeout_seconds
        self.progress = progress

    def analyze(self, request: ProsodyRequest) -> ProsodyResult:
        with tempfile.TemporaryDirectory(prefix="listen-gen-prosody-") as directory:
            input_path = Path(directory) / "prosody-input.json"
            try:
                input_path.write_bytes(_prosody_input_document(request))
            except OSError as error:
                raise _failure("prosody", "failed") from error
            argv = [
                self.executable,
                *(
                    str(input_path)
                    if argument == "{input}"
                    else argument
                    for argument in self.arguments
                ),
            ]
            stdout, command_identity = _run_bound_result_command(
                executable=self.executable,
                arguments=self.arguments,
                argv=argv,
                placeholders=frozenset({"{input}"}),
                timeout_seconds=self.timeout_seconds,
                stage="prosody",
            )
        try:
            raw = json.loads(stdout)
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("prosody", "output_invalid") from error
        result = _parse_prosody_result(raw, "prosody")
        return replace(
            result,
            config_sha256=compose_config_sha256(
                result.config_sha256, command_identity
            ),
        )


# ---------------------------------------------------------------------------
# Qualification and resource construction
# ---------------------------------------------------------------------------


def _sentence_lookup(sentences: tuple[AlignmentSentence, ...]) -> dict[int, AlignmentSentence]:
    return {sentence.index: sentence for sentence in sentences}


def _qualify_sense_groups(
    result: SenseGroupResult, sentences: tuple[AlignmentSentence, ...]
) -> tuple[dict[str, Any], ...]:
    """Resolve groups onto exact subtitle sentences as a full ordered partition.

    For every sentence the groups must form a contiguous, non-overlapping,
    complete partition of the token array starting at zero; ``group_index``
    must be contiguous from zero; the head (when present) must lie inside the
    span; every source must be a typed v1 source; and confidences must be in
    ``[0, 1]``. These rules mirror the Core v1 inspector plus the partition
    closure that keeps the analysis deterministic.
    """
    if not result.groups:
        raise _failure("sense_groups", "qualification_failed")
    lookup = _sentence_lookup(sentences)
    by_sentence: dict[int, list[SenseGroup]] = {}
    for group in result.groups:
        if group.sentence_index not in lookup:
            raise _failure("sense_groups", "qualification_failed")
        by_sentence.setdefault(group.sentence_index, []).append(group)
    if set(by_sentence) != set(lookup):
        raise _failure("sense_groups", "qualification_failed")
    resolved: list[dict[str, Any]] = []
    for sentence_index in sorted(lookup):
        sentence = lookup[sentence_index]
        groups = by_sentence[sentence_index]
        if groups[0].group_index != 0 or groups[0].start_token_index != 0:
            raise _failure("sense_groups", "qualification_failed")
        previous_end = 0
        for position, group in enumerate(groups):
            token_count = len(sentence.tokens)
            if (
                group.group_index != position
                or group.start_token_index != previous_end
                or group.end_token_index_exclusive > token_count
            ):
                raise _failure("sense_groups", "qualification_failed")
            if group.head_token_index is not None and not (
                group.start_token_index
                <= group.head_token_index
                < group.end_token_index_exclusive
            ):
                raise _failure("sense_groups", "qualification_failed")
            resolved.append(
                {
                    "sentence_id": sentence.id,
                    "group_index": group.group_index,
                    "start_token_index": group.start_token_index,
                    "end_token_index_exclusive": group.end_token_index_exclusive,
                    "label": group.label,
                    "head_token_index": group.head_token_index,
                    "confidence": group.confidence,
                    "sources": list(group.sources),
                }
            )
            previous_end = group.end_token_index_exclusive
        if previous_end != len(sentence.tokens):
            raise _failure("sense_groups", "qualification_failed")
    return tuple(resolved)


def _qualify_acoustics(
    result: AcousticsResult,
    words: tuple[RichWord, ...],
    sentences: tuple[AlignmentSentence, ...],
) -> tuple[dict[str, Any], ...]:
    """Resolve measurements onto exact Word Timeline entries.

    The measurements must exactly cover the word timeline: every word appears
    exactly once, in presentation order, with no extras, and the measured
    duration cannot exceed the exact word timing span. The scalar rules mirror
    the Core v1 inspector.
    """
    if not words or not result.measurements:
        raise _failure("acoustics", "qualification_failed")
    lookup = _sentence_lookup(sentences)
    word_refs = [(word.sentence_index, word.token_index) for word in words]
    expected_order = list(word_refs)
    measured_order = [
        (measurement.sentence_index, measurement.token_index)
        for measurement in result.measurements
    ]
    if measured_order != expected_order:
        raise _failure("acoustics", "qualification_failed")
    duration_by_ref = {(word.sentence_index, word.token_index): word for word in words}
    resolved: list[dict[str, Any]] = []
    for measurement in result.measurements:
        word = duration_by_ref[(measurement.sentence_index, measurement.token_index)]
        sentence = lookup[measurement.sentence_index]
        duration_ms = measurement.duration["duration_ms"]
        assert isinstance(duration_ms, int)
        if duration_ms > word.end_ms - word.start_ms:
            raise _failure("acoustics", "qualification_failed")
        if not any(
            token.index == measurement.token_index and token.kind == "word"
            for token in sentence.tokens
        ):
            raise _failure("acoustics", "qualification_failed")
        resolved.append(
            {
                "word_ref": {
                    "sentence_id": sentence.id,
                    "token_index": measurement.token_index,
                },
                "energy": measurement.energy,
                "pitch": measurement.pitch,
                "duration": measurement.duration,
                "voiced_frame_ratio": measurement.voiced_frame_ratio,
            }
        )
    return tuple(resolved)


def _qualify_acoustic_track(
    result: AcousticTrackResult,
) -> tuple[dict[str, Any], ...]:
    """Resolve frame-level measurements onto the emitted payload shape.

    Frame times must be absolute media milliseconds that strictly increase and
    fall on the declared fixed hop. No word or sentence coordinate is involved:
    the acoustic track is a fact about the audio rendition alone.
    """
    if not result.frames:
        raise _failure("acoustic_track", "qualification_failed")
    resolved: list[dict[str, Any]] = []
    previous_time: int | None = None
    for frame in result.frames:
        if frame.time_ms < 0:
            raise _failure("acoustic_track", "qualification_failed")
        if previous_time is not None:
            if frame.time_ms <= previous_time:
                raise _failure("acoustic_track", "qualification_failed")
            if frame.time_ms - previous_time != result.frame_step_ms:
                raise _failure("acoustic_track", "qualification_failed")
        previous_time = frame.time_ms
        if frame.f0_hz is None and frame.f0_rel_st is not None:
            raise _failure("acoustic_track", "qualification_failed")
        resolved.append(
            {
                "time_ms": frame.time_ms,
                "energy_dbfs": frame.energy_dbfs,
                "energy_rel_db": frame.energy_rel_db,
                "f0_hz": frame.f0_hz,
                "f0_rel_st": frame.f0_rel_st,
                "voiced": frame.voiced,
            }
        )
    return tuple(resolved)


def _qualify_speech_activity(
    result: SpeechActivityResult,
) -> tuple[dict[str, Any], ...]:
    """Resolve speech/non-speech spans onto the emitted payload shape.

    Spans are absolute-media-time half-open windows that are ordered and never
    overlap. Gen states only measured speech/silence: it never relabels a
    silence as any kind of boundary.
    """
    if not result.spans:
        raise _failure("speech_activity", "qualification_failed")
    resolved: list[dict[str, Any]] = []
    previous_end: int | None = None
    for span in result.spans:
        if span.start_ms < 0 or span.end_ms <= span.start_ms:
            raise _failure("speech_activity", "qualification_failed")
        if previous_end is not None and span.start_ms < previous_end:
            raise _failure("speech_activity", "qualification_failed")
        if span.activity not in ("speech", "silence"):
            raise _failure("speech_activity", "qualification_failed")
        previous_end = span.end_ms
        resolved.append(
            {
                "start_ms": span.start_ms,
                "end_ms": span.end_ms,
                "activity": span.activity,
            }
        )
    return tuple(resolved)


def _qualify_prosody(
    result: ProsodyResult,
    words: tuple[RichWord, ...],
    measurements: tuple[dict[str, Any], ...],
    sentences: tuple[AlignmentSentence, ...],
    groups: tuple[dict[str, Any], ...] | None,
) -> tuple[tuple[dict[str, Any], ...], tuple[dict[str, Any], ...]]:
    """Resolve anchors and Prosodic Chunk token spans onto exact references.

    Every anchor must reference a word that exists in the exact Word Timeline
    and has an exact Word Acoustics measurement; evidence must be non-empty
    and unique; chunks must be non-empty, ordered, non-overlapping spans within
    their sentence with a nucleus inside the span. When the provider declares
    it used exact Sense Group evidence, the chunk spans must exactly equal the
    sense-group spans of the produced Sense Group Analysis resource.
    """
    if not result.anchors or not result.chunks:
        raise _failure("prosody", "qualification_failed")
    lookup = _sentence_lookup(sentences)
    word_refs = {(word.sentence_index, word.token_index) for word in words}
    index_by_id = {sentence.id: sentence.index for sentence in sentences}
    measured_refs = {
        (index_by_id[measurement["word_ref"]["sentence_id"]], measurement["word_ref"]["token_index"])
        for measurement in measurements
    }
    for anchor in result.anchors:
        if anchor.sentence_index not in lookup:
            raise _failure("prosody", "qualification_failed")
        reference = (anchor.sentence_index, anchor.token_index)
        if reference not in word_refs or reference not in measured_refs:
            raise _failure("prosody", "qualification_failed")
    chunks_by_sentence: dict[int, list[ProsodicChunk]] = {}
    for chunk in result.chunks:
        if chunk.sentence_index not in lookup:
            raise _failure("prosody", "qualification_failed")
        chunks_by_sentence.setdefault(chunk.sentence_index, []).append(chunk)
    resolved_chunks: list[dict[str, Any]] = []
    for sentence_index in sorted(chunks_by_sentence):
        sentence = lookup[sentence_index]
        chunks = chunks_by_sentence[sentence_index]
        if chunks[0].chunk_index != 0:
            raise _failure("prosody", "qualification_failed")
        previous_end = 0
        for position, chunk in enumerate(chunks):
            token_count = len(sentence.tokens)
            if (
                chunk.chunk_index != position
                or chunk.start_token_index < previous_end
                or chunk.end_token_index_exclusive > token_count
            ):
                raise _failure("prosody", "qualification_failed")
            if chunk.nucleus_token_index is not None and not (
                chunk.start_token_index
                <= chunk.nucleus_token_index
                < chunk.end_token_index_exclusive
            ):
                raise _failure("prosody", "qualification_failed")
            resolved_chunks.append(
                {
                    "sentence_id": sentence.id,
                    "chunk_index": chunk.chunk_index,
                    "start_token_index": chunk.start_token_index,
                    "end_token_index_exclusive": chunk.end_token_index_exclusive,
                    "nucleus_token_index": chunk.nucleus_token_index,
                    "confidence": chunk.confidence,
                }
            )
            previous_end = chunk.end_token_index_exclusive
    if result.uses_sense_groups:
        if groups is None:
            raise _failure("prosody", "upstream_missing")
        group_spans = [
            (group["sentence_id"], group["start_token_index"], group["end_token_index_exclusive"])
            for group in groups
        ]
        chunk_spans = [
            (chunk["sentence_id"], chunk["start_token_index"], chunk["end_token_index_exclusive"])
            for chunk in resolved_chunks
        ]
        if chunk_spans != group_spans:
            raise _failure("prosody", "qualification_failed")
    resolved_anchors = [
        {
            "word_ref": {
                "sentence_id": lookup[anchor.sentence_index].id,
                "token_index": anchor.token_index,
            },
            "lexical_stress": anchor.lexical_stress,
            "realized_prominence": anchor.realized_prominence,
            "utterance_role": anchor.utterance_role,
            "evidence": list(anchor.evidence),
            "confidence": anchor.confidence,
            **(
                {"syllable_index": anchor.syllable_index}
                if anchor.syllable_index is not None
                else {}
            ),
        }
        for anchor in result.anchors
    ]
    return tuple(resolved_anchors), tuple(resolved_chunks)


def _compose_audio_pipeline_config_sha256(
    provider_config_sha256: str | None,
    audio_stream_index: int,
    adapter_protocol: str,
) -> str:
    """Bind an audio-stage config identity to the normalization choices."""
    pipeline_config = {
        "schema": ACOUSTICS_PIPELINE_CONFIG_SCHEMA,
        "adapter_protocol": adapter_protocol,
        "audio_preprocessing": {
            "audio_stream_index": audio_stream_index,
            "channels": 1,
            "container": "wav",
            "sample_format": "pcm_s16le",
            "sample_rate_hz": NORMALIZED_SAMPLE_RATE_HZ,
        },
        "provider_config_sha256": provider_config_sha256,
    }
    config_bytes = json.dumps(
        pipeline_config,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return f"sha256:{hashlib.sha256(config_bytes).hexdigest()}"


def _compose_acoustics_config_sha256(
    provider_config_sha256: str | None, audio_stream_index: int
) -> str:
    """Bind the acoustics config identity to the normalization choices."""
    return _compose_audio_pipeline_config_sha256(
        provider_config_sha256, audio_stream_index, ACOUSTICS_RESULT_SCHEMA
    )


def _rich_resource(
    *,
    kind: str,
    schema: str,
    context: RichContext,
    dependencies: tuple[str, ...],
    payload: dict[str, object],
    provider_id: str,
    provider_version: str,
    model_id: str | None,
    model_version: str | None,
    config_sha256: str | None,
    subject: dict[str, object] | None = None,
) -> tuple[PackageResource, bytes]:
    """Build one v3 rich resource: canonical payload, declared provenance.

    ``subject`` defaults to the shared reading-anchored context subject; an
    audio-only resource passes a rendition-only subject so it does not claim to
    be *about* the reading it never depended on.
    """
    provider = {"id": provider_id, "version": provider_version}
    model = None
    if model_id is not None:
        model = {"id": model_id, "version": model_version}
    payload_bytes = canonical_json(payload)
    resource = PackageResource(
        kind=kind,
        schema=schema,
        role="base",
        content_language=context.language,
        payload_blob=blob_declaration(
            sha256_of_bytes(payload_bytes), len(payload_bytes), True
        ),
        subject=context.subject if subject is None else subject,
        dependencies=dependencies,
        provenance=provenance(
            context.created_at_ms,
            input_rendition_ids=[context.rendition_id],
            input_resource_ids=list(dependencies),
            provider=provider,
            model=model,
            config_sha256=config_sha256,
        ),
        quality=quality(),
        required=False,
    )
    return resource, payload_bytes


def _sense_group_resource(
    *,
    context: RichContext,
    dependencies: tuple[str, ...],
    result: SenseGroupResult,
    groups: tuple[dict[str, Any], ...],
) -> tuple[PackageResource, bytes]:
    return _rich_resource(
        kind="sense_group_analysis",
        schema=SENSE_GROUP_SCHEMA,
        context=context,
        dependencies=dependencies,
        payload={"groups": list(groups)},
        provider_id=result.provider_id,
        provider_version=result.provider_version,
        model_id=result.model_id,
        model_version=result.model_version,
        config_sha256=result.config_sha256,
    )


def _acoustics_resource(
    *,
    context: RichContext,
    dependencies: tuple[str, ...],
    result: AcousticsResult,
    measurements: tuple[dict[str, Any], ...],
    config_sha256: str | None,
) -> tuple[PackageResource, bytes]:
    return _rich_resource(
        kind="word_acoustics",
        schema=ACOUSTICS_SCHEMA,
        context=context,
        dependencies=dependencies,
        payload={
            "sample_rate_hz": result.sample_rate_hz,
            "energy_baseline": "sentence_median_dbfs",
            "pitch_baseline": "sentence_median_f0_hz",
            "measurements": list(measurements),
        },
        provider_id=result.provider_id,
        provider_version=result.provider_version,
        model_id=result.model_id,
        model_version=result.model_version,
        config_sha256=config_sha256,
    )


def _prosody_resource(
    *,
    context: RichContext,
    dependencies: tuple[str, ...],
    result: ProsodyResult,
    anchors: tuple[dict[str, Any], ...],
    chunks: tuple[dict[str, Any], ...],
) -> tuple[PackageResource, bytes]:
    return _rich_resource(
        kind="prosody_analysis",
        schema=PROSODY_SCHEMA,
        context=context,
        dependencies=dependencies,
        payload={"chunks": list(chunks), "anchors": list(anchors)},
        provider_id=result.provider_id,
        provider_version=result.provider_version,
        model_id=result.model_id,
        model_version=result.model_version,
        config_sha256=result.config_sha256,
    )


def _audio_only_subject(context: RichContext) -> dict[str, object]:
    """A subject that names only the audio rendition, not the reading anchor.

    Frame-level and speech-activity evidence are facts about the audio alone,
    so they are ``about`` the rendition and nothing text-derived.
    """
    return {"rendition_ids": [context.rendition_id], "anchor_resource_ids": []}


def _acoustic_track_resource(
    *,
    context: RichContext,
    result: AcousticTrackResult,
    frames: tuple[dict[str, Any], ...],
    config_sha256: str | None,
) -> tuple[PackageResource, bytes]:
    # Audio-only evidence: no word timeline or subtitle dependency. The rendition
    # is named through provenance ``input_rendition_ids`` (via ``_rich_resource``);
    # the empty resource dependency keeps the track decoupled from text.
    return _rich_resource(
        kind=ACOUSTIC_TRACK_RESOURCE_KIND,
        schema=ACOUSTIC_TRACK_SCHEMA,
        context=context,
        dependencies=(),
        subject=_audio_only_subject(context),
        payload={
            "sample_rate_hz": result.sample_rate_hz,
            "frame_step_ms": result.frame_step_ms,
            "energy_baseline": result.energy_baseline,
            "pitch_baseline": result.pitch_baseline,
            "frames": list(frames),
        },
        provider_id=result.provider_id,
        provider_version=result.provider_version,
        model_id=result.model_id,
        model_version=result.model_version,
        config_sha256=config_sha256,
    )


def _speech_activity_resource(
    *,
    context: RichContext,
    result: SpeechActivityResult,
    spans: tuple[dict[str, Any], ...],
    config_sha256: str | None,
) -> tuple[PackageResource, bytes]:
    return _rich_resource(
        kind=SPEECH_ACTIVITY_RESOURCE_KIND,
        schema=SPEECH_ACTIVITY_SCHEMA,
        context=context,
        dependencies=(),
        subject=_audio_only_subject(context),
        payload={"spans": list(spans)},
        provider_id=result.provider_id,
        provider_version=result.provider_version,
        model_id=result.model_id,
        model_version=result.model_version,
        config_sha256=config_sha256,
    )


# ---------------------------------------------------------------------------
# Pipeline stage runners
# ---------------------------------------------------------------------------


def run_sense_groups(
    *,
    analyzer: SenseGroupAnalyzer,
    context: RichContext,
    sentences: tuple[AlignmentSentence, ...],
    dependencies: tuple[str, ...],
    progress: Callable[[str], None] | None = None,
) -> tuple[
    str, PackageResource | None, bytes | None, list[dict[str, str]], tuple[dict[str, Any], ...]
]:
    """Run the optional sense-group stage and convert failures into degradation.

    Returns ``(status, resource, payload_bytes, typed_warnings, resolved_groups)``
    where status is ``"produced"`` or ``"degraded"``. Degradable failures
    preserve the upstream resources; cancellation is never swallowed.
    """
    if progress is not None:
        progress("analyzing_sense_groups")
    try:
        request = SenseGroupRequest(language=context.language, sentences=sentences)
        result = analyzer.analyze(request)
        groups = _qualify_sense_groups(result, sentences)
        resource, payload_bytes = _sense_group_resource(
            context=context,
            dependencies=dependencies,
            result=result,
            groups=groups,
        )
        return "produced", resource, payload_bytes, [], groups
    except RichStageFailure as error:
        return "degraded", None, None, [{"code": error.code, "message": str(error)}], ()
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        code, message = rich_warning(error, "sense_groups")
        return "degraded", None, None, [{"code": code, "message": message}], ()


def run_acoustics(
    *,
    extractor: AcousticsExtractor,
    preprocessor: AudioPreprocessor | None,
    media_path: Path,
    audio_stream_index: int | None,
    context: RichContext,
    sentences: tuple[AlignmentSentence, ...],
    words: tuple[RichWord, ...],
    dependencies: tuple[str, ...],
    progress: Callable[[str], None] | None = None,
) -> tuple[
    str, PackageResource | None, bytes | None, list[dict[str, str]], tuple[dict[str, Any], ...]
]:
    """Run the optional word-acoustics stage and convert failures into degradation.

    The extractor receives the normalized 16 kHz mono PCM WAV when a media
    preprocessor is configured (the fixture adapter ignores it and replays
    committed measurements). Returns ``(status, resource, typed_warnings,
    resolved_measurements)``.
    """
    if progress is not None:
        progress("measuring_acoustics")
    try:
        if preprocessor is not None:
            with preprocessor.prepare(
                media_path, audio_stream_index=audio_stream_index
            ) as prepared:
                request = AcousticsRequest(
                    language=context.language,
                    sentences=sentences,
                    words=words,
                    audio_path=prepared.path,
                )
                result = extractor.measure(request)
            stream_index = prepared.stream_index
        else:
            request = AcousticsRequest(
                language=context.language,
                sentences=sentences,
                words=words,
                audio_path=media_path,
            )
            result = extractor.measure(request)
            stream_index = None
        measurements = _qualify_acoustics(result, words, sentences)
        config_sha256 = result.config_sha256
        if stream_index is not None:
            config_sha256 = _compose_acoustics_config_sha256(
                result.config_sha256, stream_index
            )
        resource, payload_bytes = _acoustics_resource(
            context=context,
            dependencies=dependencies,
            result=result,
            measurements=measurements,
            config_sha256=config_sha256,
        )
        return "produced", resource, payload_bytes, [], measurements
    except RichStageFailure as error:
        return "degraded", None, None, [{"code": error.code, "message": str(error)}], ()
    except (ConversionError, OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        code, message = rich_warning(error, "acoustics")
        return "degraded", None, None, [{"code": code, "message": message}], ()


def run_acoustic_track(
    *,
    extractor: AcousticTrackExtractor,
    preprocessor: AudioPreprocessor | None,
    media_path: Path,
    audio_stream_index: int | None,
    context: RichContext,
    progress: Callable[[str], None] | None = None,
) -> tuple[str, PackageResource | None, bytes | None, list[dict[str, str]]]:
    """Run the optional frame-level acoustic-track stage.

    The extractor receives the normalized 16 kHz mono PCM WAV when a media
    preprocessor is configured (the fixture adapter ignores it and replays a
    committed track). The track is audio-only: it never receives the word
    timeline or the sentences, so the measurement stays decoupled from text.
    Returns ``(status, resource, payload_bytes, typed_warnings)``.
    """
    if progress is not None:
        progress("measuring_acoustic_track")
    try:
        if preprocessor is not None:
            with preprocessor.prepare(
                media_path, audio_stream_index=audio_stream_index
            ) as prepared:
                result = extractor.measure(AcousticTrackRequest(audio_path=prepared.path))
            stream_index = prepared.stream_index
        else:
            result = extractor.measure(AcousticTrackRequest(audio_path=media_path))
            stream_index = None
        frames = _qualify_acoustic_track(result)
        config_sha256 = result.config_sha256
        if stream_index is not None:
            config_sha256 = _compose_audio_pipeline_config_sha256(
                result.config_sha256, stream_index, ACOUSTIC_TRACK_RESULT_SCHEMA
            )
        resource, payload_bytes = _acoustic_track_resource(
            context=context,
            result=result,
            frames=frames,
            config_sha256=config_sha256,
        )
        return "produced", resource, payload_bytes, []
    except RichStageFailure as error:
        return "degraded", None, None, [{"code": error.code, "message": str(error)}]
    except (ConversionError, OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        code, message = rich_warning(error, "acoustic_track")
        return "degraded", None, None, [{"code": code, "message": message}]


def run_speech_activity(
    *,
    detector: SpeechActivityDetector,
    preprocessor: AudioPreprocessor | None,
    media_path: Path,
    audio_stream_index: int | None,
    context: RichContext,
    progress: Callable[[str], None] | None = None,
) -> tuple[str, PackageResource | None, bytes | None, list[dict[str, str]]]:
    """Run the optional speech/non-speech stage.

    Like the acoustic track, this is audio-only measurement evidence: it
    reports where speech and silence are in the recording and never interprets
    a silence as a boundary. Returns
    ``(status, resource, payload_bytes, typed_warnings)``.
    """
    if progress is not None:
        progress("measuring_speech_activity")
    try:
        if preprocessor is not None:
            with preprocessor.prepare(
                media_path, audio_stream_index=audio_stream_index
            ) as prepared:
                result = detector.measure(SpeechActivityRequest(audio_path=prepared.path))
            stream_index = prepared.stream_index
        else:
            result = detector.measure(SpeechActivityRequest(audio_path=media_path))
            stream_index = None
        spans = _qualify_speech_activity(result)
        config_sha256 = result.config_sha256
        if stream_index is not None:
            config_sha256 = _compose_audio_pipeline_config_sha256(
                result.config_sha256, stream_index, SPEECH_ACTIVITY_RESULT_SCHEMA
            )
        resource, payload_bytes = _speech_activity_resource(
            context=context,
            result=result,
            spans=spans,
            config_sha256=config_sha256,
        )
        return "produced", resource, payload_bytes, []
    except RichStageFailure as error:
        return "degraded", None, None, [{"code": error.code, "message": str(error)}]
    except (ConversionError, OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        code, message = rich_warning(error, "speech_activity")
        return "degraded", None, None, [{"code": code, "message": message}]


def run_prosody(
    *,
    analyzer: ProsodyAnalyzer,
    context: RichContext,
    sentences: tuple[AlignmentSentence, ...],
    words: tuple[RichWord, ...],
    measurements: tuple[dict[str, Any], ...],
    groups: tuple[dict[str, Any], ...] | None,
    dependencies: tuple[str, ...],
    progress: Callable[[str], None] | None = None,
) -> tuple[str, PackageResource | None, bytes | None, list[dict[str, str]]]:
    """Run the optional prosody stage and convert failures into degradation.

    The prosody request carries the exact Word Timeline, the exact Word
    Acoustics measurements, and the exact Sense Group evidence when the
    sense-group stage produced a resource. Returns
    ``(status, resource, typed_warnings)``.
    """
    if progress is not None:
        progress("analyzing_prosody")
    try:
        request = ProsodyRequest(
            language=context.language,
            sentences=sentences,
            words=words,
            measurements=measurements,
            groups=groups,
        )
        result = analyzer.analyze(request)
        anchors, chunks = _qualify_prosody(
            result, words, measurements, sentences, groups
        )
        resource, payload_bytes = _prosody_resource(
            context=context,
            dependencies=dependencies,
            result=result,
            anchors=anchors,
            chunks=chunks,
        )
        return "produced", resource, payload_bytes, []
    except RichStageFailure as error:
        return "degraded", None, None, [{"code": error.code, "message": str(error)}]
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        code, message = rich_warning(error, "prosody")
        return "degraded", None, None, [{"code": code, "message": message}]
