"""The capability production engine: plan, run, qualify, package.

One :func:`produce` call executes one bounded Generation Run against a
CapabilityRequest: it plans the smallest derivation graph, runs the selected
providers, reports honest warnings for every abstention, and writes one
deterministic Content Package v3 carrier. Provider selection and secrets
never enter the request; they are supplied as adapters here.

Honesty rules implemented here:
- a document with no extractable text abstains (an honest capability result,
  never an import failure);
- every derivation emits exactly one self-contained Structured Reading
  resource; a compatible available reading is reused instead of regenerated,
  and an incompatible one never suppresses generation;
- TTS consumes only the exact logical text of a Structured Reading through a
  production input projection, never the raw document;
- exact alignment that cannot be produced abstains the alignment resource
  while the audio still succeeds; timing is never fabricated;
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
from .asr import AsrAdapter, AsrTranscript
from .media import FfmpegAudioPreprocessor
from .capability import (
    CapabilityRequest,
    AvailableDocumentRendition,
    AvailableMediaRendition,
)
from .document import (
    DecodedDocument,
    DocumentDecodeError,
    NoTextLayer,
    OcrProvider,
    build_reading_structure,
    decode_document,
)
from .package import ConversionError
from .package_v3 import (
    ANCHOR_TIME_ALIGNMENT_SCHEMA_V1,
    STRUCTURED_READING_SCHEMA_V1,
    V3Release,
    blob_declaration,
    canonical_json,
    compatibility,
    PackageDocumentRendition,
    PackageMediaRendition,
    PackageResource,
    producer_declaration,
    provenance,
    quality,
    sha256_of_bytes,
    write_v3_package,
)
from .plan import Derivation, DerivationKind, ProductionPlan, plan
from .production_input_projection import (
    project_plain_text_for_speech,
    sentences_from_structured_reading,
)
from .rich import RichContext
from .rich_stages import (
    RichStages,
    alignment_sentences_from,
    alignment_segments_from,
    build_subtitle_text_track_resource,
    build_word_timeline_resource,
    run_rich_stages,
)
from .subtitle import SubtitleBlock, parse_subtitle
from .tts import AnchorAlignment, TtsAdapter, TtsProviderError, _wav_duration_ms


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
class DerivedAudio:
    bytes: bytes
    media_type: str
    alignment: tuple[AnchorAlignment, ...] | None
    duration_ms: int | None
    provider: dict[str, object]


@dataclass(frozen=True)
class ProduceOutcome:
    release: V3Release | None
    package_sha256: str | None
    warnings: tuple[Warning, ...]
    package_path: Path | None = None


@dataclass(frozen=True)
class ProduceConfig:
    tts: TtsAdapter | None = None
    ocr: OcrProvider | None = None
    asr: AsrAdapter | None = None
    asr_preprocessor: FfmpegAudioPreprocessor | None = None
    rich: "RichStages | None" = None
    subtitle: Path | None = None


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


def _language_for(request: CapabilityRequest, rendition) -> str:
    if getattr(rendition, "language", None):
        return rendition.language
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


def _run_document_derivation(
    request: CapabilityRequest,
    derivation: Derivation,
    *,
    ocr: OcrProvider | None,
    created_at_ms: int,
    package_rendition_id: str,
    progress: Progress | None,
) -> tuple[DecodedDocument, DerivedStructuredReading]:
    rendition = next(
        entry
        for entry in request.document_renditions
        if entry.rendition_id == derivation.input_rendition_ids[0]
    )
    raw = _blob_source_bytes(rendition.blob)
    if progress:
        progress(f"decoding {rendition.media_type}")
    try:
        decoded = decode_document(raw, rendition.media_type, ocr=ocr)
    except NoTextLayer as error:
        raise ProductionAbstained(
            "document_text_unavailable",
            "the document has no text layer and no OCR provider could produce text",
        ) from error
    except DocumentDecodeError as error:
        raise ProductionAbstained(
            "document_text_unavailable", str(error)
        ) from error
    language = _language_for(request, rendition)
    structure = build_reading_structure(
        decoded, language=language, rendition_id=package_rendition_id
    )
    subject = _subject(request, rendition_ids=(package_rendition_id,))
    derived, _ = _reading_resource(
        language=language,
        payload=structure.structured_reading,
        subject=subject,
        provenance_document=provenance(
            created_at_ms,
            input_rendition_ids=[package_rendition_id],
        ),
    )
    return decoded, derived


def _run_tts_derivation(
    request: CapabilityRequest,
    structured_reading: dict[str, object],
    *,
    tts: TtsAdapter,
    created_at_ms: int,
    progress: Progress | None,
) -> DerivedAudio:
    projection = project_plain_text_for_speech(structured_reading)
    sentence_anchors = sentences_from_structured_reading(structured_reading)
    if progress:
        progress(f"running the {tts.name} TTS provider")
    try:
        result = tts.synthesize(projection.text, sentence_anchors)
    except TtsProviderError as error:
        raise ProductionFailure(
            "tts_provider_failed", str(error)
        ) from error
    combined_config = "sha256:" + sha256_of_bytes(
        canonical_json(
            {
                "projection": projection.config_sha256,
                "tts": result.config_sha256,
            }
        )
    ).removeprefix("sha256:")
    provider = _producer_facts(
        created_at_ms,
        provider_id=result.provider_id,
        provider_version=result.provider_version,
        model_id=result.model_id,
        model_version=result.model_version,
        config_sha256=combined_config,
    )
    return DerivedAudio(
        bytes=result.audio_bytes,
        media_type=result.media_type,
        alignment=result.alignment,
        duration_ms=result.duration_ms,
        provider=provider,
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
        decoded = _transcript_document(transcript)
        language = transcript.language
        structure = build_reading_structure(
            decoded, language=language, rendition_id=package_rendition_id
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


def _subtitle_document(blocks: tuple[SubtitleBlock, ...]) -> DecodedDocument:
    """Render a subtitle track as the extracted reading text.

    Blocks are the exact sentence units; character offsets accumulate over
    the joined text so reading anchors and the subtitle timing agree. Each
    block is one sentence; embedded line breaks collapse to spaces (subtitle
    wrapping, not meaning).
    """
    from .document import ExtractedText, Paragraph, Sentence, _blocks_from_paragraphs

    sentences: list[Sentence] = []
    cursor = 0
    block_count = len(blocks)
    for index, block in enumerate(blocks):
        text = " ".join(block.text.split())
        start = cursor
        if index < block_count - 1:
            cursor += len(text) + 1
            end = cursor
            sentence_text = text + "\n"
        else:
            cursor += len(text)
            end = cursor
            sentence_text = text
        sentences.append(
            Sentence(
                id=f"sentence-{index}",
                index=index,
                start_char=start,
                end_char=end,
                text=sentence_text,
            )
        )
    joined = "".join(sentence.text for sentence in sentences)
    paragraphs = [
        Paragraph(
            id=f"block-{index}",
            index=index,
            start_char=sentence.start_char,
            end_char=sentence.end_char - 1 if index < block_count - 1 else sentence.end_char,
            sentence_ids=(sentence.id,),
        )
        for index, sentence in enumerate(sentences)
    ]
    blocks_out = _blocks_from_paragraphs(paragraphs, sentences)
    return DecodedDocument(
        media_type="application/vnd.listen.subtitle",
        text=joined,
        paragraphs=tuple(paragraphs),
        sentences=tuple(sentences),
        blocks=blocks_out,
        byte_identical=False,
    )


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
    tuple[SubtitleBlock, ...],
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
        blocks = parse_subtitle(config.subtitle)
    except ConversionError as error:
        raise ProductionFailure("subtitle_unavailable", str(error)) from error
    decoded = _subtitle_document(blocks)
    language = _language_for(request, rendition)
    structure = build_reading_structure(
        decoded, language=language, rendition_id=package_rendition_id
    )
    subject = _subject(request, rendition_ids=(package_rendition_id,))
    derived, _ = _reading_resource(
        language=language,
        payload=structure.structured_reading,
        subject=subject,
        provenance_document=provenance(
            created_at_ms,
            input_rendition_ids=[package_rendition_id],
        ),
    )
    alignment = tuple(
        AnchorAlignment(anchor_id=f"sentence-{index}", media_time_ms=block.start_ms)
        for index, block in enumerate(blocks)
    )
    raw = _blob_source_bytes(rendition.blob)
    return derived, alignment, {}, blocks, raw


def _transcript_document(transcript: AsrTranscript) -> DecodedDocument:
    """Render an ASR transcript as the extracted reading text.

    Segments are the exact sentence units; character offsets accumulate over
    the joined text so reading anchors and the transcript timing agree. The
    newline between segments belongs to the preceding sentence, so the
    sentence units cover the whole text without gaps.
    """
    from .document import ExtractedText, Paragraph, Sentence, _blocks_from_paragraphs

    sentences: list[Sentence] = []
    cursor = 0
    segment_count = len(transcript.segments)
    for index, segment in enumerate(transcript.segments):
        text = segment.display_text or segment.text
        start = cursor
        if index < segment_count - 1:
            cursor += len(text) + 1
            end = cursor
            sentence_text = text + "\n"
        else:
            cursor += len(text)
            end = cursor
            sentence_text = text
        sentences.append(
            Sentence(
                id=f"sentence-{index}",
                index=index,
                start_char=start,
                end_char=end,
                text=sentence_text,
            )
        )
    joined = "".join(sentence.text for sentence in sentences)
    if not joined.strip():
        raise ProductionAbstained(
            "document_text_unavailable", "the transcript contains no text"
        )
    paragraphs = [
        Paragraph(
            id=f"block-{index}",
            index=index,
            start_char=sentence.start_char,
            end_char=sentence.end_char - 1 if index < segment_count - 1 else sentence.end_char,
            sentence_ids=(sentence.id,),
        )
        for index, sentence in enumerate(sentences)
    ]
    blocks = _blocks_from_paragraphs(paragraphs, sentences)
    return DecodedDocument(
        media_type="application/vnd.listen.transcript",
        text=joined,
        paragraphs=tuple(paragraphs),
        sentences=tuple(sentences),
        blocks=blocks,
        byte_identical=False,
    )


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


def _source_document_renditions(
    request: CapabilityRequest,
) -> tuple[PackageDocumentRendition, ...]:
    return tuple(
        PackageDocumentRendition(
            media_type=entry.media_type,
            language=entry.language,
            text_blob=blob_declaration(entry.blob.digest, entry.blob.size_bytes, False),
            origin="source",
            source_asset_id=entry.source_asset_id,
        )
        for entry in request.document_renditions
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
        producer=producer or None,
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


def _available_reading_payload(
    request: CapabilityRequest, resource_id: str
) -> tuple[dict[str, object], str]:
    """Read and validate an available Structured Reading payload for reuse."""
    entry = next(
        candidate
        for candidate in request.resources
        if candidate.resource_id == resource_id
    )
    raw = _blob_source_bytes(entry.blob)
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ProductionFailure(
            "resource_invalid",
            "the available resource payload is not valid JSON",
        ) from error
    if not isinstance(payload, dict):
        raise ProductionFailure(
            "resource_invalid", "the available resource payload is invalid"
        )
    if not payload.get("text") or not isinstance(payload.get("anchors"), list):
        raise ProductionFailure(
            "resource_invalid",
            "the available resource is not a qualified structured reading",
        )
    return payload, entry.content_language or request.edition.target_language




def _tts_rich_stages(
    *,
    request: CapabilityRequest,
    config: ProduceConfig,
    audio_bytes: bytes,
    audio_duration_ms: int | None,
    reading_payload: dict[str, object],
    alignments: tuple[AnchorAlignment, ...],
    producer: dict[str, object],
    anchor_resource_id: str,
    language: str,
    subject: dict[str, object],
    rendition_id: str,
    created_at_ms: int,
    progress: Progress | None,
) -> tuple[list[PackageResource], dict[str, bytes], list[Warning]]:
    """Derived TTS audio joins the same rich pipeline.

    The source text is already known and every sentence's audio window is
    measured (per-sentence synthesis), so a forced aligner produces the exact
    word timeline directly. Without an aligner, a ``tts_aligner`` ASR adapter
    re-transcribes the derived audio as the honest fallback; without either,
    the document path produces no word-level resources.
    """
    stages = config.rich
    if stages is None or (stages.aligner is None and stages.tts_aligner is None):
        return [], {}, []
    sentence_ids, sentence_times = _sentence_ids_and_times(
        reading_payload, alignments
    )
    context = RichContext(
        language=language,
        subject=subject,
        anchor_resource_id=anchor_resource_id,
        rendition_id=rendition_id,
        created_at_ms=created_at_ms,
    )
    with tempfile.TemporaryDirectory(prefix="listen-gen-rich-") as directory:
        audio_path = Path(directory) / "tts-audio.bin"
        audio_path.write_bytes(audio_bytes)
        warnings: list[Warning] = []
        aligned_result = None
        align_segments: tuple[AlignSegment, ...] = ()
        transcript: AsrTranscript | None = None
        asr_input: Path | None = audio_path
        stream_index: int | None = None
        if stages.aligner is not None:
            if audio_duration_ms is None:
                try:
                    audio_duration_ms = _wav_duration_ms(audio_path)
                except ConversionError:
                    audio_duration_ms = None
            sentences = alignment_sentences_from(
                reading_payload=reading_payload,
                sentence_times_ms=sentence_times,
                audio_duration_ms=audio_duration_ms,
            )
            segments = alignment_segments_from(sentences)
            if segments:
                try:
                    aligned_result = stages.aligner.align(
                        AlignmentRequest(audio_path, segments)
                    )
                    align_segments = segments
                except ConversionError as error:
                    warnings.append(
                        _warning(
                            "aligner_degraded",
                            f"forced alignment failed; falling back to "
                            f"re-transcription: {error}",
                        )
                    )
            else:
                warnings.append(
                    _warning(
                        "aligner_abstained",
                        "the reading carries no sentence text to align",
                    )
                )
        if aligned_result is None and stages.tts_aligner is not None:
            asr_input = audio_path
            stream_index = None
            if config.asr_preprocessor is not None:
                with config.asr_preprocessor.prepare(
                    audio_path, audio_stream_index=None
                ) as prepared:
                    transcript = stages.tts_aligner.transcribe(prepared.path)
                stream_index = prepared.stream_index
                asr_input = prepared.path
            else:
                transcript = stages.tts_aligner.transcribe(audio_path)
            if transcript.segments:
                transcript = AsrTranscript(
                    language=transcript.language or language,
                    segments=transcript.segments,
                    provider_id=transcript.provider_id,
                    provider_version=transcript.provider_version,
                    model_id=transcript.model_id,
                    model_version=transcript.model_version,
                    config_sha256=transcript.config_sha256,
                )
            else:
                transcript = None
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
            audio_path=asr_input,
            audio_stream_index=stream_index,
            progress=progress,
        )
        attach_warnings[:0] = warnings
        return resources, bytes_by_digest, attach_warnings


def _media_rich_stages(
    *,
    request: CapabilityRequest,
    config: ProduceConfig,
    derived: DerivedStructuredReading,
    alignment: tuple[AnchorAlignment, ...],
    transcript: AsrTranscript | None,
    producer: dict[str, object],
    subtitle_blocks: tuple[SubtitleBlock, ...],
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
        audio_duration_ms: int | None = None
        if stages.aligner is not None:
            if transcript is not None and transcript.segments:
                audio_duration_ms = transcript.segments[-1].end_ms
            elif subtitle_blocks:
                audio_duration_ms = subtitle_blocks[-1].end_ms
            sentences = alignment_sentences_from(
                reading_payload=reading_payload,
                sentence_times_ms=sentence_times,
                audio_duration_ms=audio_duration_ms,
            )
            segments = alignment_segments_from(sentences)
            if segments:
                try:
                    aligned_result = stages.aligner.align(
                        AlignmentRequest(audio_path, segments)
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
    source_document_renditions = _source_document_renditions(request)
    source_media_renditions = _source_media_renditions(request)
    document_id_map = {
        entry.rendition_id: package.rendition_id
        for entry, package in zip(request.document_renditions, source_document_renditions)
    }
    media_id_map = {
        entry.rendition_id: package.rendition_id
        for entry, package in zip(request.media_renditions, source_media_renditions)
    }
    production_plan: ProductionPlan = plan(request)
    if check_cancelled:
        check_cancelled()
    if production_plan.empty:
        return ProduceOutcome(release=None, package_sha256=None, warnings=())

    warnings: list[Warning] = []
    embedded_bytes: dict[str, bytes] = {}
    derived_media_renditions: list[PackageMediaRendition] = []
    resources: list[PackageResource] = []
    resource_bytes: dict[str, bytes] = {}
    generated_reading: dict[str, object] | None = None
    generated_reading_resource: PackageResource | None = None

    for derivation in production_plan.derivations:
        if check_cancelled:
            check_cancelled()
        if derivation.kind == DerivationKind.DOCUMENT_READ:
            _, derived = _run_document_derivation(
                request,
                derivation,
                ocr=config.ocr,
                created_at_ms=created_at_ms,
                package_rendition_id=document_id_map[derivation.input_rendition_ids[0]],
                progress=progress,
            )
            resources.append(derived.resource)
            resource_bytes[derived.resource.payload_blob["digest"]] = derived.bytes
            generated_reading = json.loads(derived.bytes.decode("utf-8"))
            generated_reading_resource = derived.resource
        elif derivation.kind == DerivationKind.DOCUMENT_LISTEN:
            if config.tts is None:
                raise ProductionFailure(
                    "provider_not_configured", "no TTS provider is configured"
                )
            input_rendition_ids = [
                document_id_map[derivation.input_rendition_ids[0]]
            ]
            if derivation.input_resource_ids:
                reading_payload, language = _available_reading_payload(
                    request, derivation.input_resource_ids[0]
                )
                derived, _ = _reading_resource(
                    language=language,
                    payload=reading_payload,
                    subject=_subject(
                        request, rendition_ids=input_rendition_ids
                    ),
                    provenance_document=provenance(
                        created_at_ms,
                        input_rendition_ids=input_rendition_ids,
                        input_resource_ids=list(derivation.input_resource_ids),
                    ),
                )
                resources.append(derived.resource)
                resource_bytes[derived.resource.payload_blob["digest"]] = (
                    derived.bytes
                )
                anchor_resource_id = derived.resource.resource_id
                subject = _subject(
                    request,
                    rendition_ids=input_rendition_ids,
                    anchor_resource_ids=[anchor_resource_id],
                )
            else:
                if generated_reading is None:
                    _, derived = _run_document_derivation(
                        request,
                        derivation,
                        ocr=config.ocr,
                        created_at_ms=created_at_ms,
                        package_rendition_id=input_rendition_ids[0],
                        progress=progress,
                    )
                    resources.append(derived.resource)
                    resource_bytes[derived.resource.payload_blob["digest"]] = (
                        derived.bytes
                    )
                    generated_reading = json.loads(derived.bytes.decode("utf-8"))
                    generated_reading_resource = derived.resource
                reading_payload = generated_reading
                anchor_resource_id = generated_reading_resource.resource_id
                language = generated_reading_resource.content_language
                subject = _subject(
                    request,
                    rendition_ids=input_rendition_ids,
                    anchor_resource_ids=[anchor_resource_id],
                )
            audio = _run_tts_derivation(
                request,
                reading_payload,
                tts=config.tts,
                created_at_ms=created_at_ms,
                progress=progress,
            )
            audio_blob = blob_declaration(
                sha256_of_bytes(audio.bytes), len(audio.bytes), True
            )
            embedded_bytes[audio_blob["digest"]] = audio.bytes
            compatibility_verified = [
                {"rendition_id": input_rendition_ids[0], "resource_id": anchor_resource_id}
            ]
            audio_rendition = PackageMediaRendition(
                kind="audio",
                media_type=audio.media_type,
                media_blob=audio_blob,
                fingerprint=sha256_of_bytes(audio.bytes),
                origin="derived",
                producer=audio.provider,
                compatibility=compatibility(
                    [f"provider:{audio.provider.get('provider', {}).get('id', 'unknown')}"],
                    compatibility_verified,
                ),
            )
            derived_media_renditions.append(audio_rendition)
            if audio.alignment:
                alignment_resource, alignment_bytes = _alignment_resource(
                    anchor_resource_id=anchor_resource_id,
                    rendition_id=audio_rendition.rendition_id,
                    alignments=audio.alignment,
                    created_at_ms=created_at_ms,
                    language=language,
                    subject=subject,
                    producer=audio.provider,
                )
                resources.append(alignment_resource)
                resource_bytes[alignment_resource.payload_blob["digest"]] = (
                    alignment_bytes
                )
                rich_resources, rich_bytes, rich_warnings = _tts_rich_stages(
                    request=request,
                    config=config,
                    audio_bytes=audio.bytes,
                    audio_duration_ms=audio.duration_ms,
                    reading_payload=reading_payload,
                    alignments=audio.alignment,
                    producer=audio.provider,
                    anchor_resource_id=anchor_resource_id,
                    language=language,
                    subject=subject,
                    rendition_id=audio_rendition.rendition_id,
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
                        "exact anchor timing could not be produced; audio is "
                        "available but synchronized reading is not",
                    )
                )
        elif derivation.kind == DerivationKind.MEDIA_READ:
            subtitle_blocks: tuple[SubtitleBlock, ...] = ()
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
        document_renditions=source_document_renditions,
        media_renditions=_source_media_renditions(request)
        + tuple(derived_media_renditions),
        resources=tuple(resources),
        payload_bytes=resource_bytes,
        embedded_bytes=embedded_bytes,
        referenced_digests=frozenset(
            entry.blob.digest
            for entry in request.document_renditions
        )
        | frozenset(entry.blob.digest for entry in request.media_renditions),
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
