//! Native realtime speech protocol adapters.

mod protocol;
mod transport;

pub use protocol::{OpenAiRealtimeCodec, QwenRealtimeCodec, RealtimeProtocolCodec};
pub use transport::{OpenAiRealtimeAdapter, QwenRealtimeAdapter, RealtimeAdapterConfig};
