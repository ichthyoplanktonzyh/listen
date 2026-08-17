from __future__ import annotations

import sys
import unittest
import zipfile
import io
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.document import (
    DecodedDocument,
    DocumentDecodeError,
    FixtureOcrProvider,
    NoOcrProvider,
    NoTextLayer,
    build_reading_structure,
    decode_document,
    decode_epub,
    decode_html,
    decode_pdf,
    plain_text_for_speech,
    segment_text,
)


class SegmentTextTests(unittest.TestCase):
    def test_sentences_cover_the_whole_text(self) -> None:
        paragraphs, sentences = segment_text(
            "Hello world. This is a test.\nSecond paragraph!"
        )
        self.assertEqual(len(paragraphs), 2)
        self.assertEqual(len(sentences), 3)
        self.assertEqual(sentences[-1].end_char, len("Hello world. This is a test.\nSecond paragraph!"))
        expected = [
            "Hello world.",
            " This is a test.\n",
            "Second paragraph!",
        ]
        self.assertEqual([sentence.text for sentence in sentences], expected)

    def test_blank_line_newline_belongs_to_previous_sentence(self) -> None:
        _, sentences = segment_text("First line.\n\nThird line!")
        self.assertEqual(sentences[0].text, "First line.\n\n")
        self.assertEqual(sentences[-1].end_char, len("First line.\n\nThird line!"))

    def test_single_line_no_trailing_newline(self) -> None:
        _, sentences = segment_text("Just one sentence.")
        self.assertEqual(sentences[0].start_char, 0)
        self.assertEqual(sentences[0].end_char, 18)

    def test_trailing_space_after_punctuation_stays_with_sentence(self) -> None:
        text = "First sentence. \nSecond sentence."
        _, sentences = segment_text(text)
        self.assertEqual(len(sentences), 2)
        self.assertEqual(sentences[0].text, "First sentence. \n")
        self.assertEqual("".join(sentence.text for sentence in sentences), text)
        self.assertTrue(all(sentence.text.strip() for sentence in sentences))

    def test_paragraph_offsets_are_contiguous(self) -> None:
        paragraphs, _ = segment_text("One.\nTwo!\n\nThree?")
        self.assertEqual([(p.start_char, p.end_char) for p in paragraphs],
                         [(0, 4), (5, 9), (11, 17)])


class DecodeTextFamilyTests(unittest.TestCase):
    def test_plain_text_round_trip(self) -> None:
        decoded = decode_document(b"Hello world.\nSecond line!", "text/plain")
        self.assertTrue(decoded.source_identical)
        self.assertEqual(decoded.text, "Hello world.\nSecond line!")

    def test_bom_is_stripped(self) -> None:
        decoded = decode_document(b"\xef\xbb\xbfHello.", "text/plain")
        self.assertEqual(decoded.text, "Hello.")

    def test_invalid_utf8_rejected(self) -> None:
        with self.assertRaises(DocumentDecodeError):
            decode_document(b"\xc3\x28", "text/plain")

    def test_empty_text_rejected(self) -> None:
        with self.assertRaises(DocumentDecodeError):
            decode_document(b"   \n", "text/plain")

    def test_markdown_is_parsed_and_markup_free(self) -> None:
        decoded = decode_document(
            b"# Title\n\nSome **bold** and *italic* and `code` text.",
            "text/markdown",
        )
        self.assertFalse(decoded.source_identical)
        self.assertEqual(decoded.text, "Title\nSome bold and italic and code text.")

    def test_markdown_markers_never_reach_speech(self) -> None:
        decoded = decode_document(
            b"# Heading\n\nSee [link](https://example.com) and ![alt](img.png).\n"
            b"- item one\n- item two\n\n> quoted line.",
            "text/markdown",
        )
        speech = plain_text_for_speech(decoded)
        self.assertNotIn("#", speech)
        self.assertNotIn("*", speech)
        self.assertNotIn("[", speech)
        self.assertNotIn("]", speech)
        self.assertNotIn("(", speech)
        self.assertNotIn(")", speech)
        self.assertNotIn("https://", speech)
        self.assertIn("Heading", speech)
        self.assertIn("link", speech)
        self.assertIn("alt", speech)
        self.assertIn("item one", speech)
        self.assertIn("quoted line", speech)

    def test_markdown_blocks_carry_heading_structure(self) -> None:
        decoded = decode_document(
            b"# Title\n\nFirst paragraph.\n\n## Section\n\nSecond.",
            "text/markdown",
        )
        kinds = [block.kind for block in decoded.blocks]
        self.assertIn("heading", kinds)
        blocks = [
            block for block in decoded.blocks if block.kind != "root"
        ]
        self.assertEqual([block.kind for block in blocks], ["heading", "paragraph", "heading", "paragraph"])
        root = decoded.blocks[0]
        self.assertEqual(root.kind, "root")
        self.assertTrue(root.sentence_ids)


class DecodeHtmlTests(unittest.TestCase):
    def test_scripts_and_styles_are_discarded(self) -> None:
        html = (
            b"<html><head><style>.x{}</style><script>alert('xss')</script></head>"
            b"<body><p>Hello <b>world</b>.</p><script>alert(2)</script>"
            b"<p>Second.</p></body></html>"
        )
        text = decode_html(html)
        self.assertNotIn("alert", text)
        self.assertNotIn("xss", text)
        self.assertNotIn("script", text.lower())
        self.assertIn("Hello world.", text)
        self.assertIn("Second.", text)

    def test_entities_are_decoded(self) -> None:
        text = decode_html(b"<p>A &amp; B &lt; C.</p>")
        self.assertIn("A & B < C.", text)

    def test_iframes_and_svg_are_discarded(self) -> None:
        html = b"<p>Keep.</p><iframe src=\"http://evil\">drop</iframe><svg><text>drop</text></svg>"
        text = decode_html(html)
        self.assertIn("Keep.", text)
        self.assertNotIn("drop", text)

    def test_no_extractable_text_rejected(self) -> None:
        with self.assertRaises(DocumentDecodeError):
            decode_html(b"<html><body><script>alert(1)</script></body></html>")


def make_epub(chapters: list[tuple[str, str]]) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr("mimetype", b"application/epub+zip")
        archive.writestr(
            "META-INF/container.xml",
            (
                '<?xml version="1.0"?><container>'
                '<rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles>'
                "</container>"
            ).encode(),
        )
        archive.writestr(
            "OEBPS/content.opf",
            (
                '<?xml version="1.0"?><package>'
                "<manifest>"
                + "".join(
                    f'<item id="c{i}" href="{href}" media-type="application/xhtml+xml"/>'
                    for i, (href, _) in enumerate(chapters)
                )
                + "</manifest><spine>"
                + "".join(f'<itemref idref="c{i}"/>' for i in range(len(chapters)))
                + "</spine></package>"
            ).encode(),
        )
        for i, (href, content) in enumerate(chapters):
            archive.writestr(f"OEBPS/{href}", content.encode())
    return buffer.getvalue()


class DecodeEpubTests(unittest.TestCase):
    def test_spine_text_concatenates_chapters(self) -> None:
        epub = make_epub(
            [
                ("c1.xhtml", "<html><body><p>Chapter one.</p></body></html>"),
                ("c2.xhtml", "<html><body><p>Chapter two!</p></body></html>"),
            ]
        )
        text = decode_epub(epub)
        self.assertIn("Chapter one.", text)
        self.assertIn("Chapter two!", text)

    def test_missing_mimetype_rejected(self) -> None:
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("META-INF/container.xml", b"x")
        with self.assertRaises(DocumentDecodeError):
            decode_epub(buffer.getvalue())

    def test_missing_container_rejected(self) -> None:
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("mimetype", b"application/epub+zip")
        with self.assertRaises(DocumentDecodeError):
            decode_epub(buffer.getvalue())

    def test_path_traversal_href_is_sanitized(self) -> None:
        buffer = io.BytesIO()
        with zipfile.ZipFile(buffer, "w") as archive:
            archive.writestr("mimetype", b"application/epub+zip")
            archive.writestr(
                "META-INF/container.xml",
                b'<container><rootfiles><rootfile full-path="OEBPS/c.opf"/></rootfiles></container>',
            )
            archive.writestr(
                "OEBPS/c.opf",
                b'<package><manifest><item id="c0" href="../../etc/passwd" media-type="text/html"/>'
                b"</manifest><spine><itemref idref=\"c0\"/></spine></package>",
            )
            archive.writestr("OEBPS/c.opf" + "", b"")
        with self.assertRaises(DocumentDecodeError):
            decode_epub(buffer.getvalue())

    def test_epub_preserves_chapter_blocks(self) -> None:
        epub = make_epub(
            [
                (
                    "c1.xhtml",
                    "<html><body><h1>First</h1><p>Chapter one.</p></body></html>",
                ),
                ("c2.xhtml", "<html><body><p>Chapter two!</p></body></html>"),
            ]
        )
        decoded = decode_document(epub, "application/epub+zip")
        kinds = [block.kind for block in decoded.blocks]
        self.assertIn("chapter", kinds)
        chapters = [b for b in decoded.blocks if b.kind == "chapter"]
        self.assertEqual(len(chapters), 2)
        self.assertTrue(
            all(chapter.parent_id == "block-root" for chapter in chapters)
        )
        nested = [
            b for b in decoded.blocks if b.kind in ("heading", "paragraph")
        ]
        self.assertTrue(
            all(n.parent_id.startswith("chapter-") for n in nested)
        )
        self.assertIn("Chapter one.", decoded.text)
        self.assertIn("Chapter two!", decoded.text)

    def test_html_navigation_is_discarded(self) -> None:
        text = decode_html(
            b"<html><body><nav><a href=\"/x\">Menu</a></nav>"
            b"<article><p>Content.</p></article></body></html>"
        )
        self.assertNotIn("Menu", text)
        self.assertIn("Content.", text)

    def test_script_content_never_reaches_text(self) -> None:
        epub = make_epub(
            [("c1.xhtml", "<html><body><p>Good.</p><script>bad()</script></body></html>")]
        )
        text = decode_epub(epub)
        self.assertIn("Good.", text)
        self.assertNotIn("bad", text)


def blank_pdf() -> bytes:
    from pypdf import PdfWriter

    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    buffer = io.BytesIO()
    writer.write(buffer)
    return buffer.getvalue()


class DecodePdfTests(unittest.TestCase):
    def test_scanned_pdf_without_ocr_abstains_honestly(self) -> None:
        with self.assertRaises(NoTextLayer):
            decode_pdf(blank_pdf())

    def test_corrupt_pdf_is_a_decode_error_not_a_text_failure(self) -> None:
        with self.assertRaises(DocumentDecodeError):
            decode_pdf(b"%PDF-1.4\n%%EOF")

    def test_ocr_provider_recognizes_text(self) -> None:
        with tempfile_directory() as directory:
            fixture = Path(directory) / "ocr.txt"
            fixture.write_text("Recognized text.", encoding="utf-8")
            provider = FixtureOcrProvider(fixture)
            text = decode_pdf(blank_pdf(), ocr=provider)
            self.assertEqual(text, "Recognized text.")

    def test_no_ocr_provider_is_default_seam(self) -> None:
        with self.assertRaises(NoTextLayer):
            NoOcrProvider().extract_text(b"", "application/pdf")


class ReadingStructureTests(unittest.TestCase):
    def test_document_mappings_only_for_byte_identical_sources(self) -> None:
        decoded = decode_document(b"Hello world.\nSecond line!", "text/plain")
        structure = build_reading_structure(
            decoded, language="en", rendition_id="sha256:" + "a" * 64
        )
        self.assertTrue(structure.structured_reading["text"])
        self.assertNotEqual(structure.structured_reading["document_mappings"], [])
        mapping = structure.structured_reading["document_mappings"][0]
        self.assertEqual(mapping["locator"]["kind"], "character_range")
        html_decoded = decode_document(b"<p>Hello.</p>", "text/html")
        html_structure = build_reading_structure(
            html_decoded, language="en", rendition_id="sha256:" + "a" * 64
        )
        self.assertEqual(html_structure.structured_reading["document_mappings"], [])

    def test_anchor_offsets_are_utf8_byte_offsets(self) -> None:
        decoded = decode_document("大熊猫吃竹子。\n它们生活在中国。".encode(), "text/plain")
        structure = build_reading_structure(
            decoded, language="zh-Hans", rendition_id="sha256:" + "a" * 64
        )
        anchors = structure.structured_reading["anchors"]
        first = next(
            anchor
            for anchor in anchors
            if anchor["kind"] == "sentence"
        )
        self.assertEqual(first["start_offset"], 0)
        self.assertEqual(
            first["end_offset"],
            len("大熊猫吃竹子。\n".encode("utf-8")),
        )
        self.assertEqual(
            structure.structured_reading["text"],
            "大熊猫吃竹子。\n它们生活在中国。",
        )
        end = anchors[-1]["end_offset"]
        self.assertEqual(
            end, len("大熊猫吃竹子。\n它们生活在中国。".encode("utf-8"))
        )

    def test_blocks_reference_sentence_anchors(self) -> None:
        decoded = decode_document(b"One. Two!\nThree?", "text/plain")
        structure = build_reading_structure(
            decoded, language="en", rendition_id="sha256:" + "a" * 64
        )
        blocks = structure.structured_reading["blocks"]
        self.assertTrue(all(block["span_anchor_ids"] for block in blocks))


def tempfile_directory():
    import tempfile
    import contextlib

    return contextlib.contextmanager(lambda: (yield tempfile.mkdtemp()))()


class SpeechTextTests(unittest.TestCase):
    def test_speech_text_joins_sentences(self) -> None:
        decoded = decode_document(b"Hello world.\nSecond paragraph!", "text/plain")
        speech = plain_text_for_speech(decoded)
        self.assertEqual(speech, "Hello world. Second paragraph!")


if __name__ == "__main__":
    unittest.main()
