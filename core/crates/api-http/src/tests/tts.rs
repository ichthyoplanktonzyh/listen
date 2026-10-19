use super::*;
use application::{
    ProviderSynthesisOutput, ProviderSynthesisRequest, SpeechSynthesisError,
    SpeechSynthesisLocality, SpeechSynthesisProvider, SpeechSynthesisProviderDescriptor,
    SpeechSynthesisVoice,
};
use async_trait::async_trait;
use local_runtime::SpeechSynthesisManager;

#[derive(Debug)]
struct RouteSpeechProvider;

#[async_trait]
impl SpeechSynthesisProvider for RouteSpeechProvider {
    fn descriptor(&self) -> SpeechSynthesisProviderDescriptor {
        SpeechSynthesisProviderDescriptor {
            id: "route-speech".into(),
            display_name: "Route Speech".into(),
            version: "1".into(),
            locality: SpeechSynthesisLocality::Local,
        }
    }

    async fn voices(&self) -> Result<Vec<SpeechSynthesisVoice>, SpeechSynthesisError> {
        Ok(vec![SpeechSynthesisVoice {
            id: "route-en".into(),
            provider_id: "route-speech".into(),
            display_name: "Route English".into(),
            language: "en-US".into(),
        }])
    }

    async fn synthesize(
        &self,
        _request: &ProviderSynthesisRequest,
    ) -> Result<ProviderSynthesisOutput, SpeechSynthesisError> {
        Ok(ProviderSynthesisOutput {
            bytes: b"route-audio".to_vec(),
            file_extension: "aiff".into(),
            mime_type: "audio/aiff".into(),
        })
    }
}

fn tts_app() -> Router {
    let cache = std::env::temp_dir().join(format!(
        "llplayer-route-tts-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    router(
        test_state().with_speech_synthesis(SpeechSynthesisManager::new(
            cache,
            vec![Arc::new(RouteSpeechProvider)],
        )),
    )
}

#[tokio::test]
async fn speech_synthesis_routes_expose_capability_asset_and_cache_lifecycle() {
    let app = tts_app();
    let capability = app
        .clone()
        .oneshot(
            Request::get("/v1/speech-synthesis/capability")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(capability.status(), StatusCode::OK);
    let capability: serde_json::Value =
        serde_json::from_slice(&to_bytes(capability.into_body(), usize::MAX).await.unwrap())
            .unwrap();
    assert_eq!(capability["status"], "ready");
    assert_eq!(capability["providers"][0]["locality"], "local");
    assert_eq!(capability["voices"][0]["provider_id"], "route-speech");

    let request = || {
        Request::post("/v1/speech-synthesis")
            .header(AUTHORIZATION, "Bearer secret")
            .header(CONTENT_TYPE, "application/json")
            .body(Body::from(
                serde_json::json!({
                    "text": "Read my sentence.",
                    "language": "en",
                    "purpose": "writing_readback"
                })
                .to_string(),
            ))
            .unwrap()
    };
    let first = app.clone().oneshot(request()).await.unwrap();
    assert_eq!(first.status(), StatusCode::OK);
    let first: serde_json::Value =
        serde_json::from_slice(&to_bytes(first.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(first["synthetic"], true);
    assert_eq!(first["cache_hit"], false);
    assert_eq!(first["purpose"], "writing_readback");

    let second = app.clone().oneshot(request()).await.unwrap();
    let second: serde_json::Value =
        serde_json::from_slice(&to_bytes(second.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(second["cache_hit"], true);

    let cleared = app
        .oneshot(
            Request::delete("/v1/speech-synthesis/cache")
                .header(AUTHORIZATION, "Bearer secret")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    let cleared: serde_json::Value =
        serde_json::from_slice(&to_bytes(cleared.into_body(), usize::MAX).await.unwrap()).unwrap();
    assert_eq!(cleared["cache_entries"], 0);
}

#[tokio::test]
async fn speech_synthesis_rejects_invalid_text_without_creating_an_asset() {
    let response = tts_app()
        .oneshot(
            Request::post("/v1/speech-synthesis")
                .header(AUTHORIZATION, "Bearer secret")
                .header(CONTENT_TYPE, "application/json")
                .body(Body::from(r#"{"text":" ","language":"en"}"#))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::BAD_REQUEST);
}
