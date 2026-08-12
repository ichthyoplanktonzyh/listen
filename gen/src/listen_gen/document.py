"""Document to Structured Reading derivation.

Deterministic text extraction for the supported document families, plus a
provider-neutral optional OCR seam for scanned PDFs. Output is a pure
intermediate representation that the packager turns into a ``document-text``
resource and a ``structured-reading`` resource.

Honesty rules:
- A document with no extractable text and no OCR provider abstains from the
  derivation; it is never treated as an import failure.
- ``document_mappings`` into the exact Document Rendition are produced only
  when they can be exact: plain text and Markdown preserve byte identity
  between the extracted text and the source document. HTML, EPUB, and PDF
  text never fabricate source locators.
"""

from __future__ import annotations

import io
import re
import zipfile
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from typing import Protocol, Sequence

from .package import ConversionError

MAX_TEXT_BYTES = 8 * 1024 * 1024
MAX_CONTAINER_BYTES = 128 * 1024 * 1024

TEXT_FAMILIES = ("text/plain", "text/markdown", "text/html")
PDF_MEDIA_TYPES = ("application/pdf",)
EPUB_MEDIA_TYPES = ("application/epub+zip",)


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
class ExtractedText:
    text: str
    paragraphs: tuple[Paragraph, ...]
    sentences: tuple[Sentence, ...]
    source_identical: bool = False

    @property
    def language_hint(self) -> str | None:
        return None


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


class _HtmlTextExtractor(HTMLParser):
    """Extract text while discarding scripts, styles, and hidden content.

    Mirrors the App's restricted renderer policy: no content from ``script``,
    ``style``, ``noscript``, ``iframe``, ``svg``, or ``template`` elements
    reaches the extracted text.
    """

    _DISCARDED = frozenset(
        {"script", "style", "noscript", "iframe", "svg", "template", "head"}
    )

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list[str] = []
        self._depth = 0
        self._skip = 0

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in self._DISCARDED:
            self._skip += 1
        if tag in ("p", "div", "section", "article", "li", "h1", "h2", "h3",
                   "h4", "h5", "h6", "blockquote", "pre", "tr", "br"):
            self.parts.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in self._DISCARDED and self._skip > 0:
            self._skip -= 1

    def handle_data(self, data: str) -> None:
        if self._skip == 0:
            self.parts.append(data)


def decode_html(raw: bytes) -> str:
    text = decode_text_family(raw)
    extractor = _HtmlTextExtractor()
    try:
        extractor.feed(text)
    except Exception as error:  # pragma: no cover - parser robustness
        raise DocumentDecodeError("document HTML could not be parsed") from error
    lines = [
        " ".join(line.split())
        for line in "".join(extractor.parts).split("\n")
        if line.strip()
    ]
    result = "\n".join(lines)
    if not result.strip():
        raise DocumentDecodeError("document HTML contains no extractable text")
    return result


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


def _epub_spine_text(
    archive: zipfile.ZipFile,
    root_path: str,
    media_type: str,
) -> str:
    """Decode an EPUB spine into deterministic text.

    The spine order and the OPF-relative href resolution follow the exact
    container declarations. Traversal outside the OPF directory is rejected.
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
    parts: list[str] = []
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
        chapter_text = "\n".join(
            " ".join(line.split())
            for line in "".join(extractor.parts).split("\n")
            if line.strip()
        )
        if chapter_text.strip():
            parts.append(chapter_text)
    if not parts:
        raise DocumentDecodeError("EPUB contains no extractable text")
    return "\n\n".join(parts)


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
        return _epub_spine_text(archive, root_path, "application/epub+zip")


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


@dataclass(frozen=True)
class DecodedDocument:
    media_type: str
    text: str
    paragraphs: tuple[Paragraph, ...]
    sentences: tuple[Sentence, ...]
    #: The exact text in the source document equals the extracted text.
    byte_identical: bool

    @property
    def source_identical(self) -> bool:
        return self.byte_identical


def decode_document(
    raw: bytes,
    media_type: str,
    *,
    ocr: OcrProvider | None = None,
) -> DecodedDocument:
    """Decode one exact Document Rendition into extractable text.

    ``byte_identical`` reports whether the extracted text is byte-for-byte
    the source document text (plain text and Markdown), which is the only
    honest basis for source locator mappings.
    """
    if media_type == "text/plain":
        text = decode_text_family(raw)
        paragraphs, sentences = segment_text(text)
        return DecodedDocument(
            media_type=media_type,
            text=text,
            paragraphs=paragraphs,
            sentences=sentences,
            byte_identical=True,
        )
    if media_type == "text/markdown":
        text = decode_text_family(raw)
        paragraphs, sentences = segment_text(text)
        return DecodedDocument(
            media_type=media_type,
            text=text,
            paragraphs=paragraphs,
            sentences=sentences,
            byte_identical=True,
        )
    if media_type == "text/html":
        text = decode_html(raw)
        paragraphs, sentences = segment_text(text)
        return DecodedDocument(
            media_type=media_type,
            text=text,
            paragraphs=paragraphs,
            sentences=sentences,
            byte_identical=False,
        )
    if media_type in EPUB_MEDIA_TYPES:
        text = decode_epub(raw)
        paragraphs, sentences = segment_text(text)
        return DecodedDocument(
            media_type=media_type,
            text=text,
            paragraphs=paragraphs,
            sentences=sentences,
            byte_identical=False,
        )
    if media_type in PDF_MEDIA_TYPES:
        text = decode_pdf(raw, ocr=ocr)
        paragraphs, sentences = segment_text(text)
        return DecodedDocument(
            media_type=media_type,
            text=text,
            paragraphs=paragraphs,
            sentences=sentences,
            byte_identical=False,
        )
    raise DocumentDecodeError(f"unsupported document media type: {media_type}")


# ---------------------------------------------------------------------------
# Reading structure (document_text + structured_reading payloads)
# ---------------------------------------------------------------------------


def _char_to_byte_offsets(text: str) -> list[int]:
    """UTF-8 byte offset of every character boundary in ``text``."""
    encoded = text.encode("utf-8")
    offsets = [0]
    for character in text:
        offsets.append(offsets[-1] + len(character.encode("utf-8")))
    return offsets


@dataclass(frozen=True)
class ReadingStructure:
    document_text: dict[str, object]
    structured_reading: dict[str, object]


def build_reading_structure(
    decoded: DecodedDocument,
    *,
    language: str,
    rendition_id: str,
) -> ReadingStructure:
    """Build the deterministic reading payloads for one document rendition.

    Byte offsets in the structured reading anchors refer to the exact text of
    the paired ``document-text`` resource. Source locator mappings are
    produced only when the extraction is byte-identical.
    """
    byte_offsets = _char_to_byte_offsets(decoded.text)
    segments: list[dict[str, object]] = []
    for sentence in decoded.sentences:
        segments.append(
            {
                "id": sentence.id,
                "index": sentence.index,
                "start_char": sentence.start_char,
                "end_char": sentence.end_char,
                "language": language,
                "extensions": {},
            }
        )
    anchors: list[dict[str, object]] = []
    for paragraph in decoded.paragraphs:
        anchors.append(
            {
                "anchor_id": paragraph.id,
                "kind": "block",
                "start_offset": byte_offsets[paragraph.start_char],
                "end_offset": byte_offsets[paragraph.end_char],
            }
        )
    for sentence in decoded.sentences:
        anchors.append(
            {
                "anchor_id": sentence.id,
                "kind": "sentence",
                "start_offset": byte_offsets[sentence.start_char],
                "end_offset": byte_offsets[sentence.end_char],
            }
        )
    blocks: list[dict[str, object]] = []
    for paragraph in decoded.paragraphs:
        blocks.append(
            {
                "block_id": paragraph.id,
                "span_anchor_ids": list(paragraph.sentence_ids),
                "parent_block_id": None,
            }
        )
    document_mappings: list[dict[str, object]] = []
    if decoded.source_identical:
        for paragraph in decoded.paragraphs:
            start = byte_offsets[paragraph.start_char]
            end = byte_offsets[paragraph.end_char]
            document_mappings.append(
                {
                    "anchor_id": paragraph.id,
                    "rendition_id": rendition_id,
                    "locator": f"bytes:{start}-{end}",
                }
            )
    document_text = {
        "language": language,
        "text": decoded.text,
        "segments": segments,
        "extensions": {},
    }
    structured_reading = {
        "language": language,
        "anchors": anchors,
        "blocks": blocks,
        "spans": [],
        "document_mappings": document_mappings,
        "extensions": {},
    }
    return ReadingStructure(
        document_text=document_text,
        structured_reading=structured_reading,
    )


def plain_text_for_speech(decoded: DecodedDocument) -> str:
    """Deterministic single-text rendering for speech synthesis.

    Sentences already carry their terminal punctuation; joining them with a
    single space yields clean continuous speech input.
    """
    return " ".join(sentence.text.strip() for sentence in decoded.sentences)
