import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/types.dart';

void main() {
  const fixture = {
    'display_form': 'Hello',
    'normalized_form': 'hello',
    'occurrence_count': 5,
  };

  group('ColdStartWordCandidate', () {
    test('parses the wire shape', () {
      final candidate = ColdStartWordCandidate.fromJson(fixture);
      expect(candidate.displayForm, 'Hello');
      expect(candidate.normalizedForm, 'hello');
      expect(candidate.occurrenceCount, 5);
    });

    test('round-trips through toJson', () {
      final candidate = ColdStartWordCandidate.fromJson(fixture);
      final roundTripped = ColdStartWordCandidate.fromJson(candidate.toJson());
      expect(roundTripped.displayForm, candidate.displayForm);
      expect(roundTripped.normalizedForm, candidate.normalizedForm);
      expect(roundTripped.occurrenceCount, candidate.occurrenceCount);
    });
  });
}
