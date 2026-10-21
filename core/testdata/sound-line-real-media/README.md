# Sound-line media verifier inputs

`manifest.jsonl` describes existing external-media cases for
`scripts/verify-sound-line-real-media.py`. `cases/*.md` are the manifest's
`qa_notes` inputs: the verifier checks that each file exists. Keep their data
and paths intact. They are fixed observations/templates, not current project
instructions or evidence of present acceptance.

The manifest records case identity, source/license information, local media
paths/hashes, timeline paths, target phenomena, and QA-note paths. It may name
local-only resources absent on another machine. Media bodies, restricted
corpora, and generated full transcripts are not redistributed here.

From `core/`:

```sh
python3 scripts/verify-sound-line-real-media.py \
  --manifest testdata/sound-line-real-media/manifest.jsonl --json
```

The verifier's `--help` documents stricter local-file and timeline-readiness
checks. Missing external data is not permission to download or regenerate it
as part of an ordinary test run. The headless generation runner may invoke
models and requires separate authorization for live work.
