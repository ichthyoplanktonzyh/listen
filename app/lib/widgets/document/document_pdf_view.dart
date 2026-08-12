import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Direct PDF view: renders the exact source bytes through the local pdfium
/// engine. No network, no external resources — the bytes are the document.
class DocumentPdfView extends StatelessWidget {
  const DocumentPdfView({super.key, required this.bytes});

  final List<int> bytes;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 720,
      child: PdfViewer(
        PdfDocumentRefData(
          Uint8List.fromList(bytes),
          sourceName: 'document-view',
        ),
        params: const PdfViewerParams(
          sizeDelegateProvider: PdfViewerSizeDelegateProviderLegacy(
            maxScale: 4,
            minScale: 0.5,
          ),
        ),
      ),
    );
  }
}
