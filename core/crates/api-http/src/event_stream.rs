use std::convert::Infallible;

use api_events::EventEnvelope;
use axum::extract::State;
use axum::response::sse::{Event, KeepAlive, Sse};
use tokio::sync::broadcast;

use crate::ApiState;

/// Streams best-effort notifications for state that remains authoritative
/// behind the corresponding read endpoints.
///
/// A broadcast receiver can lag when the desktop client is briefly unable to
/// consume events. Lag is not server shutdown: skip the lost notifications and
/// continue from the oldest retained envelope. Callers already refresh the
/// authoritative job/resource state after reconnecting or receiving a later
/// change notification.
pub(crate) async fn events(
    State(state): State<ApiState>,
) -> Sse<impl futures_core::Stream<Item = Result<Event, Infallible>>> {
    let mut receiver = state.infrastructure.events.subscribe();
    let stream = async_stream::stream! {
        while let Some(envelope) = next_envelope(&mut receiver).await {
            yield Ok(Event::default().json_data(envelope).expect("event envelope serializes"));
        }
    };
    Sse::new(stream).keep_alive(KeepAlive::default())
}

async fn next_envelope(receiver: &mut broadcast::Receiver<EventEnvelope>) -> Option<EventEnvelope> {
    loop {
        match receiver.recv().await {
            Ok(envelope) => return Some(envelope),
            Err(broadcast::error::RecvError::Lagged(skipped)) => {
                tracing::warn!(
                    event = "api.events.lagged",
                    skipped,
                    "local event receiver lagged; continuing with retained notifications"
                );
            }
            Err(broadcast::error::RecvError::Closed) => return None,
        }
    }
}

#[cfg(test)]
mod tests {
    use api_events::EventName;

    use super::*;

    fn envelope(sequence: u64) -> EventEnvelope {
        EventEnvelope::v1(
            EventName::LexicalEntryChanged,
            serde_json::json!({"sequence": sequence}),
        )
    }

    #[tokio::test]
    async fn lag_skips_lost_notifications_and_continues_with_retained_event() {
        let (sender, mut receiver) = broadcast::channel(2);
        sender.send(envelope(1)).unwrap();
        sender.send(envelope(2)).unwrap();
        sender.send(envelope(3)).unwrap();

        let retained = next_envelope(&mut receiver).await.unwrap();

        assert_eq!(retained.payload["sequence"], 2);
        assert_eq!(
            next_envelope(&mut receiver).await.unwrap().payload["sequence"],
            3
        );
    }

    #[tokio::test]
    async fn closed_channel_ends_delivery() {
        let (sender, mut receiver) = broadcast::channel(2);
        drop(sender);

        assert!(next_envelope(&mut receiver).await.is_none());
    }
}
