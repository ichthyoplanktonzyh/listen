"""Build the shared structured-reading representation from media text."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence


@dataclass(frozen=True)
class Sentence:
    """One transcript sentence with character offsets into the logical text."""

    id: str
    index: int
    start_char: int
    end_char: int
    text: str


@dataclass(frozen=True)
class Paragraph:
    """One transcript or subtitle block with exact character offsets."""

    id: str
    index: int
    start_char: int
    end_char: int
    sentence_ids: tuple[str, ...]


@dataclass(frozen=True)
class ReadingBlock:
    """One structured block in the media transcript hierarchy."""

    id: str
    kind: str
    parent_id: str | None
    order: int
    start_char: int
    end_char: int
    sentence_ids: tuple[str, ...]


@dataclass(frozen=True)
class StructuredText:
    """Text and anchors produced from an audio or video rendition."""

    text: str
    paragraphs: tuple[Paragraph, ...]
    sentences: tuple[Sentence, ...]
    blocks: tuple[ReadingBlock, ...]


@dataclass(frozen=True)
class ReadingStructure:
    structured_reading: dict[str, object]


def text_from_segments(segments: Sequence[str]) -> StructuredText:
    """Create stable sentence and paragraph anchors from ordered media text.

    A newline between segments belongs to the preceding sentence. This keeps
    each sentence's text span aligned with the transcript's logical text and
    lets its anchor be joined to the media time alignment independently.
    """
    text_parts: list[str] = []
    paragraphs: list[Paragraph] = []
    sentences: list[Sentence] = []
    cursor = 0
    for index, value in enumerate(segments):
        segment = str(value)
        start = cursor
        sentence_text = segment + ("\n" if index < len(segments) - 1 else "")
        sentence = Sentence(
            id=f"sentence-{index}",
            index=index,
            start_char=start,
            end_char=start + len(sentence_text),
            text=sentence_text,
        )
        sentences.append(sentence)
        paragraphs.append(
            Paragraph(
                id=f"block-{index}",
                index=index,
                start_char=start,
                end_char=start + len(segment),
                sentence_ids=(sentence.id,),
            )
        )
        text_parts.append(sentence_text)
        cursor = sentence.end_char

    text = "".join(text_parts)
    blocks = tuple(
        [
            ReadingBlock(
                id=paragraph.id,
                kind="paragraph",
                parent_id="block-root",
                order=paragraph.index,
                start_char=paragraph.start_char,
                end_char=paragraph.end_char,
                sentence_ids=paragraph.sentence_ids,
            )
            for paragraph in paragraphs
        ]
    )
    root = ReadingBlock(
        id="block-root",
        kind="root",
        parent_id=None,
        order=0,
        start_char=0,
        end_char=len(text),
        sentence_ids=tuple(sentence.id for sentence in sentences),
    )
    return StructuredText(
        text=text,
        paragraphs=tuple(paragraphs),
        sentences=tuple(sentences),
        blocks=(root, *blocks),
    )


def _char_to_byte_offsets(text: str) -> list[int]:
    offsets = [0]
    for character in text:
        offsets.append(offsets[-1] + len(character.encode("utf-8")))
    return offsets


def build_reading_structure(
    decoded: StructuredText,
    *,
    language: str,
) -> ReadingStructure:
    """Build the v1 structured-reading payload for transcript or subtitles."""
    byte_offsets = _char_to_byte_offsets(decoded.text)
    sentence_anchors = [
        {
            "anchor_id": sentence.id,
            "kind": "sentence",
            "start_offset": byte_offsets[sentence.start_char],
            "end_offset": byte_offsets[sentence.end_char],
        }
        for sentence in decoded.sentences
    ]
    block_anchors = [
        {
            "anchor_id": block.id,
            "kind": "block",
            "start_offset": byte_offsets[block.start_char],
            "end_offset": byte_offsets[block.end_char],
        }
        for block in decoded.blocks
        if block.kind != "root"
    ]
    payload_blocks = [
        {
            "block_id": block.id,
            "kind": block.kind,
            "order": block.order,
            "span_anchor_ids": list(block.sentence_ids),
            "parent_block_id": block.parent_id,
        }
        for block in decoded.blocks
    ]
    anchors = sorted(
        sentence_anchors + block_anchors,
        key=lambda anchor: (anchor["start_offset"], anchor["end_offset"]),
    )
    return ReadingStructure(
        structured_reading={
            "language": language,
            "text": decoded.text,
            "anchors": anchors,
            "blocks": payload_blocks,
            "spans": [],
            "document_mappings": [],
            "extensions": {},
        }
    )
