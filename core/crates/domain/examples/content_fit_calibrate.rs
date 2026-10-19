use std::path::PathBuf;

use domain::{
    CalibrationSample, ContentFitEvaluationReport, ContentFitThresholds,
    evaluate_calibration_samples_with_thresholds, search_sound_thresholds,
};
use serde::Serialize;

#[derive(Serialize)]
struct CalibrationRun {
    training_samples: usize,
    holdout_samples: usize,
    selected_thresholds: ContentFitThresholds,
    holdout: ContentFitEvaluationReport,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let input = std::env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .ok_or("usage: content_fit_calibrate <calibration-samples.json>")?;
    let mut samples: Vec<CalibrationSample> = serde_json::from_slice(&std::fs::read(input)?)?;
    samples.retain(|sample| sample.observed_difficulty.is_some());
    samples.sort_by(|left, right| left.subject_id.cmp(&right.subject_id));

    let (mut training, mut holdout) = (Vec::new(), Vec::new());
    for (index, sample) in samples.into_iter().enumerate() {
        if index % 5 == 4 {
            holdout.push(sample);
        } else {
            training.push(sample);
        }
    }
    if holdout.is_empty() {
        holdout.clone_from(&training);
    }

    let thresholds = search_sound_thresholds(&training);
    let run = CalibrationRun {
        training_samples: training.len(),
        holdout_samples: holdout.len(),
        selected_thresholds: thresholds,
        holdout: evaluate_calibration_samples_with_thresholds(&holdout, thresholds),
    };
    println!("{}", serde_json::to_string_pretty(&run)?);
    Ok(())
}
