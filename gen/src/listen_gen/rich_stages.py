"""Rich stage orchestration for the capability production engine.

Optional analysis stages derive word-level, chunk, sense-group, prosody and
phone resources on top of the Structured Reading and its anchor timing. Both
input directions converge here:

- media -> structured reading: the ASR transcript carries word timings
  (``AsrWord``) that qualify into the exact word timeline resource;
- document -> listen: when a ``tts_aligner`` ASR adapter is configured, the
  derived TTS audio is transcribed again, producing the same word timeline
  shape — the TTS path then continues through exactly the same rich stages as
  the media path.

Every stage is optional and degrades honestly: a failing stage preserves the
already-qualified upstream resources and reports a stable typed warning.
Cancellation and media-change failures are never treated as degradation.
"""

from __future__ import annotations

import json
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from .asr import AsrAdapter, AsrTranscript, AsrWord, _tokens
from .package import ConversionError
from .package_v3 import (
    WORD_TIMELINE_SCHEMA_V1,
    PackageResource,
    blob_declaration,
    canonical_json,
    provenance,
    quality,
    sha256_of_bytes,
)
from .phone import run_phone
from .rich import (
    AlignmentSentence,
    AlignmentToken,
    RichContext,
    RichStageFailure,
    RichWord,
    run_acoustics,
    run_prosody,
    run_sense_groups,
)

WORD_TIMELINE_RESOURCE_KIND = "word_timeline"
WORD_TIMELINE_WORD_TIMING_SOURCE = "asr_reported"

Warning = dict[str, str]


@dataclass(frozen=True)
class RichStages:
    """Provider selection for the optional analysis stages.

    ``sense_groups``, ``acoustics``, ``prosody``, and ``phone`` are the rich
    stage adapters (fixture/command/baseline); ``acoustics_preprocessor``
    normalizes the media window the acoustics extractor receives; a
    ``tts_aligner`` ASR adapter transcribes derived TTS audio into word
    timings so the document path joins the same word timeline pipeline.
    """

    sense_groups: Any | None = None
    acoustics: Any | None = None
    acoustics_preprocessor: Any | None = None
    prosody: Any | None = None
    phone: Any | None = None
    tts_aligner: AsrAdapter | None = None


def _byte_slice(text: str, start: int, end: int) -> str:
    """Slice ``text`` by UTF-8 byte offsets (the payload anchor coordinates)."""
    encoded = text.encode("utf-8")
    if start < 0 or end < start or end > len(encoded):
        raise ConversionError("reading anchor offsets are out of range")
    if end == start:
        return ""
    return encoded[start:end].decode("utf-8")


def reading_sentences(
    reading_payload: dict[str, object],
) -> list[dict[str, object]]:
    """The exact sentence anchors of a structured reading payload."""
    anchors = reading_payload.get("anchors")
    if not isinstance(anchors, list):
        raise ConversionError("structured reading carries no anchors")
    sentences = [
        entry
        for entry in anchors
        if isinstance(entry, dict)
        and entry.get("kind") == "sentence"
        and isinstance(entry.get("anchor_id"), str)
    ]
    return sentences


def alignment_sentences_from(
    *,
    reading_payload: dict[str, object],
    sentence_times_ms: dict[str, int],
    audio_duration_ms: int | None,
) -> tuple[AlignmentSentence, ...]:
    """Project structured reading sentences into alignment sentences.

    ``sentence_times_ms`` maps anchor id to its media start time (from the
    anchor-time-alignment resource). A sentence without a mapped time keeps
    ``start_ms``/``end_ms`` zero and is never fabricated.
    """
    text = reading_payload.get("text")
    if not isinstance(text, str):
        raise ConversionError("structured reading carries no text")
    anchors = reading_payload.get("anchors")
    if not isinstance(anchors, list):
        raise ConversionError("structured reading carries no anchors")
    result: list[AlignmentSentence] = []
    times: list[int] = []
    for sentence in reading_sentences(reading_payload):
        anchor_id = sentence["anchor_id"]
        start_offset = sentence.get("start_offset")
        end_offset = sentence.get("end_offset")
        if not isinstance(start_offset, int) or not isinstance(end_offset, int):
            continue
        sentence_text = _byte_slice(text, start_offset, end_offset).rstrip("\n")
        times.append(sentence_times_ms.get(anchor_id, 0))
        tokens = tuple(
            AlignmentToken(
                index=token["index"],
                kind=token["kind"],
                text=token["text"],
                normalized=token["normalized"],
                start_char=token["start_char"],
                end_char=token["end_char"],
            )
            for token in _tokens(sentence_text)
        )
        result.append(
            AlignmentSentence(
                id=anchor_id,
                index=len(result),
                start_ms=times[-1],
                end_ms=times[-1],
                original_text=sentence_text,
                display_text=sentence_text,
                tokens=tokens,
            )
        )
    for index in range(len(result)):
        if index + 1 < len(result):
            result[index] = AlignmentSentence(
                id=result[index].id,
                index=result[index].index,
                start_ms=result[index].start_ms,
                end_ms=result[index + 1].start_ms,
                original_text=result[index].original_text,
                display_text=result[index].display_text,
                tokens=result[index].tokens,
            )
        elif audio_duration_ms is not None and audio_duration_ms > 0:
            result[index] = AlignmentSentence(
                id=result[index].id,
                index=result[index].index,
                start_ms=result[index].start_ms,
                end_ms=audio_duration_ms,
                original_text=result[index].original_text,
                display_text=result[index].display_text,
                tokens=result[index].tokens,
            )
    return tuple(result)


def _words_from_transcript(
    transcript: AsrTranscript,
    sentence_ids: tuple[str, ...],
) -> list[dict[str, object]]:
    """Resolve ASR word timings against the exact emitted sentence tokens.

    Every ``AsrWord`` must match exactly one word token of its sentence
    (character-span match); a mismatch is a qualification failure, never a
    fabricated timing.
    """
    words: list[dict[str, object]] = []
    for segment_index, segment in enumerate(transcript.segments):
        if not segment.words:
            continue
        if segment_index >= len(sentence_ids):
            raise ConversionError("ASR segments exceed the reading sentences")
        sentence_id = sentence_ids[segment_index]
        sentence_text = segment.display_text or segment.text
        tokens = _tokens(sentence_text)
        token_by_span: dict[tuple[int, int], dict[str, object]] = {}
        for token in tokens:
            if token["kind"] == "word":
                token_by_span[(token["start_char"], token["end_char"])] = token

        def word_char_at(index: int) -> str:
            return sentence_text[index]

        for word in segment.words:
            token = token_by_span.get((word.start_char, word.end_char))
            if token is None:
                # whisper may fold trailing punctuation into the word entry
                # (or split a hyphenated word); strip non-word edges and try
                # again. A pure-punctuation entry carries no word timing and
                # is skipped; an entry that still cannot resolve is a
                # qualification failure, never a fabricated timing.
                start, end = word.start_char, word.end_char
                while end > start and not (
                    word_char_at(end - 1).isalnum() or word_char_at(end - 1) == "_"
                ):
                    end -= 1
                while start < end and not (
                    word_char_at(start).isalnum() or word_char_at(start) == "_"
                ):
                    start += 1
                if start >= end:
                    continue
                token = token_by_span.get((start, end))
            if token is None:
                raise ConversionError(
                    f"ASR word does not exactly match a word token of sentence {sentence_id}"
                )
            entry: dict[str, object] = {
                "sentence_id": sentence_id,
                "token_index": token["index"],
                "start_ms": word.start_ms,
                "end_ms": word.end_ms,
                "timing_source": word.timing_source,
            }
            if word.confidence is not None:
                entry["confidence"] = word.confidence
            words.append(entry)
    return words


def build_word_timeline_resource(
    *,
    transcript: AsrTranscript,
    sentence_ids: tuple[str, ...],
    context: RichContext,
    producer: dict[str, object],
) -> tuple[PackageResource, bytes] | None:
    """The exact word timeline resource, or None when the transcript carries
    no word timings (an honest abstention)."""
    words = _words_from_transcript(transcript, sentence_ids)
    if not words:
        return None
    payload: dict[str, object] = {
        "language": transcript.language,
        "words": words,
    }
    payload_bytes = canonical_json(payload)
    provider = producer.get("provider")
    model = producer.get("model")
    config_sha256 = producer.get("config_sha256")
    resource = PackageResource(
        kind=WORD_TIMELINE_RESOURCE_KIND,
        schema=WORD_TIMELINE_SCHEMA_V1,
        role="base",
        content_language=context.language,
        payload_blob=blob_declaration(
            sha256_of_bytes(payload_bytes), len(payload_bytes), True
        ),
        subject=context.subject,
        dependencies=(context.anchor_resource_id,),
        provenance=provenance(
            context.created_at_ms,
            input_rendition_ids=[context.rendition_id],
            input_resource_ids=[context.anchor_resource_id],
            provider=provider,
            model=model,
            config_sha256=config_sha256,
        ),
        quality=quality(),
        required=False,
    )
    return resource, payload_bytes


def _rich_words(
    word_timeline_payload: dict[str, object],
    sentences: tuple[AlignmentSentence, ...],
) -> tuple[RichWord, ...]:
    """Project the word timeline payload into rich coordinates."""
    raw_words = word_timeline_payload.get("words")
    if not isinstance(raw_words, list):
        raise RichStageFailure("acoustics", "upstream_missing")
    index_by_id = {sentence.id: sentence.index for sentence in sentences}
    words: list[RichWord] = []
    for entry in raw_words:
        if not isinstance(entry, dict):
            raise RichStageFailure("acoustics", "upstream_missing")
        sentence_id = entry.get("sentence_id")
        token_index = entry.get("token_index")
        start_ms = entry.get("start_ms")
        end_ms = entry.get("end_ms")
        if (
            not isinstance(sentence_id, str)
            or not isinstance(token_index, int)
            or not isinstance(start_ms, int)
            or not isinstance(end_ms, int)
        ):
            raise RichStageFailure("acoustics", "upstream_missing")
        words.append(
            RichWord(
                sentence_index=index_by_id.get(sentence_id, -1),
                token_index=token_index,
                start_ms=start_ms,
                end_ms=end_ms,
                sentence_id=sentence_id,
            )
        )
    return tuple(words)


def run_rich_stages(
    *,
    stages: RichStages,
    context: RichContext,
    sentences: tuple[AlignmentSentence, ...],
    word_timeline_payload: dict[str, object],
    word_timeline_id: str,
    audio_path: Path | None,
    audio_stream_index: int | None,
    progress: Callable[[str], None] | None = None,
) -> tuple[list[PackageResource], dict[str, bytes], list[Warning]]:
    """Run the optional rich chain in strict dependency order.

    Returns ``(resources, payload_bytes_by_digest, warnings)``. Every stage is
    optional: a stage without a configured adapter is skipped silently, and a
    failing stage degrades to a stable typed warning while preserving the
    upstream resources.
    """
    resources: list[PackageResource] = []
    bytes_by_digest: dict[str, bytes] = {}
    warnings: list[Warning] = []
    words = _rich_words(word_timeline_payload, sentences)
    groups: tuple[dict[str, Any], ...] | None = None

    if stages.sense_groups is not None:
        status, resource, payload_bytes, typed_warnings, resolved = run_sense_groups(
            analyzer=stages.sense_groups,
            context=context,
            sentences=sentences,
            dependencies=(word_timeline_id, context.anchor_resource_id),
            progress=progress,
        )
        warnings.extend(typed_warnings)
        if status == "produced" and resource is not None and payload_bytes is not None:
            resources.append(resource)
            bytes_by_digest[resource.payload_blob["digest"]] = payload_bytes
            groups = resolved

    acoustics_id: str | None = None
    measurements: tuple[dict[str, Any], ...] = ()
    if stages.acoustics is not None and audio_path is not None:
        status, resource, payload_bytes, typed_warnings, resolved = run_acoustics(
            extractor=stages.acoustics,
            preprocessor=stages.acoustics_preprocessor,
            media_path=audio_path,
            audio_stream_index=audio_stream_index,
            context=context,
            sentences=sentences,
            words=words,
            dependencies=(word_timeline_id, context.anchor_resource_id),
            progress=progress,
        )
        warnings.extend(typed_warnings)
        if status == "produced" and resource is not None and payload_bytes is not None:
            resources.append(resource)
            bytes_by_digest[resource.payload_blob["digest"]] = payload_bytes
            acoustics_id = resource.resource_id
            measurements = resolved

    if stages.prosody is not None and acoustics_id is not None:
        status, resource, payload_bytes, typed_warnings = run_prosody(
            analyzer=stages.prosody,
            context=context,
            sentences=sentences,
            words=words,
            measurements=measurements,
            groups=groups,
            dependencies=(word_timeline_id, acoustics_id, context.anchor_resource_id),
            progress=progress,
        )
        warnings.extend(typed_warnings)
        if status == "produced" and resource is not None and payload_bytes is not None:
            resources.append(resource)
            bytes_by_digest[resource.payload_blob["digest"]] = payload_bytes

    if stages.phone is not None and audio_path is not None:
        status, resource, payload_bytes, typed_warnings = run_phone(
            analyzer=stages.phone,
            audio_path=audio_path,
            words=words,
            context=context,
            dependencies=(word_timeline_id, context.anchor_resource_id),
            progress=progress,
        )
        warnings.extend(typed_warnings)
        if status == "produced" and resource is not None and payload_bytes is not None:
            resources.append(resource)
            bytes_by_digest[resource.payload_blob["digest"]] = payload_bytes

    return resources, bytes_by_digest, warnings
