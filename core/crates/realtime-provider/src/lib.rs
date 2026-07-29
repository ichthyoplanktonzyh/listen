//! Native realtime speech protocol adapters.

mod factory;
mod protocol;
mod transport;

pub use factory::NativeRealtimeAdapterFactory;
pub use protocol::{
    LocalCascadeRealtimeCodec, OpenAiRealtimeCodec, QwenRealtimeCodec, RealtimeProtocolCodec,
};
pub use transport::{
    LocalCascadeRealtimeAdapter, OpenAiRealtimeAdapter, QwenRealtimeAdapter, RealtimeAdapterConfig,
};
