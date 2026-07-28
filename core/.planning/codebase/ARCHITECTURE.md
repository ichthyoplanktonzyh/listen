# Architecture

## System Shape

```text
contracts / HTTP / events
          |
       api-http
          |
      application
       /   |    \
 domain  repositories  provider traits
          |              |
 persistence-sqlite   *-provider adapters

scripts/timeline-production and evaluation tools
          |
 versioned LLTimeline/resource artifacts
```

`domain` owns stable concepts. `application` owns use cases and ports.
`api-http` adapts loopback HTTP/SSE/WebSocket requests. Persistence and provider
crates implement ports. Python tooling produces/evaluates resources but is not
embedded in the lightweight consumer runtime.

## Runtime Boundary

`api-http` binds loopback on a random port and emits a structured startup
handshake containing address, bearer token, API version, contract version, and
runtime version. The app launches the pinned binary and rejects incompatible
handshakes before normal requests.

## Contract Boundary

OpenAPI and resource/event schemas are core-owned. Route parity validates
method+path coverage. Contract and runtime archives include manifests,
core commit, versions, and hashes. `listen-app` consumes releases through its
lock file; no compile-time source dependency exists.
