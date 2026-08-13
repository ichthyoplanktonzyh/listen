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
class DerivedStructuredReading:
    resource: PackageResource
    bytes: bytes


@dataclass(frozen=True)
class DerivedAudio:
    bytes: bytes
    media_type: str
    alignment: tuple[AnchorAlignment, ...] | None
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
    return derived, alignment, producer


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
        producer=producer,
    )
    return resource, payload_bytes


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
            else:
                warnings.append(
                    _warning(
                        "alignment_abstained",
                        "exact anchor timing could not be produced; audio is "
                        "available but synchronized reading is not",
                    )
                )
        elif derivation.kind == DerivationKind.MEDIA_READ:
            derived, alignment, producer = _run_media_derivation(
                request,
                derivation,
                config=config,
                created_at_ms=created_at_ms,
                package_rendition_id=media_id_map[derivation.input_rendition_ids[0]],
                progress=progress,
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
