//! Native realtime speech protocol adapters.

mod factory;
mod protocol;
mod transport;

pub use factory::NativeRealtimeAdapterFactory;
pub use protocol::{OpenAiRealtimeCodec, QwenRealtimeCodec, RealtimeProtocolCodec};
pub use transport::{OpenAiRealtimeAdapter, QwenRealtimeAdapter, RealtimeAdapterConfig};
