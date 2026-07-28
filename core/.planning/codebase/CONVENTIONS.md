# Conventions

- Rust modules use explicit imports; production wildcard imports are guarded.
- Public types live with their concept owner; adapter details do not leak into
  domain/application public interfaces.
- HTTP routes are thin and delegate blocking/application work through the
  established executor/use-case seams.
- DTOs and schemas use explicit defaults only when backward compatibility is
  intentional.
- Jobs expose durable identity and explicit lifecycle states.
- Provider output retains provider/model/provenance metadata.
- Python scripts keep entrypoints small and deterministic logic testable.
- Release JSON is canonicalized and archives are deterministic.
- Tests use fixtures/fakes by default; live paid tests are ignored and opt-in.
- Conventional Commits, exact-minute changelog, one coherent PR.
