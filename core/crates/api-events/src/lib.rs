use serde::{Deserialize, Serialize};
use serde_json::Value;

pub const EVENT_SCHEMA_VERSION: u16 = 1;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "kebab-case")]
pub enum EventName {
    ServiceStarted,
    ServiceStopping,
    WordProfileChanged,
    WordObservationCreated,
    WordObservationCleared,
    VocabularyAssetsImported,
    MediaAvailabilityChanged,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EventEnvelope {
    pub version: u16,
    pub event: EventName,
    pub payload: Value,
}

impl EventEnvelope {
    pub fn v1(event: EventName, payload: Value) -> Self {
        Self {
            version: EVENT_SCHEMA_VERSION,
            event,
            payload,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn creates_versioned_events() {
        let event = EventEnvelope::v1(
            EventName::WordProfileChanged,
            serde_json::json!({"word": "hello"}),
        );
        assert_eq!(event.version, 1);
    }

    #[test]
    fn event_contract_schema_is_present() {
        let schema = include_str!("../../../contracts/events/v1.schema.json");
        assert!(schema.contains("word-profile-changed"));
    }
}
