use super::*;

#[test]
fn openapi_operations_match_implemented_routes() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");
    let router_source = concat!(
        include_str!("../lib.rs"),
        include_str!("../routes/router.rs")
    );
    let documented = openapi_v1_operations(openapi);
    let implemented = implemented_v1_operations(router_source);

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
        "OpenAPI operation drift\nimplemented but undocumented: {undocumented:#?}\ndocumented but unimplemented: {unimplemented:#?}"
    );
}

#[test]
fn openapi_version_snapshot_and_path_count() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");

    // API version snapshot — bump intentionally, never accidentally.
    assert!(
        openapi.contains("version: 2.1.0"),
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
        "ImportContentPackageRequest:",
        "ImportContentPackageResponse:",
        "ContentPackageImportReceipt:",
        "ContentPackageResourceDisposition:",
        "ContentPackageResourceProducer:",
        "ContentPackageResourceProvenance:",
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
fn recording_transcription_routes_stay_while_whole_media_jobs_are_absent() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");
    let router_source = concat!(
        include_str!("../lib.rs"),
        include_str!("../routes/router.rs")
    );
    let documented = openapi_v1_operations(openapi);
    let implemented = implemented_v1_operations(router_source);

    // Learner-recording transcription and the provider/model catalog remain part
    // of the contract and the router.
    for path in [
        "/v1/recording-transcriptions",
        "/v1/recording-transcriptions/{job_id}",
        "/v1/recording-transcriptions/{job_id}/cancel",
        "/v1/transcription/providers",
        "/v1/transcription/models",
        "/v1/transcription/models/install",
        "/v1/transcription/models/register-custom",
        "/v1/transcription/models/{model_id}/cancel-install",
        "/v1/transcription/models/{model_id}",
    ] {
        assert!(
            implemented
                .iter()
                .any(|(_, implemented)| implemented == path),
            "router missing retained transcription route: {path}"
        );
        assert!(
            documented.iter().any(|(_, documented)| documented == path),
            "OpenAPI missing retained transcription route: {path}"
        );
    }

    // The whole-media job surface stays deleted from both the contract and the
    // router.
    for path in [
        "/v1/transcription/jobs",
        "/v1/transcription/jobs/{job_id}",
        "/v1/transcription/jobs/{job_id}/cancel",
        "/v1/transcription/jobs/{job_id}/retry",
        "/v1/transcription/jobs/{job_id}/archive",
    ] {
        assert!(
            !documented.iter().any(|(_, documented)| documented == path),
            "removed OpenAPI path must stay absent: {path}"
        );
        assert!(
            !implemented
                .iter()
                .any(|(_, implemented)| implemented == path),
            "removed router path must stay absent: {path}"
        );
    }
    assert!(
        !router_source.contains("/v1/transcription/jobs"),
        "removed transcription jobs route must stay absent from the router"
    );
}

#[test]
fn lltimeline_sense_group_fields_match_rust_compatibility_semantics() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");
    let schema = openapi
        .split("    LLTimelineDocument:\n")
        .nth(1)
        .and_then(|tail| tail.split("\n    LLTimelineMetadata:\n").next())
        .expect("LLTimelineDocument schema block exists");
    let required = schema
        .lines()
        .find(|line| line.trim_start().starts_with("required:"))
        .expect("LLTimelineDocument required list exists");

    assert!(
        !required.contains("sense_group_analyses"),
        "legacy imports may omit sense_group_analyses"
    );
    assert!(
        !required.contains("active_sense_group_analysis_id"),
        "legacy imports may omit active_sense_group_analysis_id"
    );
    assert!(
        schema.contains("sense_group_analyses:\n          type: array\n          default: []"),
        "sense_group_analyses must default to an empty array"
    );
    assert!(
        schema.contains(
            "active_sense_group_analysis_id:\n          type: [string, \"null\"]\n          default: null"
        ),
        "active sense-group analysis id must be nullable and default to null"
    );
    assert!(
        schema.contains("items: { $ref: \"#/components/schemas/SenseGroupAnalysis\" }"),
        "sense_group_analyses items must use the canonical schema"
    );
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

fn openapi_v1_operations(openapi: &str) -> BTreeSet<(String, String)> {
    let methods = ["get", "post", "put", "patch", "delete"];
    let mut path = None;
    let mut operations = BTreeSet::new();
    for line in openapi.lines() {
        if let Some(value) = line
            .strip_prefix("  /v1/")
            .and_then(|value| value.strip_suffix(':'))
        {
            path = Some(format!("/v1/{value}"));
            continue;
        }
        let Some(current_path) = path.as_ref() else {
            continue;
        };
        if line.starts_with("  ") && !line.starts_with("    ") && line.trim_start().starts_with('/')
        {
            path = None;
            continue;
        }
        let trimmed = line.strip_prefix("    ").unwrap_or_default();
        for method in methods {
            if trimmed.starts_with(&format!("{method}:")) {
                operations.insert((method.to_owned(), current_path.clone()));
            }
        }
    }
    operations
}

fn implemented_v1_paths(router_source: &str) -> BTreeSet<String> {
    implemented_v1_operations(router_source)
        .into_iter()
        .map(|(_, path)| path)
        .collect()
}

fn implemented_v1_operations(router_source: &str) -> BTreeSet<(String, String)> {
    let methods = ["get", "post", "put", "patch", "delete"];
    let mut operations = BTreeSet::new();
    let mut offset = 0;
    while let Some(relative_start) = router_source[offset..].find(".route(") {
        let start = offset + relative_start;
        let Some(relative_end) = matching_call_end(&router_source[start..]) else {
            break;
        };
        let end = start + relative_end;
        let call = &router_source[start..end];
        let Some(path) = call
            .split('"')
            .nth(1)
            .filter(|value| value.starts_with("/v1/"))
        else {
            offset = end;
            continue;
        };
        for method in methods {
            if call.contains(&format!("{method}("))
                || call.contains(&format!(".{method}("))
                || call.contains(&format!("routing::{method}("))
            {
                operations.insert((method.to_owned(), path.to_owned()));
            }
        }
        offset = end;
    }
    operations
}

fn matching_call_end(source: &str) -> Option<usize> {
    let mut depth = 0usize;
    let mut saw_open = false;
    let mut in_string = false;
    let mut escaped = false;
    for (index, ch) in source.char_indices() {
        if in_string {
            if escaped {
                escaped = false;
            } else if ch == '\\' {
                escaped = true;
            } else if ch == '"' {
                in_string = false;
            }
            continue;
        }
        match ch {
            '"' => in_string = true,
            '(' => {
                saw_open = true;
                depth += 1;
            }
            ')' if saw_open => {
                depth -= 1;
                if depth == 0 {
                    return Some(index + ch.len_utf8());
                }
            }
            _ => {}
        }
    }
    None
}

#[test]
fn route_operation_parser_handles_chained_and_qualified_methods() {
    let source = r#"
        Router::new()
            .route("/v1/a", get(read_a).post(create_a))
            .route("/v1/b", axum::routing::patch(update_b))
            .route("/v1/c", delete(delete_c))
    "#;
    assert_eq!(
        implemented_v1_operations(source),
        BTreeSet::from([
            ("delete".to_owned(), "/v1/c".to_owned()),
            ("get".to_owned(), "/v1/a".to_owned()),
            ("patch".to_owned(), "/v1/b".to_owned()),
            ("post".to_owned(), "/v1/a".to_owned()),
        ])
    );
}
