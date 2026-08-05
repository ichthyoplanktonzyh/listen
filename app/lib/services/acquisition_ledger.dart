import 'dart:convert';
import 'dart:io';

/// What an earlier session acquired for a catalog entry.
///
/// Recognising already-acquired media used to rely on the external tool's
/// `[id]` filename convention, so it worked only on the YouTube path. A
/// podcast enclosure is saved under the publisher's own filename
/// (`p0p1qc9j.mp3`), which has nothing to do with the feed's guid
/// (`urn:bbc:podcast:p0p1qc9j`), and matching one against the other by
/// substring would be a guess. So the fact is written down instead of
/// re-derived: the app knows what it downloaded, and only has to remember it.
typedef AcquiredMedia = ({String mediaId, String path});

/// A durable entryId → acquired-media record.
///
/// Deliberately not part of `AppSettings`: settings are a person's
/// preferences, edited by hand and migrated when their meaning changes. This
/// is a growing log of what happened, and mixing the two would make every
/// download rewrite the preferences file.
class AcquisitionLedger {
  AcquisitionLedger({required Directory this._directory});

  /// The real per-user ledger, alongside the settings file.
  ///
  /// Only the composition root builds this. A default that reached for
  /// `$HOME` would mean every test that builds a ViewModel reads — and on a
  /// forget, writes — the developer's own record.
  factory AcquisitionLedger.forCurrentUser({String? home}) => AcquisitionLedger(
    directory: Directory(
      '${home ?? Platform.environment['HOME'] ?? ''}'
      '/Library/Application Support/listen',
    ),
  );

  /// A ledger that remembers nothing beyond this object.
  ///
  /// The default for any caller that did not ask for persistence, so nothing
  /// touches the file system by accident.
  AcquisitionLedger.inMemory() : _directory = null, _loaded = true;

  final Directory? _directory;
  Map<String, AcquiredMedia> _entries = {};
  bool _loaded = false;

  File? get _file => _directory == null
      ? null
      : File('${_directory.path}/acquisitions-v1.json');

  /// Reads the record, tolerating every way the file can be unusable.
  ///
  /// A ledger that cannot be read is an empty ledger, never an error: the
  /// worst case is offering a download that was already done, which is
  /// recoverable. Refusing to start a session over it would not be.
  Future<void> load() async {
    _loaded = true;
    final file = _file;
    if (file == null) return;
    try {
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<dynamic, dynamic>) return;
      final acquisitions = decoded['acquisitions'];
      if (acquisitions is! Map<dynamic, dynamic>) return;
      final parsed = <String, AcquiredMedia>{};
      acquisitions.forEach((key, value) {
        if (key is! String || value is! Map<dynamic, dynamic>) return;
        final mediaId = value['media_id'];
        final path = value['path'];
        if (mediaId is String &&
            path is String &&
            mediaId.isNotEmpty &&
            path.isNotEmpty) {
          parsed[key] = (mediaId: mediaId, path: path);
        }
      });
      _entries = parsed;
    } on FormatException {
      _entries = {};
    } on FileSystemException {
      _entries = {};
    }
  }

  /// The record for [entryId], or null when nothing was acquired for it.
  ///
  /// Callers still have to confirm the file is on disk. This says what was
  /// downloaded, not what still exists — a person who cleaned out a folder did
  /// not consult this file first.
  AcquiredMedia? operator [](String entryId) => _entries[entryId];

  bool get isLoaded => _loaded;

  Future<void> record(
    String entryId, {
    required String mediaId,
    required String path,
  }) async {
    if (_entries[entryId]?.mediaId == mediaId &&
        _entries[entryId]?.path == path) {
      return;
    }
    _entries[entryId] = (mediaId: mediaId, path: path);
    await _persist();
  }

  /// Drops a record whose file is gone, so a stale row is not re-checked on
  /// every visit for the rest of the install's life.
  Future<void> forget(String entryId) async {
    if (_entries.remove(entryId) == null) return;
    await _persist();
  }

  Future<void> _persist() async {
    final directory = _directory;
    final file = _file;
    if (directory == null || file == null) return;
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'acquisitions': {
            for (final entry in _entries.entries)
              entry.key: {
                'media_id': entry.value.mediaId,
                'path': entry.value.path,
              },
          },
        }),
      );
    } on FileSystemException {
      // An unwritable support directory costs recognition across restarts, not
      // this session's download. Failing the acquisition over it would be the
      // larger harm.
    }
  }
}
