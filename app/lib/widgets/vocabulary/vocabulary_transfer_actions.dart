import 'package:flutter/material.dart';

import '../../localization.dart';

class VocabularyTransferActions extends StatelessWidget {
  const VocabularyTransferActions({
    super.key,
    required this.onExport,
    required this.onImport,
  });

  final Future<void> Function() onExport;
  final Future<void> Function() onImport;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: AppLocalizations.of(context).text('exportAssets'),
        onPressed: onExport,
        icon: const Icon(Icons.file_upload_outlined),
      ),
      IconButton(
        tooltip: AppLocalizations.of(context).text('importAssets'),
        onPressed: onImport,
        icon: const Icon(Icons.file_download_outlined),
      ),
    ],
  );
}
