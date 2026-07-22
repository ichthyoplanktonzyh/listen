# LLPlayerNext Learning Context

LLPlayerNext turns real content into bounded learning activities and durable learning history. This glossary
names the content and task boundaries that must remain consistent across listening, reading, speaking and writing.

## Content And Task Language

**Content Document**:
A complete imported media/subtitle work that can be browsed, played or read as a whole.
_Avoid_: Task input, source clip

**Content Selection**:
An explicit contiguous part of a Content Document chosen as the source for one learning activity; it has visible
text and time boundaries and may contain one sentence, several sentences or a passage.
_Avoid_: Current content, whatever is playing, implicit context

**Playback Context**:
The document, cursor and playback state currently open in the player. It helps create a Content Selection but is
not itself a task input.
_Avoid_: Task source

**Task Prompt**:
The immutable instructions and source snapshot presented for one activity, derived from an explicit Content
Selection or from a user-owned asset.
_Avoid_: Current sentence, live player state

**Learning Attempt**:
One completed or explicitly abandoned response to one Task Prompt. Its source, assistance and channel are facts
about that attempt, not proof of capability in another channel.
_Avoid_: Capability, score

## Availability Language

**Unavailable State**:
A condition where the exact requested activity cannot be performed because a required resource or permission is
absent. It explains the cause and a concrete recovery action without pretending the activity occurred.
_Avoid_: Silent fallback, generic error

**Fallback**:
An alternate path that preserves the same user goal and authority semantics when the preferred implementation is
unavailable. If the medium or learning goal changes, it is not a fallback.
_Avoid_: Any degraded screen, substitute task

**Source Snapshot**:
An immutable historical explanation of what a learning fact referred to. It preserves provenance after source
loss but does not make an audio, speaking or navigation activity available.
_Avoid_: Playable source, replacement media
