from __future__ import annotations

import io
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.document import (
    DocumentDecodeError,
    NoTextLayer,
    RapidOcrProvider,
    SuryaOcrProvider,
    decode_pdf,
)


def blank_pdf() -> bytes:
    from pypdf import PdfWriter

    writer = PdfWriter()
    writer.add_blank_page(width=200, height=200)
    buffer = io.BytesIO()
    writer.write(buffer)
    return buffer.getvalue()


class OcrProvidersTests(unittest.TestCase):
    def test_surya_ocr_with_custom_engine(self) -> None:
        def mock_engine(images: list) -> str:
            return "Surya extracted document text.\nSecond paragraph."

        provider = SuryaOcrProvider(
            langs=["en", "zh"],
            engine=mock_engine,
            pdf_renderer=lambda raw: ["mock_page_image"],
        )
        text = provider.extract_text(blank_pdf(), "application/pdf")
        self.assertEqual(text, "Surya extracted document text.\nSecond paragraph.")

    def test_rapidocr_with_custom_engine(self) -> None:
        def mock_engine(images: list) -> str:
            return "RapidOCR recognized text."

        provider = RapidOcrProvider(
            engine=mock_engine,
            pdf_renderer=lambda raw: ["mock_page_image"],
        )
        text = provider.extract_text(blank_pdf(), "application/pdf")
        self.assertEqual(text, "RapidOCR recognized text.")

    def test_empty_ocr_result_raises_no_text_layer(self) -> None:
        def empty_engine(images: list) -> str:
            return "   \n  "

        provider = SuryaOcrProvider(
            engine=empty_engine,
            pdf_renderer=lambda raw: ["mock_page_image"],
        )
        with self.assertRaises(NoTextLayer):
            provider.extract_text(blank_pdf(), "application/pdf")

    def test_decode_pdf_delegates_to_ocr_provider(self) -> None:
        def mock_engine(images: list) -> str:
            return "PDF recognized text via OCR."

        provider = RapidOcrProvider(
            engine=mock_engine,
            pdf_renderer=lambda raw: ["mock_page_image"],
        )
        text = decode_pdf(blank_pdf(), ocr=provider)
        self.assertEqual(text, "PDF recognized text via OCR.")


if __name__ == "__main__":
    unittest.main()
