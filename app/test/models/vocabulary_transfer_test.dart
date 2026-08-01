import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/vocabulary_transfer.dart';

void main() {
  test('typed vocabulary export preserves unknown transfer fields', () {
    final bundle = VocabularyExportBundle.fromJson({
      'version': 7,
      'exported_at_ms': 42,
      'lexical_entries': <Object?>[],
      'future_extension': {'preserved': true},
    });

    expect(bundle.version, 7);
    expect(bundle.exportedAtMs, 42);
    expect(bundle.lexicalEntries, isEmpty);
    expect(bundle['future_extension'], {'preserved': true});
    expect(() => bundle.toJson()['new_field'] = true, throwsUnsupportedError);
  });
}
