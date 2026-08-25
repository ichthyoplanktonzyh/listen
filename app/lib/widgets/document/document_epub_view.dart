import 'package:flutter/material.dart';

import '../../services/document_decoding/epub_decoder.dart';
import '../../services/document_decoding/html_parser_restricted.dart';
import '../../theme/spacing.dart';
import 'document_block_view.dart';

/// Direct EPUB view: renders the spine's chapters in reading order with
/// explicit chapter navigation. Every chapter is parsed through the restricted
/// HTML parser; the original container bytes are the document.
class DocumentEpubView extends StatefulWidget {
  const DocumentEpubView({super.key, required this.epub});

  final EpubDocument epub;

  @override
  State<DocumentEpubView> createState() => _DocumentEpubViewState();
}

class _DocumentEpubViewState extends State<DocumentEpubView> {
  final _parser = const RestrictedHtmlParser();
  int _chapter = 0;

  @override
  Widget build(BuildContext context) {
    final chapters = widget.epub.chapters;
    final current = chapters[_chapter.clamp(0, chapters.length - 1)];
    final document = _parser.parse(current.html);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chapters.length > 1)
          Row(
            children: [
              IconButton(
                tooltip: 'Previous chapter',
                onPressed: _chapter > 0
                    ? () => setState(() => _chapter -= 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  current.title ??
                      'Chapter ${_chapter + 1} of ${chapters.length}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Next chapter',
                onPressed: _chapter < chapters.length - 1
                    ? () => setState(() => _chapter += 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        const SizedBox(height: ListenSpacing.gap8),
        DocumentBlockView(document: document),
      ],
    );
  }
}
