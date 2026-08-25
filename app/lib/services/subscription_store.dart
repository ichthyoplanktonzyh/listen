import 'dart:convert';
import 'dart:io';

import '../models/discovery.dart';

/// The content sources a person subscribed to, kept across restarts.
///
/// Both discovery repositories held their custom sources in a plain in-memory
/// list, so pasting a feed address added a source that existed until the app
/// closed. The built-in starters came back and everything the person had added
/// did not — silent data loss, and the kind that looks like the subscription
/// never worked.
///
/// This store replaced the pre-Phase-1 subscription store outright: the new
/// format is `subscriptions-v2.json`, there is no v1 migration and no dual
/// read, and a v1 file left behind is simply not read. A subscription that
/// cannot be reconstructed exactly is not one to reconstruct approximately.
///
/// Shaped after [AcquisitionLedger]: a file of its own rather than a corner of
/// `AppSettings`, tolerant of every way it can be unreadable, and persisting
/// only when a caller asked for it.
class SubscriptionStore {
  SubscriptionStore({required Directory this._directory});

  /// The real per-user store, beside the settings file. Only the composition
  /// root builds this; a default reaching for `$HOME` would mean every test
  /// that builds a repository read the developer's own subscriptions.
  factory SubscriptionStore.forCurrentUser({String? home}) => SubscriptionStore(
    directory: Directory(
      '${home ?? Platform.environment['HOME'] ?? ''}'
      '/Library/Application Support/listen',
    ),
  );

  /// A store that remembers nothing beyond this object.
  SubscriptionStore.inMemory() : _directory = null, _loaded = true;

  final Directory? _directory;
  final List<ContentSource> _sources = [];
  bool _loaded = false;

  File? get _file => _directory == null
      ? null
      : File('${_directory.path}/subscriptions-v2.json');

  bool get isLoaded => _loaded;

  /// Subscriptions of one kind, in the order they were added.
  List<ContentSource> of(ContentSourceKind kind) => List.unmodifiable([
    for (final source in _sources)
      if (source.kind == kind) source,
  ]);

  Future<void> load() async {
    _loaded = true;
    final file = _file;
    if (file == null) return;
    try {
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<dynamic, dynamic>) return;
      final subscriptions = decoded['subscriptions'];
      if (subscriptions is! List<dynamic>) return;
      _sources
        ..clear()
        ..addAll(
          subscriptions
              .whereType<Map<dynamic, dynamic>>()
              .map(_sourceFrom)
              .whereType<ContentSource>(),
        );
    } on FormatException {
      _sources.clear();
    } on FileSystemException {
      _sources.clear();
    }
  }

  /// Adds or replaces a subscription. Re-subscribing refreshes the stored
  /// title and artwork rather than adding the source twice.
  Future<void> add(ContentSource source) async {
    _sources
      ..removeWhere((existing) => existing.id == source.id)
      ..add(source);
    await _persist();
  }

  Future<void> remove(String sourceId) async {
    if (!_sources.any((source) => source.id == sourceId)) return;
    _sources.removeWhere((source) => source.id == sourceId);
    await _persist();
  }

  static ContentSource? _sourceFrom(Map<dynamic, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.isEmpty || name is! String) return null;
    final kind = ContentSourceKind.values
        .where((value) => value.name == json['kind'])
        .firstOrNull;
    final cover = ChannelCoverTone.values
        .where((value) => value.name == json['cover'])
        .firstOrNull;
    if (kind == null || cover == null) return null;
    return ContentSource(
      id: id,
      name: name,
      language: json['language'] as String? ?? '',
      description: json['description'] as String? ?? '',
      cover: cover,
      kind: kind,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Future<void> _persist() async {
    final directory = _directory;
    final file = _file;
    if (directory == null || file == null) return;
    try {
      if (!await directory.exists()) await directory.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 2,
          'subscriptions': [
            for (final source in _sources)
              {
                'id': source.id,
                'name': source.name,
                'language': source.language,
                'description': source.description,
                'cover': source.cover.name,
                'kind': source.kind.name,
                if (source.avatarUrl != null) 'avatar_url': source.avatarUrl,
              },
          ],
        }),
      );
    } on FileSystemException {
      // An unwritable support directory costs the subscription across
      // restarts, not this session's. Failing the subscribe over it would be
      // the larger harm.
    }
  }
}
