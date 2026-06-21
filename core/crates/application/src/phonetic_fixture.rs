use crate::*;

impl AppServices {
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
            phones.push(DetectedPhone {
                symbol: word
                    .normalized
                    .as_deref()
                    .and_then(|value| value.chars().next())
                    .unwrap_or('?')
                    .to_ascii_uppercase()
                    .to_string(),
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
        let canonical = sentence
            .map(speech_analysis::analyze_sentence)
            .into_iter()
            .flat_map(|analysis| analysis.phonemes)
            .filter_map(|phone| {
                phone.token_index.map(|token_index| {
                    speech_analysis::phonetic_alignment::CanonicalPhone {
                        symbol: phone.symbol,
                        token_index,
                    }
                })
            })
            .collect::<Vec<_>>();
        let alignments = speech_analysis::phonetic_alignment::align_phones(&canonical, &phones);
        let findings = speech_analysis::phonetic_findings::findings_from_alignments(
            &id,
            job.audio_start_ms,
            job.audio_end_ms,
            &alignments,
            &phones,
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
            analyzer_version: "research-fixture-v1".into(),
            created_at_ms: now_ms(),
        };
        analysis.validate().map_err(ApplicationError::from)?;
        Ok(analysis)
    }
}
