"""The capability production engine: plan, run, qualify, package.

One :func:`produce` call executes one bounded Generation Run against a
CapabilityRequest: it plans the smallest derivation graph, runs the selected
providers, reports honest warnings for every abstention, and writes one
deterministic Content Package v3 carrier. Provider selection and secrets
never enter the request; they are supplied as adapters here.

Honesty rules implemented here:
- every media derivation emits one self-contained Structured Reading resource;
- exact alignment that cannot be produced abstains the alignment resource
  while the transcript still succeeds; timing is never fabricated;
- provider failures (start, timeout, invalid output) are terminal failures,
  distinct from abstention;
- an empty plan (the capability is already satisfied) completes without an
  artifact;
- retry is a new run: the old attempt's facts and packages are never
  rewritten.
"""

from __future__ import annotations

import json
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence

from . import __version__ as TOOL_VERSION
from .align import (
    AlignmentRequest,
    AlignSegment,
    build_word_timeline_from_alignment,
)
from .asr import AsrAdapter, AsrTranscript, _tokens
from .media import FfmpegAudioPreprocessor
from .capability import (
    CapabilityRequest,
)
from .package import ConversionError
from .package_v3 import (
    ANCHOR_TIME_ALIGNMENT_SCHEMA_V1,
    STRUCTURED_READING_SCHEMA_V1,
    V3Release,
    blob_declaration,
    canonical_json,
    PackageMediaRendition,
    PackageResource,
    producer_declaration,
    provenance,
    quality,
    sha256_of_bytes,
    write_v3_package,
)
from .plan import Derivation, DerivationKind, ProductionPlan, plan
from .rich import RichContext
from .rich_stages import (
    RichStages,
    alignment_sentences_from,
    alignment_segments_from,
    build_subtitle_text_track_resource,
    build_word_timeline_resource,
    run_rich_stages,
)
from .subtitle import parse_subtitle_bytes, read_subtitle_source
from .sentence_assembly import (
    ASSEMBLY_CONFIG_SHA256,
    AssembledSentence,
    assemble_asr_transcript,
    assemble_subtitle_blocks,
)
from .structured_reading import (
    Paragraph,
    Sentence,
    StructuredText,
    build_reading_structure,
    text_from_segments,
)


class ProductionFailure(ConversionError):
    """A terminal generation failure with a stable typed code."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code


class ProductionAbstained(ProductionFailure):
    """Every planned derivation abstained honestly; no package is produced."""


class Cancelled(Exception):
    """The run was asked to stop before its terminal commit."""


Progress = Callable[[str], None]
Warning = dict[str, str]


def _warning(code: str, message: str) -> Warning:
    return {"code": code, "message": message}


@dataclass(frozen=True)
class DerivedStructuredReading:
    resource: PackageResource
    bytes: bytes


@dataclass(frozen=True)
class AnchorAlignment:
    anchor_id: str
    media_time_ms: int


@dataclass(frozen=True)
class ProduceOutcome:
    release: V3Release | None
    package_sha256: str | None
    warnings: tuple[Warning, ...]
    package_path: Path | None = None


@dataclass(frozen=True)
class ProduceConfig:
    asr: AsrAdapter | None = None
    asr_preprocessor: FfmpegAudioPreprocessor | None = None
    rich: "RichStages | None" = None
    subtitle: Path | None = None
    subtitle_sha256: str | None = None


def _blob_source_bytes(blob) -> bytes:
    if blob.path is None:
        raise ProductionFailure(
            "input_unavailable", "the declared input bytes are not available"
        )
    try:
        data = blob.path.read_bytes()
    except OSError as error:
        raise ProductionFailure(
            "input_unavailable", "the declared input bytes could not be read"
        ) from error
    if sha256_of_bytes(data) != blob.digest:
        raise ProductionFailure(
            "input_changed", "the declared input bytes changed during generation"
        )
    return data


def _reading_resource(
    *,
    language: str,
    payload: dict[str, object],
    subject: dict[str, object],
    provenance_document: dict[str, object],
) -> tuple[DerivedStructuredReading, bytes]:
    payload_bytes = canonical_json(payload)
    resource = PackageResource(
        kind="structured_reading",
        schema=STRUCTURED_READING_SCHEMA_V1,
        role="base",
        content_language=language,
        payload_blob=blob_declaration(
            sha256_of_bytes(payload_bytes), len(payload_bytes), True
        ),
        subject=subject,
        provenance=provenance_document,
        quality=quality(),
    )
    return DerivedStructuredReading(resource=resource, bytes=payload_bytes), payload_bytes


def _language_for(request: CapabilityRequest) -> str:
    return request.edition.target_language


def _subject(
    request: CapabilityRequest,
    *,
    rendition_ids: Sequence[str],
    anchor_resource_ids: Sequence[str] = (),
) -> dict[str, object]:
    return {
        "material_revision_id": request.material.material_revision_id,
        "rendition_ids": list(rendition_ids),
        "anchor_resource_ids": list(anchor_resource_ids),
    }


def _producer_facts(
    created_at_ms: int,
    *,
    provider_id: str | None,
    provider_version: str | None,
    model_id: str | None,
    model_version: str | None,
    config_sha256: str | None,
) -> dict[str, object]:
    provider: dict[str, object] | None = None
    if provider_id and provider_version:
        provider = {"id": provider_id, "version": provider_version}
    model: dict[str, object] | None = None
    if model_id and model_version:
        model = {"id": model_id, "version": model_version}
    elif model_id:
        model = {"id": model_id, "version": ""}
    return producer_declaration(
        created_at_ms,
        provider=provider,
        model=model,
        config_sha256=config_sha256,
    )


def _run_media_derivation(
    request: CapabilityRequest,
    derivation: Derivation,
    *,
    config: ProduceConfig,
    created_at_ms: int,
    package_rendition_id: str,
    progress: Progress | None,
) -> tuple[
    DerivedStructuredReading,
    tuple[AnchorAlignment, ...] | None,
    dict[str, object],
    AsrTranscript,
    bytes,
]:
    rendition = next(
        entry
        for entry in request.media_renditions
        if entry.rendition_id == derivation.input_rendition_ids[0]
    )
    if config.asr is None:
        raise ProductionFailure(
            "provider_not_configured", "no ASR provider is configured"
        )
    raw = _blob_source_bytes(rendition.blob)
    with tempfile.TemporaryDirectory(prefix="listen-gen-asr-") as directory:
        media_path = Path(directory) / "input.media"
        media_path.write_bytes(raw)
        if progress:
            progress("transcribing the media")
        try:
            transcript: AsrTranscript = config.asr.transcribe(media_path)
        except (ConversionError, OSError) as error:
            raise ProductionFailure(
                "asr_provider_failed", "the ASR provider failed"
            ) from error
        # ASR time segments are provider windows, not linguistic sentence
        # boundaries.  Assemble them once here; every downstream resource
        # receives this same sentence identity and remapped word coordinates.
        transcript = assemble_asr_transcript(transcript)
        decoded = _transcript_reading(transcript)
        language = transcript.language
        structure = build_reading_structure(
            decoded, language=language
        )
        producer = _producer_facts(
            created_at_ms,
            provider_id=transcript.provider_id,
            provider_version=transcript.provider_version,
            model_id=transcript.model_id,
            model_version=transcript.model_version,
            config_sha256=transcript.config_sha256,
        )
        subject = _subject(request, rendition_ids=(package_rendition_id,))
        derived, _ = _reading_resource(
            language=language,
            payload=structure.structured_reading,
            subject=subject,
            provenance_document=provenance(
                created_at_ms,
                input_rendition_ids=[package_rendition_id],
                provider=producer["provider"],
                model=producer["model"],
                config_sha256=producer["config_sha256"],
            ),
        )
        alignment = _transcript_alignment(transcript)
    return derived, alignment, producer, transcript, raw


def _subtitle_reading(
    assembled: tuple[AssembledSentence, ...],
) -> StructuredText:
    """Build reading anchors from the subtitle's assembled sentence text."""
    decoded = text_from_segments(tuple(sentence.text for sentence in assembled))
    if not decoded.text.strip():
        raise ProductionAbstained(
            "subtitle_text_unavailable", "the subtitle track contains no text"
        )
    return decoded


def _run_subtitle_derivation(
    request: CapabilityRequest,
    derivation: Derivation,
    *,
    config: ProduceConfig,
    created_at_ms: int,
    package_rendition_id: str,
    progress: Progress | None,
) -> tuple[
    DerivedStructuredReading,
    tuple[AnchorAlignment, ...],
    dict[str, object],
    tuple[AssembledSentence, ...],
    bytes,
]:
    """A media derivation whose reading comes from its subtitle track.

    The subtitle is the authoritative text: no speech recognition runs. The
    word timeline then derives by forced alignment against the subtitle's own
    time windows.
    """
    rendition = next(
        entry
        for entry in request.media_renditions
        if entry.rendition_id == derivation.input_rendition_ids[0]
    )
    if progress:
        progress("parsing the subtitle track")
    try:
        subtitle_bytes = read_subtitle_source(config.subtitle)
        subtitle_sha256 = sha256_of_bytes(subtitle_bytes)
        if subtitle_sha256 != derivation.subtitle_sha256:
            raise ProductionFailure(
                "input_changed", "the subtitle input changed after planning"
            )
        blocks = parse_subtitle_bytes(subtitle_bytes)
    except ProductionFailure:
        raise
    except ConversionError as error:
        raise ProductionFailure("subtitle_unavailable", str(error)) from error
    subtitle_config_sha256 = sha256_of_bytes(
        canonical_json(
            {
                "assembly_config_sha256": ASSEMBLY_CONFIG_SHA256,
                "subtitle_sha256": subtitle_sha256,
            }
        )
    )
    assembled = assemble_subtitle_blocks(blocks)
    decoded = _subtitle_reading(assembled)
    language = _language_for(request)
    structure = build_reading_structure(
        decoded, language=language
    )
    subject = _subject(request, rendition_ids=(package_rendition_id,))
    derived, _ = _reading_resource(
        language=language,
        payload=structure.structured_reading,
        subject=subject,
        provenance_document=provenance(
            created_at_ms,
            input_rendition_ids=[package_rendition_id],
            config_sha256=subtitle_config_sha256,
        ),
    )
    alignment = tuple(
        AnchorAlignment(anchor_id=f"sentence-{sentence.index}", media_time_ms=sentence.start_ms)
        for sentence in assembled
    )
    raw = _blob_source_bytes(rendition.blob)
    # Keep the subtitle blocks argument shape for rich-stage duration
    # calculation, but return assembled sentence windows so no downstream
    # consumer can accidentally recover the old block/sentence identity.
    return derived, alignment, {"config_sha256": subtitle_config_sha256}, assembled, raw


def _transcript_reading(transcript: AsrTranscript) -> StructuredText:
    """Build reading anchors from the assembled ASR sentence text."""
    decoded = text_from_segments(
        tuple(segment.display_text or segment.text for segment in transcript.segments)
    )
    if not decoded.text.strip():
        raise ProductionAbstained(
            "transcript_text_unavailable", "the transcript contains no text"
        )
    return decoded


def _transcript_alignment(
    transcript: AsrTranscript,
) -> tuple[AnchorAlignment, ...] | None:
    """Exact segment timing, or an honest abstention."""
    if not transcript.segments:
        return None
    if all(segment.start_ms == 0 and segment.end_ms == 0 for segment in transcript.segments):
        return None
    return tuple(
        AnchorAlignment(anchor_id=f"sentence-{index}", media_time_ms=segment.start_ms)
        for index, segment in enumerate(transcript.segments)
    )


def _source_media_renditions(
    request: CapabilityRequest,
) -> tuple[PackageMediaRendition, ...]:
    return tuple(
        PackageMediaRendition(
            kind=entry.media_kind,
            media_type=entry.media_type,
            media_blob=blob_declaration(entry.blob.digest, entry.blob.size_bytes, False),
            media_id=entry.media_id,
            fingerprint=entry.fingerprint,
            origin="source",
        )
        for entry in request.media_renditions
    )


def _alignment_resource(
    *,
    anchor_resource_id: str,
    rendition_id: str,
    alignments: Sequence[AnchorAlignment],
    created_at_ms: int,
    language: str,
    subject: dict[str, object],
    producer: dict[str, object],
) -> tuple[PackageResource, bytes]:
    payload = {
        "anchor_resource_id": anchor_resource_id,
        "rendition_id": rendition_id,
        "alignments": [
            {"anchor_id": entry.anchor_id, "media_time_ms": entry.media_time_ms}
            for entry in alignments
        ],
        "extensions": {},
    }
    payload_bytes = canonical_json(payload)
    # A subtitle assembly has no external provider, but its algorithm/config
    # still belongs in provenance.  Keep the optional descriptor producer
    # absent when only that config identity is known, preserving the contract
    # distinction between provider facts and pipeline configuration.
    producer_descriptor = (
        producer
        if producer.get("provider") is not None or producer.get("model") is not None
        else None
    )
    resource = PackageResource(
        kind="anchor_time_alignment",
        schema=ANCHOR_TIME_ALIGNMENT_SCHEMA_V1,
        role="base",
        content_language=language,
        dependencies=(anchor_resource_id,),
        payload_blob=blob_declaration(
            sha256_of_bytes(payload_bytes), len(payload_bytes), True
        ),
        subject=subject,
        provenance=provenance(
            created_at_ms,
            input_rendition_ids=[rendition_id],
            input_resource_ids=[anchor_resource_id],
            provider=producer.get("provider"),
            model=producer.get("model"),
            config_sha256=producer.get("config_sha256"),
        ),
        quality=quality(),
        producer=producer_descriptor,
    )
    return resource, payload_bytes



def _sentence_ids_and_times(
    reading_payload: dict[str, object],
    alignments: tuple[AnchorAlignment, ...] | None,
) -> tuple[tuple[str, ...], dict[str, int]]:
    """The reading's sentence ids in order, and anchor id -> start ms."""
    sentence_ids: list[str] = []
    anchors = reading_payload.get("anchors")
    if isinstance(anchors, list):
        for entry in anchors:
            if (
                isinstance(entry, dict)
                and entry.get("kind") == "sentence"
                and isinstance(entry.get("anchor_id"), str)
            ):
                sentence_ids.append(entry["anchor_id"])
    times: dict[str, int] = {}
    if alignments is not None:
        for alignment in alignments:
            times[alignment.anchor_id] = alignment.media_time_ms
    return tuple(sentence_ids), times


def _attach_rich_resources(
    *,
    config: ProduceConfig,
    context: RichContext,
    reading_payload: dict[str, object],
    sentence_ids: tuple[str, ...],
    sentence_times_ms: dict[str, int],
    transcript: AsrTranscript | None,
    aligned_result,
    align_segments: tuple[AlignSegment, ...],
    audio_duration_ms: int | None,
    producer: dict[str, object],
    audio_path: Path | None,
    audio_stream_index: int | None,
    progress: Progress | None,
) -> tuple[list[PackageResource], dict[str, bytes], list[Warning]]:
    """The word timeline plus the optional rich chain, or nothing when no
    word timings exist (an honest abstention, never a fabrication).

    The word timeline prefers the forced alignment result; when no aligner
    was configured or it did not qualify, the ASR transcript word timings
    are the fallback. Both sources must resolve exactly against the reading
    sentence tokens.
    """
    stages = config.rich
    if stages is None:
        return [], {}, []
    warnings: list[Warning] = []
    # The embedded subtitle track is the anchor Core requires for every
    # word-level resource: word sentence/token references resolve against it,
    # and word times must fall inside its sentence windows. It is built from
    # the exact reading sentences and their alignment windows, so the token
    # coordinates the timeline refers to are the ones the track carries.
    # Without sentences the whole word-level chain abstains honestly.
    sentences = alignment_sentences_from(
        reading_payload=reading_payload,
        sentence_times_ms=sentence_times_ms,
        audio_duration_ms=audio_duration_ms,
    )
    subtitle_result = build_subtitle_text_track_resource(
        sentences=sentences,
        context=context,
        producer=producer,
    )
    if subtitle_result is None:
        warnings.append(
            _warning(
                "subtitle_track_abstained",
                "no reading sentences to anchor word-level resources; "
                "synchronized reading remains available without word-level "
                "alignment",
            )
        )
        return [], {}, warnings
    subtitle_resource, subtitle_payload_bytes = subtitle_result
    resources: list[PackageResource] = [subtitle_resource]
    bytes_by_digest: dict[str, bytes] = {
        subtitle_resource.payload_blob["digest"]: subtitle_payload_bytes
    }
    word_timeline_result = None
    if aligned_result is not None:
        try:
            word_timeline_result = build_word_timeline_from_alignment(
                result=aligned_result,
                segments=align_segments,
                sentence_ids=sentence_ids,
                subtitle_resource_id=subtitle_resource.resource_id,
                context=context,
                upstream_config_sha256=producer.get("config_sha256"),
            )
        except ConversionError:
            warnings.append(
                _warning(
                    "word_timeline_abstained",
                    "forced alignment did not qualify; falling back to "
                    "ASR word timings when available",
                )
            )
    if word_timeline_result is None and transcript is not None and transcript.segments:
        try:
            word_timeline_result = build_word_timeline_resource(
                transcript=transcript,
                sentence_ids=sentence_ids,
                subtitle_resource_id=subtitle_resource.resource_id,
                context=context,
                producer=producer,
            )
        except ConversionError:
            warnings.append(
                _warning(
                    "word_timeline_abstained",
                    "exact word timings could not be qualified; "
                    "synchronized reading remains available without "
                    "word-level alignment",
                )
            )
    if word_timeline_result is None:
        return [], {}, warnings
    word_resource, word_payload_bytes = word_timeline_result
    word_payload = json.loads(word_payload_bytes.decode("utf-8"))
    if audio_duration_ms is None:
        raw_words = word_payload.get("words")
        if isinstance(raw_words, list) and raw_words:
            ends = [entry.get("end_ms") for entry in raw_words if isinstance(entry, dict)]
            if ends:
                audio_duration_ms = max(ends)
    resources.append(word_resource)
    bytes_by_digest[word_resource.payload_blob["digest"]] = word_payload_bytes
    rich_resources, rich_bytes, rich_warnings = run_rich_stages(
        stages=stages,
        context=context,
        sentences=sentences,
        word_timeline_payload=word_payload,
        word_timeline_id=word_resource.resource_id,
        audio_path=audio_path,
        audio_stream_index=audio_stream_index,
        progress=progress,
    )
    resources.extend(rich_resources)
    bytes_by_digest.update(rich_bytes)
    warnings.extend(rich_warnings)
    return resources, bytes_by_digest, warnings


def _media_rich_stages(
    *,
    request: CapabilityRequest,
    config: ProduceConfig,
    derived: DerivedStructuredReading,
    alignment: tuple[AnchorAlignment, ...],
    transcript: AsrTranscript | None,
    producer: dict[str, object],
    subtitle_blocks: tuple[AssembledSentence, ...],
    media_bytes: bytes,
    rendition_id: str,
    created_at_ms: int,
    progress: Progress | None,
) -> tuple[list[PackageResource], dict[str, bytes], list[Warning]]:
    """The word timeline and optional rich stages for a media derivation.

    With an aligner, the known sentence text (ASR transcript or subtitle
    track) is forced-aligned against the media; without one the ASR word
    timings are the fallback.
    """
    stages = config.rich
    if stages is None:
        if transcript is None and subtitle_blocks:
            return [], {}, [
                _warning(
                    "word_timeline_abstained",
                    "no aligner and no ASR transcript are available; word-level "
                    "timing is not produced",
                )
            ]
        return [], {}, []
    if stages.aligner is None and transcript is None:
        return [], {}, [
            _warning(
                "word_timeline_abstained",
                "no aligner and no ASR transcript are available; word-level "
                "timing is not produced",
            )
        ]
    reading_payload = json.loads(derived.bytes.decode("utf-8"))
    sentence_ids, sentence_times = _sentence_ids_and_times(
        reading_payload, alignment
    )
    context = RichContext(
        language=derived.resource.content_language,
        subject=_subject(
            request,
            rendition_ids=(rendition_id,),
            anchor_resource_ids=(derived.resource.resource_id,),
        ),
        anchor_resource_id=derived.resource.resource_id,
        rendition_id=rendition_id,
        created_at_ms=created_at_ms,
    )
    with tempfile.TemporaryDirectory(prefix="listen-gen-rich-") as directory:
        audio_path = Path(directory) / "media-audio.bin"
        audio_path.write_bytes(media_bytes)
        warnings: list[Warning] = []
        aligned_result = None
        align_segments: tuple[AlignSegment, ...] = ()
        # The final assembled sentence window must be closed even when the
        # ASR word-timing fallback is used.  Previously duration was computed
        # only inside the forced-aligner branch, leaving a one-sentence
        # subtitle track with ``end_ms == start_ms`` for ASR-only rich runs.
        if transcript is not None and transcript.segments:
            audio_duration_ms = transcript.segments[-1].end_ms
        elif subtitle_blocks:
            audio_duration_ms = subtitle_blocks[-1].end_ms
        else:
            audio_duration_ms = None
        if stages.aligner is not None:
            sentences = alignment_sentences_from(
                reading_payload=reading_payload,
                sentence_times_ms=sentence_times,
                audio_duration_ms=audio_duration_ms,
            )
            segments = alignment_segments_from(sentences)
            if segments:
                try:
                    aligned_result = stages.aligner.align(
                        AlignmentRequest(
                            audio_path,
                            segments,
                            language=derived.resource.content_language,
                        )
                    )
                    align_segments = segments
                except ConversionError as error:
                    warnings.append(
                        _warning(
                            "aligner_degraded",
                            f"forced alignment failed; falling back to "
                            f"ASR word timings: {error}",
                        )
                    )
            else:
                warnings.append(
                    _warning(
                        "aligner_abstained",
                        "the reading carries no sentence text to align",
                    )
                )
        resources, bytes_by_digest, attach_warnings = _attach_rich_resources(
            config=config,
            context=context,
            reading_payload=reading_payload,
            sentence_ids=sentence_ids,
            sentence_times_ms=sentence_times,
            transcript=transcript,
            aligned_result=aligned_result,
            align_segments=align_segments,
            audio_duration_ms=audio_duration_ms,
            producer=producer,
            audio_path=audio_path,
            audio_stream_index=None,
            progress=progress,
        )
        attach_warnings[:0] = warnings
        return resources, bytes_by_digest, attach_warnings


def produce(
    request: CapabilityRequest,
    output_path: Path,
    *,
    config: ProduceConfig,
    progress: Progress | None = None,
    check_cancelled: Callable[[], None] | None = None,
) -> ProduceOutcome:
    """Execute one bounded Generation Run and write one v3 carrier.

    ``output_path`` must be a staging path owned by the caller; the final
    atomic replace is the caller's terminal commit.

    Note on identities: the caller's rendition ids follow the Core 4.0 domain
    identity rules, while the package declares v3 contract identities (the
    canonical descriptor hash). The package always uses the contract
    identities; compatibility evidence and alignment references point at the
    package's own declarations.
    """
    created_at_ms = request.created_at_ms
    source_media_renditions = _source_media_renditions(request)
    media_id_map = {
        entry.rendition_id: package.rendition_id
        for entry, package in zip(request.media_renditions, source_media_renditions)
    }
    subtitle_sha256 = config.subtitle_sha256
    if config.subtitle is None:
        if subtitle_sha256 is not None:
            raise ProductionFailure(
                "invalid_request", "subtitle_sha256 requires a subtitle input"
            )
    else:
        try:
            current_subtitle_sha256 = sha256_of_bytes(
                read_subtitle_source(config.subtitle)
            )
        except ConversionError as error:
            raise ProductionFailure("subtitle_unavailable", str(error)) from error
        if subtitle_sha256 is not None and current_subtitle_sha256 != subtitle_sha256:
            raise ProductionFailure(
                "input_changed", "the subtitle input changed after planning"
            )
        subtitle_sha256 = current_subtitle_sha256
    production_plan: ProductionPlan = plan(
        request, subtitle_sha256=subtitle_sha256
    )
    if check_cancelled:
        check_cancelled()
    if production_plan.empty:
        return ProduceOutcome(release=None, package_sha256=None, warnings=())

    warnings: list[Warning] = []
    embedded_bytes: dict[str, bytes] = {}
    resources: list[PackageResource] = []
    resource_bytes: dict[str, bytes] = {}
    for derivation in production_plan.derivations:
        if check_cancelled:
            check_cancelled()
        if derivation.kind == DerivationKind.MEDIA_READ:
            subtitle_blocks: tuple[AssembledSentence, ...] = ()
            if config.subtitle is not None:
                derived, alignment, producer, subtitle_blocks, source_media_bytes = (
                    _run_subtitle_derivation(
                        request,
                        derivation,
                        config=config,
                        created_at_ms=created_at_ms,
                        package_rendition_id=media_id_map[
                            derivation.input_rendition_ids[0]
                        ],
                        progress=progress,
                    )
                )
                transcript = None
            else:
                derived, alignment, producer, transcript, source_media_bytes = (
                    _run_media_derivation(
                        request,
                        derivation,
                        config=config,
                        created_at_ms=created_at_ms,
                        package_rendition_id=media_id_map[
                            derivation.input_rendition_ids[0]
                        ],
                        progress=progress,
                    )
                )
            resources.append(derived.resource)
            resource_bytes[derived.resource.payload_blob["digest"]] = derived.bytes
            if alignment:
                alignment_resource, alignment_bytes = _alignment_resource(
                    anchor_resource_id=derived.resource.resource_id,
                    rendition_id=media_id_map[derivation.input_rendition_ids[0]],
                    alignments=alignment,
                    created_at_ms=created_at_ms,
                    language=derived.resource.content_language,
                    subject=_subject(
                        request,
                        rendition_ids=(media_id_map[derivation.input_rendition_ids[0]],),
                        anchor_resource_ids=(derived.resource.resource_id,),
                    ),
                    producer=producer,
                )
                resources.append(alignment_resource)
                resource_bytes[alignment_resource.payload_blob["digest"]] = (
                    alignment_bytes
                )
                if config.rich is not None or config.subtitle is not None:
                    rich_resources, rich_bytes, rich_warnings = _media_rich_stages(
                        request=request,
                        config=config,
                        derived=derived,
                        alignment=alignment,
                        transcript=transcript,
                        producer=producer,
                        subtitle_blocks=subtitle_blocks,
                        media_bytes=source_media_bytes,
                        rendition_id=media_id_map[
                            derivation.input_rendition_ids[0]
                        ],
                        created_at_ms=created_at_ms,
                        progress=progress,
                    )
                    resources.extend(rich_resources)
                    resource_bytes.update(rich_bytes)
                    warnings.extend(rich_warnings)
            else:
                warnings.append(
                    _warning(
                        "alignment_abstained",
                        "the transcription carries no exact timing; structured "
                        "reading is available without media alignment",
                    )
                )
        else:  # pragma: no cover - planner owns the derivation kinds
            raise ProductionFailure("internal_error", "unknown derivation kind")

    if not resources:
        raise ProductionAbstained(
            "abstained",
            "no requested resource could be produced for the capability",
        )

    release = V3Release(
        created_at_ms=created_at_ms,
        edition={
            "edition_id": request.edition.edition_id,
            "title": request.edition.title,
            "target_language": request.edition.target_language,
            "support_languages": list(request.edition.support_languages),
        },
        material={
            "material_id": request.material.material_id,
            "material_revision_id": request.material.material_revision_id,
            "title": request.material.title,
        },
        document_renditions=(),
        media_renditions=source_media_renditions,
        resources=tuple(resources),
        payload_bytes=resource_bytes,
        embedded_bytes=embedded_bytes,
        referenced_digests=frozenset(
            entry.blob.digest for entry in request.media_renditions
        ),
    )
    if check_cancelled:
        check_cancelled()
    package_sha256 = write_v3_package(release, output_path)
    return ProduceOutcome(
        release=release,
        package_sha256=package_sha256,
        warnings=tuple(warnings),
        package_path=output_path,
    )
