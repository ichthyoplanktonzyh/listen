# Architecture

```text
macOS / Flutter shell
        |
   widgets + screens
        |
controllers / coordinators / state
        |
typed models + LocalApi services
        |
loopback HTTP/SSE/WebSocket
        |
pinned listen-core api-http runtime
```

`lib/main.dart` composes the app. Widgets/screens render explicit state and emit
intent. Controllers/coordinators own lifecycle, orchestration, generation
guards, focus and cancellation. Services own I/O and map wire payloads into
typed client models. `backend_event_coordinator` connects event envelopes to
client state.

Playback frame/position, subtitle cursor, current word, seeking and loops stay
inside the app/player layer. Backend requests are for durable/application work,
not per-frame UI state.

The shipped app embeds the exact `api-http` and runtime files installed from
`backend.lock.json`; startup negotiation prevents incompatible use.
