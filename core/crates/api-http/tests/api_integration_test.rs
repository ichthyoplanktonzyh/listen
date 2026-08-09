//! Full-stack HTTP integration tests for the local API.
//!
//! These exercise the real axum router built by [`api_http::router`] on top of
//! a real [`AppServices`] backed by an in-memory SQLite repository. Requests are
//! driven in-process with `tower`'s `oneshot`, so the whole
//! `api-http -> application -> persistence-sqlite` stack is covered without
//! binding a TCP port or pulling in whisper/ffmpeg style runtimes.

use std::sync::Arc;

use api_http::{ApiState, router};
use application::AppServices;
use axum::Router;
use axum::body::Body;
use axum::http::{Request, StatusCode};
use persistence_sqlite::SqliteRepository;
use serde_json::{Value, json};
use tower::ServiceExt;

const TOKEN: &str = "test-token";

/// Build a fresh app over an isolated in-memory database, mirroring the
/// repository wiring used by the real binary in `main.rs`.
fn build_app() -> Router {
    let repo = Arc::new(SqliteRepository::in_memory().expect("in-memory sqlite"));
    let services = AppServices::new(
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
        repo.clone(),
    )
    .with_learning_loop_repositories(repo.clone(), repo.clone(), repo.clone(), repo.clone())
    .with_material_repository(repo.clone());
    router(ApiState::new(services, repo, TOKEN))
}

/// Drive one request through the router and decode the JSON body (if any).
async fn send(app: &Router, request: Request<Body>) -> (StatusCode, Value) {
    let response = app
        .clone()
        .oneshot(request)
        .await
        .expect("router produces a response");
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .expect("collect response body");
    let value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(Value::Null)
    };
    (status, value)
}

fn get(uri: &str, token: Option<&str>) -> Request<Body> {
    let mut builder = Request::builder().method("GET").uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    builder.body(Body::empty()).expect("build GET request")
}

fn post_json(uri: &str, token: Option<&str>, body: &Value) -> Request<Body> {
    let mut builder = Request::builder()
        .method("POST")
        .uri(uri)
        .header("content-type", "application/json");
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    builder
        .body(Body::from(
            serde_json::to_vec(body).expect("serialize body"),
        ))
        .expect("build POST request")
}

fn put_json(uri: &str, token: Option<&str>, body: &Value) -> Request<Body> {
    let mut builder = Request::builder()
        .method("PUT")
        .uri(uri)
        .header("content-type", "application/json");
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    builder
        .body(Body::from(
            serde_json::to_vec(body).expect("serialize body"),
        ))
        .expect("build PUT request")
}

fn method_no_body(method: &str, uri: &str, token: Option<&str>) -> Request<Body> {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    builder.body(Body::empty()).expect("build request")
}

async fn register_media(app: &Router, title: &str) -> Value {
    let (status, media) = send(
        app,
        post_json(
            "/v1/media",
            Some(TOKEN),
            &json!({
                "path": format!("/tmp/{title}.mp4"),
                "fingerprint": format!("fp-{title}"),
                "title": title,
                "kind": "video",
                "duration_ms": 10_000,
            }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "register media: {media}");
    media
}

/// Register media with an explicit membership choice and return the response.
async fn register_media_with_retain(app: &Router, title: &str, retain: Option<bool>) -> Value {
    let mut body = json!({
        "path": format!("/tmp/{title}.mp4"),
        "fingerprint": format!("fp-{title}-retain"),
        "title": title,
        "kind": "video",
        "duration_ms": 10_000,
    });
    if let Some(retain) = retain {
        body["retain"] = json!(retain);
    }
    let (status, media) = send(app, post_json("/v1/media", Some(TOKEN), &body)).await;
    assert_eq!(status, StatusCode::OK, "register media {title}: {media}");
    media
}

async fn library_ids(app: &Router) -> Vec<String> {
    let (status, library) = send(app, get("/v1/media", Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{library}");
    library
        .as_array()
        .expect("library array")
        .iter()
        .map(|entry| entry["media"]["id"].as_str().expect("media id").to_owned())
        .collect()
}

/// Stage `srt` to a real temp file and import it as a subtitle track, since
/// `import_subtitle` reads the source from disk. Returns the import response.
async fn import_srt(app: &Router, media_id: &str, srt: &str) -> (StatusCode, Value) {
    let path = std::env::temp_dir().join(format!(
        "llplayernext-itest-{}-{}.srt",
        std::process::id(),
        application::now_ms()
    ));
    std::fs::write(&path, srt).expect("write temp srt");
    let result = send(
        app,
        post_json(
            &format!("/v1/media/{media_id}/subtitles"),
            Some(TOKEN),
            &json!({ "path": path.to_string_lossy(), "language": "en" }),
        ),
    )
    .await;
    let _ = std::fs::remove_file(&path);
    result
}

const SAMPLE_SRT: &str = "1\n00:00:01,000 --> 00:00:02,000\nHello world\n\n2\n00:00:02,500 --> 00:00:04,000\nSecond line here\n";

#[tokio::test]
async fn health_endpoint_is_unprotected() {
    let app = build_app();
    let (status, body) = send(&app, get("/v1/health", None)).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["status"], "ok");
    assert_eq!(body["api_version"], 1);
    assert_eq!(body["contract_version"], api_http::CONTRACT_VERSION);
    // The learning-material contract is locked exactly: 3.2.0 is the
    // additive minor over the material-retention 3.1.0 (itself additive over
    // the R5 breaking 3.0.0, never the previously published R4 2.1.0).
    assert_eq!(body["contract_version"], "3.2.0");
    assert_eq!(body["runtime_version"], env!("CARGO_PKG_VERSION"));
}

#[tokio::test]
async fn protected_route_rejects_missing_token() {
    let app = build_app();
    let (status, body) = send(&app, post_json("/v1/media", None, &json!({ "title": "x" }))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "{body}");
}

#[tokio::test]
async fn protected_route_rejects_wrong_token() {
    let app = build_app();
    let (status, _) = send(&app, get("/v1/media/anything", Some("wrong-token"))).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn media_register_and_read_round_trip() {
    let app = build_app();

    let registered = register_media(&app, "Round Trip Clip").await;
    let media_id = registered["id"].as_str().expect("media id is a string");
    assert!(!media_id.is_empty());
    assert_eq!(registered["title"], "Round Trip Clip");
    assert_eq!(registered["kind"], "video");

    let (status, fetched) = send(&app, get(&format!("/v1/media/{media_id}"), Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{fetched}");
    assert_eq!(fetched["id"], registered["id"]);
    assert_eq!(fetched["title"], "Round Trip Clip");
}

#[tokio::test]
async fn read_unknown_media_returns_404() {
    let app = build_app();
    let (status, _) = send(
        &app,
        get(
            "/v1/media/0000000000000000000000000000000000000000000000000000000000000000",
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn subtitle_import_round_trips_through_media() {
    let app = build_app();
    let registered = register_media(&app, "Subtitle Host").await;
    let media_id = registered["id"].as_str().expect("media id").to_owned();

    let (status, track) = import_srt(&app, &media_id, SAMPLE_SRT).await;
    assert_eq!(status, StatusCode::OK, "import subtitle: {track}");
    let track_id = track["id"].as_str().expect("track id");
    assert!(!track_id.is_empty());
    let sentences = track["sentences"].as_array().expect("sentences array");
    assert_eq!(sentences.len(), 2, "two SRT cues import as two sentences");

    // The imported track is now listed for the media.
    let (status, list) = send(
        &app,
        get(&format!("/v1/media/{media_id}/subtitles"), Some(TOKEN)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{list}");
    let tracks = list.as_array().expect("subtitle list array");
    assert!(
        tracks.iter().any(|t| t["id"] == track["id"]),
        "imported track appears in media subtitle list"
    );
}

#[tokio::test]
async fn subtitle_archive_restore_delete_lifecycle() {
    let app = build_app();
    let registered = register_media(&app, "Lifecycle Host").await;
    let media_id = registered["id"].as_str().expect("media id").to_owned();

    let (status, track) = import_srt(&app, &media_id, SAMPLE_SRT).await;
    assert_eq!(status, StatusCode::OK, "{track}");
    let track_id = track["id"].as_str().expect("track id").to_owned();
    assert_eq!(track["status"], "available");

    // Archive moves the track out of the active set without deleting it.
    let (status, archived) = send(
        &app,
        method_no_body(
            "POST",
            &format!("/v1/subtitles/{track_id}/archive"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{archived}");
    assert_eq!(archived["status"], "archived");

    // Restore brings it back to available.
    let (status, restored) = send(
        &app,
        method_no_body(
            "POST",
            &format!("/v1/subtitles/{track_id}/restore"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{restored}");
    assert_eq!(restored["status"], "available");

    // Delete removes it; a subsequent read 404s.
    let (status, _) = send(
        &app,
        method_no_body("DELETE", &format!("/v1/subtitles/{track_id}"), Some(TOKEN)),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = send(&app, get(&format!("/v1/subtitles/{track_id}"), Some(TOKEN))).await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "deleted track no longer readable"
    );
}

#[tokio::test]
async fn lltimeline_import_creates_track_with_word_timeline() {
    let app = build_app();

    // Import a full LLTimeline v1 document; this is the core resource contract.
    let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../testdata/lltimeline/v1-minimal.lltimeline.json");
    let document: Value = serde_json::from_slice(&std::fs::read(&fixture).expect("read fixture"))
        .expect("parse lltimeline fixture");

    let (status, track) = send(
        &app,
        post_json("/v1/lltimeline/import", Some(TOKEN), &document),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "import lltimeline: {track}");
    let track_id = track["id"].as_str().expect("track id").to_owned();
    assert!(
        track["sentences"].as_array().is_some_and(|s| !s.is_empty()),
        "imported document yields subtitle sentences"
    );

    // Detached import preserves the text/analysis resource but never claims
    // that the document's path snapshot is a live playback source.
    let media_id = document["metadata"]["media"]["id"]
        .as_str()
        .expect("fixture media id");
    let (status, media) = send(&app, get(&format!("/v1/media/{media_id}"), Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{media}");
    assert_eq!(media["availability"], "missing");
    assert_eq!(media["path"], format!("lltimeline://{media_id}"));

    let (status, library) = send(&app, get("/v1/media", Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{library}");
    assert_eq!(library[0]["media"]["availability"], "missing");
    assert_eq!(library[0]["primary_track_id"], track_id);

    // A synthetic source cannot be made playable by flipping a status bit.
    // Recovery must bind the resource to registered real media.
    let (status, unavailable) = send(
        &app,
        put_json(
            &format!("/v1/media/{media_id}/availability"),
            Some(TOKEN),
            &json!({"availability": "available"}),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{unavailable}");
    assert_eq!(unavailable["code"], "invalid_input");
    assert!(
        unavailable["message"]
            .as_str()
            .is_some_and(|message| message.contains("import the LLTimeline for that media"))
    );

    // The bundled word timeline imports alongside the track.
    let (status, timelines) = send(
        &app,
        get(
            &format!("/v1/subtitles/{track_id}/word-timelines"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{timelines}");
    assert!(
        !timelines
            .as_array()
            .expect("word timeline array")
            .is_empty(),
        "imported document carries its word timeline"
    );
}

#[tokio::test]
async fn lltimeline_import_for_missing_media_preserves_source_loss_state() {
    let app = build_app();
    let media = register_media(&app, "Missing LLTimeline Host").await;
    let media_id = media["id"].as_str().expect("media id");

    let (status, missing) = send(
        &app,
        put_json(
            &format!("/v1/media/{media_id}/availability"),
            Some(TOKEN),
            &json!({"availability": "missing"}),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{missing}");
    assert_eq!(missing["availability"], "missing");

    let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../testdata/lltimeline/v1-minimal.lltimeline.json");
    let document: Value = serde_json::from_slice(&std::fs::read(&fixture).expect("read fixture"))
        .expect("parse lltimeline fixture");
    let (status, track) = send(
        &app,
        post_json(
            &format!("/v1/media/{media_id}/lltimeline/import?allow_mismatch=true"),
            Some(TOKEN),
            &document,
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{track}");
    assert_eq!(track["media_id"], media_id);

    let (status, after_import) =
        send(&app, get(&format!("/v1/media/{media_id}"), Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{after_import}");
    assert_eq!(after_import["availability"], "missing");
    assert_eq!(after_import["path"], media["path"]);
}

#[tokio::test]
async fn word_timeline_create_and_activate_lifecycle() {
    let app = build_app();
    let registered = register_media(&app, "Word Timeline Host").await;
    let media_id = registered["id"].as_str().expect("media id").to_owned();
    let (status, track) = import_srt(&app, &media_id, SAMPLE_SRT).await;
    assert_eq!(status, StatusCode::OK, "{track}");
    let track_id = track["id"].as_str().expect("track id").to_owned();
    let sentence_id = track["sentences"][0]["id"]
        .as_str()
        .expect("sentence id")
        .to_owned();

    let (status, timeline) = send(
        &app,
        post_json(
            &format!("/v1/subtitles/{track_id}/word-timelines"),
            Some(TOKEN),
            &json!({
                "status": "candidate",
                "words": [{
                    "sentence_id": sentence_id,
                    "token_index": 0,
                    "text": "Hello",
                    "start_ms": 1000,
                    "end_ms": 1500,
                    "timing_source": "estimated",
                    "provider_id": "integration-test",
                    "provider_version": "1",
                }],
            }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "create word timeline: {timeline}");
    let timeline_id = timeline["id"].as_str().expect("timeline id").to_owned();
    assert_eq!(timeline["status"], "candidate");

    let (status, activated) = send(
        &app,
        method_no_body(
            "POST",
            &format!("/v1/word-timelines/{timeline_id}/activate"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "activate: {activated}");
    assert_eq!(activated["status"], "active");
}

#[tokio::test]
async fn sentence_diagnosis_returns_well_formed_structure() {
    let app = build_app();
    let registered = register_media(&app, "Diagnosis Host").await;
    let media_id = registered["id"].as_str().expect("media id").to_owned();
    let (status, track) = import_srt(&app, &media_id, SAMPLE_SRT).await;
    assert_eq!(status, StatusCode::OK, "{track}");
    let sentence_id = track["sentences"][0]["id"]
        .as_str()
        .expect("sentence id")
        .to_owned();

    let (status, diagnosis) = send(
        &app,
        get(
            &format!("/v1/sentences/{sentence_id}/diagnosis"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "diagnose: {diagnosis}");
    assert_eq!(diagnosis["sentence_id"], sentence_id);
    assert!(
        diagnosis["hints"].is_array(),
        "diagnosis exposes a hints array"
    );
}

#[tokio::test]
async fn lexical_entry_upsert_list_detail_and_update_lifecycle() {
    let app = build_app();

    // Upsert a word entry (the learning asset the vocabulary book is built on).
    let (status, details) = send(
        &app,
        put_json(
            "/v1/lexical-entries",
            Some(TOKEN),
            &json!({
                "language": "en",
                "kind": "word",
                "canonical_form": "ubiquitous",
                "display_form": "ubiquitous",
                "status": "unknown_meaning",
            }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "upsert lexical entry: {details}");
    let entry_id = details["entry"]["id"]
        .as_str()
        .expect("entry id")
        .to_owned();
    assert_eq!(details["entry"]["normalized_form"], "ubiquitous");
    assert_eq!(details["entry"]["status"], "unknown_meaning");

    // It appears in the language/kind-scoped list.
    let (status, list) = send(
        &app,
        get("/v1/lexical-entries?language=en&kind=word", Some(TOKEN)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{list}");
    assert!(
        list.as_array()
            .expect("entry list array")
            .iter()
            .any(|d| d["entry"]["id"] == details["entry"]["id"]),
        "upserted entry appears in the list"
    );

    // Detail fetch by id round-trips.
    let (status, fetched) = send(
        &app,
        get(&format!("/v1/lexical-entries/{entry_id}"), Some(TOKEN)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{fetched}");
    assert_eq!(fetched["entry"]["id"], details["entry"]["id"]);

    // Durable learning content updates persist on the entry.
    let (status, updated) = send(
        &app,
        put_json(
            &format!("/v1/lexical-entries/{entry_id}/learning-content"),
            Some(TOKEN),
            &json!({
                "user_definition": "found everywhere",
                "personal_note": "GRE word",
            }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "update learning content: {updated}");
    assert_eq!(updated["entry"]["user_definition"], "found everywhere");
    assert_eq!(updated["entry"]["personal_note"], "GRE word");
}

#[tokio::test]
async fn sense_folder_http_lifecycle_keeps_entry_occurrences_and_assigns_manually() {
    let app = build_app();
    let (status, entry) = send(
        &app,
        put_json(
            "/v1/lexical-entries",
            Some(TOKEN),
            &json!({
                "language": "en", "kind": "word", "canonical_form": "run", "display_form": "run",
                "source": {
                    "original_form": "runs", "sentence_text": "She runs a business.",
                    "media_title": "Personal media", "media_fingerprint": "fp-run",
                    "start_ms": 100, "end_ms": 900, "token_start": 1, "token_end": 1
                }
            }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{entry}");
    let entry_id = entry["entry"]["id"].as_str().unwrap();
    let occurrence_id = entry["occurrences"][0]["id"].as_str().unwrap();

    let (status, created) = send(
        &app,
        post_json(
            &format!("/v1/lexical-entries/{entry_id}/sense-folders"),
            Some(TOKEN),
            &json!({"label": "operate a business", "external_ref": "scenelex:run-03"}),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{created}");
    assert_eq!(created["occurrences"].as_array().unwrap().len(), 1);
    let sense_id = created["sense_folders"][0]["folder"]["id"]
        .as_str()
        .unwrap();

    let (status, assigned) = send(
        &app,
        put_json(
            &format!("/v1/lexical-entries/{entry_id}/sense-folders/{sense_id}/occurrences/{occurrence_id}"),
            Some(TOKEN),
            &json!({}),
        ),
    ).await;
    assert_eq!(status, StatusCode::OK, "{assigned}");
    assert_eq!(
        assigned["sense_folders"][0]["occurrences"]
            .as_array()
            .unwrap()
            .len(),
        1
    );

    let (status, deleted) = send(
        &app,
        method_no_body(
            "DELETE",
            &format!("/v1/lexical-entries/{entry_id}/sense-folders/{sense_id}"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{deleted}");
    assert!(deleted["sense_folders"].as_array().unwrap().is_empty());
    assert_eq!(deleted["occurrences"].as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn temporary_registration_is_readable_but_absent_from_library() {
    let app = build_app();
    let media = register_media_with_retain(&app, "Temporary Clip", Some(false)).await;
    let media_id = media["id"].as_str().expect("media id");
    assert!(media["retained_at_ms"].is_null());

    // Readable by ID...
    let (status, fetched) = send(&app, get(&format!("/v1/media/{media_id}"), Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{fetched}");
    assert_eq!(fetched["id"], media["id"]);
    assert!(fetched["retained_at_ms"].is_null());

    // ...but absent from the Personal Library projection.
    assert!(!library_ids(&app).await.contains(&media_id.to_owned()));
}

#[tokio::test]
async fn omitted_retain_registration_stays_retained_for_old_clients() {
    let app = build_app();
    let media = register_media_with_retain(&app, "Legacy Clip", None).await;
    let media_id = media["id"].as_str().expect("media id");
    assert!(
        media["retained_at_ms"].is_number(),
        "omitted retain must default to retained: {media}"
    );
    assert!(library_ids(&app).await.contains(&media_id.to_owned()));
}

#[tokio::test]
async fn explicit_true_registration_retains_immediately() {
    let app = build_app();
    let media = register_media_with_retain(&app, "Kept Clip", Some(true)).await;
    let media_id = media["id"].as_str().expect("media id");
    assert!(
        media["retained_at_ms"].is_number(),
        "explicit retain true must retain: {media}"
    );
    assert!(library_ids(&app).await.contains(&media_id.to_owned()));
}

#[tokio::test]
async fn library_membership_put_delete_cycle_preserves_timestamps_and_is_idempotent() {
    let app = build_app();
    let media = register_media_with_retain(&app, "Membership Clip", Some(false)).await;
    let media_id = media["id"].as_str().expect("media id").to_owned();

    // PUT joins the library and stamps membership once.
    let (status, retained) = send(
        &app,
        method_no_body(
            "PUT",
            &format!("/v1/media/{media_id}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{retained}");
    let first_membership = retained["retained_at_ms"]
        .as_u64()
        .expect("membership time");
    assert!(library_ids(&app).await.contains(&media_id));

    // Repeated PUT preserves the original membership timestamp.
    let (status, retained_again) = send(
        &app,
        method_no_body(
            "PUT",
            &format!("/v1/media/{media_id}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{retained_again}");
    assert_eq!(
        retained_again["retained_at_ms"].as_u64(),
        Some(first_membership),
        "repeated retention must preserve the original membership time"
    );

    // DELETE leaves it readable but removes it from the library.
    let (status, unretained) = send(
        &app,
        method_no_body(
            "DELETE",
            &format!("/v1/media/{media_id}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{unretained}");
    assert!(unretained["retained_at_ms"].is_null());
    let (status, fetched) = send(&app, get(&format!("/v1/media/{media_id}"), Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{fetched}");
    assert!(!library_ids(&app).await.contains(&media_id));

    // DELETE is idempotent.
    let (status, unretained_again) = send(
        &app,
        method_no_body(
            "DELETE",
            &format!("/v1/media/{media_id}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{unretained_again}");
    assert!(unretained_again["retained_at_ms"].is_null());

    // PUT after DELETE obtains a new membership timestamp and returns to the
    // library. The sleep guarantees the millisecond clock advances so the
    // re-stamp is observably fresh.
    tokio::time::sleep(std::time::Duration::from_millis(2)).await;
    let (status, re_retained) = send(
        &app,
        method_no_body(
            "PUT",
            &format!("/v1/media/{media_id}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{re_retained}");
    let second_membership = re_retained["retained_at_ms"]
        .as_u64()
        .expect("membership time");
    assert!(
        second_membership > first_membership,
        "PUT after DELETE must obtain a fresh membership timestamp"
    );
    assert!(library_ids(&app).await.contains(&media_id));
}

#[tokio::test]
async fn repeated_registration_never_clears_existing_membership() {
    let app = build_app();
    let media = register_media_with_retain(&app, "Re-register Clip", Some(false)).await;
    let media_id = media["id"].as_str().expect("media id").to_owned();
    let fingerprint = format!("fp-{}-retain", "Re-register Clip");

    // A later registration with `retain: false` over the same fingerprint
    // must not silently unretain an already retained item.
    let (status, retained) = send(
        &app,
        method_no_body(
            "PUT",
            &format!("/v1/media/{media_id}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{retained}");
    let membership = retained["retained_at_ms"]
        .as_u64()
        .expect("membership time");

    let (status, re_registered) = send(
        &app,
        post_json(
            "/v1/media",
            Some(TOKEN),
            &json!({
                "path": "/tmp/Re-register Clip.mp4",
                "fingerprint": fingerprint,
                "title": "Re-register Clip",
                "kind": "video",
                "duration_ms": 10_000,
                "retain": false,
            }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{re_registered}");
    assert_eq!(
        re_registered["retained_at_ms"].as_u64(),
        Some(membership),
        "registration with retain false must preserve existing membership"
    );
    assert!(library_ids(&app).await.contains(&media_id));
}

#[tokio::test]
async fn library_membership_unknown_media_is_typed_not_found() {
    let app = build_app();
    let unknown = "0000000000000000000000000000000000000000000000000000000000000000";
    let (status, body) = send(
        &app,
        method_no_body(
            "PUT",
            &format!("/v1/media/{unknown}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "not_found");

    let (status, body) = send(
        &app,
        method_no_body(
            "DELETE",
            &format!("/v1/media/{unknown}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "not_found");
}

#[tokio::test]
async fn retained_media_states_membership_in_every_response_shape() {
    let app = build_app();
    let media = register_media_with_retain(&app, "Shape Clip", Some(true)).await;
    let media_id = media["id"].as_str().expect("media id");

    // The MediaItem read shape always carries membership evidence.
    let (status, fetched) = send(&app, get(&format!("/v1/media/{media_id}"), Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{fetched}");
    assert!(fetched.get("retained_at_ms").is_some());

    // The library entry embeds the same MediaItem shape.
    let (status, library) = send(&app, get("/v1/media", Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{library}");
    let entry = library
        .as_array()
        .expect("library array")
        .iter()
        .find(|entry| entry["media"]["id"] == media_id)
        .expect("retained media appears in the library");
    assert!(entry["media"].get("retained_at_ms").is_some());
    assert!(entry["media"]["retained_at_ms"].is_number());
}

// ---------------------------------------------------------------------------
// Learning-material HTTP surface (contract 3.2.0): acceptance coverage A-G.
// ---------------------------------------------------------------------------

/// Create a learning material over HTTP and return the details response.
async fn create_material(app: &Router, title: &str, assets: Value, retain: Option<bool>) -> Value {
    let mut body = json!({ "title": title, "assets": assets });
    if let Some(retain) = retain {
        body["retain"] = json!(retain);
    }
    let (status, material) = send(app, post_json("/v1/materials", Some(TOKEN), &body)).await;
    assert_eq!(
        status,
        StatusCode::OK,
        "create material {title}: {material}"
    );
    material
}

/// Material ids present in the retained Personal Library projection.
async fn material_library_ids(app: &Router) -> Vec<String> {
    let (status, list) = send(app, get("/v1/materials", Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{list}");
    list.as_array()
        .expect("material list array")
        .iter()
        .map(|entry| {
            entry["material"]["id"]
                .as_str()
                .expect("material id")
                .to_owned()
        })
        .collect()
}

// A. Register media with retain:false; resolve immediately; assert matching
// media_id, temporary material, deterministic response, path-free assets, and
// absence from the material list.
#[tokio::test]
async fn temporary_media_resolves_temporary_material_without_path() {
    let app = build_app();
    let media = register_media_with_retain(&app, "Resolvable Clip", Some(false)).await;
    let media_id = media["id"].as_str().expect("media id").to_owned();
    assert!(media["retained_at_ms"].is_null());

    // Media registration creates one deterministic material graph, so the
    // material resolves immediately.
    let (status, material) = send(
        &app,
        get(&format!("/v1/media/{media_id}/material"), Some(TOKEN)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{material}");
    let material_id = material["material"]["id"]
        .as_str()
        .expect("material id")
        .to_owned();
    assert!(
        material["material"]["retained_at_ms"].is_null(),
        "retain:false media registers a temporary material: {material}"
    );
    assert_eq!(material["shape"], "video");
    let rendition = &material["current_revision"]["assets"][0];
    assert_eq!(rendition["asset_type"], "media_rendition");
    assert_eq!(rendition["media_id"], media_id);
    assert_eq!(rendition["media_kind"], "video");
    // No material, revision, or asset response exposes a path.
    assert!(
        rendition.get("path").is_none(),
        "asset leaks path: {rendition}"
    );
    assert!(material["current_revision"].get("path").is_none());
    assert!(material["material"].get("path").is_none());

    // Deterministic response: a second read returns the same identities.
    let (status, again) = send(
        &app,
        get(&format!("/v1/media/{media_id}/material"), Some(TOKEN)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{again}");
    assert_eq!(again["material"]["id"], material_id);
    assert_eq!(
        again["current_revision"]["id"],
        material["current_revision"]["id"]
    );

    // Temporary Material is absent from the retained material list.
    assert!(!material_library_ids(&app).await.contains(&material_id));
}

// B. PUT membership: original material enters the list exactly once and
// membership timestamps agree with the legacy media projection/read; a repeat
// PUT preserves the original timestamp.
#[tokio::test]
async fn material_membership_put_is_idempotent_and_syncs_with_media_projection() {
    let app = build_app();
    let media = register_media_with_retain(&app, "Material Member Clip", Some(false)).await;
    let media_id = media["id"].as_str().expect("media id").to_owned();
    let (_, resolved) = send(
        &app,
        get(&format!("/v1/media/{media_id}/material"), Some(TOKEN)),
    )
    .await;
    let material_id = resolved["material"]["id"]
        .as_str()
        .expect("material id")
        .to_owned();
    assert!(resolved["material"]["retained_at_ms"].is_null());

    // Legacy media projection agrees the item is temporary.
    let (_, media_read) = send(&app, get(&format!("/v1/media/{media_id}"), Some(TOKEN))).await;
    assert!(media_read["retained_at_ms"].is_null());

    // PUT joins the library and stamps membership once.
    let (status, retained) = send(
        &app,
        method_no_body(
            "PUT",
            &format!("/v1/materials/{material_id}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{retained}");
    let first_membership = retained["material"]["retained_at_ms"]
        .as_u64()
        .expect("membership time");

    // The original material enters the retained list exactly once.
    let (status, list) = send(&app, get("/v1/materials", Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{list}");
    let matches: Vec<_> = list
        .as_array()
        .expect("material list array")
        .iter()
        .filter(|entry| entry["material"]["id"] == material_id)
        .collect();
    assert_eq!(
        matches.len(),
        1,
        "material must appear exactly once: {list}"
    );
    assert_eq!(
        matches[0]["material"]["retained_at_ms"].as_u64(),
        Some(first_membership)
    );

    // Membership timestamps agree with the legacy media projection/read.
    let (status, media_read) = send(&app, get(&format!("/v1/media/{media_id}"), Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{media_read}");
    assert_eq!(
        media_read["retained_at_ms"].as_u64(),
        Some(first_membership)
    );
    let (status, library) = send(&app, get("/v1/media", Some(TOKEN))).await;
    assert_eq!(status, StatusCode::OK, "{library}");
    let entry = library
        .as_array()
        .expect("library array")
        .iter()
        .find(|entry| entry["media"]["id"] == media_id)
        .expect("media enters the legacy library too");
    assert_eq!(
        entry["media"]["retained_at_ms"].as_u64(),
        Some(first_membership),
        "material membership and legacy media membership must agree"
    );

    // Repeat PUT preserves the original membership timestamp.
    let (status, retained_again) = send(
        &app,
        method_no_body(
            "PUT",
            &format!("/v1/materials/{material_id}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{retained_again}");
    assert_eq!(
        retained_again["material"]["retained_at_ms"].as_u64(),
        Some(first_membership),
        "repeated retention must preserve the original membership time"
    );
}

// C. DELETE membership: leaves the list but stays readable/resolvable with
// unchanged revision identity; repeated DELETE is idempotent.
#[tokio::test]
async fn material_membership_delete_preserves_material_and_is_idempotent() {
    let app = build_app();
    let media = register_media_with_retain(&app, "Material Temp Clip", Some(false)).await;
    let media_id = media["id"].as_str().expect("media id").to_owned();
    let (_, resolved) = send(
        &app,
        get(&format!("/v1/media/{media_id}/material"), Some(TOKEN)),
    )
    .await;
    let material_id = resolved["material"]["id"]
        .as_str()
        .expect("material id")
        .to_owned();
    let revision_id = resolved["current_revision"]["id"]
        .as_str()
        .expect("revision id")
        .to_owned();

    // Retain first, then DELETE membership.
    let (status, _) = send(
        &app,
        method_no_body(
            "PUT",
            &format!("/v1/materials/{material_id}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, unretained) = send(
        &app,
        method_no_body(
            "DELETE",
            &format!("/v1/materials/{material_id}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{unretained}");
    assert!(unretained["material"]["retained_at_ms"].is_null());

    // It leaves the retained list...
    assert!(!material_library_ids(&app).await.contains(&material_id));

    // ...but stays readable with unchanged revision identity.
    let (status, read) = send(
        &app,
        get(&format!("/v1/materials/{material_id}"), Some(TOKEN)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{read}");
    assert_eq!(read["material"]["id"], material_id);
    assert_eq!(read["material"]["current_revision_id"], revision_id);
    assert_eq!(read["current_revision"]["id"], revision_id);

    // ...and stays resolvable from its media.
    let (status, resolved_again) = send(
        &app,
        get(&format!("/v1/media/{media_id}/material"), Some(TOKEN)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{resolved_again}");
    assert_eq!(resolved_again["material"]["id"], material_id);

    // DELETE is idempotent.
    let (status, again) = send(
        &app,
        method_no_body(
            "DELETE",
            &format!("/v1/materials/{material_id}/library-membership"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{again}");
    assert!(again["material"]["retained_at_ms"].is_null());
}

// D. Text-only material with exact multibyte/whitespace bytes and language:
// default retained, exact text/digest/byte_size, no path; append a revision,
// then read current and historical revisions and prove ownership and shape.
#[tokio::test]
async fn text_material_preserves_exact_bytes_and_revision_ownership() {
    use sha2::{Digest, Sha256};

    let app = build_app();
    // Exact bytes are never trimmed or mutated: leading/trailing spaces, a
    // newline, and non-ASCII characters.
    let text = "  Hello, 世界!  \n";
    let (status, created) = send(
        &app,
        post_json(
            "/v1/materials",
            Some(TOKEN),
            &json!({
                "title": "Exact Bytes",
                "assets": [
                    { "asset_type": "document_text", "text": text, "language": "en" },
                ],
            }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{created}");
    let material_id = created["material"]["id"]
        .as_str()
        .expect("material id")
        .to_owned();
    let first_revision_id = created["current_revision"]["id"]
        .as_str()
        .expect("revision id")
        .to_owned();

    // Omitted retain defaults to retained membership.
    assert!(
        created["material"]["retained_at_ms"].is_number(),
        "omitted retain must default to retained: {created}"
    );
    assert_eq!(created["shape"], "text");

    let asset = &created["current_revision"]["assets"][0];
    assert_eq!(asset["asset_type"], "document_text");
    assert_eq!(asset["text"], text, "stored text must be the exact bytes");
    assert_eq!(asset["language"], "en");
    assert_eq!(asset["byte_size"], text.len() as u64);
    assert_eq!(
        asset["sha256_digest"],
        hex::encode(Sha256::digest(text.as_bytes())),
        "digest must be computed over the exact stored bytes"
    );
    assert!(asset.get("path").is_none());
    assert!(created["current_revision"].get("path").is_none());
    assert!(created["material"].get("path").is_none());

    // The default-retained material enters the list.
    assert!(material_library_ids(&app).await.contains(&material_id));

    // Append a revision with different exact bytes and a null language.
    let new_text = "  Second revision — 修正.  ";
    let (status, appended) = send(
        &app,
        post_json(
            &format!("/v1/materials/{material_id}/revisions"),
            Some(TOKEN),
            &json!({
                "title": "Exact Bytes v2",
                "assets": [
                    { "asset_type": "document_text", "text": new_text, "language": null },
                ],
            }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{appended}");
    let current = &appended["current_revision"];
    assert_eq!(current["title"], "Exact Bytes v2");
    assert_eq!(current["assets"][0]["text"], new_text);
    assert_eq!(current["assets"][0]["byte_size"], new_text.len() as u64);
    assert!(
        current["assets"][0]["language"].is_null(),
        "null language stays null"
    );
    let second_revision_id = current["id"].as_str().expect("revision id").to_owned();
    assert_ne!(first_revision_id, second_revision_id);
    // Creation time and membership survive a revision append.
    assert_eq!(
        appended["material"]["created_at_ms"],
        created["material"]["created_at_ms"]
    );
    assert!(appended["material"]["retained_at_ms"].is_number());

    // Reading the material returns the appended revision as current.
    let (status, read) = send(
        &app,
        get(&format!("/v1/materials/{material_id}"), Some(TOKEN)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{read}");
    assert_eq!(read["current_revision"]["id"], second_revision_id);
    assert_eq!(read["shape"], "text");

    // Historical revision read: exact original bytes, owned by the material.
    let (status, historical) = send(
        &app,
        get(
            &format!("/v1/materials/{material_id}/revisions/{first_revision_id}"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{historical}");
    assert_eq!(historical["id"], first_revision_id);
    assert_eq!(historical["material_id"], material_id);
    assert_eq!(historical["title"], "Exact Bytes");
    assert_eq!(historical["assets"][0]["text"], text);
    assert_eq!(
        historical["assets"][0]["sha256_digest"],
        asset["sha256_digest"]
    );
    assert!(historical.get("path").is_none());
    assert!(historical["assets"][0].get("path").is_none());

    // Current revision read through the revision endpoint.
    let (status, current_read) = send(
        &app,
        get(
            &format!("/v1/materials/{material_id}/revisions/{second_revision_id}"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{current_read}");
    assert_eq!(current_read["id"], second_revision_id);
    assert_eq!(current_read["title"], "Exact Bytes v2");
}

// D-null. Explicit JSON `retain: null` (as opposed to omitting the field)
// must create a retained material that appears in the retained list. Unique
// text assets guarantee the assertion cannot pass by converging on a material
// retained by an earlier step.
#[tokio::test]
async fn explicit_null_retain_creates_a_retained_material() {
    let app = build_app();
    let unique_text = format!("explicit-null-retain-{}", application::now_ms());
    let (status, created) = send(
        &app,
        post_json(
            "/v1/materials",
            Some(TOKEN),
            &json!({
                "title": "Explicit Null Retain",
                "assets": [
                    { "asset_type": "document_text", "text": unique_text, "language": null },
                ],
                "retain": null,
            }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{created}");
    let material_id = created["material"]["id"]
        .as_str()
        .expect("material id")
        .to_owned();
    assert!(
        created["material"]["retained_at_ms"].is_number(),
        "explicit retain:null must default to retained membership: {created}"
    );
    assert!(
        material_library_ids(&app).await.contains(&material_id),
        "retain:null material must appear in GET /v1/materials: {created}"
    );
}

// E. Unknown/malformed material, revision, and media ids are typed 4xx; a
// revision owned by another material is a typed 404.
#[tokio::test]
async fn material_unknown_and_malformed_ids_are_typed_4xx() {
    let app = build_app();
    let unknown = "0".repeat(64);

    // Malformed (whitespace/empty) ids are validation errors.
    for uri in [
        "/v1/materials/%20".to_owned(),
        format!("/v1/materials/{unknown}/revisions/%20"),
        "/v1/media/%20/material".to_owned(),
    ] {
        let (status, body) = send(&app, get(&uri, Some(TOKEN))).await;
        assert_eq!(
            status,
            StatusCode::BAD_REQUEST,
            "malformed id {uri}: {body}"
        );
        assert_eq!(body["code"], "domain_error");
    }

    // Well-formed but unknown ids are typed not-found.
    let (status, body) = send(&app, get(&format!("/v1/materials/{unknown}"), Some(TOKEN))).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "not_found");

    let (status, body) = send(
        &app,
        get(
            &format!("/v1/materials/{unknown}/revisions/{unknown}"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "not_found");

    let (status, body) = send(
        &app,
        get(&format!("/v1/media/{unknown}/material"), Some(TOKEN)),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "not_found");

    // A revision owned by another material is a typed 404.
    let material_a = create_material(
        &app,
        "Owner A",
        json!([{ "asset_type": "document_text", "text": "alpha" }]),
        None,
    )
    .await;
    let id_a = material_a["material"]["id"].as_str().expect("material id");
    let revision_a = material_a["current_revision"]["id"]
        .as_str()
        .expect("revision id")
        .to_owned();
    let material_b = create_material(
        &app,
        "Owner B",
        json!([{ "asset_type": "document_text", "text": "beta" }]),
        None,
    )
    .await;
    let id_b = material_b["material"]["id"].as_str().expect("material id");

    let (status, body) = send(
        &app,
        get(
            &format!("/v1/materials/{id_b}/revisions/{revision_a}"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "cross-material revision: {body}"
    );
    assert_eq!(body["code"], "not_found");
    assert_eq!(body["message"], "material revision was not found");

    // The owner still reads its own revision.
    let (status, _) = send(
        &app,
        get(
            &format!("/v1/materials/{id_a}/revisions/{revision_a}"),
            Some(TOKEN),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

// F. Mixed/media conflicts and unknown media inputs prove application error
// mapping without duplicating the application-layer test suite.
#[tokio::test]
async fn mixed_and_unknown_media_inputs_map_through_application_errors() {
    let app = build_app();
    let media_a = register_media_with_retain(&app, "Mix A", Some(false)).await;
    let media_b = register_media_with_retain(&app, "Mix B", Some(false)).await;
    let id_a = media_a["id"].as_str().expect("media id");
    let id_b = media_b["id"].as_str().expect("media id");

    // Two distinct media renditions bound to different materials is an
    // application conflict: the use case maps it to a typed 409 and keeps
    // repository details redacted.
    let (status, body) = send(
        &app,
        post_json(
            "/v1/materials",
            Some(TOKEN),
            &json!({
                "title": "Ambiguous Mix",
                "assets": [
                    { "asset_type": "media_rendition", "media_id": id_a },
                    { "asset_type": "media_rendition", "media_id": id_b },
                ],
            }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT, "{body}");
    assert_eq!(body["code"], "asset_conflict");
    assert!(
        body["message"]
            .as_str()
            .unwrap()
            .contains("media renditions belong to different materials"),
        "conflict names the binding conflict: {body}"
    );

    // A well-formed media id that is not registered is a typed not-found.
    let unknown_media = "0".repeat(64);
    let (status, body) = send(
        &app,
        post_json(
            "/v1/materials",
            Some(TOKEN),
            &json!({
                "title": "Unknown Media",
                "assets": [{ "asset_type": "media_rendition", "media_id": unknown_media }],
            }),
        ),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "{body}");
    assert_eq!(body["code"], "not_found");
    assert!(
        body["message"].as_str().unwrap().contains("media"),
        "not-found names the media entity: {body}"
    );
}
