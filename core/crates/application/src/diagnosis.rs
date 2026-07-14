use crate::*;

impl MediaAnalysisUseCases {
    pub fn diagnose_sentence(
        &self,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<SentenceDiagnosis, ApplicationError> {
        let sentence = self
            .subtitle_tracks
            .get_sentence(sentence_id)?
            .ok_or(ApplicationError::NotFound("subtitle sentence"))?;
        let lemmas = sentence
            .tokens
            .iter()
            .filter_map(|token| token.normalized.clone())
            .collect::<Vec<_>>();
        let language = self.sentence_language(sentence_id)?;
        let mut lexical_keys = std::collections::HashMap::new();
        for lemma in &lemmas {
            if lexical_keys.contains_key(lemma) {
                continue;
            }
            let normalized = self
                .lexical_learning()
                .normalize_lexical_form(language.as_str(), lemma)?
                .normalized;
            lexical_keys.insert(lemma.clone(), normalized);
        }
        let keys = lexical_keys
            .values()
            .cloned()
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        let entries = self.lexical_entries.lexical_entries_by_keys(
            &language,
            LexicalEntryKind::Word,
            &keys,
        )?;
        let phrase_keys = self
            .lexical_learning()
            .phrase_candidates(sentence_id)?
            .into_iter()
            .map(|candidate| candidate.normalized_form)
            .collect::<std::collections::BTreeSet<_>>()
            .into_iter()
            .collect::<Vec<_>>();
        let phrase_entries = self.lexical_entries.lexical_entries_by_keys(
            &language,
            LexicalEntryKind::Phrase,
            &phrase_keys,
        )?;
        let mut profiles = std::collections::HashMap::new();
        for entry in entries.iter().chain(phrase_entries.iter()) {
            if let Some(profile) = self
                .lexical_learning()
                .lexical_capabilities
                .lexical_capability_profile(&entry.id, None)?
            {
                profiles.insert(entry.id.clone(), profile);
            }
        }
        let observations = self
            .lexical_learning()
            .learning_observations
            .list_lexical_observations_by_sentence(sentence_id)?;
        let mut diagnosis = diagnosis_core::diagnose_with_profiles(
            &sentence,
            &entries,
            &phrase_entries,
            &profiles,
            &observations,
            &lexical_keys,
        );
        let reasons = domain::profile_for(&language).diagnosis_reasons;
        if !reasons.is_empty() {
            for hint in &mut diagnosis.hints {
                if hint.kind == domain::DiagnosisKind::RecognitionBarrier {
                    hint.reasons = reasons.clone();
                }
            }
        }
        self.apply_l1_diagnosis(&mut diagnosis, &language, sentence_id)?;
        Ok(diagnosis)
    }

    /// Layer the L1-aware short hints (Phase 3.9) onto a base diagnosis.
    /// Clean-degradation ladder: no declared L1 -> untouched baseline; L1 set
    /// but (L1, L2) pair unsupported -> context only (client shows a neutral
    /// note); supported pair but no sound-side barrier, no rhythm frame, or
    /// no replayable evidence -> context only, no hints. Hints follow the
    /// possibilities register of `DiagnosisHint.reasons`, never detections.
    fn apply_l1_diagnosis(
        &self,
        diagnosis: &mut SentenceDiagnosis,
        language: &LanguageCode,
        sentence_id: &SubtitleSentenceId,
    ) -> Result<(), ApplicationError> {
        const MAX_HINTS: usize = 3;
        const MAX_SPANS_PER_HINT: usize = 8;
        let Some(l1) = self.learner_profile().learner_l1()? else {
            return Ok(());
        };
        let Some(rules) = diagnosis_core::l1l2_difficulty_rules(&l1, language) else {
            diagnosis.l1_context = Some(L1DiagnosisContext {
                l1,
                l2: language.clone(),
                support: L1DiagnosisSupport::UnsupportedPair,
            });
            return Ok(());
        };
        diagnosis.l1_context = Some(L1DiagnosisContext {
            l1: l1.clone(),
            l2: language.clone(),
            support: L1DiagnosisSupport::Supported,
        });
        // L1 hints explain *sound-side* misses; a pure meaning barrier is not
        // a listening-transfer story.
        let sound_side_failure = diagnosis.hints.iter().any(|hint| {
            matches!(
                hint.kind,
                DiagnosisKind::RecognitionBarrier | DiagnosisKind::OtherFactors
            )
        });
        if !sound_side_failure {
            return Ok(());
        }
        let Some(track_id) = self.subtitle_tracks.sentence_track_id(sentence_id)? else {
            return Ok(());
        };
        // Rhythm frames are assembled from the track's word timelines; any
        // assembly failure (orphaned media, no timeline yet) degrades to the
        // baseline diagnosis instead of failing the whole read.
        let Ok(document) = self.export_lltimeline_document(&track_id) else {
            return Ok(());
        };
        let Some(frame) = document
            .rhythm_frames
            .iter()
            .find(|frame| frame.sentence_id == *sentence_id)
        else {
            return Ok(());
        };
        let hits = diagnosis_core::match_l1_difficulty_hits(rules, &frame.rhythm_frame);
        for hit in hits.iter().take(MAX_HINTS) {
            diagnosis.l1_hints.push(L1DiagnosisHint {
                difficulty_kind: hit.kind.clone(),
                message: hit.explanation.clone(),
                families: hit.families.clone(),
                spans: hit
                    .spans
                    .iter()
                    .take(MAX_SPANS_PER_HINT)
                    .map(|span| L1DiagnosisSpan {
                        family: span.family.clone(),
                        start_ms: span.start_ms,
                        end_ms: span.end_ms,
                        label: span.label.clone(),
                        surface_text: span.surface_text.clone(),
                    })
                    .collect(),
            });
        }
        // Durable hit record for the 3.10 difficulty distribution. The id
        // fingerprints (sentence, category), so re-diagnosing the same
        // sentence is idempotent; a failed append must not break the
        // diagnosis read path (the event store may be disabled).
        let now = now_ms();
        for hint in &diagnosis.l1_hints {
            let _ = self.learning_events.append_learning_event(&LearningEvent {
                id: LearningEventId::from_fingerprint(
                    "learning-event",
                    &format!(
                        "l1-difficulty-hit:{}:{}",
                        sentence_id.as_str(),
                        hint.difficulty_kind
                    ),
                ),
                occurred_at_ms: now,
                kind: LearningEventKind::L1DifficultyHit,
                subject: LearningEventSubject {
                    kind: LearningEventSubjectKind::Sentence,
                    id: sentence_id.as_str().to_owned(),
                },
                payload: serde_json::json!({
                    "l1": l1.as_str(),
                    "l2": language.as_str(),
                    "difficulty_kind": hint.difficulty_kind,
                    "families": hint.families,
                    "span_count": hint.spans.len(),
                    "media_id": document.metadata.media.id.as_str(),
                }),
                session_id: None,
            });
        }
        Ok(())
    }
}
