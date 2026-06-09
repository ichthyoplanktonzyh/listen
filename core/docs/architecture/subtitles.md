# Subtitle Core Contract

The `subtitle-core` crate owns parsing, tokenization, normalized import, and
local timeline queries. It depends only on `domain`; it does not depend on
SQLite, HTTP, Flutter, or a player library.

## Import And Identity

- Supported MVP formats are SRT and basic WebVTT.
- Input accepts UTF-8, UTF-8 BOM, and BOM-marked UTF-16 LE/BE.
- A track fingerprint is SHA-256 of the original file bytes.
- Track identity combines media ID and content fingerprint. Importing the same
  file for the same media is idempotent; changing file content creates a new
  track; the same subtitle file can be attached to different media.
- Sentence identity combines track ID, chronological index, timing, and display
  text.
- Original cue text and normalized display text are both retained.

Parse errors identify the source line when possible. WebVTT tags are stripped
without executing or exposing markup; unsupported NOTE and STYLE blocks are
ignored.

## Tokenization

English tokenization emits `word`, `whitespace`, `punctuation`, and `other`.
Tokens retain original text and character ranges. Rejoining all token text must
exactly reproduce `display_text`.

Apostrophes and hyphens remain inside a word only when surrounded by
alphanumeric characters. Unicode letters and numbers are words. The initial
lemma strategy is a documented safe fallback: trim and lowercase the original
word form. It is intentionally not a linguistic stemmer.

## Timeline Rules

The complete timeline is returned to the client and queried locally:

- Cue start is inclusive and cue end is exclusive.
- Gaps return no current cue.
- During overlap, the active cue with the latest start wins.
- Previous and next follow normalized chronological order.
- Positive offset displays and seeks subtitles later relative to media time;
  negative offset displays and seeks them earlier.
- Offset is applied consistently to current-cue lookup, seeking, and loop
  boundaries.

Timeline lookup uses binary partitioning on chronological cue starts and needs
no high-frequency HTTP requests.
