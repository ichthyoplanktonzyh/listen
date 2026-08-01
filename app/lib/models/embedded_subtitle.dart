class EmbeddedSubtitle {
  const EmbeddedSubtitle({
    required this.ordinal,
    required this.codec,
    required this.title,
    required this.language,
    required this.isText,
  });

  final int ordinal;
  final String codec;
  final String? title;
  final String? language;
  final bool isText;

  String get label {
    final name = title ?? language ?? 'Subtitle ${ordinal + 1}';
    return '$name ($codec${isText ? '' : ', bitmap'})';
  }
}
