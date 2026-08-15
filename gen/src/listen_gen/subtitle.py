"""Subtitle track parsing for the capability production engine.

A subtitle track (SRT or WebVTT) provides the exact reading text and its
sentence-level time windows, so media with a subtitle can skip speech
recognition entirely and derive word timings by forced alignment.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

from .package import ConversionError

_TIME_RE = re.compile(
    r"(?P<h>\d{1,2}):(?P<m>\d{2}):(?P<s>\d{2})[,.:](?P<ms>\d{1,3})"
)
_SRT_BLOCK_SEP = re.compile(r"\n\s*\n")
_SRT_INDEX_RE = re.compile(r"^\s*\d+\s*$")
_WEBVTT_HEADER = re.compile(r"^\s*WEBVTT\b", re.IGNORECASE)
_VTT_LAYOUT_IGNORE = re.compile(r"^(NOTE\b|STYLE\b|REGION\b)")

_SUBTITLE_MAX_BLOCKS = 4096
_SUBTITLE_MAX_BLOCK_TEXT = 16 * 1024
_SUBTITLE_MAX_TEXT = 4 * 1024 * 1024


@dataclass(frozen=True)
class SubtitleBlock:
    text: str
    start_ms: int
    end_ms: int


def _parse_timestamp(value: str) -> int:
    match = _TIME_RE.search(value)
    if match is None:
        raise ConversionError("subtitle timestamp is malformed")
    milliseconds = (
        int(match.group("h")) * 3_600_000
        + int(match.group("m")) * 60_000
        + int(match.group("s")) * 1_000
        + int(match.group("ms").ljust(3, "0"))
    )
    return milliseconds


_TAG_RE = re.compile(r"<[^>]*>")


def _block_text(lines: list[str]) -> str:
    def clean(line: str) -> str:
        return _TAG_RE.sub("", line.strip())

    text = " ".join(clean(line) for line in lines if clean(line))
    if not text:
        raise ConversionError("subtitle block carries no text")
    if len(text) > _SUBTITLE_MAX_BLOCK_TEXT:
        raise ConversionError("subtitle block text is too large")
    return text


def parse_subtitle(path: Path) -> tuple[SubtitleBlock, ...]:
    """Parse an SRT or WebVTT file into timed text blocks."""
    if not path.is_file():
        raise ConversionError("subtitle input is not a regular file")
    try:
        raw = path.read_text(encoding="utf-8-sig")
    except (OSError, UnicodeDecodeError) as error:
        raise ConversionError("subtitle input could not be read") from error
    if len(raw) > _SUBTITLE_MAX_TEXT:
        raise ConversionError("subtitle input is too large")
    if "\n" not in raw and "\r" not in raw:
        raise ConversionError("subtitle input carries no block structure")
    normalized = raw.replace("\r\n", "\n").replace("\r", "\n")
    is_vtt = _WEBVTT_HEADER.match(normalized) is not None
    body = normalized
    if is_vtt:
        parts = body.split("\n", 1)
        body = parts[1] if len(parts) > 1 else ""
    body = body.strip("\n")
    blocks: list[SubtitleBlock] = []
    for chunk in _SRT_BLOCK_SEP.split(body):
        if not chunk.strip():
            continue
        lines = chunk.split("\n")
        if is_vtt and _VTT_LAYOUT_IGNORE.match(lines[0].strip()):
            continue
        if _SRT_INDEX_RE.match(lines[0]):
            lines = lines[1:]
        if not lines:
            continue
        timing_line = lines[0]
        match = re.search(
            r"(?P<start>\d{1,2}:\d{2}:\d{2}[,.:]\d{1,3})"
            r"\s*-->\s*"
            r"(?P<end>\d{1,2}:\d{2}:\d{2}[,.:]\d{1,3})",
            timing_line,
        )
        if match is None:
            continue
        start_ms = _parse_timestamp(match.group("start"))
        end_ms = _parse_timestamp(match.group("end"))
        if end_ms <= start_ms:
            raise ConversionError("subtitle block window is malformed")
        text = _block_text(lines[1:])
        blocks.append(SubtitleBlock(text, start_ms, end_ms))
        if len(blocks) > _SUBTITLE_MAX_BLOCKS:
            raise ConversionError("subtitle carries too many blocks")
    if not blocks:
        raise ConversionError("subtitle input carries no timed blocks")
    for index in range(1, len(blocks)):
        if blocks[index].start_ms < blocks[index - 1].end_ms:
            raise ConversionError("subtitle blocks overlap or are out of order")
    return tuple(blocks)
