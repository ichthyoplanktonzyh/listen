//! L1-aware listening difficulty profiles (Phase 3.9, LANG-009).
//!
//! Content is declared per (L1, L2) pair behind this provider seam; nothing
//! outside this module hard-codes a language pair. Unsupported pairs return
//! `None` and every consumer must degrade to baseline diagnosis.
//!
//! Two evidence layers are deliberately separated:
//!
//! - **Profile content** (which difficulty categories exist for a pair, and
//!   the one-sentence transfer explanation) is grounded in published
//!   contrastive phonology / L2 listening research. Citation keys live on
//!   each rule; full references and per-rule review notes are recorded in
//!   `.planning/phases/3.9-l1-aware-diagnosis-v1/3.9-L1-PROFILE-EVIDENCE.md`.
//! - **Identification rules** (mapping a category onto the audible-structure
//!   v1 shape: document-level `rhythm_frames` weak groups / compression spans
//!   and 2.16 connected-speech families) are `heuristic_proxy` — they inherit
//!   the upstream generators' evidence class and are possibilities to replay,
//!   never detections.
//!
//! Guardrail: a hit must carry a replayable audio span; categories whose
//! evidence provider does not exist yet declare no families and never fire.

use domain::{
    ConnectedSpeechFamily, L1L2DifficultyProfile, LanguageCode, ListeningHotspotKind, RhythmFrame,
};

/// Family key for rhythm-frame weak groups (runs of backgrounded words).
pub const FAMILY_WEAK_GROUP: &str = "rhythm.weak_group";
/// Family key for rhythm-frame compression spans (stress-timed squeezing).
pub const FAMILY_COMPRESSION: &str = "rhythm.compression";

/// Stable projection key for a 2.16 connected-speech family. These keys are
/// shared with the corpus family projection (`corpus_occurrences` rows of
/// kind `connected_speech` store them as `normalized_key`).
pub fn connected_speech_family_key(family: ConnectedSpeechFamily) -> &'static str {
    match family {
        ConnectedSpeechFamily::WeakForm => "cs.weak_form",
        ConnectedSpeechFamily::Deletion => "cs.deletion",
        ConnectedSpeechFamily::Linking => "cs.linking",
        ConnectedSpeechFamily::Assimilation => "cs.assimilation",
        ConnectedSpeechFamily::Contraction => "cs.contraction",
        ConnectedSpeechFamily::Flapping => "cs.flapping",
    }
}

/// One difficulty category of an (L1, L2) profile.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct L1L2DifficultyRule {
    /// Stable category id, e.g. `weak_function_words`. Clients localize the
    /// learner-facing wording by this id; `explanation` is the neutral
    /// English reference text.
    pub kind: &'static str,
    /// Evidence family keys that identify this category in a rhythm frame.
    /// Empty means "content declared, evidence provider pending" — the
    /// category never produces hints until a generator exists.
    pub families: &'static [&'static str],
    /// One-sentence L1-transfer explanation, phrased as a possibility.
    pub explanation: &'static str,
    /// Evidence class of the identification rule (AGENT.md algorithm rules).
    pub evidence_class: &'static str,
    /// Short citation keys for the profile content; full references in the
    /// phase evidence document.
    pub research_refs: &'static [&'static str],
}

/// Mandarin (zh) -> English (en) difficulty profile v1.
///
/// Category inventory follows the 3.9 plan; each explanation states a
/// perception-transfer possibility, not a diagnosis of this learner.
const MANDARIN_ENGLISH_RULES: &[L1L2DifficultyRule] = &[
    L1L2DifficultyRule {
        kind: "weak_function_words",
        families: &[FAMILY_WEAK_GROUP],
        explanation: "Mandarin gives most syllables full weight, so English function words \
                      backgrounded between stresses may carry less sound than your ear expects.",
        evidence_class: "heuristic_proxy",
        research_refs: &["brown1990", "field2008", "goh2000", "grabe-low2002"],
    },
    L1L2DifficultyRule {
        kind: "schwa_reduction",
        families: &[connected_speech_family_key_const(
            ConnectedSpeechFamily::WeakForm,
        )],
        explanation: "Mandarin vowels keep their quality everywhere, so an English reduced vowel \
                      (schwa) can sound like a different word or like nothing at all.",
        evidence_class: "heuristic_proxy",
        research_refs: &["duanmu2007", "cruttenden2014", "field2008"],
    },
    L1L2DifficultyRule {
        kind: "final_consonants",
        // No dedicated final-obstruent detector exists in the audible-structure
        // v1 shape; content is declared, evidence provider pending.
        families: &[],
        explanation: "Mandarin syllables end only in vowels or -n/-ng, so English word-final \
                      consonants get little attention from a Mandarin-trained ear.",
        evidence_class: "heuristic_proxy",
        research_refs: &["duanmu2007", "broselow-chen-wang1998", "flege1989"],
    },
    L1L2DifficultyRule {
        kind: "consonant_clusters",
        // No cluster-simplification detector exists yet; evidence pending.
        families: &[],
        explanation: "Mandarin has no consonant clusters, so English clusters may be heard with \
                      vowels inserted or consonants missing.",
        evidence_class: "heuristic_proxy",
        research_refs: &["duanmu2007", "broselow-chen-wang1998"],
    },
    L1L2DifficultyRule {
        kind: "t_d_deletion",
        families: &[connected_speech_family_key_const(
            ConnectedSpeechFamily::Deletion,
        )],
        explanation: "Final /t/ and /d/ are often weakened or dropped before another consonant in \
                      connected English; Mandarin listening habits give no cue to reconstruct them.",
        evidence_class: "heuristic_proxy",
        research_refs: &["shockey2003", "cruttenden2014", "flege1989"],
    },
    L1L2DifficultyRule {
        kind: "flapping",
        families: &[connected_speech_family_key_const(
            ConnectedSpeechFamily::Flapping,
        )],
        explanation: "American English says /t/ and /d/ between vowels as a quick flap, which a \
                      Mandarin-trained ear may hear as /d/ or an /r/-like sound.",
        evidence_class: "heuristic_proxy",
        research_refs: &["cruttenden2014", "shockey2003"],
    },
    L1L2DifficultyRule {
        kind: "linking",
        families: &[connected_speech_family_key_const(
            ConnectedSpeechFamily::Linking,
        )],
        explanation: "Mandarin keeps syllable boundaries clean, while English links a final \
                      consonant into the next vowel, shifting the word boundary your ear expects.",
        evidence_class: "heuristic_proxy",
        research_refs: &["cutler2012", "field2008", "brown1990"],
    },
    L1L2DifficultyRule {
        kind: "stress_timed_rhythm",
        families: &[FAMILY_COMPRESSION],
        explanation: "English squeezes unstressed stretches to keep stress beats regular; Mandarin \
                      rhythm spaces syllables more evenly, so compressed spans feel too fast.",
        evidence_class: "heuristic_proxy",
        research_refs: &["grabe-low2002", "goh2000", "abercrombie1967"],
    },
    L1L2DifficultyRule {
        kind: "compressed_forms",
        families: &[
            connected_speech_family_key_const(ConnectedSpeechFamily::Contraction),
            connected_speech_family_key_const(ConnectedSpeechFamily::Assimilation),
        ],
        explanation: "Frequent phrases fuse into spoken units like gonna, wanna, or didja that must \
                      be recognized whole, not word by word.",
        evidence_class: "heuristic_proxy",
        research_refs: &["brown1990", "shockey2003", "field2008"],
    },
];

/// `const`-context twin of [`connected_speech_family_key`], so the rule table
/// cannot drift from the runtime key mapping.
const fn connected_speech_family_key_const(family: ConnectedSpeechFamily) -> &'static str {
    match family {
        ConnectedSpeechFamily::WeakForm => "cs.weak_form",
        ConnectedSpeechFamily::Deletion => "cs.deletion",
        ConnectedSpeechFamily::Linking => "cs.linking",
        ConnectedSpeechFamily::Assimilation => "cs.assimilation",
        ConnectedSpeechFamily::Contraction => "cs.contraction",
        ConnectedSpeechFamily::Flapping => "cs.flapping",
    }
}

/// Resolve the difficulty rules for an (L1, L2) pair. Matching is on primary
/// subtags so `zh-hans` -> `en-us` resolves like `zh` -> `en`. Unsupported
/// pairs return `None`: the caller must degrade cleanly, never synthesize
/// generic content.
pub fn l1l2_difficulty_rules(
    l1: &LanguageCode,
    l2: &LanguageCode,
) -> Option<&'static [L1L2DifficultyRule]> {
    let primary = |code: &LanguageCode| {
        code.as_str()
            .split('-')
            .next()
            .unwrap_or(code.as_str())
            .to_owned()
    };
    match (primary(l1).as_str(), primary(l2).as_str()) {
        ("zh", "en") => Some(MANDARIN_ENGLISH_RULES),
        _ => None,
    }
}

/// The domain wire shape of a supported profile (settings/diagnostic surfaces
/// show category inventory and explanations from this).
pub fn l1l2_difficulty_profile(
    l1: &LanguageCode,
    l2: &LanguageCode,
) -> Option<L1L2DifficultyProfile> {
    let rules = l1l2_difficulty_rules(l1, l2)?;
    Some(L1L2DifficultyProfile {
        l1: l1.clone(),
        l2: l2.clone(),
        difficulty_kinds: rules.iter().map(|rule| rule.kind.to_owned()).collect(),
        explanation_templates: serde_json::Value::Object(
            rules
                .iter()
                .map(|rule| {
                    (
                        rule.kind.to_owned(),
                        serde_json::Value::String(rule.explanation.to_owned()),
                    )
                })
                .collect(),
        ),
        specialty_query_rules: serde_json::Value::Object(
            rules
                .iter()
                .map(|rule| {
                    (
                        rule.kind.to_owned(),
                        serde_json::Value::Array(
                            rule.families
                                .iter()
                                .map(|family| serde_json::Value::String((*family).to_owned()))
                                .collect(),
                        ),
                    )
                })
                .collect(),
        ),
    })
}

/// A replayable audio span backing one difficulty hit. Spans always come from
/// the sentence's own rhythm frame, so "listen again" lands on real audio.
#[derive(Debug, Clone, PartialEq)]
pub struct L1DifficultyEvidenceSpan {
    pub family: String,
    pub start_ms: u64,
    pub end_ms: u64,
    pub label: String,
    pub surface_text: String,
}

/// One difficulty category matched against a sentence's rhythm frame.
#[derive(Debug, Clone, PartialEq)]
pub struct L1DifficultyHit {
    pub kind: String,
    pub explanation: String,
    pub families: Vec<String>,
    pub spans: Vec<L1DifficultyEvidenceSpan>,
}

/// Match a rhythm frame against a rule set. Only categories with at least one
/// replayable span are returned (guardrail: no span, no hint); hits are
/// ordered by evidence volume so the caller can truncate for a short card.
pub fn match_l1_difficulty_hits(
    rules: &[L1L2DifficultyRule],
    frame: &RhythmFrame,
) -> Vec<L1DifficultyHit> {
    let mut hits = Vec::new();
    for rule in rules {
        let mut spans = Vec::new();
        for family in rule.families {
            collect_family_spans(frame, family, &mut spans);
        }
        if spans.is_empty() {
            continue;
        }
        spans.sort_by_key(|span| (span.start_ms, span.end_ms));
        hits.push(L1DifficultyHit {
            kind: rule.kind.to_owned(),
            explanation: rule.explanation.to_owned(),
            families: rule.families.iter().map(|f| (*f).to_owned()).collect(),
            spans,
        });
    }
    hits.sort_by(|a, b| b.spans.len().cmp(&a.spans.len()).then(a.kind.cmp(&b.kind)));
    hits
}

/// Every replayable family-annotated span in a rhythm frame, across all
/// declared families. This is the single source for the corpus family
/// projection (Phase 3.9): reindex writes one `connected_speech` occurrence
/// per span, keyed by the family, so specialty aggregation and diagnosis
/// matching cannot drift apart.
pub fn rhythm_family_spans(frame: &RhythmFrame) -> Vec<L1DifficultyEvidenceSpan> {
    let mut spans = Vec::new();
    collect_family_spans(frame, FAMILY_WEAK_GROUP, &mut spans);
    collect_family_spans(frame, FAMILY_COMPRESSION, &mut spans);
    for family in [
        ConnectedSpeechFamily::WeakForm,
        ConnectedSpeechFamily::Deletion,
        ConnectedSpeechFamily::Linking,
        ConnectedSpeechFamily::Assimilation,
        ConnectedSpeechFamily::Contraction,
        ConnectedSpeechFamily::Flapping,
    ] {
        collect_family_spans(frame, connected_speech_family_key(family), &mut spans);
    }
    spans
}

fn collect_family_spans(
    frame: &RhythmFrame,
    family: &str,
    spans: &mut Vec<L1DifficultyEvidenceSpan>,
) {
    match family {
        FAMILY_WEAK_GROUP => {
            for group in &frame.weak_groups {
                if group.end_ms > group.start_ms {
                    spans.push(L1DifficultyEvidenceSpan {
                        family: family.to_owned(),
                        start_ms: group.start_ms,
                        end_ms: group.end_ms,
                        label: group.label.clone(),
                        surface_text: group.label.clone(),
                    });
                }
            }
        }
        FAMILY_COMPRESSION => {
            for span in &frame.compression_spans {
                if span.end_ms > span.start_ms {
                    spans.push(L1DifficultyEvidenceSpan {
                        family: family.to_owned(),
                        start_ms: span.start_ms,
                        end_ms: span.end_ms,
                        label: span.label.clone(),
                        surface_text: span.label.clone(),
                    });
                }
            }
        }
        _ => {
            // Connected-speech families: the refs carry the family + surface
            // text, the matching hotspot (same token range, ConnectedSpeech
            // kind) carries the ms span. Refs without a resolvable span are
            // dropped, honoring the replayability guardrail.
            for reference in &frame.connected_speech_refs {
                let Some(ref_family) = reference.family else {
                    continue;
                };
                if connected_speech_family_key(ref_family) != family {
                    continue;
                }
                let Some(hotspot) = frame.listening_hotspots.iter().find(|hotspot| {
                    hotspot.kind == ListeningHotspotKind::ConnectedSpeech
                        && hotspot.token_start == reference.token_start
                        && hotspot.token_end == reference.token_end
                        && hotspot.label == reference.label
                }) else {
                    continue;
                };
                if hotspot.end_ms <= hotspot.start_ms {
                    continue;
                }
                spans.push(L1DifficultyEvidenceSpan {
                    family: family.to_owned(),
                    start_ms: hotspot.start_ms,
                    end_ms: hotspot.end_ms,
                    label: reference.label.clone(),
                    surface_text: if reference.surface_text.is_empty() {
                        reference.label.clone()
                    } else {
                        reference.surface_text.clone()
                    },
                });
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use domain::*;

    fn lang(code: &str) -> LanguageCode {
        LanguageCode::parse(code).unwrap()
    }

    fn empty_frame() -> RhythmFrame {
        RhythmFrame {
            generated_from: "test".into(),
            references: RhythmFrameReferences {
                citation: reference(),
                default_connected: None,
                actual: reference(),
            },
            information_anchors: Vec::new(),
            stress_anchors: Vec::new(),
            nuclei: Vec::new(),
            weak_groups: Vec::new(),
            compression_spans: Vec::new(),
            phrase_boundaries: Vec::new(),
            connected_speech_refs: Vec::new(),
            listening_hotspots: Vec::new(),
            quality: RhythmFrameQuality {
                timing_source: "test".into(),
                prominence_sources: Vec::new(),
                boundary_sources: Vec::new(),
                connected_speech_source: RhythmSignalSource::TextPrior,
                phone_evidence_coverage: 0.0,
                rhythm_confidence: 0.5,
            },
        }
    }

    fn reference() -> RhythmReference {
        RhythmReference {
            label: "test".into(),
            source: "test".into(),
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
        }
    }

    fn weak_group(start_ms: u64, end_ms: u64) -> RhythmWeakGroup {
        RhythmWeakGroup {
            token_start: Some(0),
            token_end: Some(1),
            phone_start: None,
            phone_end: None,
            anchor_token_index: None,
            start_ms,
            end_ms,
            label: "and the".into(),
            reason: "test".into(),
            reduction_refs: Vec::new(),
            signal_sources: vec![RhythmSignalSource::TextPrior],
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            claim_status: RhythmClaimStatus::Predicted,
            confidence: 0.6,
        }
    }

    fn connected_ref(family: ConnectedSpeechFamily) -> RhythmConnectedSpeechRef {
        RhythmConnectedSpeechRef {
            id: "cs1".into(),
            connected_speech_index: Some(0),
            token_start: Some(2),
            token_end: Some(3),
            phone_start: None,
            phone_end: None,
            family: Some(family),
            surface_text: "want to".into(),
            label: "default connected form".into(),
            hint: "test".into(),
            expected_symbols: Vec::new(),
            default_symbols: Vec::new(),
            expected_display_ipa: String::new(),
            default_display_ipa: String::new(),
            divergence: RhythmDivergenceKind::TeachableRule,
            signal_sources: vec![RhythmSignalSource::TextPrior],
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            confidence: 0.7,
        }
    }

    fn connected_hotspot(start_ms: u64, end_ms: u64) -> ListeningHotspot {
        ListeningHotspot {
            id: "hs1".into(),
            kind: ListeningHotspotKind::ConnectedSpeech,
            token_start: Some(2),
            token_end: Some(3),
            phone_start: None,
            phone_end: None,
            start_ms,
            end_ms,
            label: "default connected form".into(),
            hint: "test".into(),
            signal_sources: vec![RhythmSignalSource::TextPrior],
            evidence_class: RhythmEvidenceClass::HeuristicProxy,
            claim_status: RhythmClaimStatus::Predicted,
            confidence: 0.7,
        }
    }

    #[test]
    fn mandarin_english_pair_resolves_with_regional_variants() {
        assert!(l1l2_difficulty_rules(&lang("zh"), &lang("en")).is_some());
        assert!(l1l2_difficulty_rules(&lang("zh-Hans"), &lang("en-US")).is_some());
    }

    #[test]
    fn unsupported_pairs_return_none_not_generic_content() {
        assert!(l1l2_difficulty_rules(&lang("ja"), &lang("en")).is_none());
        assert!(l1l2_difficulty_rules(&lang("zh"), &lang("ja")).is_none());
        assert!(l1l2_difficulty_rules(&lang("en"), &lang("zh")).is_none());
    }

    #[test]
    fn profile_wire_shape_carries_kinds_templates_and_query_rules() {
        let profile = l1l2_difficulty_profile(&lang("zh"), &lang("en")).unwrap();
        assert!(
            profile
                .difficulty_kinds
                .contains(&"weak_function_words".to_owned())
        );
        assert_eq!(profile.difficulty_kinds.len(), 9);
        let templates = profile.explanation_templates.as_object().unwrap();
        assert!(templates.contains_key("stress_timed_rhythm"));
        let queries = profile.specialty_query_rules.as_object().unwrap();
        assert_eq!(
            queries["weak_function_words"],
            serde_json::json!([FAMILY_WEAK_GROUP])
        );
        // Categories without an evidence provider declare empty families.
        assert_eq!(queries["final_consonants"], serde_json::json!([]));
    }

    #[test]
    fn every_rule_records_research_refs_and_evidence_class() {
        for rule in l1l2_difficulty_rules(&lang("zh"), &lang("en")).unwrap() {
            assert!(!rule.research_refs.is_empty(), "{} lacks refs", rule.kind);
            assert_eq!(rule.evidence_class, "heuristic_proxy");
        }
    }

    #[test]
    fn weak_group_evidence_produces_weak_function_words_hit() {
        let rules = l1l2_difficulty_rules(&lang("zh"), &lang("en")).unwrap();
        let mut frame = empty_frame();
        frame.weak_groups.push(weak_group(100, 400));
        let hits = match_l1_difficulty_hits(rules, &frame);
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].kind, "weak_function_words");
        assert_eq!(hits[0].spans.len(), 1);
        assert_eq!(hits[0].spans[0].start_ms, 100);
        assert_eq!(hits[0].spans[0].end_ms, 400);
    }

    #[test]
    fn connected_speech_ref_needs_matching_hotspot_span() {
        let rules = l1l2_difficulty_rules(&lang("zh"), &lang("en")).unwrap();
        // Ref without a hotspot: replayability guardrail drops the category.
        let mut frame = empty_frame();
        frame
            .connected_speech_refs
            .push(connected_ref(ConnectedSpeechFamily::Contraction));
        assert!(match_l1_difficulty_hits(rules, &frame).is_empty());

        // Same ref with its hotspot: compressed_forms fires with the span.
        frame.listening_hotspots.push(connected_hotspot(800, 1200));
        let hits = match_l1_difficulty_hits(rules, &frame);
        assert_eq!(hits.len(), 1);
        assert_eq!(hits[0].kind, "compressed_forms");
        assert_eq!(hits[0].spans[0].surface_text, "want to");
        assert_eq!(
            (hits[0].spans[0].start_ms, hits[0].spans[0].end_ms),
            (800, 1200)
        );
    }

    #[test]
    fn zero_length_spans_never_fire() {
        let rules = l1l2_difficulty_rules(&lang("zh"), &lang("en")).unwrap();
        let mut frame = empty_frame();
        frame.weak_groups.push(weak_group(500, 500));
        assert!(match_l1_difficulty_hits(rules, &frame).is_empty());
    }

    #[test]
    fn hits_rank_by_evidence_volume() {
        let rules = l1l2_difficulty_rules(&lang("zh"), &lang("en")).unwrap();
        let mut frame = empty_frame();
        frame.weak_groups.push(weak_group(100, 300));
        frame.weak_groups.push(weak_group(600, 900));
        frame
            .connected_speech_refs
            .push(connected_ref(ConnectedSpeechFamily::Contraction));
        frame.listening_hotspots.push(connected_hotspot(800, 1200));
        let hits = match_l1_difficulty_hits(rules, &frame);
        assert_eq!(hits[0].kind, "weak_function_words");
        assert_eq!(hits[0].spans.len(), 2);
        assert_eq!(hits[1].kind, "compressed_forms");
    }
}
