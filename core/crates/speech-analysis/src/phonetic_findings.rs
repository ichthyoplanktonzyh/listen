use domain::{
    DetectedPhone, PhoneAlignment, PhoneAlignmentKind, PhoneticAnalysisId, PhoneticFinding,
    PhoneticFindingId, PhoneticFindingStatus,
};

pub fn findings_from_alignments(
    analysis_id: &PhoneticAnalysisId,
    audio_start_ms: u64,
    audio_end_ms: u64,
    alignments: &[PhoneAlignment],
    detected_phones: &[DetectedPhone],
) -> Vec<PhoneticFinding> {
    alignments
        .iter()
        .enumerate()
        .filter(|(_, alignment)| alignment.kind != PhoneAlignmentKind::Match)
        .filter_map(|(index, alignment)| {
            let token_start = alignment.token_start.or_else(|| {
                alignment
                    .detected_phone_start
                    .and_then(|phone| detected_phones.get(phone as usize)?.token_index)
            })?;
            let token_end = alignment.token_end.unwrap_or(token_start);
            let detected = detected_slice(alignment, detected_phones);
            let (start_ms, end_ms) = detected
                .first()
                .zip(detected.last())
                .map(|(first, last)| (first.start_ms, last.end_ms))
                .unwrap_or((audio_start_ms, audio_end_ms));
            let confidence = alignment.confidence.clamp(0.0, 1.0);
            let finding_type = classify(alignment, detected);
            let status = if confidence >= 0.75 {
                PhoneticFindingStatus::DetectedInAudio
            } else if confidence >= 0.6 {
                PhoneticFindingStatus::SupportedByAlignment
            } else {
                PhoneticFindingStatus::Uncertain
            };
            Some(PhoneticFinding {
                id: PhoneticFindingId::from_fingerprint(
                    "phonetic-finding",
                    &format!("{}:{index}:{finding_type}", analysis_id.as_str()),
                ),
                analysis_id: analysis_id.clone(),
                finding_type: finding_type.into(),
                affected_token_start: token_start,
                affected_token_end: token_end,
                canonical_phones: alignment.canonical_phones.clone(),
                detected_phones: detected.iter().map(|phone| phone.symbol.clone()).collect(),
                aligned_phone_start: alignment.detected_phone_start,
                aligned_phone_end: alignment.detected_phone_end,
                audio_start_ms: start_ms,
                audio_end_ms: end_ms,
                confidence,
                evidence: format!(
                    "{:?} alignment between canonical and detected phone timelines",
                    alignment.kind
                ),
                status,
            })
        })
        .collect()
}

fn classify(alignment: &PhoneAlignment, detected: &[DetectedPhone]) -> &'static str {
    let canonical = alignment
        .canonical_phones
        .iter()
        .map(String::as_str)
        .collect::<Vec<_>>();
    let detected = detected
        .iter()
        .map(|phone| phone.symbol.as_str())
        .collect::<Vec<_>>();
    match alignment.kind {
        PhoneAlignmentKind::Substitution
            if canonical.iter().any(|phone| matches!(*phone, "T" | "D"))
                && detected.iter().any(|phone| matches!(*phone, "DX" | "ɾ")) =>
        {
            "flapping"
        }
        PhoneAlignmentKind::Substitution
            if detected
                .iter()
                .any(|phone| matches!(*phone, "AX" | "AH" | "ə")) =>
        {
            "weak_form"
        }
        PhoneAlignmentKind::Merge => "assimilation",
        PhoneAlignmentKind::Deletion if alignment.token_start != alignment.token_end => {
            "contraction"
        }
        PhoneAlignmentKind::Deletion => "elision",
        PhoneAlignmentKind::Substitution => "phone_substitution",
        PhoneAlignmentKind::Insertion => "linking_or_insertion",
        PhoneAlignmentKind::Match => "match",
    }
}

fn detected_slice<'a>(
    alignment: &PhoneAlignment,
    detected_phones: &'a [DetectedPhone],
) -> &'a [DetectedPhone] {
    match (alignment.detected_phone_start, alignment.detected_phone_end) {
        (Some(start), Some(end)) if start <= end => detected_phones
            .get(start as usize..=end as usize)
            .unwrap_or_default(),
        _ => &[],
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn below_detection_threshold_never_claims_detected_in_audio() {
        let analysis_id = PhoneticAnalysisId::from_fingerprint("analysis", "low-confidence");
        let findings = findings_from_alignments(
            &analysis_id,
            0,
            100,
            &[alignment(PhoneAlignmentKind::Substitution, 0.74)],
            &[phone("AX", 0.74)],
        );

        assert_eq!(findings.len(), 1);
        assert_eq!(
            findings[0].status,
            PhoneticFindingStatus::SupportedByAlignment
        );
        assert_ne!(findings[0].status, PhoneticFindingStatus::DetectedInAudio);
    }

    #[test]
    fn calibrated_alignment_can_claim_detected_in_audio() {
        let analysis_id = PhoneticAnalysisId::from_fingerprint("analysis", "calibrated");
        let findings = findings_from_alignments(
            &analysis_id,
            0,
            100,
            &[alignment(PhoneAlignmentKind::Substitution, 0.9)],
            &[phone("AX", 0.9)],
        );

        assert_eq!(findings[0].status, PhoneticFindingStatus::DetectedInAudio);
        assert_eq!(findings[0].audio_start_ms, 10);
        assert_eq!(findings[0].audio_end_ms, 20);
    }

    #[test]
    fn classifies_required_connected_speech_families() {
        let analysis_id = PhoneticAnalysisId::from_fingerprint("analysis", "families");
        for (alignment, phone_symbol, expected) in [
            (
                alignment_with(PhoneAlignmentKind::Substitution, 0.7, &["AH"], 0, 0),
                "AX",
                "weak_form",
            ),
            (
                alignment_with(PhoneAlignmentKind::Substitution, 0.7, &["T"], 0, 0),
                "DX",
                "flapping",
            ),
            (
                alignment_with(PhoneAlignmentKind::Deletion, 0.0, &["T"], 0, 0),
                "X",
                "elision",
            ),
            (
                alignment_with(PhoneAlignmentKind::Merge, 0.7, &["D", "Y"], 0, 2),
                "JH",
                "assimilation",
            ),
            (
                alignment_with(PhoneAlignmentKind::Deletion, 0.0, &["N", "T"], 0, 2),
                "X",
                "contraction",
            ),
            (
                alignment_with(PhoneAlignmentKind::Insertion, 0.7, &[], 0, 0),
                "R",
                "linking_or_insertion",
            ),
        ] {
            let findings = findings_from_alignments(
                &analysis_id,
                0,
                100,
                &[alignment],
                &[phone(phone_symbol, 0.7)],
            );
            assert_eq!(findings[0].finding_type, expected);
            assert!(!findings[0].evidence.is_empty());
        }
    }

    #[test]
    fn medium_confidence_is_alignment_support_not_audio_detection() {
        let analysis_id = PhoneticAnalysisId::from_fingerprint("analysis", "supported");
        let findings = findings_from_alignments(
            &analysis_id,
            0,
            100,
            &[alignment(PhoneAlignmentKind::Substitution, 0.7)],
            &[phone("AX", 0.7)],
        );
        assert_eq!(
            findings[0].status,
            PhoneticFindingStatus::SupportedByAlignment
        );
    }

    fn alignment(kind: PhoneAlignmentKind, confidence: f32) -> PhoneAlignment {
        alignment_with(kind, confidence, &["AH"], 0, 0)
    }

    fn alignment_with(
        kind: PhoneAlignmentKind,
        confidence: f32,
        canonical: &[&str],
        token_start: u32,
        token_end: u32,
    ) -> PhoneAlignment {
        PhoneAlignment {
            kind,
            token_start: Some(token_start),
            token_end: Some(token_end),
            canonical_phones: canonical.iter().map(|value| (*value).into()).collect(),
            detected_phone_start: (kind != PhoneAlignmentKind::Deletion).then_some(0),
            detected_phone_end: (kind != PhoneAlignmentKind::Deletion).then_some(0),
            confidence,
        }
    }

    fn phone(symbol: &str, confidence: f32) -> DetectedPhone {
        DetectedPhone {
            symbol: symbol.into(),
            display_ipa: symbol.into(),
            phone_set: "test".into(),
            start_ms: 10,
            end_ms: 20,
            confidence: Some(confidence),
            token_index: Some(0),
            provider_id: "test".into(),
            provider_version: "v1".into(),
            model_revision: "v1".into(),
        }
    }
}
