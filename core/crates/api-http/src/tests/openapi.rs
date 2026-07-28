use super::*;

#[test]
fn openapi_paths_match_implemented_routes() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");
    let router_source = concat!(
        include_str!("../lib.rs"),
        include_str!("../routes/router.rs")
    );
    let documented = openapi_v1_paths(openapi);
    let implemented = implemented_v1_paths(router_source);

    let undocumented = implemented
        .difference(&documented)
        .cloned()
        .collect::<Vec<_>>();
    let unimplemented = documented
        .difference(&implemented)
        .cloned()
        .collect::<Vec<_>>();
    assert!(
        undocumented.is_empty() && unimplemented.is_empty(),
        "OpenAPI route drift\nimplemented but undocumented: {undocumented:#?}\ndocumented but unimplemented: {unimplemented:#?}"
    );
}

#[test]
fn openapi_version_snapshot_and_path_count() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");

    // API version snapshot — bump intentionally, never accidentally.
    assert!(
        openapi.contains("version: 1.0.0"),
        "OpenAPI info.version snapshot changed — update test if intentional"
    );

    // OpenAPI specification version.
    assert!(
        openapi.contains("openapi: 3.1.0"),
        "OpenAPI spec version snapshot changed"
    );

    // Count documented paths using the router source as the implementation fact
    // source, so new routes cannot bypass OpenAPI.
    let path_count = openapi.lines().filter(|l| l.starts_with("  /v1/")).count();
    let implemented_count = implemented_v1_paths(concat!(
        include_str!("../lib.rs"),
        include_str!("../routes/router.rs")
    ))
    .len();
    assert_eq!(
        path_count, implemented_count,
        "OpenAPI path count must match implemented /v1 route count"
    );

    // All paths must be under /v1/.
    for line in openapi.lines() {
        if line.starts_with("  /") && !line.starts_with("  /v1/") {
            panic!("OpenAPI path not under /v1/ prefix: {}", line.trim());
        }
    }

    // Key schemas must exist (defines the response contract surface).
    for schema in [
        "Health:",
        "MediaItem:",
        "RegisterMedia:",
        "SubtitleTrack:",
        "SubtitleSentence:",
        "SubtitleToken:",
        "LexicalEntry:",
        "LexicalEntryDetails:",
        "BatchLexicalEntries:",
        "CreateLexicalObservation:",
        "LexicalObservation:",
        "SentenceDiagnosis:",
        "DictionaryLookup:",
        "DictionaryLookupBundle:",
        "VocabularyAssetBundle:",
        "LearningResource:",
        "SubtitleSearchResult:",
        "UpdateLexicalLearningContent:",
    ] {
        assert!(
            openapi.contains(&format!("    {schema}")),
            "OpenAPI schema missing: {schema}"
        );
    }
}

#[test]
fn practice_token_result_openapi_values_match_domain() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");
    let documented = openapi
        .split("    PracticeTokenResult:\n")
        .nth(1)
        .and_then(|section| section.lines().next())
        .expect("PracticeTokenResult enum follows its schema heading")
        .trim();
    let serialized = [
        domain::PracticeTokenResult::Correct,
        domain::PracticeTokenResult::Equivalent,
        domain::PracticeTokenResult::Missing,
        domain::PracticeTokenResult::Extra,
        domain::PracticeTokenResult::Mismatch,
    ]
    .map(|value| serde_json::to_value(value).unwrap());
    let values = serialized
        .iter()
        .map(|value| value.as_str().unwrap())
        .collect::<Vec<_>>()
        .join(", ");
    assert_eq!(documented, format!("enum: [{values}]"));
}

fn openapi_v1_paths(openapi: &str) -> BTreeSet<String> {
    openapi
        .lines()
        .filter_map(|line| line.strip_prefix("  /v1/"))
        .filter_map(|line| line.strip_suffix(':'))
        .map(|path| format!("/v1/{path}"))
        .collect()
}

fn implemented_v1_paths(router_source: &str) -> BTreeSet<String> {
    router_source
        .split('"')
        .filter(|value| value.starts_with("/v1/"))
        .map(str::to_owned)
        .collect()
}
