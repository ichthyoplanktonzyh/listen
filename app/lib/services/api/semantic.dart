part of '../api_service.dart';

// Phase 3.11 semantic-task facts, first consumed by the Reading Studio
// (Phase 3.13). Append-only: there are deliberately no update or delete
// calls. All ids and judgment timestamps are minted server-side.

extension SemanticApi on LocalApi {
  /// Computes the hex sha256 the judgment endpoints expect for snapshot and
  /// response hashes (mirrors domain::transcript_sha256).
  static String transcriptSha256(String transcript) =>
      sha256.convert(utf8.encode(transcript)).toString();

  Future<SemanticRubricView> createSemanticRubric({
    required String purpose,
    required RubricSourceView source,
    required String responseLanguage,
    required List<RubricPointView> points,
    required SemanticProvenanceView provenance,
    int version = 1,
    String? revisionNote,
    int? revisedFromVersion,
  }) async => SemanticRubricView.fromJson(
    (await _request('POST', '/v1/semantic/rubrics', {
          'purpose': purpose,
          'source': source.toJson(),
          'response_language': responseLanguage,
          'points': points.map((p) => p.toJson()).toList(),
          'version': version,
          'provenance': provenance.toJson(),
          if (revisionNote != null && revisedFromVersion != null)
            'revision': {
              'revised_from_version': revisedFromVersion,
              'note': revisionNote,
              'revised_at_ms': DateTime.now().millisecondsSinceEpoch,
            },
        }))
        as Map<String, dynamic>,
  );

  /// Finds the latest rubric for one source segment + purpose, or null.
  /// Identity is server-minted, so lookup goes by source fields + snapshot
  /// hash instead of re-deriving the fingerprint client-side.
  Future<SemanticRubricView?> lookupSemanticRubric({
    String? mediaId,
    required int startMs,
    required int endMs,
    required String purpose,
    required String responseLanguage,
    required String transcriptSnapshot,
  }) async {
    final query = Uri(
      queryParameters: {
        'media_id': ?mediaId,
        'start_ms': '$startMs',
        'end_ms': '$endMs',
        'purpose': purpose,
        'response_language': responseLanguage,
        'source_sha256': transcriptSha256(transcriptSnapshot),
      },
    ).query;
    final json = await _request('GET', '/v1/semantic/rubrics/lookup?$query');
    if (json == null) return null;
    return SemanticRubricView.fromJson(json as Map<String, dynamic>);
  }

  Future<SemanticRubricView?> semanticRubric(
    String rubricId, {
    int? version,
  }) async {
    try {
      final query = version == null ? '' : '?version=$version';
      final json = await _request(
        'GET',
        '/v1/semantic/rubrics/${Uri.encodeComponent(rubricId)}$query',
      );
      return SemanticRubricView.fromJson(json as Map<String, dynamic>);
    } on HttpException {
      return null;
    }
  }

  Future<List<SemanticAttemptView>> semanticRubricAttempts(
    String rubricId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/semantic/rubrics/${Uri.encodeComponent(rubricId)}/attempts',
              ))
              as List<dynamic>)
          .map((a) => SemanticAttemptView.fromJson(a as Map<String, dynamic>))
          .toList(growable: false);

  Future<SemanticAttemptView> semanticAttempt(String attemptId) async =>
      SemanticAttemptView.fromJson(
        (await _request(
              'GET',
              '/v1/semantic/attempts/${Uri.encodeComponent(attemptId)}',
            ))
            as Map<String, dynamic>,
      );

  /// Records a completed reading-comprehension attempt. Conditions are the
  /// honest record of what the learner could access; the caller supplies
  /// them, this layer never invents them.
  Future<SemanticAttemptView> createSemanticAttempt({
    required String kind,
    required Map<String, dynamic> target,
    required String rubricId,
    required int rubricVersion,
    required bool sourceTextVisible,
    int? audioPlayCount,
    bool notesAllowed = false,
    String? l1Trigger,
    required String responseTranscript,
    required String responseLanguage,
    required int startedAtMs,
    required int endedAtMs,
  }) async => SemanticAttemptView.fromJson(
    (await _request('POST', '/v1/semantic/attempts', {
          'kind': kind,
          'target': target,
          'anchors': const <dynamic>[],
          'rubric_id': rubricId,
          'rubric_version': rubricVersion,
          'conditions': {
            'source_text_visible': sourceTextVisible,
            'audio_play_count': audioPlayCount,
            'notes_allowed': notesAllowed,
            'l1_trigger': l1Trigger,
            'speaking_assistance': null,
            'speaking_recall': null,
            'prompt_snapshot': null,
          },
          'responses': [
            {
              'revision': 1,
              'raw_transcript': null,
              'transcript': responseTranscript,
              'source': 'typed',
              'recording_asset_id': null,
              'asr_reliability': null,
              'language': responseLanguage,
              'recorded_at_ms': endedAtMs,
            },
          ],
          'status': 'completed',
          'started_at_ms': startedAtMs,
          'ended_at_ms': endedAtMs,
        }))
        as Map<String, dynamic>,
  );

  /// Records one constructed spoken response. Raw ASR and the learner-edited
  /// transcript remain separate; this method records no judgment or score.
  Future<SemanticAttemptView> createSpokenSemanticAttempt({
    required String kind,
    required Map<String, dynamic> target,
    required String rubricId,
    required int rubricVersion,
    required int audioPlayCount,
    String? l1Trigger,
    String? speakingAssistance,
    required String speakingRecall,
    String? promptSnapshot,
    required String recordingAssetId,
    required String rawTranscript,
    required String correctedTranscript,
    required String asrReliability,
    required String responseLanguage,
    required int startedAtMs,
    required int endedAtMs,
  }) async => SemanticAttemptView.fromJson(
    (await _request('POST', '/v1/semantic/attempts', {
          'kind': kind,
          'target': target,
          'anchors': const <dynamic>[],
          'rubric_id': rubricId,
          'rubric_version': rubricVersion,
          'conditions': {
            'source_text_visible': false,
            'audio_play_count': audioPlayCount,
            'notes_allowed': false,
            'l1_trigger': l1Trigger,
            'speaking_assistance': speakingAssistance,
            'speaking_recall': speakingRecall,
            'prompt_snapshot': promptSnapshot,
          },
          'responses': [
            {
              'revision': 1,
              'raw_transcript': rawTranscript,
              'transcript': correctedTranscript,
              'source': 'asr',
              'recording_asset_id': recordingAssetId,
              'asr_reliability': asrReliability,
              'language': responseLanguage,
              'recorded_at_ms': endedAtMs,
            },
          ],
          'status': 'completed',
          'started_at_ms': startedAtMs,
          'ended_at_ms': endedAtMs,
        }))
        as Map<String, dynamic>,
  );

  Future<SemanticAttemptView> createWritingAttempt({
    required String kind,
    required Map<String, dynamic> target,
    required String rubricId,
    required int rubricVersion,
    required bool sourceTextVisible,
    required int? audioPlayCount,
    required String promptSnapshot,
    required List<String> revisions,
    required String responseLanguage,
    required int startedAtMs,
    required int endedAtMs,
  }) async => SemanticAttemptView.fromJson(
    (await _request('POST', '/v1/semantic/attempts', {
          'kind': kind,
          'target': target,
          'anchors': const <dynamic>[],
          'rubric_id': rubricId,
          'rubric_version': rubricVersion,
          'conditions': {
            'source_text_visible': sourceTextVisible,
            'audio_play_count': audioPlayCount,
            'notes_allowed': true,
            'l1_trigger': null,
            'speaking_assistance': null,
            'speaking_recall': null,
            'prompt_snapshot': promptSnapshot,
          },
          'responses': [
            for (var index = 0; index < revisions.length; index++)
              {
                'revision': index + 1,
                'raw_transcript': null,
                'transcript': revisions[index],
                'source': 'typed',
                'recording_asset_id': null,
                'asr_reliability': null,
                'language': responseLanguage,
                'recorded_at_ms': endedAtMs + index,
              },
          ],
          'status': 'completed',
          'started_at_ms': startedAtMs,
          'ended_at_ms': endedAtMs,
        }))
        as Map<String, dynamic>,
  );

  Future<List<WritingFeedbackFindingView>> generateLocalWritingFindings(
    String attemptId,
    int revision,
  ) async =>
      ((await _request(
                'POST',
                '/v1/semantic/attempts/${Uri.encodeComponent(attemptId)}/writing-findings/local',
                {'response_revision': revision},
              ))
              as List<dynamic>)
          .map(
            (item) => WritingFeedbackFindingView.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);

  Future<WritingDraftView?> writingDraft(String rubricId) async {
    // Draft recovery is best-effort: the writes in the controller
    // (`_persistDraft`, `deleteWritingDraft`) already swallow failures, so a
    // failed read must not block opening the task either. Any transport/HTTP
    // error degrades to "no recoverable draft".
    try {
      final json = await _request(
        'GET',
        '/v1/semantic/writing-drafts/${Uri.encodeComponent(rubricId)}',
      );
      if (json == null) return null;
      return WritingDraftView.fromJson(json as Map<String, dynamic>);
    } on HttpException {
      return null;
    }
  }

  Future<WritingDraftView> saveWritingDraft({
    required String rubricId,
    required String promptSnapshot,
    required String transcript,
  }) async => WritingDraftView.fromJson(
    (await _request(
          'PUT',
          '/v1/semantic/writing-drafts/${Uri.encodeComponent(rubricId)}',
          {'prompt_snapshot': promptSnapshot, 'transcript': transcript},
        ))
        as Map<String, dynamic>,
  );

  Future<void> deleteWritingDraft(String rubricId) async {
    await _request(
      'DELETE',
      '/v1/semantic/writing-drafts/${Uri.encodeComponent(rubricId)}',
    );
  }

  Future<WritingFindingDispositionView> createWritingDisposition({
    required String findingId,
    required String decision,
    String? resultingAttemptId,
    int? resultingRevision,
  }) async => WritingFindingDispositionView.fromJson(
    (await _request(
          'POST',
          '/v1/semantic/writing-findings/${Uri.encodeComponent(findingId)}/dispositions',
          {
            'decision': decision,
            'resulting_attempt_id': resultingAttemptId,
            'resulting_response_revision': resultingRevision,
            'note': null,
          },
        ))
        as Map<String, dynamic>,
  );

  Future<List<SemanticJudgmentView>> semanticAttemptJudgments(
    String attemptId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/semantic/attempts/${Uri.encodeComponent(attemptId)}/judgments',
              ))
              as List<dynamic>)
          .map((j) => SemanticJudgmentView.fromJson(j as Map<String, dynamic>))
          .toList(growable: false);

  /// Records a judgment over one attempt response. The server re-validates
  /// hashes and the point/span contract against the stored rubric/attempt.
  Future<SemanticJudgmentView> createSemanticJudgment({
    required String attemptId,
    required int responseRevision,
    required String rubricId,
    required int rubricVersion,
    required String rubricTranscriptSnapshot,
    required String responseTranscript,
    required List<PointJudgmentView> points,
    required SemanticProvenanceView provenance,
    required String evidenceClass,
  }) async => SemanticJudgmentView.fromJson(
    (await _request('POST', '/v1/semantic/judgments', {
          'attempt_id': attemptId,
          'response_revision': responseRevision,
          'rubric_id': rubricId,
          'rubric_version': rubricVersion,
          'rubric_source_sha256': transcriptSha256(rubricTranscriptSnapshot),
          'response_transcript_sha256': transcriptSha256(responseTranscript),
          'points': points.map((p) => p.toJson()).toList(),
          'abstain': null,
          'provenance': provenance.toJson(),
          'evidence_class': evidenceClass,
        }))
        as Map<String, dynamic>,
  );

  Future<void> confirmSpeakingTarget({
    required String attemptId,
    required String lexicalEntryId,
    required String surfaceForm,
    String? sentenceId,
  }) async {
    await _request(
      'POST',
      '/v1/semantic/attempts/${Uri.encodeComponent(attemptId)}/speaking-targets',
      {
        'lexical_entry_id': lexicalEntryId,
        'surface_form': surfaceForm,
        'sentence_id': sentenceId,
      },
    );
  }

  Future<List<JudgmentAdjudicationView>> judgmentAdjudications(
    String judgmentId,
  ) async =>
      ((await _request(
                'GET',
                '/v1/semantic/judgments/${Uri.encodeComponent(judgmentId)}/adjudications',
              ))
              as List<dynamic>)
          .map(
            (a) => JudgmentAdjudicationView.fromJson(a as Map<String, dynamic>),
          )
          .toList(growable: false);

  Future<JudgmentAdjudicationView> createJudgmentAdjudication({
    required String judgmentId,
    required String pointId,
    required String priorVerdict,
    required String userVerdict,
    String? note,
  }) async => JudgmentAdjudicationView.fromJson(
    (await _request('POST', '/v1/semantic/adjudications', {
          'judgment_id': judgmentId,
          'point_id': pointId,
          'prior_verdict': priorVerdict,
          'user_verdict': userVerdict,
          'note': ?note,
        }))
        as Map<String, dynamic>,
  );
}
