use application::{
    RealtimeAudioFormat, RealtimeEvent, RealtimeSessionRequest, RealtimeTurnDetection,
};
use base64::{Engine as _, engine::general_purpose::STANDARD};
use domain::RealtimeProviderError;
use std::{collections::HashMap, sync::Mutex};

pub trait RealtimeProtocolCodec: Send + Sync + 'static {
    fn adapter_kind(&self) -> &'static str;
    fn protocol_version(&self) -> &'static str;
    fn session_update(&self, request: &RealtimeSessionRequest) -> serde_json::Value;
    fn audio_append(&self, pcm: &[u8]) -> serde_json::Value {
        serde_json::json!({
            "type": "input_audio_buffer.append",
            "audio": STANDARD.encode(pcm),
        })
    }
    fn commit_turn(&self) -> serde_json::Value {
        serde_json::json!({"type": "input_audio_buffer.commit"})
    }
    fn cancel_response(&self) -> serde_json::Value {
        serde_json::json!({"type": "response.cancel"})
    }
    fn supports_manual_turns(&self) -> bool {
        true
    }
    fn decode(
        &self,
        value: &serde_json::Value,
    ) -> Result<Option<RealtimeEvent>, RealtimeProviderError>;
    fn decode_many(
        &self,
        value: &serde_json::Value,
    ) -> Result<Vec<RealtimeEvent>, RealtimeProviderError> {
        Ok(self.decode(value)?.into_iter().collect())
    }
}

fn require_openai_pcm(format: RealtimeAudioFormat) -> serde_json::Value {
    let rate = match format {
        RealtimeAudioFormat::Pcm16Mono16Khz => 16000,
        RealtimeAudioFormat::Pcm16Mono24Khz => 24000,
    };
    serde_json::json!({"type": "audio/pcm", "rate": rate})
}

fn string(value: &serde_json::Value, path: &[&str]) -> Option<String> {
    let mut current = value;
    for key in path {
        current = current.get(*key)?;
    }
    current.as_str().map(ToOwned::to_owned)
}

fn unsigned(value: &serde_json::Value, path: &[&str]) -> Option<u64> {
    let mut current = value;
    for key in path {
        current = current.get(*key)?;
    }
    current.as_u64()
}

fn provider_error(value: &serde_json::Value) -> RealtimeProviderError {
    let code = string(value, &["error", "code"])
        .or_else(|| string(value, &["error", "type"]))
        .unwrap_or_default();
    match code.as_str() {
        value if value.contains("auth") || value.contains("api_key") => RealtimeProviderError::Auth,
        value if value.contains("rate") || value.contains("quota") => {
            RealtimeProviderError::RateLimit {
                retry_after_ms: None,
            }
        }
        _ => RealtimeProviderError::Protocol {
            detail: string(value, &["error", "message"])
                .unwrap_or_else(|| "provider returned an error event".into()),
        },
    }
}

fn audio_delta(value: &serde_json::Value) -> Result<Vec<u8>, RealtimeProviderError> {
    let delta = string(value, &["delta"])
        .or_else(|| string(value, &["audio"]))
        .ok_or_else(|| RealtimeProviderError::Protocol {
            detail: "audio delta was missing".into(),
        })?;
    STANDARD
        .decode(delta)
        .map_err(|_| RealtimeProviderError::Protocol {
            detail: "audio delta was not valid base64".into(),
        })
}

#[derive(Debug, Default)]
pub struct OpenAiRealtimeCodec {
    input_transcript_previews: Mutex<HashMap<String, String>>,
}

impl RealtimeProtocolCodec for OpenAiRealtimeCodec {
    fn adapter_kind(&self) -> &'static str {
        "openai_realtime"
    }
    fn protocol_version(&self) -> &'static str {
        "realtime-ga-v1"
    }

    fn session_update(&self, request: &RealtimeSessionRequest) -> serde_json::Value {
        let input_format = require_openai_pcm(request.input_audio);
        let output_format = match request.output_audio {
            RealtimeAudioFormat::Pcm16Mono16Khz => serde_json::json!({
                "type": "audio/pcm",
                "rate": 16000,
            }),
            RealtimeAudioFormat::Pcm16Mono24Khz => serde_json::json!({
                "type": "audio/pcm",
                "rate": 24000,
            }),
        };
        serde_json::json!({
            "type": "session.update",
            "session": {
                "type": "realtime",
                "output_modalities": ["audio"],
                "instructions": request.instructions,
                "audio": {
                    "input": {
                        "format": input_format,
                        "transcription": {
                            "model": "gpt-4o-mini-transcribe",
                            "language": request.language.as_str(),
                        },
                        "turn_detection": match request.turn_detection {
                            RealtimeTurnDetection::ServerVad => serde_json::json!({"type": "server_vad"}),
                            RealtimeTurnDetection::Manual => serde_json::Value::Null,
                        }
                    },
                    "output": {
                        "format": output_format,
                        "voice": request.voice,
                    }
                }
            }
        })
    }

    fn decode(
        &self,
        value: &serde_json::Value,
    ) -> Result<Option<RealtimeEvent>, RealtimeProviderError> {
        let kind = value
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        let item_id = || string(value, &["item_id"]);
        Ok(match kind {
            "error" => return Err(provider_error(value)),
            "session.created" | "session.updated" => Some(RealtimeEvent::SessionReady {
                provider_session_id: string(value, &["session", "id"]),
            }),
            "input_audio_buffer.speech_started" => Some(RealtimeEvent::SpeechStarted {
                provider_item_id: item_id(),
                audio_start_ms: unsigned(value, &["audio_start_ms"]),
            }),
            "input_audio_buffer.speech_stopped" => Some(RealtimeEvent::SpeechStopped {
                provider_item_id: item_id(),
            }),
            "input_audio_buffer.committed" => Some(RealtimeEvent::TurnCommitted {
                provider_item_id: item_id(),
            }),
            "conversation.item.input_audio_transcription.delta" => {
                let provider_item_id = item_id();
                let key = provider_item_id.clone().unwrap_or_default();
                let delta = string(value, &["delta"]).unwrap_or_default();
                let text = {
                    let mut previews = self.input_transcript_previews.lock().map_err(|_| {
                        RealtimeProviderError::Protocol {
                            detail: "input transcript preview state was unavailable".into(),
                        }
                    })?;
                    let preview = previews.entry(key).or_default();
                    preview.push_str(&delta);
                    preview.clone()
                };
                Some(RealtimeEvent::ProviderTranscriptPreview {
                    provider_item_id,
                    text,
                })
            }
            "conversation.item.input_audio_transcription.completed" => {
                let provider_item_id = item_id();
                if let Ok(mut previews) = self.input_transcript_previews.lock() {
                    previews.remove(&provider_item_id.clone().unwrap_or_default());
                }
                Some(RealtimeEvent::ProviderTranscriptFinal {
                    provider_item_id,
                    transcript: string(value, &["transcript"]).unwrap_or_default(),
                })
            }
            "response.audio_transcript.delta" | "response.output_audio_transcript.delta" => {
                Some(RealtimeEvent::AssistantTranscriptDelta {
                    provider_item_id: item_id(),
                    delta: string(value, &["delta"]).unwrap_or_default(),
                })
            }
            "response.audio_transcript.done" | "response.output_audio_transcript.done" => {
                Some(RealtimeEvent::AssistantTranscriptFinal {
                    provider_item_id: item_id(),
                    transcript: string(value, &["transcript"]).unwrap_or_default(),
                })
            }
            "response.audio.delta" | "response.output_audio.delta" => {
                Some(RealtimeEvent::AssistantAudioDelta {
                    provider_item_id: item_id(),
                    pcm16_mono_24khz: audio_delta(value)?,
                })
            }
            "response.done" => Some(RealtimeEvent::ResponseDone {
                provider_response_id: string(value, &["response", "id"]),
            }),
            "rate_limits.updated" => None,
            _ => None,
        })
    }
}

#[derive(Debug, Clone, Copy, Default)]
pub struct QwenRealtimeCodec;

impl RealtimeProtocolCodec for QwenRealtimeCodec {
    fn adapter_kind(&self) -> &'static str {
        "qwen_omni_realtime"
    }
    fn protocol_version(&self) -> &'static str {
        "qwen-omni-realtime-v1"
    }

    fn session_update(&self, request: &RealtimeSessionRequest) -> serde_json::Value {
        serde_json::json!({
            "type": "session.update",
            "session": {
                "modalities": ["text", "audio"],
                "voice": request.voice,
                "instructions": request.instructions,
                "input_audio_format": "pcm",
                "output_audio_format": "pcm",
                "turn_detection": match request.turn_detection {
                    RealtimeTurnDetection::ServerVad => serde_json::json!({
                        "type": "semantic_vad",
                        "threshold": 0.2,
                        "silence_duration_ms": 800,
                    }),
                    RealtimeTurnDetection::Manual => serde_json::Value::Null,
                }
            }
        })
    }

    fn decode(
        &self,
        value: &serde_json::Value,
    ) -> Result<Option<RealtimeEvent>, RealtimeProviderError> {
        let kind = value
            .get("type")
            .and_then(|v| v.as_str())
            .unwrap_or_default();
        let item_id = || string(value, &["item_id"]);
        Ok(match kind {
            "error" => return Err(provider_error(value)),
            "session.created" | "session.updated" => Some(RealtimeEvent::SessionReady {
                provider_session_id: string(value, &["session", "id"]),
            }),
            "input_audio_buffer.speech_started" => Some(RealtimeEvent::SpeechStarted {
                provider_item_id: item_id(),
                audio_start_ms: unsigned(value, &["audio_start_ms"]),
            }),
            "input_audio_buffer.speech_stopped" => Some(RealtimeEvent::SpeechStopped {
                provider_item_id: item_id(),
            }),
            "input_audio_buffer.committed" => Some(RealtimeEvent::TurnCommitted {
                provider_item_id: item_id(),
            }),
            "conversation.item.input_audio_transcription.delta" => {
                Some(RealtimeEvent::ProviderTranscriptPreview {
                    provider_item_id: item_id(),
                    // Qwen's preview is the complete confirmed prefix plus mutable stash,
                    // not an append-only OpenAI-style delta.
                    text: format!(
                        "{}{}",
                        string(value, &["text"]).unwrap_or_default(),
                        string(value, &["stash"]).unwrap_or_default()
                    ),
                })
            }
            "conversation.item.input_audio_transcription.completed" => {
                Some(RealtimeEvent::ProviderTranscriptFinal {
                    provider_item_id: item_id(),
                    transcript: string(value, &["transcript"]).unwrap_or_default(),
                })
            }
            "response.audio_transcript.delta" => Some(RealtimeEvent::AssistantTranscriptDelta {
                provider_item_id: item_id(),
                delta: string(value, &["delta"]).unwrap_or_default(),
            }),
            "response.audio_transcript.done" => Some(RealtimeEvent::AssistantTranscriptFinal {
                provider_item_id: item_id(),
                transcript: string(value, &["transcript"]).unwrap_or_default(),
            }),
            "response.audio.delta" => Some(RealtimeEvent::AssistantAudioDelta {
                provider_item_id: item_id(),
                pcm16_mono_24khz: audio_delta(value)?,
            }),
            "response.done" => Some(RealtimeEvent::ResponseDone {
                provider_response_id: string(value, &["response", "id"]),
            }),
            _ => None,
        })
    }
}

#[derive(Debug, Default)]
pub struct LocalCascadeRealtimeCodec {
    assistant_transcripts: Mutex<HashMap<String, (Option<String>, String)>>,
}

impl RealtimeProtocolCodec for LocalCascadeRealtimeCodec {
    fn adapter_kind(&self) -> &'static str {
        "local_cascade_realtime"
    }

    fn protocol_version(&self) -> &'static str {
        "hf-speech-to-speech-ora-cc37fe84fe08710e888ecc2eb5b468e41df74bca"
    }

    fn session_update(&self, request: &RealtimeSessionRequest) -> serde_json::Value {
        let mut update = OpenAiRealtimeCodec::default().session_update(request);
        if let Some(turn_detection) = update.pointer_mut("/session/audio/input/turn_detection")
            && !turn_detection.is_null()
        {
            turn_detection["interrupt_response"] = serde_json::Value::Bool(true);
        }
        update
    }

    fn supports_manual_turns(&self) -> bool {
        false
    }

    fn decode(
        &self,
        value: &serde_json::Value,
    ) -> Result<Option<RealtimeEvent>, RealtimeProviderError> {
        Ok(self.decode_many(value)?.into_iter().next())
    }

    fn decode_many(
        &self,
        value: &serde_json::Value,
    ) -> Result<Vec<RealtimeEvent>, RealtimeProviderError> {
        let kind = value
            .get("type")
            .and_then(serde_json::Value::as_str)
            .unwrap_or_default();
        let item_id = || string(value, &["item_id"]);
        match kind {
            // HF progressive transcription sends the complete current
            // snapshot in `delta`, rather than an append-only fragment.
            "conversation.item.input_audio_transcription.delta" => {
                Ok(vec![RealtimeEvent::ProviderTranscriptPreview {
                    provider_item_id: item_id(),
                    text: string(value, &["delta"]).unwrap_or_default(),
                }])
            }
            // HF emits one transcript "done" event for every streamed LLM
            // text chunk. Preserve those as deltas and publish exactly one
            // final transcript immediately before response.done.
            "response.output_audio_transcript.done" => {
                let response_id = string(value, &["response_id"]).unwrap_or_default();
                let chunk = string(value, &["transcript"]).unwrap_or_default();
                let provider_item_id = item_id();
                let mut transcripts = self.assistant_transcripts.lock().map_err(|_| {
                    RealtimeProviderError::Protocol {
                        detail: "local assistant transcript state was unavailable".into(),
                    }
                })?;
                let (_, text) = transcripts
                    .entry(response_id)
                    .or_insert_with(|| (provider_item_id.clone(), String::new()));
                text.push_str(&chunk);
                Ok(vec![RealtimeEvent::AssistantTranscriptDelta {
                    provider_item_id,
                    delta: chunk,
                }])
            }
            "response.done" => {
                let response_id = string(value, &["response", "id"]).unwrap_or_default();
                let completed = self
                    .assistant_transcripts
                    .lock()
                    .map_err(|_| RealtimeProviderError::Protocol {
                        detail: "local assistant transcript state was unavailable".into(),
                    })?
                    .remove(&response_id);
                let mut events = Vec::with_capacity(2);
                if let Some((provider_item_id, transcript)) = completed {
                    events.push(RealtimeEvent::AssistantTranscriptFinal {
                        provider_item_id,
                        transcript,
                    });
                }
                events.push(RealtimeEvent::ResponseDone {
                    provider_response_id: (!response_id.is_empty()).then_some(response_id),
                });
                Ok(events)
            }
            _ => Ok(OpenAiRealtimeCodec::default()
                .decode(value)?
                .into_iter()
                .collect()),
        }
    }
}
