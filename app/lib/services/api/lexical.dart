part of '../api_service.dart';

// Lexical entries, vocabulary, dictionary, learner profile, diagnosis.
// Split out of api_service.dart (mechanical decomposition).

extension LexicalApi on LocalApi {
  Future<List<LexicalEntry>> readLexicalEntriesBatch(
    List<String> forms, {
    required String language,
    String kind = 'word',
  }) async {
    final values =
        await _request('POST', '/v1/lexical-entries/batch', {
              'language': language,
              'kind': kind,
              'forms': forms,
            })
            as List<dynamic>;
    return values
        .map((value) => LexicalEntry.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<LexicalEntryDetails> upsertWordLexicalEntry(
    String canonicalForm,
    String displayForm,
    String? status, {
    required String language,
    Map<String, dynamic>? source,
  }) async {
    final details = await upsertLexicalEntry({
      'language': language,
      'kind': 'word',
      'canonical_form': canonicalForm,
      'display_form': displayForm,
      'status': status,
      'source': source,
    });
    return details;
  }

  Future<void> createLexicalObservation({
    required String lexicalEntryId,
    required String sentenceId,
    required String originalForm,
    required bool heard,
    Map<String, dynamic>? source,
  }) async {
    await _request('POST', '/v1/lexical-observations', {
      'lexical_entry_id': lexicalEntryId,
      'sentence_id': sentenceId,
      'original_form': originalForm,
      'result': heard ? 'recognized_in_context' : 'not_recognized_in_context',
      'source': source,
    });
  }

  Future<void> clearLexicalObservation({
    required String lexicalEntryId,
    required String sentenceId,
  }) async {
    await _request('POST', '/v1/lexical-observations', {
      'lexical_entry_id': lexicalEntryId,
      'sentence_id': sentenceId,
      'original_form': '',
      'clear': true,
    });
  }

  /// Evidence & history for one entry (issue #2): the append-only channelized
  /// observation trail, newest first. [capability] narrows to one channel;
  /// paging via [limit]/[offset] (server caps limit at 200).
  Future<List<LearningObservationView>> learningObservationHistory(
    String lexicalEntryId, {
    String? capability,
    int? limit,
    int? offset,
  }) async {
    final query = <String, String>{
      'capability': ?capability,
      if (limit != null) 'limit': '$limit',
      if (offset != null) 'offset': '$offset',
    };
    final suffix = query.isEmpty ? '' : '?${Uri(queryParameters: query).query}';
    final values =
        await _request(
              'GET',
              '/v1/lexical-entries/${Uri.encodeComponent(lexicalEntryId)}/observations$suffix',
              null,
            )
            as List<dynamic>;
    return values
        .map(
          (value) =>
              LearningObservationView.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  /// Lists the vocabulary book. All filters are optional and additive: [status]
  /// is the legacy status axis; [capability] + [assessment] together filter by a
  /// four-channel capability dimension (both required to take effect); [kind]
  /// omitted returns both words and phrases.
  Future<List<LexicalEntryDetails>> listVocabulary({
    required String language,
    String? status,
    String? capability,
    String? assessment,
    String? kind,
    String search = '',
    int limit = 200,
    int offset = 0,
  }) async {
    final params = <String, String>{
      'language': language,
      'search': search,
      'limit': '$limit',
      'offset': '$offset',
      'status': ?status,
      'capability': ?capability,
      'assessment': ?assessment,
      'kind': ?kind,
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final values =
        await _request('GET', '/v1/vocabulary?$query') as List<dynamic>;
    return values
        .map(
          (value) =>
              LexicalEntryDetails.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<LexicalEntryDetails> lexicalEntryDetails(String entryId) async =>
      LexicalEntryDetails.fromJson(
        (await _request('GET', '/v1/lexical-entries/$entryId'))
            as Map<String, dynamic>,
      );

  Future<LexicalCapabilityProfile> setCapabilityOverride(
    String entryId,
    String capability, {
    String? conclusion,
  }) async => LexicalCapabilityProfile.fromJson(
    (await _request(
          'PUT',
          '/v1/lexical-entries/${Uri.encodeComponent(entryId)}/capability/$capability',
          {'conclusion': conclusion},
        ))
        as Map<String, dynamic>,
  );

  Future<LexicalEntryDetails> updateLexicalLearningContent(
    String entryId, {
    String? userDefinition,
    String? personalNote,
  }) async => LexicalEntryDetails.fromJson(
    (await _request('PUT', '/v1/lexical-entries/$entryId/learning-content', {
          'user_definition': userDefinition,
          'personal_note': personalNote,
        }))
        as Map<String, dynamic>,
  );

  Future<LexicalEntryDetails> createLexicalSenseFolder(
    String entryId, {
    required String label,
    String? definition,
    String? gloss,
    String? externalRef,
  }) async => LexicalEntryDetails.fromJson(
    (await _request(
          'POST',
          '/v1/lexical-entries/${Uri.encodeComponent(entryId)}/sense-folders',
          {
            'label': label,
            'definition': definition,
            'gloss': gloss,
            'external_ref': externalRef,
          },
        ))
        as Map<String, dynamic>,
  );

  Future<LexicalEntryDetails> updateLexicalSenseFolder(
    String entryId,
    String senseId, {
    required String label,
    String? definition,
    String? gloss,
    String? externalRef,
  }) async => LexicalEntryDetails.fromJson(
    (await _request(
          'PUT',
          '/v1/lexical-entries/${Uri.encodeComponent(entryId)}/sense-folders/${Uri.encodeComponent(senseId)}',
          {
            'label': label,
            'definition': definition,
            'gloss': gloss,
            'external_ref': externalRef,
          },
        ))
        as Map<String, dynamic>,
  );

  Future<LexicalEntryDetails> deleteLexicalSenseFolder(
    String entryId,
    String senseId,
  ) async => LexicalEntryDetails.fromJson(
    (await _request(
          'DELETE',
          '/v1/lexical-entries/${Uri.encodeComponent(entryId)}/sense-folders/${Uri.encodeComponent(senseId)}',
        ))
        as Map<String, dynamic>,
  );

  Future<LexicalEntryDetails> assignLexicalSenseFolderOccurrence(
    String entryId,
    String senseId,
    String occurrenceId,
  ) async => LexicalEntryDetails.fromJson(
    (await _request(
          'PUT',
          '/v1/lexical-entries/${Uri.encodeComponent(entryId)}/sense-folders/${Uri.encodeComponent(senseId)}/occurrences/${Uri.encodeComponent(occurrenceId)}',
          const {},
        ))
        as Map<String, dynamic>,
  );

  Future<LexicalEntryDetails> unassignLexicalSenseFolderOccurrence(
    String entryId,
    String senseId,
    String occurrenceId,
  ) async => LexicalEntryDetails.fromJson(
    (await _request(
          'DELETE',
          '/v1/lexical-entries/${Uri.encodeComponent(entryId)}/sense-folders/${Uri.encodeComponent(senseId)}/occurrences/${Uri.encodeComponent(occurrenceId)}',
        ))
        as Map<String, dynamic>,
  );

  Future<ExternalVocabularyImportSummary> importExternalVocabulary(
    List<Map<String, dynamic>> entries, {
    required String language,
    String? defaultStatus,
    bool overwriteExisting = false,
  }) async => ExternalVocabularyImportSummary.fromJson(
    (await _request('POST', '/v1/vocabulary/import-external', {
          'language': language,
          'entries': entries,
          'default_status': defaultStatus,
          'overwrite_existing': overwriteExisting,
        }))
        as Map<String, dynamic>,
  );

  Future<VocabularyExportBundle> exportVocabulary() async =>
      VocabularyExportBundle.fromJson(
        (await _request('GET', '/v1/vocabulary/export'))
            as Map<String, dynamic>,
      );

  /// Total saved vocabulary for [language], aggregated client-side across the
  /// learning statuses. Each status page is capped by the backend, so very
  /// large collections report the cap with [SavedVocabularyCount.capped] set.
  Future<SavedVocabularyCount> savedVocabularyCount({
    required String language,
  }) async {
    const statuses = [
      'unknown_meaning',
      'known_not_recognized',
      'known_recognized',
    ];
    const pageLimit = 200;
    final pages = await Future.wait(
      statuses.map(
        (status) => listVocabulary(status: status, language: language),
      ),
    );
    var total = 0;
    var capped = false;
    for (final page in pages) {
      total += page.length;
      if (page.length >= pageLimit) capped = true;
    }
    return SavedVocabularyCount(total: total, capped: capped);
  }

  Future<void> importVocabulary(Map<String, dynamic> bundle) async {
    await _request('POST', '/v1/vocabulary/import', bundle);
  }

  Future<DictionaryLookupBundle> lookupDictionary(
    String lemma, {
    required String language,
  }) async => DictionaryLookupBundle.fromJson(
    (await _request(
          'GET',
          '/v1/dictionary?language=${Uri.encodeQueryComponent(language)}&lemma=${Uri.encodeQueryComponent(lemma)}',
        ))
        as Map<String, dynamic>,
  );

  Future<LearnerProfileView> learnerProfile() async =>
      LearnerProfileView.fromJson(
        (await _request('GET', '/v1/learner/profile')) as Map<String, dynamic>,
      );

  Future<LearnerProfileView> updateLearnerProfile({
    String? l1Language,
    String? uiLanguage,
  }) async => LearnerProfileView.fromJson(
    (await _request('PUT', '/v1/learner/profile', {
          'l1_language': l1Language,
          'ui_language': uiLanguage,
        }))
        as Map<String, dynamic>,
  );

  Future<L1SpecialtyView> l1SpecialtyOccurrences({
    required String difficultyKind,
    required String language,
    String? trackId,
    int limit = 30,
  }) async {
    final query = <String, String>{
      'difficulty_kind': difficultyKind,
      'language': language,
      'track_id': ?trackId,
      'limit': '$limit',
    };
    final encoded = query.entries
        .map((entry) => '${entry.key}=${Uri.encodeQueryComponent(entry.value)}')
        .join('&');
    return L1SpecialtyView.fromJson(
      (await _request('GET', '/v1/learner/l1-specialty?$encoded'))
          as Map<String, dynamic>,
    );
  }

  Future<Diagnosis> diagnose(String sentenceId) async => Diagnosis.fromJson(
    (await _request(
          'GET',
          '/v1/sentences/${Uri.encodeComponent(sentenceId)}/diagnosis',
        ))
        as Map<String, dynamic>,
  );

  Future<List<LexicalEntryDetails>> lexicalEntries({
    required String language,
    String? kind,
    String? status,
    String search = '',
  }) async {
    final query = <String, String>{
      'language': language,
      'search': search,
      'limit': '200',
      'offset': '0',
    };
    if (kind != null) query['kind'] = kind;
    if (status != null) query['status'] = status;
    final values =
        await _request(
              'GET',
              '/v1/lexical-entries?${Uri(queryParameters: query).query}',
            )
            as List<dynamic>;
    return values
        .map(
          (value) =>
              LexicalEntryDetails.fromJson(value as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<LexicalEntryDetails> upsertLexicalEntry(
    Map<String, dynamic> value,
  ) async => LexicalEntryDetails.fromJson(
    (await _request('PUT', '/v1/lexical-entries', value))
        as Map<String, dynamic>,
  );

  Future<LexicalNormalization> correctLemma(
    String original,
    String corrected, {
    required String language,
  }) async => LexicalNormalization.fromJson(
    (await _request('POST', '/v1/lexical-normalization/correct', {
          'language': language,
          'original': original,
          'corrected': corrected,
        }))
        as Map<String, dynamic>,
  );

  Future<List<PhraseCandidate>> phraseCandidates(String sentenceId) async =>
      ((await _request(
                'GET',
                '/v1/sentences/${Uri.encodeComponent(sentenceId)}/phrase-candidates',
              ))
              as List<dynamic>)
          .map(
            (value) => PhraseCandidate.fromJson(value as Map<String, dynamic>),
          )
          .toList(growable: false);
}
