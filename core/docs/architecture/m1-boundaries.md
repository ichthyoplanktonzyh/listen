# M1 Workspace Boundaries

Dependency direction:

```text
domain <- application <- persistence-sqlite
                    <- api-http
api-events
```

## Ownership

| Crate | Owns | Must not own |
|---|---|---|
| `domain` | Stable IDs, time/language values, domain records and enums | SQLite, HTTP, Flutter, or player-library types |
| `application` | Transport-independent use cases and repository ports | SQL statements, HTTP handlers, or player control |
| `persistence-sqlite` | Migrations and repository implementations | Business decisions or transport behavior |
| `api-http` | Loopback process lifecycle, authentication, request mapping, unified HTTP errors | Domain rules or high-frequency playback |
| `api-events` | Versioned event names and envelope | Event transport or domain decisions |

Desktop player rendering, position events, local subtitle cursor, seeking, and
looping remain in the desktop client and do not enter these crates.

## Dependency Rule

`domain` has no workspace dependencies. `application` depends only on `domain`.
Adapters depend inward on application ports. No inward crate may import an
adapter. Cargo workspace review and CI compilation enforce this direction.

## Transport Boundary

`AppServices` is callable directly in process and does not know whether its
caller is HTTP, Flutter FFI, tests, or a future mobile binding. HTTP handlers
only deserialize requests, call one application service, and serialize a
result. Playback control is deliberately absent from the local API.

## Platform Boundary

The MVP ships on macOS Apple Silicon, but no domain or application type exposes
macOS, Flutter, media_kit, or libmpv types. Future Windows, Linux, Android, and
iOS adapters reuse these inward contracts.
