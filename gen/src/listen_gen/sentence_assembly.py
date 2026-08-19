"""Deterministic assembly of timed transcription/subtitle fragments.

ASR and subtitle providers expose *timed fragments*.  A fragment is a useful
media coordinate, but it is not a reliable linguistic sentence boundary.  The
production pipeline therefore normalizes fragments here, before creating a
Structured Reading.  This module deliberately has no package or provider
dependencies: its result is the single sentence identity authority consumed
by the reading, anchor, subtitle, word-timeline, and rich-stage projections.

The implementation is intentionally conservative:

* fragments are joined only while the accumulated text has no real terminal
  boundary;
* a fragment containing multiple sentences is split only when word timings
  make each split precisely addressable;
* subtitle fragments (which have no word timings) are never split internally;
* deterministic bounds flush an overlong candidate instead of inventing a
  sentence boundary or timing;
* all provider word times remain absolute and unchanged.  Only their
  sentence-local character coordinates are remapped.
"""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, replace
from typing import Any, Iterable, Sequence

from .asr import AsrSegment, AsrTranscript, AsrWord


ASSEMBLY_ALGORITHM_ID = "listen-gen.timed-sentence-assembly"
ASSEMBLY_ALGORITHM_VERSION = "2"

# These are intentionally explicit and part of the assembly identity.  They
# prevent an ASR provider that omits punctuation from joining an unbounded
# amount of speech while still allowing ordinary pauses between subtitle/ASR
# fragments in one sentence.
MAX_ASSEMBLED_WORDS = 80
MAX_ASSEMBLED_CHARS = 640
MAX_ASSEMBLED_DURATION_MS = 30_000
MAX_INTER_FRAGMENT_GAP_MS = 4_000
MAX_SOURCE_FRAGMENTS = 8

_ASSEMBLY_CONFIG = {
    "algorithm": ASSEMBLY_ALGORITHM_ID,
    "version": ASSEMBLY_ALGORITHM_VERSION,
    "max_assembled_words": MAX_ASSEMBLED_WORDS,
    "max_assembled_chars": MAX_ASSEMBLED_CHARS,
    "max_assembled_duration_ms": MAX_ASSEMBLED_DURATION_MS,
    "max_inter_fragment_gap_ms": MAX_INTER_FRAGMENT_GAP_MS,
    "max_source_fragments": MAX_SOURCE_FRAGMENTS,
    "join_separator": " ",
    "domain_continuation_join_separator": "",
    "sentence_boundary_policy": (
        "terminal-punctuation-with-abbreviation-url-decimal-and-"
        "cross-fragment-domain-continuation-guards"
    ),
    "split_policy": "word-timing-only",
}
ASSEMBLY_CONFIG_SHA256 = "sha256:" + hashlib.sha256(
    json.dumps(
        _ASSEMBLY_CONFIG,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
).hexdigest()

_ABBREVIATIONS = frozenset(
    {
        "mr",
        "mrs",
        "ms",
        "dr",
        "prof",
        "rev",
        "gen",
        "sen",
        "rep",
        "st",
        "lt",
        "col",
        "sgt",
        "adm",
        "vs",
        "etc",
        "fig",
        "eq",
        "inc",
        "jr",
        "sr",
        "jan",
        "feb",
        "mar",
        "apr",
        "jun",
        "jul",
        "aug",
        "sep",
        "sept",
        "oct",
        "nov",
        "dec",
    }
)
_CLOSERS = frozenset('"\'\u201d\u2019)]}»）】》')
_TERMINAL_CHARS = frozenset(".!?\u3002\uff01\uff1f\u2026")
_WORD_RE = re.compile(r"\w+(?:['\u2019]\w+)*", re.UNICODE)
_DOMAIN_TLDS = frozenset(
    {
        "com",
        "org",
        "net",
        "edu",
        "gov",
        "mil",
        "int",
        "info",
        "biz",
        "name",
        "pro",
        "me",
        "tv",
        "io",
        "ai",
        "app",
        "dev",
        "co",
        "uk",
        "us",
        "ca",
        "au",
        "de",
        "fr",
        "es",
        "it",
        "nl",
        "be",
        "ch",
        "cn",
        "jp",
        "kr",
        "in",
        "xyz",
        "online",
        "site",
        "tech",
    }
)


@dataclass(frozen=True)
class TimedWord:
    """A source word with a character span relative to one fragment."""

    start_char: int
    end_char: int
    start_ms: int
    end_ms: int
    confidence: float | None
    timing_source: str


@dataclass(frozen=True)
class TimedFragment:
    """Provider-neutral timed text fragment used by the assembly core."""

    start_ms: int
    end_ms: int
    text: str
    words: tuple[TimedWord, ...] = ()
    source_index: int = 0
    # False means the provider supplied words, but at least one could not be
    # proven to map into the display text.  This is intentionally carried
    # through assembly so one bad source fragment can invalidate the entire
    # ASR-word fallback atomically.
    word_mapping_complete: bool = True


@dataclass(frozen=True)
class AssembledWord:
    """A timed word remapped to an assembled sentence's local text."""

    start_char: int
    end_char: int
    start_ms: int
    end_ms: int
    confidence: float | None
    timing_source: str
    source_fragment_index: int


@dataclass(frozen=True)
class AssembledSentence:
    """One complete timed sentence and its exact source word mappings."""

    index: int
    start_ms: int
    end_ms: int
    text: str
    display_text: str
    words: tuple[AssembledWord, ...]
    source_fragment_indices: tuple[int, ...]

    def as_asr_segment(self) -> AsrSegment:
        """Project the sentence to the existing provider-neutral ASR type."""
        return AsrSegment(
            start_ms=self.start_ms,
            end_ms=self.end_ms,
            text=self.text,
            display_text=self.display_text,
            words=tuple(
                AsrWord(
                    start_char=word.start_char,
                    end_char=word.end_char,
                    start_ms=word.start_ms,
                    end_ms=word.end_ms,
                    confidence=word.confidence,
                    timing_source=word.timing_source,
                )
                for word in self.words
            ),
        )


@dataclass(frozen=True)
class _Piece:
    """A split-able fragment candidate before cross-fragment joining."""

    start_ms: int
    end_ms: int
    text: str
    words: tuple[TimedWord, ...]
    source_fragment_indices: tuple[int, ...]


def assembly_config_sha256(provider_config_sha256: str | None = None) -> str:
    """Return the reproducible identity for provider output plus assembly.

    ``provider_config_sha256`` is treated as an opaque identity; it is never
    parsed or emitted as a path.  The assembly algorithm/config is always part
    of the resulting identity, including on subtitle paths with no provider.
    """
    payload = {
        "assembly": ASSEMBLY_CONFIG_SHA256,
        "provider_config_sha256": provider_config_sha256,
    }
    return "sha256:" + hashlib.sha256(
        json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()


def _normal_text(value: str) -> str:
    # Subtitle parsing already collapses line wrapping.  ASR providers can
    # still leave edge whitespace; removing only that whitespace keeps all
    # meaningful internal characters and makes joining deterministic.
    return value.strip()


def _word_count(text: str) -> int:
    return len(_WORD_RE.findall(text))


def _period_is_terminal(text: str, period_index: int) -> bool:
    """Whether a period is a sentence boundary, not an abbreviation/decimal."""
    if period_index + 1 < len(text):
        next_character = text[period_index + 1]
        if next_character not in _CLOSERS and not next_character.isspace():
            # A dot in a URL, e-mail address, decimal, or abbreviation inside
            # a token is never a boundary.
            return False
    prefix = text[: period_index + 1]
    without_current = prefix[:-1]
    # A decimal point has digits on both sides.  A final period after a
    # decimal ("The value is 3.14.") remains a real boundary and is handled
    # by the following period, not this one.
    if (
        period_index > 0
        and period_index + 1 < len(text)
        and text[period_index - 1].isdigit()
        and text[period_index + 1].isdigit()
    ):
        return False
    # Dotted initialisms (e.g. e.g., i.e., U.S.) are not sentence ends when
    # another lexical token follows.  This guard also handles the final dot
    # in a dotted initialism at the end of a fragment.
    if re.search(r"(?:[A-Za-z]\.){2,}$", prefix):
        return False
    match = re.search(r"(?:^|[\s(\[{])([A-Za-z]{1,8})$", without_current)
    if match and match.group(1).casefold() in _ABBREVIATIONS:
        return False
    # A single capital initial followed by a period is conventionally an
    # abbreviation, not a reliable boundary.
    if re.search(r"(?:^|[\s(\[{])[A-Z]$", without_current):
        return False
    return True


def _boundary_end(text: str, punctuation_index: int) -> int:
    """Include paired closing punctuation in a sentence's text span."""
    end = punctuation_index + 1
    while end < len(text) and text[end] in _CLOSERS:
        end += 1
    return end


def _sentence_spans(text: str) -> tuple[tuple[int, int], ...]:
    """Find conservative sentence spans in one fragment."""
    bounds: list[tuple[int, int]] = []
    start = 0
    index = 0
    while index < len(text):
        character = text[index]
        terminal = character in _TERMINAL_CHARS
        if character == ".":
            terminal = _period_is_terminal(text, index)
        if terminal:
            end = _boundary_end(text, index)
            # Require whitespace or end after the terminal punctuation.  This
            # prevents a period in a URL/email or an ellipsis inside a token
            # from splitting a sentence.
            # CJK sentence terminators conventionally do not require a
            # following space ("你好。世界。").  Western terminal marks do:
            # an adjacent lexical character is otherwise likely part of a
            # URL/token rather than a boundary.
            separator_is_valid = (
                end == len(text)
                or text[end].isspace()
                or character in "\u3002\uff01\uff1f"
            )
            if separator_is_valid:
                if text[start:end].strip():
                    bounds.append((start, end))
                    # Whitespace after terminal punctuation is a separator,
                    # not part of the next sentence.  Consume it before
                    # establishing the next local character origin so word
                    # spans remain exact and sentence text stays clean.
                    start = end
                    while start < len(text) and text[start].isspace():
                        start += 1
                index = start
                continue
        index += 1
    if text[start:].strip():
        bounds.append((start, len(text)))
    if not bounds and text.strip():
        return ((0, len(text)),)
    return tuple(bounds)


def _remap_word_to_display(
    source_text: str,
    display_text: str,
    word: TimedWord,
) -> TimedWord | None:
    """Map a source word span to the text used by the reading.

    Provider contracts normally make ``text`` and ``display_text`` equal.  A
    trim-only difference is mapped exactly; for a richer display rewrite we
    search the exact source lexeme in order.  If that cannot be proven, the
    timing is omitted rather than guessed (the rich chain then abstains).
    """
    if source_text == display_text:
        return word
    leading = len(source_text) - len(source_text.lstrip())
    trimmed_source = source_text.strip()
    if trimmed_source == display_text:
        start = word.start_char - leading
        end = word.end_char - leading
        if 0 <= start < end <= len(display_text):
            return replace(word, start_char=start, end_char=end)
    lexeme = source_text[word.start_char : word.end_char]
    search_from = max(0, word.start_char - leading - 2)
    candidate = display_text.find(lexeme, search_from)
    if candidate >= 0:
        return replace(word, start_char=candidate, end_char=candidate + len(lexeme))
    return None


def _fragment_from_provider(value: Any, index: int) -> TimedFragment:
    text = getattr(value, "text", None)
    if not isinstance(text, str) or not text.strip():
        raise ValueError("timed fragment text must be non-empty")
    start_ms = getattr(value, "start_ms", None)
    end_ms = getattr(value, "end_ms", None)
    if not isinstance(start_ms, int) or not isinstance(end_ms, int) or end_ms <= start_ms:
        raise ValueError("timed fragment window must be positive")
    display_text = getattr(value, "display_text", text)
    if not isinstance(display_text, str) or not display_text.strip():
        display_text = text
    source_text = text
    normalized_text = _normal_text(display_text)
    source_words: list[TimedWord] = []
    word_mapping_complete = True
    for raw_word in tuple(getattr(value, "words", ()) or ()):
        source_word = TimedWord(
            start_char=int(raw_word.start_char),
            end_char=int(raw_word.end_char),
            start_ms=int(raw_word.start_ms),
            end_ms=int(raw_word.end_ms),
            confidence=raw_word.confidence,
            timing_source=raw_word.timing_source,
        )
        mapped = _remap_word_to_display(source_text, normalized_text, source_word)
        if mapped is not None:
            source_words.append(mapped)
        else:
            word_mapping_complete = False
    return TimedFragment(
        start_ms=start_ms,
        end_ms=end_ms,
        text=normalized_text,
        words=tuple(source_words) if word_mapping_complete else (),
        source_index=index,
        word_mapping_complete=word_mapping_complete,
    )


def _split_fragment(fragment: TimedFragment) -> tuple[_Piece, ...]:
    spans = _sentence_spans(fragment.text)
    if len(spans) <= 1 or not fragment.words:
        # A subtitle block has no word evidence and therefore cannot be split;
        # an ASR segment with no words follows the same honest policy.
        return (
            _Piece(
                fragment.start_ms,
                fragment.end_ms,
                fragment.text,
                fragment.words,
                (fragment.source_index,),
            ),
        )

    # A sentence boundary is only precise when the lexical token immediately
    # before and after that boundary both have real provider timings.  Interior
    # words may be untimed; the boundary evidence is the minimum proof needed
    # to create two distinct sentence windows without guessing.
    lexical_spans = tuple(
        tuple((match.start(), match.end()) for match in _WORD_RE.finditer(fragment.text, start, end))
        for start, end in spans
    )
    if any(not piece_spans for piece_spans in lexical_spans):
        return (
            _Piece(
                fragment.start_ms,
                fragment.end_ms,
                fragment.text,
                fragment.words,
                (fragment.source_index,),
            ),
        )

    def boundary_word(
        token_span: tuple[int, int], piece_span: tuple[int, int]
    ) -> TimedWord | None:
        token_start, token_end = token_span
        piece_start, piece_end = piece_span
        for word in fragment.words:
            if (
                piece_start <= word.start_char
                and word.end_char <= piece_end
                and word.start_char <= token_start
                and word.end_char >= token_end
                and word.end_ms > word.start_ms
            ):
                return word
        return None

    boundary_words: list[tuple[TimedWord, TimedWord]] = []
    for boundary_index in range(len(spans) - 1):
        previous = boundary_word(
            lexical_spans[boundary_index][-1], spans[boundary_index]
        )
        following = boundary_word(
            lexical_spans[boundary_index + 1][0], spans[boundary_index + 1]
        )
        if previous is None or following is None:
            return (
                _Piece(
                    fragment.start_ms,
                    fragment.end_ms,
                    fragment.text,
                    fragment.words,
                    (fragment.source_index,),
                ),
            )
        boundary_words.append((previous, following))

    pieces: list[_Piece] = []
    for piece_index, (start, end) in enumerate(spans):
        words = tuple(
            replace(word, start_char=word.start_char - start, end_char=word.end_char - start)
            for word in fragment.words
            if start <= word.start_char and word.end_char <= end
        )
        # Every split sentence must have exact lexical timing.  If a word
        # spans a proposed boundary or a piece has no words, retain the whole
        # source fragment; do not fabricate a sentence-local window.
        if any(
            word.start_char < start or word.end_char > end
            for word in fragment.words
            if word.start_char < end and word.end_char > start
        ):
            return (
                _Piece(
                    fragment.start_ms,
                    fragment.end_ms,
                    fragment.text,
                    fragment.words,
                    (fragment.source_index,),
                ),
            )
        if piece_index == 0:
            start_ms = fragment.start_ms
        else:
            start_ms = boundary_words[piece_index - 1][1].start_ms
        if piece_index == len(spans) - 1:
            end_ms = fragment.end_ms
        else:
            end_ms = boundary_words[piece_index][0].end_ms
        if end_ms <= start_ms:
            return (
                _Piece(
                    fragment.start_ms,
                    fragment.end_ms,
                    fragment.text,
                    fragment.words,
                    (fragment.source_index,),
                ),
            )
        pieces.append(
            _Piece(
                start_ms,
                end_ms,
                fragment.text[start:end],
                words,
                (fragment.source_index,),
            )
        )
    return tuple(pieces)


def _piece_words(piece: _Piece, prefix_length: int) -> tuple[AssembledWord, ...]:
    return tuple(
        AssembledWord(
            start_char=word.start_char + prefix_length,
            end_char=word.end_char + prefix_length,
            start_ms=word.start_ms,
            end_ms=word.end_ms,
            confidence=word.confidence,
            timing_source=word.timing_source,
            source_fragment_index=piece.source_fragment_indices[0],
        )
        for word in piece.words
    )


def _join_separator(current: AssembledSentence, piece: _Piece) -> str:
    return "" if _is_cross_fragment_domain_continuation(current.text, piece.text) else " "


def _merged_piece(current: AssembledSentence, piece: _Piece) -> AssembledSentence:
    separator = _join_separator(current, piece)
    prefix = len(current.text) + len(separator)
    text = current.text + separator + piece.text
    return AssembledSentence(
        index=current.index,
        start_ms=current.start_ms,
        end_ms=piece.end_ms,
        text=text,
        display_text=text,
        words=current.words + _piece_words(piece, prefix),
        source_fragment_indices=current.source_fragment_indices
        + piece.source_fragment_indices,
    )


def _piece_sentence(piece: _Piece, index: int) -> AssembledSentence:
    return AssembledSentence(
        index=index,
        start_ms=piece.start_ms,
        end_ms=piece.end_ms,
        text=piece.text,
        display_text=piece.text,
        words=_piece_words(piece, 0),
        source_fragment_indices=piece.source_fragment_indices,
    )


def _ends_in_terminal_boundary(text: str) -> bool:
    """Return whether the current candidate has a reliable sentence end."""
    final = text.rstrip()
    if not final:
        return False
    last = len(final) - 1
    while last >= 0 and final[last] in _CLOSERS:
        last -= 1
    if last < 0 or final[last] not in _TERMINAL_CHARS:
        return False
    if final[last] == ".":
        return _period_is_terminal(final, last)
    return True


def _starts_with_domain_label(text: str) -> bool:
    """Return whether a fragment starts with a known hostname label.

    ASR providers occasionally split ``example.`` and ``com.`` into separate
    timed fragments.  The label must be followed by a dot, whitespace, or the
    end of the fragment; this deliberately rejects ordinary words such as
    ``completely``.
    """
    match = re.match(r"\s*([A-Za-z0-9-]{2,63})(?=\.|\s|$)", text)
    return bool(match and match.group(1).casefold() in _DOMAIN_TLDS)


def _is_cross_fragment_domain_continuation(
    current_text: str,
    next_text: str,
) -> bool:
    """Recognize a hostname/e-mail continuation at a fragment boundary.

    The current fragment's terminal dot is normally a reliable sentence end.
    A following fragment beginning with a real top-level domain label is the
    one provider shape that makes that dot demonstrably internal, e.g.
    ``BBCLearningEnglish.`` + ``com.`` or ``www.example.`` + ``com/path``.
    ``completely new`` is not a domain label and therefore remains a new
    sentence.
    """
    current = current_text.rstrip()
    if not current.endswith(".") or not _starts_with_domain_label(next_text):
        return False
    # A known top-level label is strong enough evidence at a provider
    # fragment boundary: ordinary continuations such as ``completely`` do
    # not match the label guard above. This covers bare hostnames as well as
    # mixed-case brands, URLs, and e-mail addresses.
    return True


def _can_merge(current: AssembledSentence, piece: _Piece) -> bool:
    # A genuine boundary in the accumulated candidate always wins over a
    # continuation guess, including when the next provider fragment starts
    # with a lower-case word.
    if _ends_in_terminal_boundary(current.text) and not _is_cross_fragment_domain_continuation(
        current.text,
        piece.text,
    ):
        return False
    if piece.start_ms - current.end_ms > MAX_INTER_FRAGMENT_GAP_MS:
        return False
    if len(current.source_fragment_indices) >= MAX_SOURCE_FRAGMENTS:
        return False
    prospective_text_length = (
        len(current.text) + len(_join_separator(current, piece)) + len(piece.text)
    )
    if prospective_text_length > MAX_ASSEMBLED_CHARS:
        return False
    prospective_duration = piece.end_ms - current.start_ms
    if prospective_duration > MAX_ASSEMBLED_DURATION_MS:
        return False
    prospective_words = _word_count(current.text) + _word_count(piece.text)
    if prospective_words > MAX_ASSEMBLED_WORDS:
        return False
    return True


def assemble_timed_fragments(
    fragments: Iterable[TimedFragment | Any],
) -> tuple[AssembledSentence, ...]:
    """Assemble provider fragments into deterministic timed sentences."""
    normalized = tuple(
        fragment
        if isinstance(fragment, TimedFragment)
        else _fragment_from_provider(fragment, index)
        for index, fragment in enumerate(fragments)
    )
    if not normalized:
        return ()
    result: list[AssembledSentence] = []
    current: AssembledSentence | None = None
    next_index = 0
    for fragment in normalized:
        for piece in _split_fragment(fragment):
            if current is None:
                current = _piece_sentence(piece, next_index)
                next_index += 1
            elif _can_merge(current, piece):
                current = _merged_piece(current, piece)
            else:
                result.append(current)
                current = _piece_sentence(piece, next_index)
                next_index += 1
    if current is not None:
        result.append(current)
    # A display-text remap failure is a transcript-level qualification issue,
    # not a reason to publish whichever words happened to map successfully.
    # Keep the assembled text/timing available for reading and forced
    # alignment, but make ASR-word fallback abstain as one atomic unit.
    if not all(fragment.word_mapping_complete for fragment in normalized):
        result = [replace(sentence, words=()) for sentence in result]
    return tuple(result)


def assemble_asr_segments(
    segments: Sequence[AsrSegment],
) -> tuple[AssembledSentence, ...]:
    """Assemble ASR segments, preserving exact absolute word timings."""
    return assemble_timed_fragments(segments)


def assemble_asr_transcript(transcript: AsrTranscript) -> AsrTranscript:
    """Return a transcript whose segments are assembled sentence units."""
    assembled = assemble_asr_segments(transcript.segments)
    return replace(
        transcript,
        segments=tuple(sentence.as_asr_segment() for sentence in assembled),
        config_sha256=assembly_config_sha256(transcript.config_sha256),
    )


def assemble_subtitle_blocks(blocks: Sequence[Any]) -> tuple[AssembledSentence, ...]:
    """Assemble subtitle blocks using the same boundary and safety policy."""
    return assemble_timed_fragments(
        TimedFragment(
            start_ms=int(block.start_ms),
            end_ms=int(block.end_ms),
            text=_normal_text(str(block.text)),
            words=(),
            source_index=index,
        )
        for index, block in enumerate(blocks)
    )


__all__ = [
    "ASSEMBLY_ALGORITHM_ID",
    "ASSEMBLY_ALGORITHM_VERSION",
    "ASSEMBLY_CONFIG_SHA256",
    "MAX_ASSEMBLED_WORDS",
    "MAX_ASSEMBLED_CHARS",
    "MAX_ASSEMBLED_DURATION_MS",
    "MAX_INTER_FRAGMENT_GAP_MS",
    "MAX_SOURCE_FRAGMENTS",
    "TimedWord",
    "TimedFragment",
    "AssembledWord",
    "AssembledSentence",
    "assembly_config_sha256",
    "assemble_timed_fragments",
    "assemble_asr_segments",
    "assemble_asr_transcript",
    "assemble_subtitle_blocks",
]
