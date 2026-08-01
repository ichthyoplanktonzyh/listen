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

`lib/main.dart` is the application composition root. Route helpers in
`lib/widgets/flows` are the route-scoped composition boundary: they receive
factories or already-constructed dependencies, own transient notifiers, and
dispose them when the route closes. Reusable widgets/screens never construct
application ViewModels, Controllers, Repositories, or Services. They render an
immutable state snapshot and emit intent. Controllers/ViewModels own lifecycle,
orchestration, stale-request generation guards, focus, and cancellation.

Every presentation feature reaches backend data through a narrow repository.
Concrete `LocalApi`-backed implementations are created only at the composition
root; screens and widgets receive ViewModels/Controllers, while those logic
objects receive repository interfaces. Repositories map transport failures to
typed failures and return typed client/domain views. UI sequencing remains in
its ViewModel/Controller.

A screen that grew its own state and I/O is split into view / view model /
repository. `VocabularyViewModel` is the worked example: it owns an immutable
`VocabularyState` in a `Store`, re-broadcasts as a `ChangeNotifier`, holds no
`BuildContext` and no localized text, and returns outcomes for anything whose
only visible result is a dialog or a SnackBar. View models live beside the other
controllers in `lib/controllers`; dependencies are wired by hand at the
composition root. Platform file access, pickers, environment reads, diagnostic
exports, and desktop bootstrap work are hidden behind injected services in
`lib/services`. Rendering-only plugin adapters are isolated in narrow widgets
such as `DesktopDropSurface`; they expose plain values/callbacks to the shell.

`test/architecture_layering_test.dart` enforces the dependency direction. In
particular, presentation cannot import repositories, `LocalApi`, `dart:io`, or
file/platform I/O plugins; reusable Views cannot construct application
ViewModels/Controllers; and immutable notifier state must defensively wrap
collection fields.

Playback frame/position, subtitle cursor, current word, seeking and loops stay
inside the app/player layer. Backend requests are for durable/application work,
not per-frame UI state.

The shipped app embeds the exact `api-http` and runtime files installed from
`backend.lock.json`; startup negotiation prevents incompatible use.
