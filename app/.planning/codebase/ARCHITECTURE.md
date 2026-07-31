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

The repository row is optional and appears where a surface would otherwise
depend on the whole of `LocalApi`. `lib/data/repositories/lexical_repository.dart`
is the first: it names the ~30 endpoints the listening dictionary uses, takes a
non-nullable `LocalApi` by constructor and returns the same typed client models.
It is a boundary, not a second model layer — no cache, no domain types of its
own, and sequencing stays with the state that owns it.

A screen that grew its own state and I/O is split into view / view model /
repository. `VocabularyViewModel` is the worked example: it owns an immutable
`VocabularyState` in a `Store`, re-broadcasts as a `ChangeNotifier`, holds no
`BuildContext` and no localized text, and returns outcomes for anything whose
only visible result is a dialog or a SnackBar. View models live beside the other
controllers in `lib/controllers`; dependencies are wired by hand at the
composition site, as everywhere else in this app.

Playback frame/position, subtitle cursor, current word, seeking and loops stay
inside the app/player layer. Backend requests are for durable/application work,
not per-frame UI state.

The shipped app embeds the exact `api-http` and runtime files installed from
`backend.lock.json`; startup negotiation prevents incompatible use.
