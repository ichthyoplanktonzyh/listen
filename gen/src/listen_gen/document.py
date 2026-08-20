"""Document to Structured Reading derivation.

Deterministic, semantic text extraction for the supported document families,
plus a provider-neutral optional OCR seam for scanned PDFs. Output is a pure
intermediate representation that the packager turns into exactly one
``structured-reading`` resource.

The logical text and its block hierarchy are the source of every downstream
production decision:

- plain text keeps byte identity with the source document (the only family
  that can honestly produce ``character_range`` document mappings);
- Markdown is parsed semantically: heading/paragraph structure is preserved,
  the extracted logical text is free of markup characters, and speech never
  receives markdown markers;
- HTML discards ``script``/``style``/``nav``/hidden content and preserves
  heading structure;
- EPUB preserves the spine order and chapter boundaries;
- a PDF with a text layer is extracted deterministically; a scanned PDF uses
  the configured OCR provider or abstains honestly.

Honesty rules:
- A document with no extractable text and no OCR provider abstains from the
  derivation; it is never treated as an import failure.
- ``document_mappings`` into the exact Document Rendition are produced only
  when they can be exact (byte-identical plain text); no other family
  fabricates source locators.
"""

from __future__ import annotations

import io
import re
import zipfile
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Callable, Protocol, Sequence

from .package import ConversionError

MAX_TEXT_BYTES = 8 * 1024 * 1024
MAX_CONTAINER_BYTES = 128 * 1024 * 1024

TEXT_FAMILIES = ("text/plain", "text/markdown", "text/html")
PDF_MEDIA_TYPES = ("application/pdf",)
EPUB_MEDIA_TYPES = ("application/epub+zip",)

BLOCK_KINDS = ("root", "book", "chapter", "section", "heading", "paragraph")


class DocumentDecodeError(ConversionError):
    """The document cannot be decoded into extractable text."""


class NoTextLayer(DocumentDecodeError):
    """The document carries no text layer (for example a scanned PDF)."""


class TextTooLarge(DocumentDecodeError):
    """The extracted text exceeds the safety limit."""


class ContainerTooLarge(DocumentDecodeError):
    """The document container exceeds the safety limit."""


@dataclass(frozen=True)
class Sentence:
    """One sentence unit: exact character offsets into the extracted text."""

    id: str
    index: int
    start_char: int
    end_char: int
    text: str


@dataclass(frozen=True)
class Paragraph:
    """One block unit: exact character offsets into the extracted text."""

    id: str
    index: int
    start_char: int
    end_char: int
    sentence_ids: tuple[str, ...]


@dataclass(frozen=True)
class ReadingBlock:
    """One structured block: kind, hierarchy, order, and exact ranges.

    ``order`` is the 0-based sibling order under ``parent_id``; the block
    tree has exactly one root block covering the whole text.
    """

    id: str
    kind: str
    parent_id: str | None
    order: int
    start_char: int
    end_char: int
    sentence_ids: tuple[str, ...]


@dataclass(frozen=True)
class ExtractedText:
    text: str
    paragraphs: tuple[Paragraph, ...]
    sentences: tuple[Sentence, ...]
    blocks: tuple[ReadingBlock, ...] = ()
    source_identical: bool = False

    @property
    def language_hint(self) -> str | None:
        return None


@dataclass(frozen=True)
class DecodedDocument:
    media_type: str
    text: str
    paragraphs: tuple[Paragraph, ...]
    sentences: tuple[Sentence, ...]
    blocks: tuple[ReadingBlock, ...]
    #: The exact text in the source document equals the extracted text.
    byte_identical: bool

    @property
    def source_identical(self) -> bool:
        return self.byte_identical


# ---------------------------------------------------------------------------
# Sentence and paragraph segmentation
# ---------------------------------------------------------------------------

_SENTENCE_END = re.compile(
    r"(?<=[\u3002\uff01\uff1f\u002e\u003f\u0021\u2026])[ \t\u3000]*"
)
_BLANK_LINE = re.compile(r"\s*\n")


def segment_text(text: str) -> tuple[tuple[Paragraph, ...], tuple[Sentence, ...]]:
    """Deterministic block (paragraph) and sentence segmentation.

    Paragraphs are non-empty lines; sentences split each paragraph at
    terminal punctuation. The sentence units cover the whole text without
    gaps: a line's trailing newline belongs to its last sentence, and the
    newline of a blank line belongs to the previous sentence. Character
    offsets are counted against the exact extracted ``text``.
    """
    paragraphs: list[Paragraph] = []
    sentence_rows: list[dict[str, object]] = []
    paragraph_index = 0
    sentence_index = 0
    offset = 0
    lines = text.split("\n")
    for line_index, raw_line in enumerate(lines):
        line_start = offset
        line_text_end = offset + len(raw_line)
        has_newline = line_index < len(lines) - 1
        if not raw_line.strip():
            if has_newline and sentence_rows:
                previous = sentence_rows[-1]
                previous["end_char"] = int(previous["end_char"]) + 1
                previous["text"] = str(previous["text"]) + "\n"
            offset = line_text_end + (1 if has_newline else 0)
            continue
        starts = [match.start() for match in _SENTENCE_END.finditer(raw_line)]
        bounds: list[tuple[int, int]] = []
        if starts:
            cursor = 0
            for end in starts:
                if end > cursor:
                    bounds.append((cursor, end))
                cursor = end
            if cursor < len(raw_line):
                bounds.append((cursor, len(raw_line)))
        else:
            bounds = [(0, len(raw_line))]
        # A terminal-punctuation match starts before the whitespace it
        # consumes. When that whitespace reaches the end of the line the
        # raw bounds above contain a second, whitespace-only "sentence".
        # Keep those exact source characters on the preceding sentence so
        # sentence anchors remain non-empty while still covering the source
        # text byte-for-byte.
        qualified_bounds: list[tuple[int, int]] = []
        for start, end in bounds:
            if raw_line[start:end].strip():
                qualified_bounds.append((start, end))
            elif qualified_bounds:
                previous_start, _ = qualified_bounds[-1]
                qualified_bounds[-1] = (previous_start, end)
        bounds = qualified_bounds
        sentence_ids: list[str] = []
        for index, (start, end) in enumerate(bounds):
            is_last = index == len(bounds) - 1
            end_char = line_start + end
            text_slice = raw_line[start:end]
            if is_last and has_newline:
                end_char += 1
                text_slice += "\n"
            sentence_id = f"sentence-{sentence_index}"
            sentence_index += 1
            sentence_rows.append(
                {
                    "id": sentence_id,
                    "index": sentence_index - 1,
                    "start_char": line_start + start,
                    "end_char": end_char,
                    "text": text_slice,
                }
            )
            sentence_ids.append(sentence_id)
        paragraph_id = f"block-{paragraph_index}"
        paragraph_index += 1
        paragraphs.append(
            Paragraph(
                id=paragraph_id,
                index=paragraph_index - 1,
                start_char=line_start,
                end_char=line_text_end,
                sentence_ids=tuple(sentence_ids),
            )
        )
        offset = line_text_end + (1 if has_newline else 0)
    return tuple(paragraphs), tuple(
        Sentence(
            id=str(row["id"]),
            index=int(row["index"]),
            start_char=int(row["start_char"]),
            end_char=int(row["end_char"]),
            text=str(row["text"]),
        )
        for row in sentence_rows
    )


def _split_single_line(line: str) -> list[tuple[int, int]]:
    """Sentence bounds within one line (no trailing newline).

    Trailing whitespace after terminal punctuation is not a separate sentence,
    but it remains owned by the preceding sentence. This keeps structured
    sentence spans an exact cover of their block text while avoiding empty
    residue anchors.
    """
    starts = [match.start() for match in _SENTENCE_END.finditer(line)]
    bounds: list[tuple[int, int]] = []
    if starts:
        cursor = 0
        for end in starts:
            if end > cursor and line[cursor:end].strip():
                bounds.append((cursor, end))
            cursor = end
        if cursor < len(line):
            if line[cursor:].strip():
                bounds.append((cursor, len(line)))
            elif bounds:
                previous_start, _ = bounds[-1]
                bounds[-1] = (previous_start, len(line))
    elif line.strip():
        bounds = [(0, len(line))]
    return bounds


def _segment_raw_blocks(
    text: str, raw_blocks: Sequence[tuple[str | None, str, str | None, str]]
) -> tuple[tuple[ReadingBlock, ...], tuple[Sentence, ...]]:
    """Segment structured block texts into sentences with exact offsets.

    ``raw_blocks`` are ``(block_id, kind, parent_id, block_text)`` tuples; a
    ``None`` block id gets a deterministic ``block-<index>`` id. Leaf block
    texts join into ``text`` with ``"\\n"`` separators, so the trailing
    newline of every leaf block except the last belongs to that block's final
    sentence. Empty container blocks (for example an EPUB ``chapter``) do not
    contribute text; their span and sentence ids are derived from their
    descendants.

    The input block text is local to each block, but every emitted sentence is
    anchored against the complete logical text. Keeping the layout pass
    separate from sentence segmentation is important here: a sentence in the
    second Markdown/HTML/EPUB block must not accidentally start at offset zero.
    """
    container_kinds = frozenset({"root", "book", "chapter", "section"})

    def contributes(kind: str, block_text: str) -> bool:
        # A synthetic hierarchy block is metadata, never another copy of its
        # descendants' content. Empty leaf blocks likewise have no logical
        # text and are ignored by the deterministic layout.
        return kind not in container_kinds and bool(block_text)

    expected_text = "\n".join(
        block_text
        for _, kind, _, block_text in raw_blocks
        if contributes(kind, block_text)
    )
    if expected_text != text:
        raise DocumentDecodeError(
            "structured document blocks do not match their logical text"
        )

    # Resolve ids, parents, and sibling order before calculating spans. This
    # lets a container appear before its children (the EPUB chapter shape)
    # without making its range depend on processing order.
    rows: list[dict[str, object]] = []
    sibling_orders: dict[str, int] = {}
    seen_ids: set[str] = set()
    for index, (block_id, kind, parent_id, block_text) in enumerate(raw_blocks):
        resolved_id = block_id or f"block-{index}"
        if resolved_id in seen_ids or resolved_id == "block-root":
            raise DocumentDecodeError(
                f"structured document block id is not unique: {resolved_id}"
            )
        seen_ids.add(resolved_id)
        resolved_parent = parent_id or "block-root"
        order = sibling_orders.get(resolved_parent, 0)
        sibling_orders[resolved_parent] = order + 1
        rows.append(
            {
                "id": resolved_id,
                "kind": kind,
                "parent_id": resolved_parent,
                "order": order,
                "block_text": block_text,
                "contributes": contributes(kind, block_text),
            }
        )

    contributing_indices = [
        index for index, row in enumerate(rows) if bool(row["contributes"])
    ]
    layouts: dict[int, tuple[int, int]] = {}
    cursor = 0
    for contribution_index, row_index in enumerate(contributing_indices):
        block_text = str(rows[row_index]["block_text"])
        start_char = cursor
        end_char = start_char + len(block_text)
        if contribution_index < len(contributing_indices) - 1:
            end_char += 1
        layouts[row_index] = (start_char, end_char)
        cursor = end_char
    if cursor != len(text):  # defensive: the join check above should imply this
        raise DocumentDecodeError(
            "structured document block layout does not cover logical text"
        )

    sentences: list[Sentence] = []
    own_sentence_ids: dict[int, list[str]] = {}
    sentence_index = 0
    for row_index in contributing_indices:
        row = rows[row_index]
        block_text = str(row["block_text"])
        block_start, _ = layouts[row_index]
        sentence_ids: list[str] = []
        line_cursor = 0
        lines = block_text.split("\n")
        for line_index, raw_line in enumerate(lines):
            line_has_newline = line_index < len(lines) - 1
            if not raw_line.strip():
                # Preserve blank-line ownership, but only within this block.
                # A chapter's empty metadata row must never mutate the last
                # sentence of the preceding chapter.
                if line_has_newline and sentence_ids:
                    previous = sentences[-1]
                    previous = Sentence(
                        id=previous.id,
                        index=previous.index,
                        start_char=previous.start_char,
                        end_char=previous.end_char + 1,
                        text=previous.text + "\n",
                    )
                    sentences[-1] = previous
                line_cursor += len(raw_line) + (1 if line_has_newline else 0)
                continue
            for bound_start, bound_end in _split_single_line(raw_line):
                is_last_line_sentence = bound_end == len(raw_line)
                slice_start = block_start + line_cursor + bound_start
                slice_end = block_start + line_cursor + bound_end
                text_slice = raw_line[bound_start:bound_end]
                if is_last_line_sentence and line_has_newline:
                    slice_end += 1
                    text_slice += "\n"
                sentence_id = f"sentence-{sentence_index}"
                sentence_index += 1
                sentences.append(
                    Sentence(
                        id=sentence_id,
                        index=sentence_index - 1,
                        start_char=slice_start,
                        end_char=slice_end,
                        text=text_slice,
                    )
                )
                sentence_ids.append(sentence_id)
            line_cursor += len(raw_line) + (1 if line_has_newline else 0)
        if sentence_ids:
            # The layout gives every non-final leaf block a separator newline.
            # Attach that separator (and any deterministic trailing residue)
            # to the block's final sentence so sentence spans exactly cover
            # the same text as their block span.
            _, block_end = layouts[row_index]
            previous = sentences[-1]
            if previous.end_char < block_end:
                suffix = text[previous.end_char:block_end]
                sentences[-1] = Sentence(
                    id=previous.id,
                    index=previous.index,
                    start_char=previous.start_char,
                    end_char=block_end,
                    text=previous.text + suffix,
                )
        own_sentence_ids[row_index] = sentence_ids

    children: dict[str, list[int]] = {}
    for row_index, row in enumerate(rows):
        parent_id = str(row["parent_id"])
        children.setdefault(parent_id, []).append(row_index)

    spans: dict[int, tuple[int, int]] = dict(layouts)
    resolved_sentence_ids: dict[int, tuple[str, ...]] = {
        row_index: tuple(sentence_ids)
        for row_index, sentence_ids in own_sentence_ids.items()
    }
    sentence_order = {
        sentence.id: sentence.index for sentence in sentences
    }

    def resolve_container(row_index: int) -> tuple[tuple[int, int], tuple[str, ...]]:
        if row_index in spans and row_index in resolved_sentence_ids:
            return spans[row_index], resolved_sentence_ids[row_index]
        row_id = str(rows[row_index]["id"])
        child_spans: list[tuple[int, int]] = []
        child_sentence_ids: list[str] = []
        for child_index in children.get(row_id, []):
            child_span, child_ids = resolve_container(child_index)
            if child_index in spans or child_span != (0, 0):
                child_spans.append(child_span)
            child_sentence_ids.extend(child_ids)
        if row_index in spans:
            span = spans[row_index]
        elif child_spans:
            span = (
                min(start for start, _ in child_spans),
                max(end for _, end in child_spans),
            )
            spans[row_index] = span
        else:
            raise DocumentDecodeError(
                f"structured document container has no content: {row_id}"
            )
        if row_index in resolved_sentence_ids:
            sentence_ids = resolved_sentence_ids[row_index]
        else:
            sentence_ids = tuple(
                sorted(set(child_sentence_ids), key=sentence_order.__getitem__)
            )
            resolved_sentence_ids[row_index] = sentence_ids
        return span, sentence_ids

    for row_index in range(len(rows)):
        resolve_container(row_index)

    blocks: list[ReadingBlock] = []
    for row_index, row in enumerate(rows):
        start_char, end_char = spans[row_index]
        if not 0 <= start_char <= end_char <= len(text):
            raise DocumentDecodeError(
                f"structured document block span is invalid: {row['id']}"
            )
        blocks.append(
            ReadingBlock(
                id=str(row["id"]),
                kind=str(row["kind"]),
                parent_id=str(row["parent_id"]),
                order=int(row["order"]),
                start_char=start_char,
                end_char=end_char,
                sentence_ids=resolved_sentence_ids.get(row_index, ()),
            )
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
    return (root, *blocks), tuple(sentences)


def _blocks_from_paragraphs(
    paragraphs: Sequence[Paragraph], sentences: Sequence[Sentence]
) -> tuple[ReadingBlock, ...]:
    """Blocks for paragraph-segmented families (plain text, PDF, transcript)."""
    blocks: list[ReadingBlock] = []
    for index, paragraph in enumerate(paragraphs):
        blocks.append(
            ReadingBlock(
                id=paragraph.id,
                kind="paragraph",
                parent_id="block-root",
                order=index,
                start_char=paragraph.start_char,
                end_char=paragraph.end_char,
                sentence_ids=paragraph.sentence_ids,
            )
        )
    root = ReadingBlock(
        id="block-root",
        kind="root",
        parent_id=None,
        order=0,
        start_char=0,
        end_char=len("".join(sentence.text for sentence in sentences))
        if sentences
        else 0,
        sentence_ids=tuple(sentence.id for sentence in sentences),
    )
    return (root, *blocks)


# ---------------------------------------------------------------------------
# Text family decoders
# ---------------------------------------------------------------------------


def _strip_bom(raw: bytes) -> bytes:
    for prefix in (b"\xef\xbb\xbf", b"\xff\xfe", b"\xfe\xff"):
        if raw.startswith(prefix):
            return raw[len(prefix):]
    return raw


def decode_text_family(raw: bytes) -> str:
    raw = _strip_bom(raw)
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise DocumentDecodeError(
            "document text is not valid UTF-8"
        ) from error
    if not text.strip():
        raise DocumentDecodeError("document contains no extractable text")
    return text


# ---------------------------------------------------------------------------
# Markdown
# ---------------------------------------------------------------------------

_HEADING_RE = re.compile(r"^(#{1,6})\s+(.*)$")
_LIST_RE = re.compile(r"^(\s*[-*+]\s+|\s*\d{1,9}[.)]\s+)(.*)$")
_BLOCKQUOTE_RE = re.compile(r"^>\s?(.*)$")
_FENCE_RE = re.compile(r"^(\s*)(```|~~~)(.*)$")

_INLINE_CODE_RE = re.compile(r"`([^`]*)`")
_INLINE_IMAGE_RE = re.compile(r"!\[([^\]]*)\]\([^)]*\)")
_INLINE_LINK_RE = re.compile(r"\[([^\]]*)\]\([^)]*\)")
_INLINE_EMPHASIS_RE = re.compile(r"(\*\*|__|\*|_)(?=[^\s])(.*?)(?<=[^\s])\1")


def strip_markdown_inline(text: str) -> str:
    """Remove Markdown markup while keeping the label text.

    Inline code, images, links, and emphasis markers are stripped; the
    visible label text survives so the logical text is markup-free.
    """
    stripped = _INLINE_CODE_RE.sub(r"\1", text)
    stripped = _INLINE_IMAGE_RE.sub(r"\1", stripped)
    stripped = _INLINE_LINK_RE.sub(r"\1", stripped)
    for _ in range(4):
        replaced = _INLINE_EMPHASIS_RE.sub(r"\2", stripped)
        if replaced == stripped:
            break
        stripped = replaced
    return stripped


def parse_markdown(raw: bytes) -> tuple[str, list[tuple[str | None, str, str | None, str]]]:
    """Parse Markdown into ``(text, raw_blocks)``.

    ``raw_blocks`` are ``(kind, parent_id, block_text)``; every block text is
    free of Markdown markers. Headings keep their hierarchy intent as
    ``heading`` blocks; everything else is a ``paragraph``. The block texts
    join into ``text`` with ``"\\n"`` separators.
    """
    text = decode_text_family(raw)
    if len(text.encode("utf-8")) > MAX_TEXT_BYTES:
        raise TextTooLarge("extracted text exceeds the safety limit")
    pending: list[str] = []
    blocks: list[tuple[str | None, str, str | None, str]] = []
    in_fence: str | None = None
    fence_marker: str = ""

    def flush() -> None:
        if pending:
            content = " ".join(
                line.strip() for line in pending if line.strip()
            )
            if content:
                blocks.append((None, "paragraph", None, content))
            pending.clear()

    for raw_line in text.split("\n"):
        if in_fence is not None:
            if raw_line.strip().startswith(fence_marker) or raw_line.strip() == in_fence:
                flush()
                in_fence = None
                fence_marker = ""
            else:
                pending.append(raw_line)
            continue
        fence_match = _FENCE_RE.match(raw_line)
        if fence_match and raw_line.strip().startswith(("```", "~~~")):
            flush()
            in_fence = fence_match.group(2)
            fence_marker = in_fence
            continue
        heading = _HEADING_RE.match(raw_line)
        if heading:
            flush()
            content = strip_markdown_inline(heading.group(2).strip())
            if content:
                blocks.append((None, "heading", None, content))
            continue
        quote = _BLOCKQUOTE_RE.match(raw_line)
        if quote:
            pending.append(strip_markdown_inline(quote.group(1)))
            continue
        listed = _LIST_RE.match(raw_line)
        if listed:
            pending.append(strip_markdown_inline(listed.group(2)))
            continue
        if not raw_line.strip():
            flush()
            continue
        pending.append(strip_markdown_inline(raw_line))
    flush()
    if not blocks:
        raise DocumentDecodeError("document Markdown contains no extractable text")
    return "\n".join(content for _, _, _, content in blocks), blocks


# ---------------------------------------------------------------------------
# HTML
# ---------------------------------------------------------------------------


class _HtmlTextExtractor(HTMLParser):
    """Extract block text while discarding scripts, styles, and hidden content.

    Mirrors the App's restricted renderer policy: no content from ``script``,
    ``style``, ``noscript``, ``iframe``, ``svg``, ``template``, ``head``, or
    ``nav`` elements reaches the extracted text. Heading elements become
    ``heading`` blocks; other block elements become ``paragraph`` blocks.
    """

    _DISCARDED = frozenset(
        {
            "script",
            "style",
            "noscript",
            "iframe",
            "svg",
            "template",
            "head",
            "nav",
        }
    )
    _HEADING_TAGS = frozenset({"h1", "h2", "h3", "h4", "h5", "h6"})
    _PARAGRAPH_TAGS = frozenset(
        {
            "p",
            "div",
            "section",
            "article",
            "li",
            "blockquote",
            "pre",
            "tr",
        }
    )

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[tuple[str, list[str]]] = []
        self._skip = 0
        self._current: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in self._DISCARDED:
            self._skip += 1
        if tag in self._HEADING_TAGS:
            self._new_part("heading")
        elif tag in self._PARAGRAPH_TAGS or tag == "br":
            self._new_part("paragraph")

    def handle_endtag(self, tag: str) -> None:
        if tag in self._DISCARDED and self._skip > 0:
            self._skip -= 1

    def handle_data(self, data: str) -> None:
        if self._skip == 0:
            if self._current is None:
                self._new_part("paragraph")
            self._current.append(data)

    def _new_part(self, kind: str) -> None:
        if self._current is not None and "".join(self._current).strip():
            self.parts.append((self._current_kind, self._current))
        self._current_kind = kind
        self._current = []

    def finish(self) -> list[tuple[str, str]]:
        if self._current is not None and "".join(self._current).strip():
            self.parts.append((self._current_kind, self._current))
        result: list[tuple[str, str]] = []
        for kind, pieces in self.parts:
            content = " ".join("".join(pieces).split())
            if content:
                result.append((kind, content))
        return result


def extract_html_blocks(raw: bytes) -> tuple[str, list[tuple[str | None, str, str | None, str]]]:
    """Extract ``(text, raw_blocks)`` from an HTML document."""
    text = decode_text_family(raw)
    extractor = _HtmlTextExtractor()
    try:
        extractor.feed(text)
    except Exception as error:  # pragma: no cover - parser robustness
        raise DocumentDecodeError("document HTML could not be parsed") from error
    parts = extractor.finish()
    if not parts:
        raise DocumentDecodeError("document HTML contains no extractable text")
    raw_blocks = [
        (None, kind, None, content)
        for kind, content in parts
        if kind in ("heading", "paragraph")
    ]
    if not raw_blocks:
        raise DocumentDecodeError("document HTML contains no extractable text")
    return "\n".join(content for _, _, _, content in raw_blocks), raw_blocks


def decode_html(raw: bytes) -> str:
    return extract_html_blocks(raw)[0]


# ---------------------------------------------------------------------------
# EPUB decoder
# ---------------------------------------------------------------------------


class _EpubManifestEntry:
    def __init__(self, identifier: str, href: str, media_type: str):
        self.identifier = identifier
        self.href = href
        self.media_type = media_type


def _zip_total_size(archive: zipfile.ZipFile) -> int:
    return sum(info.file_size for info in archive.infolist())


def _resolve_opf_path(opf_dir: str, href: str) -> str:
    """Resolve an OPF-relative href inside the OPF directory with traversal
    protection."""
    combined = (opf_dir + "/" + href).strip("/")
    parts = [part for part in combined.split("/") if part not in ("", ".")]
    resolved: list[str] = []
    for part in parts:
        if part == "..":
            if resolved:
                resolved.pop()
            continue
        resolved.append(part)
    return "/".join(resolved)


def _epub_spine_blocks(
    archive: zipfile.ZipFile,
    root_path: str,
) -> list[tuple[str | None, str, str | None, str]]:
    """Decode an EPUB spine into structured blocks.

    The spine order and the OPF-relative href resolution follow the exact
    container declarations; each spine item becomes a ``chapter`` container
    whose heading/paragraph blocks are its children. The chapter tuple has an
    empty text contribution by design: its range is derived later from the
    child ranges, so the chapter cannot duplicate the child text in speech or
    structured reading. Traversal outside the OPF directory is rejected.
    """
    try:
        opf_entry = next(
            name for name in archive.namelist() if name == root_path
        )
    except StopIteration as error:
        raise DocumentDecodeError(
            "EPUB package document was not found in the container"
        ) from error
    try:
        opf = archive.read(opf_entry).decode("utf-8")
    except (KeyError, UnicodeDecodeError) as error:
        raise DocumentDecodeError("EPUB package document could not be read") from error

    manifest: dict[str, _EpubManifestEntry] = {}
    spine_items: list[str] = []
    for match in re.finditer(r"<item\b[^>]*/?>", opf):
        tag = match.group(0)
        attributes = dict(
            re.findall(r'([A-Za-z_:][\w:.-]*)\s*=\s*"([^"]*)"', tag)
        )
        if "id" in attributes and "href" in attributes:
            manifest[attributes["id"]] = _EpubManifestEntry(
                attributes["id"],
                attributes["href"],
                attributes.get("media-type", ""),
            )
    for match in re.finditer(r'<itemref\b[^>]*/?>', opf):
        tag = match.group(0)
        idref = re.search(r'idref\s*=\s*"([^"]*)"', tag)
        if idref:
            spine_items.append(idref.group(1))
    if not spine_items:
        raise DocumentDecodeError("EPUB spine is empty")

    opf_dir = opf_entry.rsplit("/", 1)[0]
    blocks: list[tuple[str | None, str, str | None, str]] = []
    chapter_index = 0
    for item_id in spine_items:
        entry = manifest.get(item_id)
        if entry is None:
            continue
        href = entry.href.split("#", 1)[0]
        if not href:
            continue
        path = _resolve_opf_path(opf_dir, href)
        try:
            content = archive.read(path)
        except KeyError:
            raise DocumentDecodeError(
                f"EPUB spine item is missing from the container: {href}"
            )
        content_text = content.decode("utf-8", errors="replace")
        extractor = _HtmlTextExtractor()
        extractor.feed(content_text)
        parts = extractor.finish()
        if not parts:
            continue
        chapter_id = f"chapter-{chapter_index}"
        chapter_index += 1
        chapter_parts: list[tuple[str | None, str, str | None, str]] = [
            (None, kind, chapter_id, content)
            for kind, content in parts
            if kind in ("heading", "paragraph")
        ]
        if not chapter_parts:
            continue
        # A chapter is hierarchy metadata, not another copy of the content.
        # ``_segment_raw_blocks`` derives its span and sentence ids from these
        # child blocks after laying out the leaf text globally.
        blocks.append((chapter_id, "chapter", None, ""))
        blocks.extend(chapter_parts)
    if not blocks:
        raise DocumentDecodeError("EPUB contains no extractable text")
    return blocks


def _logical_text_from_raw_blocks(
    raw_blocks: Sequence[tuple[str | None, str, str | None, str]],
) -> str:
    """Join only text-bearing structured blocks in deterministic order.

    Empty synthetic containers are intentionally omitted. Keeping this helper
    beside the EPUB decoder makes the same rule explicit at the call site and
    prevents a future container from reintroducing duplicate logical text.
    """
    container_kinds = frozenset({"root", "book", "chapter", "section"})
    return "\n".join(
        block_text
        for _, kind, _, block_text in raw_blocks
        if kind not in container_kinds and bool(block_text)
    )


def decode_epub(raw: bytes) -> str:
    if len(raw) > MAX_CONTAINER_BYTES:
        raise ContainerTooLarge("EPUB container exceeds the safety limit")
    try:
        archive = zipfile.ZipFile(io.BytesIO(raw))
    except zipfile.BadZipFile as error:
        raise DocumentDecodeError("EPUB container is not a valid ZIP archive") from error
    with archive:
        if _zip_total_size(archive) > MAX_CONTAINER_BYTES:
            raise ContainerTooLarge("EPUB container exceeds the safety limit")
        names = archive.namelist()
        if "mimetype" not in names or archive.read("mimetype") != b"application/epub+zip":
            raise DocumentDecodeError("EPUB container lacks a valid mimetype entry")
        try:
            container = archive.read("META-INF/container.xml").decode("utf-8")
        except KeyError as error:
            raise DocumentDecodeError(
                "EPUB container lacks META-INF/container.xml"
            ) from error
        root_match = re.search(
            r'full-path\s*=\s*"([^"]*\.opf)"', container
        )
        if root_match is None:
            raise DocumentDecodeError(
                "EPUB container.xml does not name a package document"
            )
        root_path = root_match.group(1)
        blocks = _epub_spine_blocks(archive, root_path)
    return _logical_text_from_raw_blocks(blocks)


# ---------------------------------------------------------------------------
# PDF text layer and optional OCR seam
# ---------------------------------------------------------------------------


class OcrProvider(Protocol):
    """Optional OCR path for scanned PDFs.

    A provider receives the raw document bytes and must return the recognized
    text, or raise :class:`DocumentDecodeError` to abstain honestly.
    """

    def extract_text(self, raw: bytes, media_type: str) -> str: ...


class NoOcrProvider:
    """Default OCR seam: never recognizes text."""

    def extract_text(self, raw: bytes, media_type: str) -> str:
        raise NoTextLayer("the PDF has no text layer and no OCR provider is configured")


class FixtureOcrProvider:
    """OCR seam that replays committed recognized text (tests only)."""

    def __init__(self, fixture_path: Path):
        self.fixture_path = fixture_path
        if not fixture_path.is_file():
            raise ValueError("ocr fixture must be a regular file")

    def extract_text(self, raw: bytes, media_type: str) -> str:
        try:
            text = self.fixture_path.read_text(encoding="utf-8")
        except OSError as error:
            raise DocumentDecodeError("the OCR fixture could not be read") from error
        if not text.strip():
            raise NoTextLayer("the OCR fixture contains no text")
        return text


def _render_pdf_to_images(raw: bytes) -> list[Any]:
    """Render a PDF into PIL images for OCR processing."""
    # 1. Try pypdfium2 (fastest & standalone)
    try:
        import pypdfium2 as pdfium
        doc = pdfium.PdfDocument(raw)
        images = []
        for page in doc:
            bitmap = page.render(scale=2.0)
            images.append(bitmap.to_pil())
        if images:
            return images
    except (ImportError, Exception):
        pass

    # 2. Try pdf2image
    try:
        from pdf2image import convert_from_bytes
        images = convert_from_bytes(raw, dpi=150)
        if images:
            return images
    except (ImportError, Exception):
        pass

    # 3. Try extracting embedded images from pypdf
    try:
        from pypdf import PdfReader
        from PIL import Image
        reader = PdfReader(io.BytesIO(raw))
        images = []
        for page in reader.pages:
            for img_file in page.images:
                images.append(Image.open(io.BytesIO(img_file.data)))
        if images:
            return images
    except (ImportError, Exception):
        pass

    raise DocumentDecodeError(
        "PDF page image rendering is unavailable. Install 'pypdfium2' or 'pdf2image' to enable OCR on PDF documents."
    )


class SuryaOcrProvider:
    """Document OCR provider based on Surya OCR with layout analysis and reading order reconstruction."""

    name = "surya"

    def __init__(
        self,
        *,
        langs: Sequence[str] = ("en", "zh"),
        device: str | None = None,
        engine: Callable[[list[Any]], str] | None = None,
        pdf_renderer: Callable[[bytes], list[Any]] | None = None,
    ):
        self.langs = list(langs)
        self.device = device
        self.engine = engine
        self.pdf_renderer = pdf_renderer

    def extract_text(self, raw: bytes, media_type: str) -> str:
        render_fn = self.pdf_renderer or _render_pdf_to_images
        images = render_fn(raw)
        if not images:
            raise NoTextLayer("the PDF contains no renderable pages for OCR")

        if self.engine is not None:
            text = self.engine(images)
            if not text.strip():
                raise NoTextLayer("the OCR provider detected no text")
            return text

        try:
            from surya.ocr import run_ocr
            from surya.model.detection.model import (
                load_model as load_det_model,
                load_processor as load_det_proc,
            )
            from surya.model.recognition.model import (
                load_model as load_rec_model,
                load_processor as load_rec_proc,
            )

            det_processor, det_model = load_det_proc(), load_det_model(device=self.device)
            rec_processor, rec_model = load_rec_proc(), load_rec_model(device=self.device)

            langs_list = [self.langs for _ in images]
            predictions = run_ocr(
                images,
                langs_list,
                det_model,
                det_processor,
                rec_model,
                rec_processor,
            )

            page_texts: list[str] = []
            for pred in predictions:
                lines = [line.text for line in getattr(pred, "text_lines", []) if line.text.strip()]
                if lines:
                    page_texts.append("\n".join(lines))

            full_text = "\n\n".join(page_texts).strip()
            if not full_text:
                raise NoTextLayer("Surya OCR could not detect any text in the document")
            return full_text
        except ImportError as error:
            raise DocumentDecodeError(
                "Surya OCR is not installed. Install with 'pip install surya-ocr pypdfium2 pillow'"
            ) from error
        except NoTextLayer:
            raise
        except Exception as error:
            raise DocumentDecodeError(f"Surya OCR failed during document extraction: {error}") from error


class RapidOcrProvider:
    """Fast, lightweight document OCR provider using RapidOCR (PP-OCR ONNX)."""

    name = "rapidocr"

    def __init__(
        self,
        *,
        params: dict[str, Any] | None = None,
        engine: Callable[[list[Any]], str] | None = None,
        pdf_renderer: Callable[[bytes], list[Any]] | None = None,
    ):
        self.params = params or {}
        self.engine = engine
        self.pdf_renderer = pdf_renderer

    def extract_text(self, raw: bytes, media_type: str) -> str:
        render_fn = self.pdf_renderer or _render_pdf_to_images
        images = render_fn(raw)
        if not images:
            raise NoTextLayer("the PDF contains no renderable pages for OCR")

        if self.engine is not None:
            text = self.engine(images)
            if not text.strip():
                raise NoTextLayer("the OCR provider detected no text")
            return text

        try:
            import numpy as np
            from rapidocr_onnxruntime import RapidOCR

            ocr_engine = RapidOCR(**self.params)
            page_texts: list[str] = []
            for img in images:
                img_np = np.array(img) if not isinstance(img, np.ndarray) else img
                result, _ = ocr_engine(img_np)
                if result:
                    lines = [item[1] for item in result if item and len(item) > 1 and item[1].strip()]
                    if lines:
                        page_texts.append("\n".join(lines))

            full_text = "\n\n".join(page_texts).strip()
            if not full_text:
                raise NoTextLayer("RapidOCR could not detect any text in the document")
            return full_text
        except ImportError as error:
            raise DocumentDecodeError(
                "RapidOCR is not installed. Install with 'pip install rapidocr-onnxruntime pypdfium2 pillow'"
            ) from error
        except NoTextLayer:
            raise
        except Exception as error:
            raise DocumentDecodeError(f"RapidOCR failed during document extraction: {error}") from error
        except NoTextLayer:
            raise
        except Exception as error:
            raise DocumentDecodeError(f"RapidOCR failed during document extraction: {error}") from error


def decode_pdf(raw: bytes, ocr: OcrProvider | None = None) -> str:
    """Extract the PDF text layer; fall back to the configured OCR provider."""
    try:
        from pypdf import PdfReader
    except ImportError as error:  # pragma: no cover
        raise DocumentDecodeError("PDF text extraction is unavailable") from error
    try:
        reader = PdfReader(io.BytesIO(raw))
        if reader.is_encrypted:
            raise NoTextLayer("the PDF is encrypted")
        parts: list[str] = []
        for page in reader.pages:
            try:
                page_text = page.extract_text() or ""
            except Exception:
                page_text = ""
            if page_text.strip():
                parts.append(page_text)
    except NoTextLayer:
        raise
    except Exception as error:
        raise DocumentDecodeError("the PDF could not be read") from error
    if parts:
        return "\n\n".join(parts)
    provider = ocr or NoOcrProvider()
    return provider.extract_text(raw, PDF_MEDIA_TYPES[0])


# ---------------------------------------------------------------------------
# Family dispatch
# ---------------------------------------------------------------------------


def _assemble_document(
    media_type: str,
    text: str,
    sentences: Sequence[Sentence],
    paragraphs: Sequence[Paragraph],
    blocks: Sequence[ReadingBlock],
    byte_identical: bool,
) -> DecodedDocument:
    if not text.strip():
        raise DocumentDecodeError("document contains no extractable text")
    return DecodedDocument(
        media_type=media_type,
        text=text,
        paragraphs=tuple(paragraphs),
        sentences=tuple(sentences),
        blocks=tuple(blocks),
        byte_identical=byte_identical,
    )


def _paragraphs_from_blocks(
    blocks: Sequence[ReadingBlock],
) -> tuple[Paragraph, ...]:
    return tuple(
        Paragraph(
            id=block.id,
            index=index,
            start_char=block.start_char,
            end_char=block.end_char,
            sentence_ids=block.sentence_ids,
        )
        for index, block in enumerate(blocks)
        if block.kind != "root"
    )


def decode_document(
    raw: bytes,
    media_type: str,
    *,
    ocr: OcrProvider | None = None,
) -> DecodedDocument:
    """Decode one exact Document Rendition into extractable text.

    ``byte_identical`` reports whether the extracted text is byte-for-byte
    the source document text (plain text only), which is the only honest
    basis for source locator mappings.
    """
    if media_type == "text/plain":
        text = decode_text_family(raw)
        if len(text.encode("utf-8")) > MAX_TEXT_BYTES:
            raise TextTooLarge("extracted text exceeds the safety limit")
        paragraphs, sentences = segment_text(text)
        blocks = _blocks_from_paragraphs(paragraphs, sentences)
        return _assemble_document(
            media_type, text, sentences, paragraphs, blocks, byte_identical=True
        )
    if media_type == "text/markdown":
        text, raw_blocks = parse_markdown(raw)
        blocks, sentences = _segment_raw_blocks(text, raw_blocks)
        paragraphs = _paragraphs_from_blocks(blocks)
        return _assemble_document(
            media_type, text, sentences, paragraphs, blocks, byte_identical=False
        )
    if media_type == "text/html":
        text, raw_blocks = extract_html_blocks(raw)
        blocks, sentences = _segment_raw_blocks(text, raw_blocks)
        paragraphs = _paragraphs_from_blocks(blocks)
        return _assemble_document(
            media_type, text, sentences, paragraphs, blocks, byte_identical=False
        )
    if media_type in EPUB_MEDIA_TYPES:
        if len(raw) > MAX_CONTAINER_BYTES:
            raise ContainerTooLarge("EPUB container exceeds the safety limit")
        try:
            archive = zipfile.ZipFile(io.BytesIO(raw))
        except zipfile.BadZipFile as error:
            raise DocumentDecodeError(
                "EPUB container is not a valid ZIP archive"
            ) from error
        with archive:
            if _zip_total_size(archive) > MAX_CONTAINER_BYTES:
                raise ContainerTooLarge("EPUB container exceeds the safety limit")
            names = archive.namelist()
            if (
                "mimetype" not in names
                or archive.read("mimetype") != b"application/epub+zip"
            ):
                raise DocumentDecodeError(
                    "EPUB container lacks a valid mimetype entry"
                )
            try:
                container = archive.read("META-INF/container.xml").decode("utf-8")
            except KeyError as error:
                raise DocumentDecodeError(
                    "EPUB container lacks META-INF/container.xml"
                ) from error
            root_match = re.search(
                r'full-path\s*=\s*"([^"]*\.opf)"', container
            )
            if root_match is None:
                raise DocumentDecodeError(
                    "EPUB container.xml does not name a package document"
                )
            root_path = root_match.group(1)
            raw_blocks = _epub_spine_blocks(archive, root_path)
        text = _logical_text_from_raw_blocks(raw_blocks)
        blocks, sentences = _segment_raw_blocks(text, raw_blocks)
        paragraphs = _paragraphs_from_blocks(blocks)
        return _assemble_document(
            media_type, text, sentences, paragraphs, blocks, byte_identical=False
        )
    if media_type in PDF_MEDIA_TYPES:
        text = decode_pdf(raw, ocr=ocr)
        if len(text.encode("utf-8")) > MAX_TEXT_BYTES:
            raise TextTooLarge("extracted text exceeds the safety limit")
        paragraphs, sentences = segment_text(text)
        blocks = _blocks_from_paragraphs(paragraphs, sentences)
        return _assemble_document(
            media_type, text, sentences, paragraphs, blocks, byte_identical=False
        )
    raise DocumentDecodeError(f"unsupported document media type: {media_type}")


# ---------------------------------------------------------------------------
# Reading structure (the single structured_reading payload)
# ---------------------------------------------------------------------------


def _char_to_byte_offsets(text: str) -> list[int]:
    """UTF-8 byte offset of every character boundary in ``text``."""
    encoded = text.encode("utf-8")
    offsets = [0]
    for character in text:
        offsets.append(offsets[-1] + len(character.encode("utf-8")))
    return offsets


def _blocks_for(decoded) -> tuple[ReadingBlock, ...]:
    """The decoded document's structured blocks (with a root fallback)."""
    blocks = getattr(decoded, "blocks", ())
    if blocks:
        return blocks
    return _blocks_from_paragraphs(decoded.paragraphs, decoded.sentences)


@dataclass(frozen=True)
class ReadingStructure:
    structured_reading: dict[str, object]


def build_reading_structure(
    decoded,
    *,
    language: str,
    rendition_id: str,
) -> ReadingStructure:
    """Build the deterministic structured-reading payload for one rendition.

    Byte offsets in the structured reading anchors refer to the exact logical
    ``text`` carried by the payload itself (the resource is self-contained).
    Source locator mappings are produced only when the extraction is
    byte-identical.
    """
    byte_offsets = _char_to_byte_offsets(decoded.text)
    blocks = _blocks_for(decoded)
    sentence_anchors: list[dict[str, object]] = []
    block_anchors: list[dict[str, object]] = []
    for sentence in decoded.sentences:
        sentence_anchors.append(
            {
                "anchor_id": sentence.id,
                "kind": "sentence",
                "start_offset": byte_offsets[sentence.start_char],
                "end_offset": byte_offsets[sentence.end_char],
            }
        )
    for block in blocks:
        if block.kind == "root":
            continue
        block_anchors.append(
            {
                "anchor_id": block.id,
                "kind": "block",
                "start_offset": byte_offsets[block.start_char],
                "end_offset": byte_offsets[block.end_char],
            }
        )
    payload_blocks: list[dict[str, object]] = []
    for block in blocks:
        payload_blocks.append(
            {
                "block_id": block.id,
                "kind": block.kind,
                "order": block.order,
                "span_anchor_ids": list(block.sentence_ids),
                "parent_block_id": block.parent_id,
            }
        )
    document_mappings: list[dict[str, object]] = []
    if decoded.source_identical:
        for block in blocks:
            if block.kind == "root":
                continue
            start = byte_offsets[block.start_char]
            end = byte_offsets[block.end_char]
            document_mappings.append(
                {
                    "anchor_id": block.id,
                    "rendition_id": rendition_id,
                    "locator": {
                        "kind": "character_range",
                        "value": f"{start}:{end}",
                    },
                }
            )
    anchors = sorted(
        sentence_anchors + block_anchors,
        key=lambda anchor: (anchor["start_offset"], anchor["end_offset"]),
    )
    structured_reading = {
        "language": language,
        "text": decoded.text,
        "anchors": anchors,
        "blocks": payload_blocks,
        "spans": [],
        "document_mappings": document_mappings,
        "extensions": {},
    }
    return ReadingStructure(structured_reading=structured_reading)


def plain_text_for_speech(decoded) -> str:
    """Deterministic single-text rendering for speech synthesis.

    Sentences already carry their terminal punctuation; joining them with a
    single space yields clean continuous speech input. The text is the
    exact logical text of the structured reading, free of markup markers.
    """
    return " ".join(sentence.text.strip() for sentence in decoded.sentences)


class DoclingOcrProvider:
    """Document OCR and layout parser based on IBM Docling."""

    name = "docling"

    def __init__(
        self,
        *,
        engine: Callable[[bytes], str] | None = None,
    ):
        self.engine = engine

    def extract_text(self, raw: bytes, media_type: str) -> str:
        if self.engine is not None:
            text = self.engine(raw)
            if not text.strip():
                raise NoTextLayer("the OCR provider detected no text")
            return text

        try:
            import tempfile
            from docling.document_converter import DocumentConverter

            with tempfile.NamedTemporaryFile(suffix=".pdf", delete=True) as tmp:
                tmp.write(raw)
                tmp.flush()
                converter = DocumentConverter()
                result = converter.convert(tmp.name)
                markdown_text = result.document.export_to_markdown()

            if not markdown_text.strip():
                raise NoTextLayer("Docling could not detect any text in the document")
            return markdown_text
        except ImportError as error:
            raise DocumentDecodeError(
                "Docling is not installed. Install with 'pip install docling'"
            ) from error
        except NoTextLayer:
            raise
        except Exception as error:
            raise DocumentDecodeError(f"Docling failed during document extraction: {error}") from error
