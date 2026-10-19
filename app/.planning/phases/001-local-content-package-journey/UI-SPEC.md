# UI specification

The journey is a quiet, single-column instrument opened from Subtitle
resources. Its two primary inputs are visually adjacent but mutually exclusive:
import an existing package or generate one for the open media.

Lifecycle status occupies one stable region so progress does not move the
actions. Preparing and generating states expose Cancel once a generator process
is active. Retry appears only when an original intent remains and the failure is
retryable, the package mismatched the media, or a generation was cancelled;
dismissing the file picker does not create a retry action.

The completed view separates:

- immutable archive digest from Gen and manifest digest from Core, labelled as
  distinct facts;
- imported/preserved resource disposition and local IDs;
- warnings;
- publisher, review, license, and source provenance.

Candidate selection/activation is separate after the receipt. The imported
subtitle track can be selected for the App learning experience; each consumed
`word_timeline` local ID can be explicitly activated through Core's existing
active-slot operation. Preserved or unsupported resources expose no activation
button. Neither operation shares the import label or runs automatically. The layout scrolls at small
window heights, uses existing theme tokens, has semantic labels for progress
and actions, and does not rely on motion to communicate state.
