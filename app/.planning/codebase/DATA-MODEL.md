# Client Data Model

Client models under `lib/models` are typed views of:

- media/subtitle/timeline resources;
- lexical entries, capability profiles and diagnosis;
- practice, review, reading, writing and speaking tasks;
- realtime conversation and turn assembly;
- production corpus, projection review and personal expression;
- provider/capability readiness and backend events.

Rules:

- wire compatibility is explicit in parsers and focused fixture tests;
- backend IDs/provenance remain intact through UI state;
- client-only display state does not mutate backend facts;
- source snapshot, provider caption, learner transcript, heuristic and
  adjudicated output remain distinguishable;
- adding a backend field does not imply it must be displayed or treated as
  authoritative.
