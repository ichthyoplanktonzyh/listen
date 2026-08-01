# Architecture

```text
macOS / Flutter shell
        |
   widgets + screens
        |
controllers / view models / coordinators / state
        |
   repositories (per-surface data boundaries)
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

Every presentation feature reaches backend data through a narrow repository.
Concrete `LocalApi`-backed implementations are created only in
`lib/main.dart`, the composition root; screens, widgets, controllers and flow
helpers receive repository interfaces. Repositories map transport failures to
typed failures and return typed client models. They are boundaries, not a
second model layer: UI sequencing remains in its view model/controller.

A screen that grew its own state and I/O is split into view / view model /
repository. `VocabularyViewModel` is the worked example: it owns an immutable
`VocabularyState` in a `Store`, re-broadcasts as a `ChangeNotifier`, holds no
`BuildContext` and no localized text, and returns outcomes for anything whose
only visible result is a dialog or a SnackBar. View models live beside the other
controllers in `lib/controllers`; dependencies are wired by hand at the
composition root. Platform file access and pickers are likewise hidden behind
injected services in `lib/services`.

`test/architecture_layering_test.dart` enforces the dependency direction. In
particular, presentation cannot import `LocalApi`, `dart:io`, or
`file_selector`, and it cannot construct concrete local repositories.

Playback frame/position, subtitle cursor, current word, seeking and loops stay
inside the app/player layer. Backend requests are for durable/application work,
not per-frame UI state.

The shipped app embeds the exact `api-http` and runtime files installed from
`backend.lock.json`; startup negotiation prevents incompatible use.
