use domain::{RhythmClaimStatus, RhythmNucleus, RhythmPhraseBoundary, RhythmStressAnchor};

use super::tokens::RhythmToken;

pub(super) fn select_nuclei(
    tokens: &[RhythmToken],
    anchors: &[RhythmStressAnchor],
    phrase_boundaries: &[RhythmPhraseBoundary],
) -> Vec<RhythmNucleus> {
    let Some(first_token) = tokens.first() else {
        return Vec::new();
    };
    let last_token_index = tokens
        .last()
        .map(|token| token.index)
        .unwrap_or(first_token.index);
    let mut phrase_start = first_token.index;
    let mut nuclei = Vec::new();
    let mut boundaries = phrase_boundaries
        .iter()
        .filter_map(|boundary| boundary.after_token_index)
        .collect::<Vec<_>>();
    boundaries.sort_unstable();
    boundaries.dedup();
    boundaries.push(last_token_index);

    for phrase_end in boundaries {
        if phrase_end < phrase_start {
            continue;
        }
        if let Some(anchor) = anchors
            .iter()
            .filter(|anchor| anchor.claim_status == RhythmClaimStatus::AudioSupported)
            .filter(|anchor| {
                anchor
                    .token_index
                    .is_some_and(|index| index >= phrase_start && index <= phrase_end)
            })
            .max_by(|left, right| left.prominence.total_cmp(&right.prominence))
        {
            nuclei.push(RhythmNucleus {
                phrase_index: nuclei.len() as u32,
                token_index: anchor.token_index,
                syllable_index: anchor.syllable_index,
                start_ms: anchor.start_ms,
                end_ms: anchor.end_ms,
                label: anchor.label.clone(),
                reason: "Most prominent audio-supported anchor in this phrase.".into(),
                cues: anchor.prominence_cues.clone(),
                evidence_class: anchor.evidence_class,
                claim_status: anchor.claim_status,
                confidence: anchor.confidence,
            });
        }
        phrase_start = phrase_end.saturating_add(1);
    }
    nuclei
}

pub(super) fn mark_anchor_nuclei(
    mut anchors: Vec<RhythmStressAnchor>,
    nuclei: &[RhythmNucleus],
) -> Vec<RhythmStressAnchor> {
    for anchor in &mut anchors {
        anchor.is_nucleus = nuclei.iter().any(|nucleus| {
            nucleus.token_index == anchor.token_index
                && nucleus.syllable_index == anchor.syllable_index
        });
    }
    anchors
}
