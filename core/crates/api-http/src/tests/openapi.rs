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
    // 5.1.0 keeps audio/video-only material intake and restores the parked
    // independent learning activities and text-card review.
    assert!(
        openapi.contains("version: 5.1.0"),
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
        "/v1/production-gap/review:",
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
fn transcription_model_and_provider_routes_have_typed_json_contracts() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");
    let providers = operation_path_block(openapi, "/v1/transcription/providers");
    let models = operation_path_block(openapi, "/v1/transcription/models");
    let install = operation_path_block(openapi, "/v1/transcription/models/install");
    let register = operation_path_block(openapi, "/v1/transcription/models/register-custom");
    let cancel = operation_path_block(
        openapi,
        "/v1/transcription/models/{model_id}/cancel-install",
    );
    let delete = operation_path_block(openapi, "/v1/transcription/models/{model_id}");

    assert!(providers.contains("TranscriptionProviderInfo"));
    assert!(models.contains("TranscriptionModelDescriptor"));
    assert!(install.contains("TranscriptionModelIdRequest"));
    assert!(install.contains("TranscriptionModelInstallStarted"));
    assert!(register.contains("RegisterCustomTranscriptionModelRequest"));
    assert!(register.contains("TranscriptionModelDescriptor"));
    assert!(cancel.contains("TranscriptionModelDescriptor"));
    assert!(delete.contains("\"204\": { description: Model removed }"));

    let model = openapi_schema_block(openapi, "TranscriptionModelDescriptor");
    assert!(model.contains("checksum_sha256: { type: string"));
    assert!(model.contains("download_url: { type: [string, \"null\"]"));
    assert!(model.contains("local_path:\n          type: [string, \"null\"]"));
    assert!(
        model.contains("quality: { $ref: \"#/components/schemas/TranscriptionModelQuality\" }")
    );
    assert!(model.contains("state: { $ref: \"#/components/schemas/TranscriptionModelState\" }"));
    assert!(
        openapi_schema_block(openapi, "TranscriptionModelQuality")
            .contains("enum: [fast, balanced, accurate]")
    );
    assert!(
        openapi_schema_block(openapi, "TranscriptionModelState")
            .contains("enum: [downloadable, installing, installed, custom, failed]")
    );
    assert!(
        openapi_schema_block(openapi, "TranscriptionModelIdRequest")
            .contains("required: [model_id]")
    );
    assert!(
        openapi_schema_block(openapi, "TranscriptionModelInstallStarted")
            .contains("installation_started: { type: boolean }")
    );
    let custom_request = openapi_schema_block(openapi, "RegisterCustomTranscriptionModelRequest");
    assert!(custom_request.contains("required: [path]"));
    assert!(custom_request.contains("Explicitly user-selected local model file path."));

    // Local paths are excluded from Core-managed media/material resources;
    // the retained local recording and model descriptors are scoped exceptions.
    assert!(openapi.contains("Core-managed media and material resource responses omit local"));
    assert!(openapi.contains("local recording and transcription-model asset descriptors"));
}

#[test]
fn openapi_learning_observation_task_values_match_domain() {
    let openapi = include_str!("../../../../contracts/openapi/v1.yaml");
    let task_types = [
        domain::ObservationTaskType::ContextMarking,
        domain::ObservationTaskType::Cloze,
        domain::ObservationTaskType::Dictation,
        domain::ObservationTaskType::SubtitleFade,
        domain::ObservationTaskType::Shadowing,
        domain::ObservationTaskType::ReviewRecall,
        domain::ObservationTaskType::ReadingContextMarking,
        domain::ObservationTaskType::SpeakingProduction,
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
        "LearningObservation.task_type must match domain activity channels: {schema_enum}"
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

fn operation_path_block(openapi: &str, path: &str) -> String {
    let marker = format!("  {path}:");
    let start = openapi
        .find(&marker)
        .unwrap_or_else(|| panic!("OpenAPI path {path} missing"));
    let rest = &openapi[start..];
    let end = rest
        .lines()
        .enumerate()
        .skip(1)
        .find(|(_, line)| line.starts_with("  /v1/") || line.starts_with("components:"))
        .map(|(index, _)| index)
        .unwrap_or(rest.lines().count());
    rest.lines().take(end).collect::<Vec<_>>().join("\n")
}

fn openapi_schema_block<'a>(openapi: &'a str, schema_name: &str) -> &'a str {
    let marker = format!("    {schema_name}:\n");
    let start = openapi
        .find(&marker)
        .unwrap_or_else(|| panic!("OpenAPI schema {schema_name} missing"));
    let rest = &openapi[start + marker.len()..];
    let mut end = rest.len();
    let mut offset: usize = 0;
    for line in rest.lines() {
        if line.starts_with("    ") && !line.starts_with("      ") {
            end = offset.saturating_sub(1);
            break;
        }
        offset += line.len() + 1;
    }
    &rest[..end]
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
