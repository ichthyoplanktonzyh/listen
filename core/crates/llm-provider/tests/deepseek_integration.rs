//! Live DeepSeek smoke test.
//!
//! Run explicitly with:
//! `DEEPSEEK_API_KEY=... cargo test -p llm-provider --test deepseek_integration -- --ignored`
//! The key is read once from the process environment and is never logged.

use std::time::Duration;

use application::{
    SenseGroupPartitionProvider, SenseGroupPartitionRequest, SenseGroupProtectedSpan,
    SenseGroupTokenInput,
};
use domain::LanguageCode;
use llm_provider::{LlmSemanticProvider, OpenAiChatAdapter};

#[tokio::test]
#[ignore = "requires DEEPSEEK_API_KEY and makes a paid network request"]
async fn deepseek_v4_flash_returns_valid_sense_group_boundaries() {
    let api_key = std::env::var("DEEPSEEK_API_KEY")
        .expect("DEEPSEEK_API_KEY must be present for the ignored live test");
    assert!(!api_key.trim().is_empty(), "DEEPSEEK_API_KEY was empty");
    let base_url =
        std::env::var("DEEPSEEK_BASE_URL").unwrap_or_else(|_| "https://api.deepseek.com".into());
    let model_id = std::env::var("DEEPSEEK_MODEL").unwrap_or_else(|_| "deepseek-v4-flash".into());
    let adapter =
        OpenAiChatAdapter::new(base_url, model_id, Some(api_key), Duration::from_secs(60))
            .expect("DeepSeek adapter");
    let provider = LlmSemanticProvider::new(adapter);
    let request = SenseGroupPartitionRequest {
        language: Some(LanguageCode::parse("en").unwrap()),
        source_text: "Although the train was delayed, we still arrived in time for the meeting."
            .into(),
        tokens: vec![
            token(0, "Although", "word"),
            token(1, " ", "whitespace"),
            token(2, "the", "word"),
            token(3, " ", "whitespace"),
            token(4, "train", "word"),
            token(5, " ", "whitespace"),
            token(6, "was", "word"),
            token(7, " ", "whitespace"),
            token(8, "delayed", "word"),
            token(9, ",", "punctuation"),
            token(10, " ", "whitespace"),
            token(11, "we", "word"),
            token(12, " ", "whitespace"),
            token(13, "still", "word"),
            token(14, " ", "whitespace"),
            token(15, "arrived", "word"),
            token(16, " ", "whitespace"),
            token(17, "in", "word"),
            token(18, " ", "whitespace"),
            token(19, "time", "word"),
            token(20, " ", "whitespace"),
            token(21, "for", "word"),
            token(22, " ", "whitespace"),
            token(23, "the", "word"),
            token(24, " ", "whitespace"),
            token(25, "meeting", "word"),
            token(26, ".", "punctuation"),
        ],
        protected_spans: vec![SenseGroupProtectedSpan {
            start_token_index: 17,
            end_token_index: 19,
        }],
        candidate_boundary_after_token_indices: vec![8, 19],
    };

    let draft = provider
        .partition_sense_groups(&request)
        .await
        .expect("DeepSeek sense-group response");
    println!(
        "DeepSeek sense-group boundaries: {:?}",
        draft.boundary_after_token_indices
    );
    let word_indices = [0, 2, 4, 6, 8, 11, 13, 15, 17, 19, 21, 23, 25];
    assert!(
        draft
            .boundary_after_token_indices
            .windows(2)
            .all(|pair| pair[0] < pair[1]),
        "boundaries must be strictly increasing"
    );
    assert!(
        draft
            .boundary_after_token_indices
            .iter()
            .all(|index| word_indices.contains(index) && *index != 25),
        "boundaries must name non-final word tokens"
    );
    assert!(
        draft
            .boundary_after_token_indices
            .iter()
            .all(|index| *index < 17 || *index >= 19),
        "protected span must remain intact"
    );
}

fn token(index: u32, text: &str, kind: &str) -> SenseGroupTokenInput {
    SenseGroupTokenInput {
        index,
        text: text.into(),
        kind: kind.into(),
    }
}
