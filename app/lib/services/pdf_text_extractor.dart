import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import 'document_intake_service.dart';

/// PDF text-layer extraction through the local pdfium engine. Returns null
/// when the PDF is scanned and carries no extractable text layer — an honest
/// capability fact, never an import failure. The document is opened from
/// bytes and disposed on every path.
class PdfRxPdfTextExtractor implements PdfTextExtractor {
  @override
  Future<String?> extractText(List<int> bytes) async {
    final PdfDocument? document;
    try {
      document = await PdfDocument.openData(
        Uint8List.fromList(bytes),
        sourceName: 'intake',
      );
    } on PdfException {
      return null;
    }
    try {
      final buffer = StringBuffer();
      for (final page in document.pages) {
        final text = await page.loadText();
        if (text != null) {
          buffer.writeln(text.fullText);
        }
      }
      final extracted = buffer.toString();
      return extracted.trim().isEmpty ? null : extracted;
    } on PdfException {
      return null;
    } finally {
      await document.dispose();
    }
  }
}
