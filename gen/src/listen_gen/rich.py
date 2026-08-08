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
from .alignment import AlignmentSentence
from .command_identity import command_identity_sha256, compose_config_sha256
from .media import AudioPreprocessor
from .package import ConversionError, ResourceFile, _envelope
from .process import ProcessOutputTooLarge, ProcessTimedOut, run_argv
from .protocol import RichStageFailure, rich_warning

SENSE_GROUP_RESULT_SCHEMA = "listen_gen.sense-group-result.v1"
ACOUSTICS_RESULT_SCHEMA = "listen_gen.acoustics-result.v1"
PROSODY_RESULT_SCHEMA = "listen_gen.prosody-result.v1"
SENSE_GROUP_INPUT_SCHEMA = "listen_gen.subtitle-input.v1"
ACOUSTICS_INPUT_SCHEMA = "listen_gen.acoustics-input.v1"
PROSODY_INPUT_SCHEMA = "listen_gen.prosody-input.v1"
ACOUSTICS_PIPELINE_CONFIG_SCHEMA = "listen_gen.acoustics-pipeline-config.v1"
RICH_STDOUT_LIMIT_BYTES = 16 * 1024 * 1024
NORMALIZED_SAMPLE_RATE_HZ = 16000

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


def _compose_acoustics_config_sha256(
    provider_config_sha256: str | None, audio_stream_index: int
) -> str:
    """Bind the acoustics config identity to the normalization choices."""
    pipeline_config = {
        "schema": ACOUSTICS_PIPELINE_CONFIG_SCHEMA,
        "adapter_protocol": ACOUSTICS_RESULT_SCHEMA,
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


def _rich_provenance(
    *,
    tool_id: str,
    provider_id: str,
    provider_version: str,
    model_id: str | None,
    model_version: str | None,
    config_sha256: str | None,
    created_at_ms: int,
) -> dict[str, Any]:
    provenance: dict[str, Any] = {
        "created_at_ms": created_at_ms,
        "tool": {"id": tool_id, "version": TOOL_VERSION},
        "provider": {"id": provider_id, "version": provider_version},
    }
    if model_id is not None:
        provenance["model"] = {"id": model_id, "version": model_version}
    if config_sha256 is not None:
        provenance["config_sha256"] = config_sha256
    return provenance


def _sense_group_resource(
    *,
    subtitle: ResourceFile,
    media_fingerprint: str,
    result: SenseGroupResult,
    groups: tuple[dict[str, Any], ...],
    created_at_ms: int,
) -> ResourceFile:
    return _envelope(
        kind="sense_group_analysis",
        media_fingerprint=media_fingerprint,
        dependencies=[subtitle],
        provenance=_rich_provenance(
            tool_id="listen-gen.sense-groups",
            provider_id=result.provider_id,
            provider_version=result.provider_version,
            model_id=result.model_id,
            model_version=result.model_version,
            config_sha256=result.config_sha256,
            created_at_ms=created_at_ms,
        ),
        quality={"review_status": "machine_checked"},
        payload={"groups": list(groups)},
        required=False,
    )


def _acoustics_resource(
    *,
    word_timeline: ResourceFile,
    media_fingerprint: str,
    result: AcousticsResult,
    measurements: tuple[dict[str, Any], ...],
    config_sha256: str | None,
    created_at_ms: int,
) -> ResourceFile:
    return _envelope(
        kind="word_acoustics",
        media_fingerprint=media_fingerprint,
        dependencies=[word_timeline],
        provenance=_rich_provenance(
            tool_id="listen-gen.acoustics",
            provider_id=result.provider_id,
            provider_version=result.provider_version,
            model_id=result.model_id,
            model_version=result.model_version,
            config_sha256=config_sha256,
            created_at_ms=created_at_ms,
        ),
        quality={"review_status": "machine_checked"},
        payload={
            "sample_rate_hz": result.sample_rate_hz,
            "energy_baseline": "sentence_median_dbfs",
            "pitch_baseline": "sentence_median_f0_hz",
            "measurements": list(measurements),
        },
        required=False,
    )


def _prosody_resource(
    *,
    word_timeline: ResourceFile,
    acoustics: ResourceFile,
    sense_group: ResourceFile | None,
    media_fingerprint: str,
    result: ProsodyResult,
    anchors: tuple[dict[str, Any], ...],
    chunks: tuple[dict[str, Any], ...],
    created_at_ms: int,
) -> ResourceFile:
    dependencies: list[ResourceFile] = [word_timeline, acoustics]
    if sense_group is not None:
        dependencies.append(sense_group)
    return _envelope(
        kind="prosody_analysis",
        media_fingerprint=media_fingerprint,
        dependencies=dependencies,
        provenance=_rich_provenance(
            tool_id="listen-gen.prosody",
            provider_id=result.provider_id,
            provider_version=result.provider_version,
            model_id=result.model_id,
            model_version=result.model_version,
            config_sha256=result.config_sha256,
            created_at_ms=created_at_ms,
        ),
        quality={"review_status": "machine_checked"},
        payload={
            "chunks": list(chunks),
            "anchors": list(anchors),
        },
        required=False,
    )


# ---------------------------------------------------------------------------
# Pipeline stage runners
# ---------------------------------------------------------------------------


def run_sense_groups(
    *,
    analyzer: SenseGroupAnalyzer,
    language: str,
    sentences: tuple[AlignmentSentence, ...],
    subtitle: ResourceFile,
    media_fingerprint: str,
    created_at_ms: int,
    progress: Callable[[str], None] | None = None,
) -> tuple[str, ResourceFile | None, list[dict[str, str]], tuple[dict[str, Any], ...]]:
    """Run the optional sense-group stage and convert failures into degradation.

    Returns ``(status, resource, typed_warnings, resolved_groups)`` where
    status is ``"produced"`` or ``"degraded"``. Degradable failures preserve
    the subtitle and word resources; cancellation is never swallowed.
    """
    if progress is not None:
        progress("analyzing_sense_groups")
    try:
        request = SenseGroupRequest(language=language, sentences=sentences)
        result = analyzer.analyze(request)
        groups = _qualify_sense_groups(result, sentences)
        resource = _sense_group_resource(
            subtitle=subtitle,
            media_fingerprint=media_fingerprint,
            result=result,
            groups=groups,
            created_at_ms=created_at_ms,
        )
        return "produced", resource, [], groups
    except RichStageFailure as error:
        return "degraded", None, [{"code": error.code, "message": str(error)}], ()
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        code, message = rich_warning(error, "sense_groups")
        return "degraded", None, [{"code": code, "message": message}], ()


def run_acoustics(
    *,
    extractor: AcousticsExtractor,
    preprocessor: AudioPreprocessor | None,
    media_path: Path,
    audio_stream_index: int | None,
    language: str,
    sentences: tuple[AlignmentSentence, ...],
    words: tuple[RichWord, ...],
    word_timeline: ResourceFile,
    media_fingerprint: str,
    created_at_ms: int,
    progress: Callable[[str], None] | None = None,
) -> tuple[str, ResourceFile | None, list[dict[str, str]], tuple[dict[str, Any], ...]]:
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
                    language=language,
                    sentences=sentences,
                    words=words,
                    audio_path=prepared.path,
                )
                result = extractor.measure(request)
            stream_index = prepared.stream_index
        else:
            request = AcousticsRequest(
                language=language,
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
        resource = _acoustics_resource(
            word_timeline=word_timeline,
            media_fingerprint=media_fingerprint,
            result=result,
            measurements=measurements,
            config_sha256=config_sha256,
            created_at_ms=created_at_ms,
        )
        return "produced", resource, [], measurements
    except RichStageFailure as error:
        return "degraded", None, [{"code": error.code, "message": str(error)}], ()
    except (ConversionError, OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        code, message = rich_warning(error, "acoustics")
        return "degraded", None, [{"code": code, "message": message}], ()


def run_prosody(
    *,
    analyzer: ProsodyAnalyzer,
    language: str,
    sentences: tuple[AlignmentSentence, ...],
    words: tuple[RichWord, ...],
    measurements: tuple[dict[str, Any], ...],
    groups: tuple[dict[str, Any], ...] | None,
    word_timeline: ResourceFile,
    acoustics: ResourceFile,
    sense_group: ResourceFile | None,
    media_fingerprint: str,
    created_at_ms: int,
    progress: Callable[[str], None] | None = None,
) -> tuple[str, ResourceFile | None, list[dict[str, str]]]:
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
            language=language,
            sentences=sentences,
            words=words,
            measurements=measurements,
            groups=groups,
        )
        result = analyzer.analyze(request)
        anchors, chunks = _qualify_prosody(
            result, words, measurements, sentences, groups
        )
        resource = _prosody_resource(
            word_timeline=word_timeline,
            acoustics=acoustics,
            sense_group=sense_group if result.uses_sense_groups else None,
            media_fingerprint=media_fingerprint,
            result=result,
            anchors=anchors,
            chunks=chunks,
            created_at_ms=created_at_ms,
        )
        return "produced", resource, []
    except RichStageFailure as error:
        return "degraded", None, [{"code": error.code, "message": str(error)}]
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        code, message = rich_warning(error, "prosody")
        return "degraded", None, [{"code": code, "message": message}]
