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

    // Contract version snapshot — bump intentionally, never accidentally.
    // 5.0.0 narrows material processing to audio/video, removes document,
    // conversation, and production surfaces, and retains listening-only coaching.
    assert!(
        openapi.contains("version: 5.0.0"),
        "OpenAPI info.version snapshot changed — update test if intentional"
    );

    // R5 breaking removal: the retired ChunkTimeline wire surface must stay
    // absent from the contract.
    for removed in [
        "chunk_timelines:",
        "active_chunk_timeline_id:",
        "ChunkTimeline:",
        "ChunkTimelineSummary:",
        "ChunkBoundarySource:",
        "chunk-timelines:",
    ] {
        assert!(
            !openapi.contains(removed),
            "removed OpenAPI wire surface {removed} must stay absent"
        );
    }

    // OpenAPI specification version.
    assert!(
        openapi.contains("openapi: 3.1.0"),
        "OpenAPI spec version snapshot changed"
    );
    let dashboard_start = openapi.find("  /v1/coach/dashboard:\n").unwrap();
    let dashboard_end = openapi[dashboard_start + 1..]
        .find("\n  /v1/")
        .map(|offset| dashboard_start + 1 + offset)
        .unwrap_or(openapi.len());
    assert!(
        !openapi[dashboard_start..dashboard_end].contains("name: language"),
        "the global listening dashboard must not imply a language filter"
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
        "LearningMaterial:",
        "SourceAsset:",
        "MediaRendition:",
        "MaterialRevision:",
        "MaterialDetails:",
        "MaterialCapability:",
        "CreateLearningMaterial:",
        "AppendMaterialRevision:",
        "SourceAssetInput:",
        "MediaRenditionInput:",
        "MaterialCapabilityProjection:",
        "CapabilityAttempt:",
        "StartCapabilityAttemptRequest:",
        "FinalizeCapabilityAttemptRequest:",
        "SourceIdentityMapping:",
        "SourceItemEvidence:",
        "RegisterSourceIdentityMappingRequest:",
        "InstallMaterialPackageRequest:",
        "AdoptLearningEditionRequest:",
        "LearningEditionDetails:",
        "LearningEditionResource:",
        "LearningEditionRendition:",
    ] {
        assert!(
            openapi.contains(&format!("    {schema}")),
            "OpenAPI schema missing: {schema}"
        );
    }

    for removed in [
        "/v1/materials/{material_id}/composition/renditions/{rendition_id}/blob:",
        "/v1/realtime/providers:",
        "/v1/reading/positions/{track_id}:",
        "/v1/production-corpus/search:",
        "/v1/review/anki/import:",
        "DocumentRendition:",
        "DocumentRenditionInput:",
    ] {
        assert!(
            !openapi.contains(removed),
            "retired OpenAPI surface {removed} must stay absent"
        );
    }
}

#[test]
fn openapi_learning_observation_task_values_match_domain() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");
    let task_types = [
        domain::ObservationTaskType::ContextMarking,
        domain::ObservationTaskType::Cloze,
        domain::ObservationTaskType::Dictation,
        domain::ObservationTaskType::SubtitleFade,
        domain::ObservationTaskType::ReviewRecall,
        domain::ObservationTaskType::UpgradeConfirmation,
    ];
    let values = task_types
        .iter()
        .map(|task_type| {
            serde_json::to_value(task_type)
                .unwrap()
                .as_str()
                .unwrap()
                .to_owned()
        })
        .collect::<Vec<_>>();
    let schema_enum = format!("task_type: {{ enum: [{}] }}", values.join(", "));
    assert!(
        openapi.contains(&schema_enum),
        "LearningObservation.task_type must match the listening task enum: {schema_enum}"
    );
}

#[test]
fn package_lifecycle_error_contract_is_recorded_in_openapi() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");

    // Every typed error code must exist in the canonical OpenAPI.
    for code in [
        "not_found",
        "package_installation_invalid",
        "edition_adoption_conflict",
        "cannot_delete_adopted_edition",
        "package_lifecycle_failed",
    ] {
        assert!(
            openapi.contains(&format!("code: {code}")),
            "OpenAPI must record the typed package lifecycle error code {code}"
        );
    }

    // The fixed public messages and retryable flags are part of the contract.
    for message in [
        "package release is invalid or incompatible",
        "learning edition cannot be adopted",
        "cannot delete currently adopted package release; switch adoption first",
        "local package lifecycle operation failed",
    ] {
        assert!(
            openapi.contains(message),
            "OpenAPI must record the package lifecycle public message {message:?}"
        );
    }

    // Each operation must formally declare its exact error responses.
    let install = operation_response_block(openapi, "installMaterialPackage");
    let editions = operation_response_block(openapi, "listLearningEditions");
    let delete_edition = operation_response_block(openapi, "deleteLearningEdition");
    let adoption = operation_response_block(openapi, "adoptLearningEdition");
    for status in ["\"404\"", "\"422\"", "\"500\""] {
        assert!(
            install.contains(status),
            "installMaterialPackage must declare {status} responses"
        );
    }
    for status in ["\"404\"", "\"500\""] {
        assert!(
            editions.contains(status),
            "listLearningEditions must declare {status} responses"
        );
    }
    for status in ["\"204\"", "\"404\"", "\"409\"", "\"500\""] {
        assert!(
            delete_edition.contains(status),
            "deleteLearningEdition must declare {status} responses"
        );
    }
    for status in ["\"404\"", "\"409\"", "\"500\""] {
        assert!(
            adoption.contains(status),
            "adoptLearningEdition must declare {status} responses"
        );
    }
}

/// The OpenAPI section from one `operationId` line up to the next top-level
/// path heading, used to assert per-operation response declarations.
pub(crate) fn operation_response_block(openapi: &str, operation_id: &str) -> String {
    let start = openapi
        .find(&format!("operationId: {operation_id}"))
        .unwrap_or_else(|| panic!("OpenAPI operation {operation_id} missing"));
    let rest = &openapi[start..];
    let end = rest
        .lines()
        .enumerate()
        .skip(1)
        .find(|(_, line)| line.starts_with("  /v1/"))
        .map(|(index, _)| index)
        .unwrap_or(rest.lines().count());
    rest.lines().take(end).collect::<Vec<_>>().join("\n")
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

pub(crate) fn openapi_v1_operations(openapi: &str) -> BTreeSet<(String, String)> {
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

pub(crate) fn implemented_v1_operations(router_source: &str) -> BTreeSet<(String, String)> {
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
