use domain::{DetectedPhone, PhoneAlignment, PhoneAlignmentKind};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CanonicalPhone {
    pub symbol: String,
    pub token_index: u32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Step {
    Start,
    Match,
    Substitution,
    Insertion,
    Deletion,
    Merge,
}

pub fn align_phones(
    canonical: &[CanonicalPhone],
    detected: &[DetectedPhone],
) -> Vec<PhoneAlignment> {
    let rows = canonical.len() + 1;
    let columns = detected.len() + 1;
    let mut cost = vec![vec![usize::MAX; columns]; rows];
    let mut step = vec![vec![Step::Start; columns]; rows];
    cost[0][0] = 0;
    for i in 1..rows {
        cost[i][0] = i;
        step[i][0] = Step::Deletion;
    }
    for j in 1..columns {
        cost[0][j] = j;
        step[0][j] = Step::Insertion;
    }
    for i in 1..rows {
        for j in 1..columns {
            let same = canonical[i - 1].symbol == detected[j - 1].symbol;
            let diagonal_cost = cost[i - 1][j - 1] + usize::from(!same);
            choose(
                &mut cost,
                &mut step,
                i,
                j,
                diagonal_cost,
                if same {
                    Step::Match
                } else {
                    Step::Substitution
                },
            );
            let deletion_cost = cost[i - 1][j] + 1;
            choose(&mut cost, &mut step, i, j, deletion_cost, Step::Deletion);
            let insertion_cost = cost[i][j - 1] + 1;
            choose(&mut cost, &mut step, i, j, insertion_cost, Step::Insertion);
            if i >= 2 {
                let merge_cost = cost[i - 2][j - 1] + 1;
                choose(&mut cost, &mut step, i, j, merge_cost, Step::Merge);
            }
        }
    }
    backtrace(canonical, detected, &step)
}

fn choose(
    cost: &mut [Vec<usize>],
    step: &mut [Vec<Step>],
    i: usize,
    j: usize,
    candidate: usize,
    candidate_step: Step,
) {
    if candidate < cost[i][j] {
        cost[i][j] = candidate;
        step[i][j] = candidate_step;
    }
}

fn backtrace(
    canonical: &[CanonicalPhone],
    detected: &[DetectedPhone],
    steps: &[Vec<Step>],
) -> Vec<PhoneAlignment> {
    let mut values = Vec::new();
    let mut i = canonical.len();
    let mut j = detected.len();
    while i > 0 || j > 0 {
        let current = steps[i][j];
        let (canonical_start, detected_start, kind) = match current {
            Step::Match => (i - 1, j - 1, PhoneAlignmentKind::Match),
            Step::Substitution => (i - 1, j - 1, PhoneAlignmentKind::Substitution),
            Step::Insertion => (i, j - 1, PhoneAlignmentKind::Insertion),
            Step::Deletion => (i - 1, j, PhoneAlignmentKind::Deletion),
            Step::Merge => (i - 2, j - 1, PhoneAlignmentKind::Merge),
            Step::Start => break,
        };
        let canonical_slice = &canonical[canonical_start..i];
        let detected_slice = &detected[detected_start..j];
        let confidence = if detected_slice.is_empty() {
            0.0
        } else {
            detected_slice
                .iter()
                .filter_map(|phone| phone.confidence)
                .sum::<f32>()
                / detected_slice.len() as f32
        };
        values.push(PhoneAlignment {
            kind,
            token_start: canonical_slice.first().map(|phone| phone.token_index),
            token_end: canonical_slice.last().map(|phone| phone.token_index),
            canonical_phones: canonical_slice
                .iter()
                .map(|phone| phone.symbol.clone())
                .collect(),
            detected_phone_start: (!detected_slice.is_empty()).then_some(detected_start as u32),
            detected_phone_end: (!detected_slice.is_empty()).then_some((j - 1) as u32),
            confidence,
        });
        i = canonical_start;
        j = detected_start;
    }
    values.reverse();
    values
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aligns_match_substitution_insertion_and_deletion() {
        let canonical_values = canonical(&[(0, "K"), (0, "AE"), (2, "S")]);
        let detected_values = detected(&["K", "AH", "X", "S"]);
        let values = align_phones(&canonical_values, &detected_values);
        assert_eq!(values[0].kind, PhoneAlignmentKind::Match);
        assert!(
            values
                .iter()
                .any(|value| value.kind == PhoneAlignmentKind::Substitution)
        );
        assert!(
            values
                .iter()
                .any(|value| value.kind == PhoneAlignmentKind::Insertion)
        );
        assert_eq!(values.last().unwrap().token_end, Some(2));

        let deleted = align_phones(&canonical(&[(0, "K"), (0, "AE")]), &detected(&["K"]));
        assert!(
            deleted
                .iter()
                .any(|value| value.kind == PhoneAlignmentKind::Deletion)
        );
    }

    #[test]
    fn represents_two_canonical_phones_as_merge() {
        let canonical = canonical(&[(0, "D"), (2, "Y")]);
        let detected = detected(&["JH"]);
        let values = align_phones(&canonical, &detected);
        assert_eq!(values.len(), 1);
        assert_eq!(values[0].kind, PhoneAlignmentKind::Merge);
        assert_eq!(values[0].token_start, Some(0));
        assert_eq!(values[0].token_end, Some(2));
    }

    fn canonical(values: &[(u32, &str)]) -> Vec<CanonicalPhone> {
        values
            .iter()
            .map(|(token_index, symbol)| CanonicalPhone {
                symbol: (*symbol).into(),
                token_index: *token_index,
            })
            .collect()
    }

    fn detected(values: &[&str]) -> Vec<DetectedPhone> {
        values
            .iter()
            .enumerate()
            .map(|(index, symbol)| DetectedPhone {
                symbol: (*symbol).into(),
                display_ipa: (*symbol).into(),
                phone_set: "test".into(),
                start_ms: index as u64 * 10,
                end_ms: index as u64 * 10 + 10,
                confidence: Some(0.8),
                token_index: None,
                provider_id: "test".into(),
                provider_version: "v1".into(),
                model_revision: "v1".into(),
            })
            .collect()
    }
}
