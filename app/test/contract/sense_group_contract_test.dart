import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/timeline.dart';

void main() {
  group('SenseGroup', () {
    test('parses minimal JSON', () {
      final group = SenseGroup.fromJson(const {
        'id': 'sg-1',
        'sentence_id': 'sent-1',
        'group_index': 0,
        'start_token_index': 0,
        'end_token_index': 2,
        'text': 'the green apple',
        'label': null,
        'head_token_index': null,
        'confidence': 0.5,
        'sources': ['rule'],
      });
      expect(group.id, 'sg-1');
      expect(group.sentenceId, 'sent-1');
      expect(group.groupIndex, 0);
      expect(group.startTokenIndex, 0);
      expect(group.endTokenIndex, 2);
      expect(group.text, 'the green apple');
      expect(group.label, isNull);
      expect(group.headTokenIndex, isNull);
      expect(group.confidence, 0.5);
      expect(group.sources, ['rule']);
    });

    test('parses full JSON with label and head', () {
      final group = SenseGroup.fromJson(const {
        'id': 'sg-2',
        'sentence_id': 'sent-1',
        'group_index': 1,
        'start_token_index': 3,
        'end_token_index': 5,
        'text': 'fell from the tree',
        'label': 'VP',
        'head_token_index': 3,
        'confidence': 0.8,
        'sources': ['punctuation', 'length_limit'],
      });
      expect(group.label, 'VP');
      expect(group.headTokenIndex, 3);
      expect(group.sources, ['punctuation', 'length_limit']);
    });

    test('round-trips through toJson', () {
      const json = {
        'id': 'sg-rt',
        'sentence_id': 'sent-1',
        'group_index': 0,
        'start_token_index': 0,
        'end_token_index': 4,
        'text': 'round trip test',
        'label': 'NP',
        'head_token_index': 2,
        'confidence': 0.75,
        'sources': ['dependency_parse', 'rule'],
      };
      final group = SenseGroup.fromJson(json);
      final roundTripped = SenseGroup.fromJson(group.toJson());
      expect(roundTripped.id, group.id);
      expect(roundTripped.text, group.text);
      expect(roundTripped.label, group.label);
      expect(roundTripped.headTokenIndex, group.headTokenIndex);
      expect(roundTripped.sources, group.sources);
    });
  });

  group('SenseGroupAnalysis', () {
    test('parses analysis with groups', () {
      final analysis = SenseGroupAnalysis.fromJson(const {
        'id': 'sga-1',
        'track_id': 'track-1',
        'media_id': 'media-1',
        'parent_word_timeline_id': null,
        'provider_id': 'rule-based-sense-group',
        'provider_version': 'v1',
        'algorithm': 'punctuation_length_rule_v1',
        'created_by': 'algorithm',
        'status': 'candidate',
        'metrics_json': <String, dynamic>{},
        'groups': [
          {
            'id': 'sg-1',
            'sentence_id': 'sent-1',
            'group_index': 0,
            'start_token_index': 0,
            'end_token_index': 2,
            'text': 'hello world',
            'label': null,
            'head_token_index': null,
            'confidence': 0.5,
            'sources': ['rule'],
          },
        ],
        'created_at_ms': 1000,
        'updated_at_ms': 1000,
      });
      expect(analysis.id, 'sga-1');
      expect(analysis.providerId, 'rule-based-sense-group');
      expect(analysis.algorithm, 'punctuation_length_rule_v1');
      expect(analysis.status, 'candidate');
      expect(analysis.isActive, false);
      expect(analysis.parentWordTimelineId, isNull);
      expect(analysis.groups.length, 1);
      expect(analysis.groups.first.text, 'hello world');
    });

    test('active analysis reports isActive', () {
      final analysis = SenseGroupAnalysis.fromJson(const {
        'id': 'sga-active',
        'track_id': 'track-1',
        'media_id': 'media-1',
        'parent_word_timeline_id': 'wt-1',
        'provider_id': 'rule-based-sense-group',
        'provider_version': 'v1',
        'algorithm': 'punctuation_length_rule_v1',
        'created_by': 'algorithm',
        'status': 'active',
        'metrics_json': <String, dynamic>{},
        'groups': <dynamic>[],
        'created_at_ms': 1000,
        'updated_at_ms': 1000,
      });
      expect(analysis.isActive, true);
      expect(analysis.parentWordTimelineId, 'wt-1');
    });
  });

  group('SenseGroupAnalysisSummary', () {
    test('parses summary JSON', () {
      final summary = SenseGroupAnalysisSummary.fromJson(const {
        'id': 'sga-1',
        'track_id': 'track-1',
        'media_id': 'media-1',
        'parent_word_timeline_id': null,
        'provider_id': 'rule-based-sense-group',
        'provider_version': 'v1',
        'algorithm': 'punctuation_length_rule_v1',
        'created_by': 'algorithm',
        'status': 'active',
        'group_count': 12,
        'can_activate': true,
        'can_archive': true,
        'can_delete': true,
      });
      expect(summary.groupCount, 12);
      expect(summary.isActive, true);
      expect(summary.canActivate, true);
      expect(summary.canDelete, true);
    });
  });
}
