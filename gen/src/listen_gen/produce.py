"""The capability production engine: plan, run, qualify, package.

One :func:`produce` call executes one bounded Generation Run against a
CapabilityRequest: it plans the smallest derivation graph, runs the selected
providers, reports honest warnings for every abstention, and writes one
deterministic Content Package v3 carrier. Provider selection and secrets
never enter the request; they are supplied as adapters here.

Honesty rules implemented here:
- a document with no extractable text abstains (an honest capability result,
  never an import failure);
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
    plain_text_for_speech,
)
from .package import ConversionError
from .package_v3 import (
    ANCHOR_TIME_ALIGNMENT_SCHEMA_V1,
    DOCUMENT_TEXT_SCHEMA_V1,
    STRUCTURED_READING_SCHEMA_V1,
    V3Release,
    blob_declaration,
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
from .tts import AnchorAlignment, TtsAdapter, TtsProviderError


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
class DerivedDocumentResources:
    document_text: PackageResource
    structured_reading: PackageResource
    document_text_bytes: bytes
    structured_reading_bytes: bytes

    def resource_ids(self) -> dict[str, str]:
        return {
            "document_text": self.document_text.resource_id,
            "structured_reading": self.structured_reading.resource_id,
        }


@dataclass(frozen=True)
class DerivedAudio:
    bytes: bytes
    media_type: str
    alignment: tuple[AnchorAlignment, ...] | None
    provider_id: str


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


def _blob_source_bytes(blob: Any) -> bytes:
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


def _document_text_and_structure(
    decoded: DecodedDocument,
    *,
    language: str,
    rendition_id: str,
    created_at_ms: int,
    subject: dict[str, object],
    tool_tag: str,
) -> DerivedDocumentResources:
    structure = build_reading_structure(
        decoded, language=language, rendition_id=rendition_id
    )
    document_text_bytes = json.dumps(
        structure.document_text, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    structured_reading_bytes = json.dumps(
        structure.structured_reading,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    document_text = PackageResource(
        kind="document_text",
        schema=DOCUMENT_TEXT_SCHEMA_V1,
        role="base",
        content_language=language,
        payload_blob=blob_declaration(
            sha256_of_bytes(document_text_bytes), len(document_text_bytes), True
        ),
        subject=subject,
        provenance=provenance(created_at_ms),
        quality=quality(),
    )
    structured_reading = PackageResource(
        kind="structured_reading",
        schema=STRUCTURED_READING_SCHEMA_V1,
        role="base",
        content_language=language,
        payload_blob=blob_declaration(
            sha256_of_bytes(structured_reading_bytes),
            len(structured_reading_bytes),
            True,
        ),
        subject=subject,
        provenance=provenance(created_at_ms),
        quality=quality(),
    )
    return DerivedDocumentResources(
        document_text=document_text,
        structured_reading=structured_reading,
        document_text_bytes=document_text_bytes,
        structured_reading_bytes=structured_reading_bytes,
    )


def _alignment_resource(
    *,
    anchor_resource_id: str,
    rendition_id: str,
    alignments: Sequence[AnchorAlignment],
    created_at_ms: int,
    language: str,
    subject: dict[str, object],
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
    payload_bytes = json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
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
        provenance=provenance(created_at_ms),
        quality=quality(),
        producer=producer_declaration(created_at_ms),
    )
    return resource, payload_bytes


def _language_for(request: CapabilityRequest, rendition) -> str:
    if getattr(rendition, "language", None):
        return rendition.language
    return request.edition.target_language


def _subject(request: CapabilityRequest) -> dict[str, object]:
    return {
        "material_revision_id": request.material.material_revision_id,
        "rendition_ids": [],
        "anchor_resource_ids": [],
    }


def _run_document_derivation(
    request: CapabilityRequest,
    derivation: Derivation,
    *,
    ocr: OcrProvider | None,
    created_at_ms: int,
    package_rendition_id: str,
    progress: Progress | None,
) -> tuple[DecodedDocument, DerivedDocumentResources]:
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
    structure = _document_text_and_structure(
        decoded,
        language=language,
        rendition_id=package_rendition_id,
        created_at_ms=created_at_ms,
        subject=_subject(request),
        tool_tag=TOOL_VERSION,
    )
    return decoded, structure


def _run_tts_derivation(
    request: CapabilityRequest,
    structure: DerivedDocumentResources,
    decoded: DecodedDocument,
    *,
    tts: TtsAdapter,
    created_at_ms: int,
    progress: Progress | None,
) -> DerivedAudio:
    text = plain_text_for_speech(decoded)
    sentence_anchors = [
        (sentence.id, sentence.text) for sentence in decoded.sentences
    ]
    if progress:
        progress(f"running the {tts.name} TTS provider")
    try:
        result = tts.synthesize(text, sentence_anchors)
    except TtsProviderError as error:
        raise ProductionFailure(
            "tts_provider_failed", str(error)
        ) from error
    return DerivedAudio(
        bytes=result.audio_bytes,
        media_type=result.media_type,
        alignment=result.alignment,
        provider_id=tts.name,
    )


def _run_media_derivation(
    request: CapabilityRequest,
    derivation: Derivation,
    *,
    config: ProduceConfig,
    created_at_ms: int,
    package_rendition_id: str,
    progress: Progress | None,
) -> tuple[DerivedDocumentResources, tuple[AnchorAlignment, ...] | None]:
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
        if transcript.language != request.edition.target_language:
            raise ProductionFailure(
                "language_mismatch",
                "the transcription result language does not agree with the "
                "requested target language",
            )
        decoded = _transcript_document(transcript)
        language = transcript.language
        structure = _document_text_and_structure(
            decoded,
            language=language,
            rendition_id=package_rendition_id,
            created_at_ms=created_at_ms,
            subject=_subject(request),
            tool_tag=TOOL_VERSION,
        )
        alignment = _transcript_alignment(transcript)
    return structure, alignment


def _transcript_document(transcript: AsrTranscript) -> DecodedDocument:
    """Render an ASR transcript as the extracted reading text.

    Segments are the exact sentence units; character offsets accumulate over
    the joined text so reading anchors and the transcript timing agree. The
    newline between segments belongs to the preceding sentence, so the
    sentence units cover the whole text without gaps.
    """
    from .document import ExtractedText, Paragraph, Sentence

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
    return ExtractedText(
        text=joined,
        paragraphs=tuple(paragraphs),
        sentences=tuple(sentences),
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
    derived_document_renditions: list[PackageDocumentRendition] = []
    derived_media_renditions: list[PackageMediaRendition] = []
    resources: list[PackageResource] = []
    resource_bytes: dict[str, bytes] = {}

    for derivation in production_plan.derivations:
        if check_cancelled:
            check_cancelled()
        if derivation.kind == DerivationKind.DOCUMENT_READ:
            _, structure = _run_document_derivation(
                request,
                derivation,
                ocr=config.ocr,
                created_at_ms=created_at_ms,
                package_rendition_id=document_id_map[derivation.input_rendition_ids[0]],
                progress=progress,
            )
            resources.extend(
                [structure.document_text, structure.structured_reading]
            )
            resource_bytes[structure.document_text.payload_blob["digest"]] = (
                structure.document_text_bytes
            )
            resource_bytes[structure.structured_reading.payload_blob["digest"]] = (
                structure.structured_reading_bytes
            )
        elif derivation.kind == DerivationKind.DOCUMENT_LISTEN:
            if config.tts is None:
                raise ProductionFailure(
                    "provider_not_configured", "no TTS provider is configured"
                )
            decoded, structure = _run_document_derivation(
                request,
                derivation,
                ocr=config.ocr,
                created_at_ms=created_at_ms,
                package_rendition_id=document_id_map[derivation.input_rendition_ids[0]],
                progress=progress,
            )
            audio = _run_tts_derivation(
                request,
                structure,
                decoded,
                tts=config.tts,
                created_at_ms=created_at_ms,
                progress=progress,
            )
            resources.extend([structure.document_text, structure.structured_reading])
            resource_bytes[structure.document_text.payload_blob["digest"]] = (
                structure.document_text_bytes
            )
            resource_bytes[structure.structured_reading.payload_blob["digest"]] = (
                structure.structured_reading_bytes
            )
            audio_blob = blob_declaration(
                sha256_of_bytes(audio.bytes), len(audio.bytes), True
            )
            embedded_bytes[audio_blob["digest"]] = audio.bytes
            input_rendition_ids = [
                document_id_map[derivation.input_rendition_ids[0]]
            ]
            audio_rendition = PackageMediaRendition(
                kind="audio",
                media_type=audio.media_type,
                media_blob=audio_blob,
                fingerprint=sha256_of_bytes(audio.bytes),
                origin="derived",
                producer=producer_declaration(created_at_ms),
                compatibility=compatibility(
                    [f"provider:{audio.provider_id}"], input_rendition_ids
                ),
            )
            derived_media_renditions.append(audio_rendition)
            if audio.alignment:
                alignment_resource, alignment_bytes = _alignment_resource(
                    anchor_resource_id=structure.structured_reading.resource_id,
                    rendition_id=audio_rendition.rendition_id,
                    alignments=audio.alignment,
                    created_at_ms=created_at_ms,
                    language=structure.structured_reading.content_language,
                    subject=_subject(request),
                )
                resources.append(alignment_resource)
                resource_bytes[alignment_resource.payload_blob["digest"]] = (
                    alignment_bytes
                )
            else:
                warnings.append(
                    _warning(
                        "alignment_abstained",
                        "exact anchor timing could not be produced; audio is "
                        "available but synchronized reading is not",
                    )
                )
        elif derivation.kind == DerivationKind.MEDIA_READ:
            structure, alignment = _run_media_derivation(
                request,
                derivation,
                config=config,
                created_at_ms=created_at_ms,
                package_rendition_id=media_id_map[derivation.input_rendition_ids[0]],
                progress=progress,
            )
            resources.extend([structure.document_text, structure.structured_reading])
            resource_bytes[structure.document_text.payload_blob["digest"]] = (
                structure.document_text_bytes
            )
            resource_bytes[structure.structured_reading.payload_blob["digest"]] = (
                structure.structured_reading_bytes
            )
            if alignment:
                alignment_resource, alignment_bytes = _alignment_resource(
                    anchor_resource_id=structure.structured_reading.resource_id,
                    rendition_id=media_id_map[derivation.input_rendition_ids[0]],
                    alignments=alignment,
                    created_at_ms=created_at_ms,
                    language=structure.structured_reading.content_language,
                    subject=_subject(request),
                )
                resources.append(alignment_resource)
                resource_bytes[alignment_resource.payload_blob["digest"]] = (
                    alignment_bytes
                )
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
        document_renditions=_source_document_renditions(request)
        + tuple(derived_document_renditions),
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
