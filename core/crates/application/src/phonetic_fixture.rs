use crate::*;

impl MediaAnalysisUseCases {
    pub fn build_research_fixture_phonetic_analysis(
        &self,
        job: &PhoneticAnalysisJob,
        sentence: Option<&SubtitleSentence>,
        partial: bool,
    ) -> Result<PhoneticAnalysis, ApplicationError> {
        let words = sentence
            .into_iter()
            .flat_map(|value| value.tokens.iter())
            .filter(|token| token.kind == SubtitleTokenKind::Word)
            .collect::<Vec<_>>();
        let duration = job.audio_end_ms - job.audio_start_ms;
        let width = duration / words.len().max(1) as u64;
        let mut phones = Vec::new();
        for (index, word) in words.iter().enumerate() {
            let start = job.audio_start_ms + width * index as u64;
            let end = if index + 1 == words.len() {
                job.audio_end_ms
            } else {
                start + width
            };
            let sym = word
                .normalized
                .as_deref()
                .and_then(|value| value.chars().next())
                .unwrap_or('?')
                .to_ascii_uppercase()
                .to_string();
            phones.push(DetectedPhone {
                display_ipa: sym.clone(),
                symbol: sym,
                phone_set: "research_fixture_symbols".into(),
                start_ms: start,
                end_ms: end,
                confidence: Some(0.5),
                token_index: Some(word.index),
                provider_id: "research-fixture".into(),
                provider_version: "v1".into(),
                model_revision: job.model_revision.clone(),
            });
        }
        if partial && phones.len() > 1 {
            phones.pop();
        }
        let id = PhoneticAnalysisId::from_fingerprint(
            "phonetic-analysis",
            &format!(
                "{}:{}:{}:{}:{}",
                job.id.as_str(),
                job.input_fingerprint,
                job.sentence_id
                    .as_ref()
                    .map(SubtitleSentenceId::as_str)
                    .unwrap_or("track"),
                job.audio_start_ms,
                job.audio_end_ms
            ),
        );
        let is_english = job
            .sentence_id
            .as_ref()
            .and_then(|sid| self.sentence_language(sid).ok())
            .map(|lang| lang.as_str().starts_with("en"))
            .unwrap_or(true);
        let canonical = if is_english {
            sentence
                .map(speech_analysis::analyze_sentence)
                .into_iter()
                .flat_map(|analysis| analysis.phonemes)
                .filter_map(|phone| {
                    phone.token_index.map(|token_index| {
                        speech_analysis::phonetics::CanonicalPhone {
                            symbol: phone.symbol,
                            token_index,
                            stress: phone.stress,
                        }
                    })
                })
                .collect::<Vec<_>>()
        } else {
            Vec::new()
        };
        let alignments = speech_analysis::phonetics::align_phones(&canonical, &phones);
        let findings = speech_analysis::phonetics::findings_from_alignments(
            &id,
            job.audio_start_ms,
            job.audio_end_ms,
            &alignments,
            &phones,
        );
        let word_timings =
            self.active_sentence_word_timings(&job.track_id, job.sentence_id.as_ref())?;
        let sound_analysis = speech_analysis::audible_structure::build_sound_analysis(
            &canonical,
            &phones,
            &alignments,
            speech_analysis::audible_structure::SoundAnalysisConfig {
                provider_id: "research-fixture",
                provider_version: "v1",
                model_revision: Some(job.model_revision.clone()),
                phone_set: "research_fixture_symbols",
                sentence,
                word_timings: (!word_timings.is_empty()).then_some(word_timings.as_slice()),
                word_acoustic_cues: None,
            },
        );
        let analysis = PhoneticAnalysis {
            id,
            job_id: job.id.clone(),
            media_id: job.media_id.clone(),
            track_id: job.track_id.clone(),
            sentence_id: job.sentence_id.clone(),
            audio_start_ms: job.audio_start_ms,
            audio_end_ms: job.audio_end_ms,
            provider_id: "research-fixture".into(),
            provider_version: "v1".into(),
            model_id: job.model_id.clone(),
            model_revision: job.model_revision.clone(),
            model_checksum_sha256: job.model_checksum_sha256.clone(),
            phone_set: "research_fixture_symbols".into(),
            detected_phones: phones,
            alignments,
            findings,
            sound_analysis: Some(sound_analysis),
            analyzer_version: "research-fixture-v1".into(),
            created_at_ms: now_ms(),
        };
        analysis.validate().map_err(ApplicationError::from)?;
        Ok(analysis)
    }

    pub fn build_ctc_phonetic_analysis(
        &self,
        job: &PhoneticAnalysisJob,
        sentence: Option<&SubtitleSentence>,
        audio_path: &str,
        model_dir: &str,
    ) -> Result<PhoneticAnalysis, ApplicationError> {
        let recognized = speech_analysis::phonetics::recognize_phones(
            audio_path,
            model_dir,
            job.audio_start_ms,
            job.audio_end_ms,
            &job.model_revision,
        )
        .map_err(|e| ApplicationError::ExternalProcess(e.into()))?;
        let phones = recognized.phones;
        if phones.is_empty() {
            return Err(ApplicationError::Validation("no phones detected in audio"));
        }
        let id = PhoneticAnalysisId::from_fingerprint(
            "phonetic-analysis",
            &format!(
                "{}:{}:{}:{}:{}",
                job.id.as_str(),
                job.input_fingerprint,
                job.sentence_id
                    .as_ref()
                    .map(SubtitleSentenceId::as_str)
                    .unwrap_or("track"),
                job.audio_start_ms,
                job.audio_end_ms
            ),
        );
        let canonical = sentence
            .map(speech_analysis::analyze_sentence)
            .into_iter()
            .flat_map(|analysis| analysis.phonemes)
            .filter_map(|phone| {
                phone.token_index.map(|token_index| {
                    speech_analysis::phonetics::CanonicalPhone {
                        symbol: phone.symbol,
                        token_index,
                        stress: phone.stress,
                    }
                })
            })
            .collect::<Vec<_>>();
        let alignments = speech_analysis::phonetics::align_phones(&canonical, &phones);
        let findings = speech_analysis::phonetics::findings_from_alignments(
            &id,
            job.audio_start_ms,
            job.audio_end_ms,
            &alignments,
            &phones,
        );
        let word_timings =
            self.active_sentence_word_timings(&job.track_id, job.sentence_id.as_ref())?;
        let sound_analysis = speech_analysis::audible_structure::build_sound_analysis(
            &canonical,
            &phones,
            &alignments,
            speech_analysis::audible_structure::SoundAnalysisConfig {
                provider_id: speech_analysis::phonetics::PROVIDER_ID,
                provider_version: speech_analysis::phonetics::PROVIDER_VERSION,
                model_revision: Some(job.model_revision.clone()),
                phone_set: "arpabet",
                sentence,
                word_timings: (!word_timings.is_empty()).then_some(word_timings.as_slice()),
                word_acoustic_cues: None,
            },
        );
        let analysis = PhoneticAnalysis {
            id,
            job_id: job.id.clone(),
            media_id: job.media_id.clone(),
            track_id: job.track_id.clone(),
            sentence_id: job.sentence_id.clone(),
            audio_start_ms: job.audio_start_ms,
            audio_end_ms: job.audio_end_ms,
            provider_id: speech_analysis::phonetics::PROVIDER_ID.into(),
            provider_version: speech_analysis::phonetics::PROVIDER_VERSION.into(),
            model_id: job.model_id.clone(),
            model_revision: job.model_revision.clone(),
            model_checksum_sha256: job.model_checksum_sha256.clone(),
            phone_set: "arpabet".into(),
            detected_phones: phones,
            alignments,
            findings,
            sound_analysis: Some(sound_analysis),
            analyzer_version: format!(
                "{}-{}",
                speech_analysis::phonetics::PROVIDER_ID,
                speech_analysis::phonetics::PROVIDER_VERSION
            ),
            created_at_ms: now_ms(),
        };
        analysis.validate().map_err(ApplicationError::from)?;
        Ok(analysis)
    }

    fn active_sentence_word_timings(
        &self,
        track_id: &SubtitleTrackId,
        sentence_id: Option<&SubtitleSentenceId>,
    ) -> Result<Vec<WordTiming>, ApplicationError> {
        let Some(sentence_id) = sentence_id else {
            return Ok(Vec::new());
        };
        let Some(timeline) = self.word_timelines.active_word_timeline(track_id)? else {
            return Ok(Vec::new());
        };
        let mut words = timeline
            .words
            .into_iter()
            .filter(|word| &word.sentence_id == sentence_id)
            .collect::<Vec<_>>();
        words.sort_by_key(|word| (word.start_ms, word.end_ms, word.token_index));
        Ok(words)
    }
}
