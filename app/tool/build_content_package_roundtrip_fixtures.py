#!/usr/bin/env python3
"""Build deterministic, local-only fixtures for the package E2E gate.

The gate must exercise the same material families that the App accepts without
checking private desktop files into the repository.  Text fixtures are written
directly, EPUB/PDF containers are assembled from fixed bytes, and the media
fixtures are generated with local ffmpeg.  No provider, model, network, or
system speech service is used.

The output directory is disposable.  ``manifest.json`` records the exact
hashes of every generated file, so the Dart test can refuse a partially built
or accidentally changed fixture set before it starts a Core process.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import subprocess
import wave
import zipfile
from pathlib import Path


TEXT = "Listen, carefully! Words matter."
FULL_SENTENCE = (
    "Send us their name, photo, and a couple lines "
    "about what they mean to you, CNN10@cnn.com."
)


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _write(path: Path, value: str | bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(value, str):
        path.write_text(value, encoding="utf-8")
    else:
        path.write_bytes(value)


def _pdf(objects: list[bytes]) -> bytes:
    """Return a minimal deterministic PDF with the supplied object bodies."""
    header = b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n"
    output = bytearray(header)
    offsets = [0]
    for index, body in enumerate(objects, 1):
        offsets.append(len(output))
        output.extend(f"{index} 0 obj\n".encode("ascii"))
        output.extend(body)
        output.extend(b"\nendobj\n")
    xref_offset = len(output)
    output.extend(f"xref\n0 {len(objects) + 1}\n".encode("ascii"))
    output.extend(b"0000000000 65535 f \n")
    for offset in offsets[1:]:
        output.extend(f"{offset:010d} 00000 n \n".encode("ascii"))
    output.extend(
        (
            f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
            f"startxref\n{xref_offset}\n%%EOF\n"
        ).encode("ascii")
    )
    return bytes(output)


def _text_pdf(text: str) -> bytes:
    escaped = text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
    stream = f"BT /F1 12 Tf 50 150 Td ({escaped}) Tj ET".encode("latin-1")
    return _pdf(
        [
            b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] "
            b"/Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
            b"<< /Length " + str(len(stream)).encode("ascii") + b" >>\nstream\n"
            + stream
            + b"\nendstream",
        ]
    )


def _blank_pdf() -> bytes:
    return _pdf(
        [
            b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 200] >>",
        ]
    )


def _epub() -> bytes:
    entries = {
        "mimetype": b"application/epub+zip",
        "META-INF/container.xml": (
            b'<?xml version="1.0"?><container version="1.0">'
            b'<rootfiles><rootfile full-path="OEBPS/content.opf" '
            b'media-type="application/oebps-package+xml"/></rootfiles></container>'
        ),
        "OEBPS/content.opf": (
            b'<package version="3.0" xmlns="http://www.idpf.org/2007/opf">'
            b'<manifest><item id="chapter" href="chapter.xhtml" '
            b'media-type="application/xhtml+xml"/></manifest>'
            b'<spine><itemref idref="chapter"/></spine></package>'
        ),
        "OEBPS/chapter.xhtml": (
            b'<html xmlns="http://www.w3.org/1999/xhtml"><body>'
            b'<p>Listen, carefully! Words matter.</p>'
            b'</body></html>'
        ),
    }
    from io import BytesIO

    buffer = BytesIO()
    with zipfile.ZipFile(buffer, "w") as archive:
        for name, data in entries.items():
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_STORED if name == "mimetype" else zipfile.ZIP_DEFLATED
            info.create_system = 0
            archive.writestr(info, data)
    return buffer.getvalue()


def _wav(path: Path, duration_ms: int = 4200) -> None:
    sample_rate = 16_000
    count = sample_rate * duration_ms // 1000
    frames = bytearray()
    for index in range(count):
        # A quiet deterministic tone is enough to make ffprobe and the Core
        # media registration path observe a real audio stream.
        sample = int(900 * math.sin(2 * math.pi * 440 * index / sample_rate))
        frames.extend(sample.to_bytes(2, byteorder="little", signed=True))
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(sample_rate)
        handle.writeframes(bytes(frames))


def _video(path: Path, audio: Path, ffmpeg: str) -> None:
    command = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-y",
        "-f",
        "lavfi",
        "-i",
        "color=c=0x203438:s=320x180:r=10",
        "-i",
        str(audio),
        "-t",
        "4.2",
        "-map",
        "0:v:0",
        "-map",
        "1:a:0",
        "-c:v",
        "libx264",
        "-preset",
        "ultrafast",
        "-tune",
        "zerolatency",
        "-pix_fmt",
        "yuv420p",
        "-c:a",
        "aac",
        "-ar",
        "16000",
        "-ac",
        "1",
        "-movflags",
        "+faststart",
        str(path),
    ]
    try:
        subprocess.run(command, check=True)
    except FileNotFoundError as error:
        raise RuntimeError("ffmpeg is required to build the video E2E fixture") from error
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"ffmpeg failed while building the video fixture ({error.returncode})") from error


def _assert_streams(path: Path, expected: tuple[str, ...], ffprobe: str) -> None:
    command = [
        ffprobe,
        "-v",
        "error",
        "-show_entries",
        "stream=codec_type",
        "-of",
        "csv=p=0",
        str(path),
    ]
    try:
        result = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
        )
    except FileNotFoundError as error:
        raise RuntimeError("ffprobe is required to validate media fixture streams") from error
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"ffprobe failed while validating {path.name}") from error
    actual = tuple(line.strip() for line in result.stdout.splitlines() if line.strip())
    if actual != expected:
        raise RuntimeError(
            f"{path.name} stream shape is {actual!r}, expected {expected!r}"
        )


def _asr() -> dict[str, object]:
    segments = [
        {
            "start_ms": 100,
            "end_ms": 1200,
            "text": "Listen, carefully!",
            "display_text": "Listen, carefully!",
            "words": [
                {"start_char": 0, "end_char": 6, "start_ms": 100, "end_ms": 480, "confidence": 0.98, "timing_source": "asr_reported"},
                {"start_char": 8, "end_char": 17, "start_ms": 560, "end_ms": 1100, "confidence": 0.96, "timing_source": "asr_reported"},
            ],
        },
        {
            "start_ms": 1300,
            "end_ms": 2100,
            "text": "Words matter.",
            "display_text": "Words matter.",
            "words": [
                {"start_char": 0, "end_char": 5, "start_ms": 1300, "end_ms": 1600, "confidence": 0.97, "timing_source": "asr_reported"},
                {"start_char": 6, "end_char": 12, "start_ms": 1650, "end_ms": 2020, "confidence": 0.95, "timing_source": "asr_reported"},
            ],
        },
    ]
    return {
        "schema": "listen_gen.asr-result.v1",
        "language": "en-US",
        "provider": {"id": "fixture-asr", "version": "1"},
        "model": {"id": "fixture-words", "version": "2026-08"},
        "config_sha256": "sha256:" + "a" * 64,
        "segments": segments,
    }


def _full_alignment() -> dict[str, object]:
    words = [
        "Send", "us", "their", "name", "photo", "and", "a", "couple", "lines",
        "about", "what", "they", "mean", "to", "you", "CNN10", "cnn", "com",
    ]
    timings = []
    start = 100
    for index, word in enumerate(words):
        duration = 80 + len(word) * 18
        timings.append({
            "segment_index": 0,
            "word_index": index,
            "text": word,
            "start_ms": start,
            "end_ms": start + duration,
            "score": 0.98,
        })
        start += duration + 20
    return {
        "schema": "listen_gen.alignment-result.v1",
        "provider": {"id": "fixture-aligner", "version": "1"},
        "model": {"id": "fixture-align-model", "version": "1"},
        "config_sha256": "sha256:" + "b" * 64,
        "words": timings,
    }


def _simple_alignment() -> dict[str, object]:
    words = ["Listen", "carefully", "Words", "matter"]
    timings = []
    for segment_index, (segment_words, start, end) in enumerate(
        ((words[:2], 100, 1200), (words[2:], 1300, 2100))
    ):
        cursor = start
        for word_index, word in enumerate(segment_words):
            duration = 120 + len(word) * 18
            timings.append(
                {
                    "segment_index": segment_index,
                    "word_index": word_index,
                    "text": word,
                    "start_ms": cursor,
                    "end_ms": min(cursor + duration, end),
                    "score": 0.98,
                }
            )
            cursor += duration + 20
    return {
        "schema": "listen_gen.alignment-result.v1",
        "provider": {"id": "fixture-aligner", "version": "1"},
        "model": {"id": "fixture-align-model", "version": "1"},
        "config_sha256": "sha256:" + "b" * 64,
        "words": timings,
    }


def _document_alignment() -> dict[str, object]:
    """Word timings inside Fake TTS's 0ms/1680ms sentence windows."""
    timings = [
        {
            "segment_index": 0,
            "word_index": 0,
            "text": "Listen",
            "start_ms": 100,
            "end_ms": 328,
            "score": 0.98,
        },
        {
            "segment_index": 0,
            "word_index": 1,
            "text": "carefully",
            "start_ms": 348,
            "end_ms": 630,
            "score": 0.98,
        },
        {
            "segment_index": 1,
            "word_index": 0,
            "text": "Words",
            "start_ms": 1700,
            "end_ms": 1910,
            "score": 0.98,
        },
        {
            "segment_index": 1,
            "word_index": 1,
            "text": "matter",
            "start_ms": 1930,
            "end_ms": 2158,
            "score": 0.98,
        },
    ]
    return {
        "schema": "listen_gen.alignment-result.v1",
        "provider": {"id": "fixture-aligner", "version": "1"},
        "model": {"id": "fixture-align-model", "version": "1"},
        "config_sha256": "sha256:" + "b" * 64,
        "words": timings,
    }


def _rich_fixtures() -> dict[str, object]:
    # Word tokens occupy every other/every third slot depending on
    # punctuation.  The fixture deliberately covers the complete single
    # assembled sentence; Core will reject a partial partition.
    token_indexes = [0, 2, 4, 6, 9, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 33, 35, 37]
    measurements = []
    for index, token_index in enumerate(token_indexes):
        measurements.append({
            "sentence_index": 0,
            "token_index": token_index,
            "energy": {"rms_dbfs": -22.0, "local_baseline_dbfs": -27.0, "delta_db": 5.0, "prominence": 0.7},
            "pitch": {"median_f0_hz": 180.0, "local_baseline_f0_hz": 165.0, "delta_semitones": 1.2, "range_semitones": 2.0, "prominence": 0.7, "reset_after": 0.2},
            "duration": {"duration_ms": 50, "local_ratio": 1.0},
            "voiced_frame_ratio": 0.9,
        })
    anchors = [
        {
            "sentence_index": 0,
            "token_index": token_index,
            "lexical_stress": "primary",
            "realized_prominence": 0.7,
            "utterance_role": "nucleus" if index == 14 else "prenuclear",
            "evidence": ["energy", "pitch", "duration"],
            "confidence": 0.8,
        }
        for index, token_index in enumerate(token_indexes)
    ]
    return {
        "sense": {
            "schema": "listen_gen.sense-group-result.v1",
            "provider": {"id": "fixture-sense-groups", "version": "1"},
            "model": {"id": "fixture-groups", "version": "1"},
            "config_sha256": "sha256:" + "c" * 64,
            "groups": [{
                "sentence_index": 0,
                "group_index": 0,
                "start_token_index": 0,
                "end_token_index_exclusive": 39,
                "confidence": 0.9,
                "label": "complete",
                "head_token_index": 14,
                "sources": ["rule"],
            }],
        },
        "acoustics": {
            "schema": "listen_gen.acoustics-result.v1",
            "provider": {"id": "fixture-acoustics", "version": "1"},
            "model": {"id": "fixture-acoustics-model", "version": "1"},
            "config_sha256": "sha256:" + "d" * 64,
            "sample_rate_hz": 16000,
            "measurements": measurements,
        },
        "prosody": {
            "schema": "listen_gen.prosody-result.v1",
            "provider": {"id": "fixture-prosody", "version": "1"},
            "model": {"id": "fixture-prosody-model", "version": "1"},
            "config_sha256": "sha256:" + "e" * 64,
            "uses_sense_groups": True,
            "anchors": anchors,
            "chunks": [{
                "sentence_index": 0,
                "chunk_index": 0,
                "start_token_index": 0,
                "end_token_index_exclusive": 39,
                "nucleus_token_index": 14,
                "confidence": 0.85,
            }],
        },
        "phone": {
            "schema": "listen_gen.phone-result.v1",
            "provider": {"id": "fixture-phone", "version": "1"},
            "model": {"id": "fixture-ctc", "version": "1"},
            "config_sha256": "sha256:" + "f" * 64,
            "phone_set": "ipa",
            "phones": [
                {"symbol": "s", "start_ms": 120, "end_ms": 180, "confidence": 0.9},
                {"symbol": "ɛ", "start_ms": 180, "end_ms": 260, "confidence": 0.9},
                {"symbol": "n", "start_ms": 260, "end_ms": 360, "confidence": 0.9},
                {"symbol": "m", "start_ms": 1300, "end_ms": 1400, "confidence": 0.9},
                {"symbol": "ə", "start_ms": 1400, "end_ms": 1500, "confidence": 0.9},
                {"symbol": "r", "start_ms": 1500, "end_ms": 1600, "confidence": 0.9},
            ],
        },
    }


def _simple_rich_fixtures(*, document: bool = False) -> dict[str, object]:
    """Return rich adapters that exactly cover the two short fixture cues."""
    words = [
        (0, 0, 100, 328),
        (0, 3, 348, 630),
        (
            1,
            1 if document else 0,
            1700 if document else 1300,
            1910 if document else 1510,
        ),
        (
            1,
            3 if document else 2,
            1930 if document else 1530,
            2158 if document else 1758,
        ),
    ]
    measurements = [
        {
            "sentence_index": sentence_index,
            "token_index": token_index,
            "energy": {
                "rms_dbfs": -22.0,
                "local_baseline_dbfs": -27.0,
                "delta_db": 5.0,
                "prominence": 0.7,
            },
            "pitch": {
                "median_f0_hz": 180.0,
                "local_baseline_f0_hz": 165.0,
                "delta_semitones": 1.2,
                "range_semitones": 2.0,
                "prominence": 0.7,
                "reset_after": 0.2,
            },
            "duration": {"duration_ms": end_ms - start_ms, "local_ratio": 1.0},
            "voiced_frame_ratio": 0.9,
        }
        for sentence_index, token_index, start_ms, end_ms in words
    ]
    anchors = [
        {
            "sentence_index": sentence_index,
            "token_index": token_index,
            "lexical_stress": "primary",
            "realized_prominence": 0.7,
            "utterance_role": (
                "nucleus"
                if token_index == 0 or token_index == (3 if document else 2)
                else "prenuclear"
            ),
            "evidence": ["energy", "pitch", "duration"],
            "confidence": 0.8,
        }
        for sentence_index, token_index, _, _ in words
    ]
    return {
        "sense": {
            "schema": "listen_gen.sense-group-result.v1",
            "provider": {"id": "fixture-sense-groups", "version": "1"},
            "model": {"id": "fixture-groups", "version": "1"},
            "config_sha256": "sha256:" + "c" * 64,
            "groups": [
                {
                    "sentence_index": 0,
                    "group_index": 0,
                    "start_token_index": 0,
                    "end_token_index_exclusive": 5,
                    "confidence": 0.9,
                    "label": "short-0",
                    "head_token_index": 0,
                    "sources": ["rule"],
                },
                {
                    "sentence_index": 1,
                    "group_index": 0,
                    "start_token_index": 0,
                    "end_token_index_exclusive": 5 if document else 4,
                    "confidence": 0.9,
                    "label": "short-1",
                    "head_token_index": 3 if document else 2,
                    "sources": ["rule"],
                },
            ],
        },
        "acoustics": {
            "schema": "listen_gen.acoustics-result.v1",
            "provider": {"id": "fixture-acoustics", "version": "1"},
            "model": {"id": "fixture-acoustics-model", "version": "1"},
            "config_sha256": "sha256:" + "d" * 64,
            "sample_rate_hz": 16000,
            "measurements": measurements,
        },
        "prosody": {
            "schema": "listen_gen.prosody-result.v1",
            "provider": {"id": "fixture-prosody", "version": "1"},
            "model": {"id": "fixture-prosody-model", "version": "1"},
            "config_sha256": "sha256:" + "e" * 64,
            "uses_sense_groups": True,
            "anchors": anchors,
            "chunks": [
                {
                    "sentence_index": 0,
                    "chunk_index": 0,
                    "start_token_index": 0,
                    "end_token_index_exclusive": 5,
                    "nucleus_token_index": 0,
                    "confidence": 0.85,
                },
                {
                    "sentence_index": 1,
                    "chunk_index": 0,
                    "start_token_index": 0,
                    "end_token_index_exclusive": 5 if document else 4,
                    "nucleus_token_index": 3 if document else 2,
                    "confidence": 0.85,
                },
            ],
        },
        "phone": {
            "schema": "listen_gen.phone-result.v1",
            "provider": {"id": "fixture-phone", "version": "1"},
            "model": {"id": "fixture-ctc", "version": "1"},
            "config_sha256": "sha256:" + "f" * 64,
            "phone_set": "ipa",
            "phones": [
                {
                    "symbol": symbol,
                    "start_ms": start_ms + 10,
                    "end_ms": end_ms - 10,
                    "confidence": 0.9,
                }
                for symbol, (_, _, start_ms, end_ms) in zip(
                    ("l", "k", "w", "m"), words
                )
            ],
        },
    }


def _validate_short_rich_fixtures(rich: dict[str, object], words: list[tuple[int, int, int, int]]) -> None:
    """Fail fixture construction when refs, spans, or phone clocks drift."""
    sense_groups = rich["sense"]["groups"]  # type: ignore[index]
    prosody = rich["prosody"]  # type: ignore[assignment]
    expected_ends = [5, 5 if words[-2][1] == 1 else 4]
    if [item["end_token_index_exclusive"] for item in sense_groups] != expected_ends:  # type: ignore[index]
        raise RuntimeError("short sense fixtures must cover all subtitle tokens")
    if [item["end_token_index_exclusive"] for item in prosody["chunks"]] != expected_ends:  # type: ignore[index]
        raise RuntimeError("short prosody fixtures must cover all subtitle tokens")
    measured = {
        (item["sentence_index"], item["token_index"]): item  # type: ignore[index]
        for item in rich["acoustics"]["measurements"]  # type: ignore[index]
    }
    phones = rich["phone"]["phones"]  # type: ignore[index]
    if len(measured) != len(words) or len(phones) != len(words):  # type: ignore[arg-type]
        raise RuntimeError("short rich fixtures must cover every word timing")
    for (sentence_index, token_index, start_ms, end_ms), phone in zip(words, phones):  # type: ignore[arg-type]
        if (sentence_index, token_index) not in measured:
            raise RuntimeError("short acoustic fixture has an unresolved word ref")
        if not (start_ms < phone["end_ms"] <= end_ms and start_ms <= phone["start_ms"] < end_ms):  # type: ignore[index]
            raise RuntimeError("short phone fixture is outside its word clock")


def build(output: Path, ffmpeg: str, ffprobe: str) -> None:
    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)
    _write(output / "lesson.txt", TEXT + "\n")
    _write(output / "lesson.md", TEXT + "\n")
    _write(output / "lesson.html", "<html><body><p>" + TEXT + "</p></body></html>\n")
    _write(output / "lesson.epub", _epub())
    _write(output / "lesson-text.pdf", _text_pdf(TEXT))
    _write(output / "lesson-scanned.pdf", _blank_pdf())
    _write(output / "ocr.txt", TEXT + "\n")
    _write(
        output / "subtitle-simple.srt",
        "1\n00:00:00,100 --> 00:00:01,200\nListen, carefully!\n\n"
        "2\n00:00:01,300 --> 00:00:02,100\nWords matter.\n",
    )
    _write(
        output / "subtitle-full.srt",
        "1\n00:00:00,100 --> 00:00:01,850\n"
        "Send us their name, photo, and a couple lines\n\n"
        "2\n00:00:01,860 --> 00:00:03,900\n"
        "about what they mean to you, CNN10@cnn.com.\n",
    )
    _write(
        output / "subtitle-three.srt",
        "1\n00:00:00,100 --> 00:00:01,450\n"
        "Send us their name, photo, and a couple lines\n\n"
        "2\n00:00:01,460 --> 00:00:02,750\n"
        "about what they mean to you,\n\n"
        "3\n00:00:02,760 --> 00:00:03,900\n"
        "CNN10@cnn.com.\n",
    )
    _write(output / "sample.asr.json", json.dumps(_asr(), indent=2) + "\n")
    _write(
        output / "simple.alignment.json",
        json.dumps(_simple_alignment(), indent=2) + "\n",
    )
    _write(
        output / "document.alignment.json",
        json.dumps(_document_alignment(), indent=2) + "\n",
    )
    _write(output / "full.alignment.json", json.dumps(_full_alignment(), indent=2) + "\n")
    rich = _rich_fixtures()
    _write(output / "full.sense-groups.json", json.dumps(rich["sense"], indent=2) + "\n")
    _write(output / "full.acoustics.json", json.dumps(rich["acoustics"], indent=2) + "\n")
    _write(output / "full.prosody.json", json.dumps(rich["prosody"], indent=2) + "\n")
    _write(output / "full.phones.json", json.dumps(rich["phone"], indent=2) + "\n")
    for prefix, rich in (
        ("simple", _simple_rich_fixtures()),
        ("document", _simple_rich_fixtures(document=True)),
    ):
        _validate_short_rich_fixtures(
            rich,
            [
                (0, 0, 100, 328),
                (0, 3, 348, 630),
                (
                    1,
                    1 if prefix == "document" else 0,
                    1700 if prefix == "document" else 1300,
                    1910 if prefix == "document" else 1510,
                ),
                (
                    1,
                    3 if prefix == "document" else 2,
                    1930 if prefix == "document" else 1530,
                    2158 if prefix == "document" else 1758,
                ),
            ],
        )
        _write(
            output / f"{prefix}.sense-groups.json",
            json.dumps(rich["sense"], indent=2) + "\n",
        )
        _write(
            output / f"{prefix}.acoustics.json",
            json.dumps(rich["acoustics"], indent=2) + "\n",
        )
        _write(
            output / f"{prefix}.prosody.json",
            json.dumps(rich["prosody"], indent=2) + "\n",
        )
        _write(
            output / f"{prefix}.phones.json",
            json.dumps(rich["phone"], indent=2) + "\n",
        )
    _wav(output / "sample-media.wav")
    _video(output / "sample-video.mp4", output / "sample-media.wav", ffmpeg)
    _assert_streams(output / "sample-media.wav", ("audio",), ffprobe)
    _assert_streams(output / "sample-video.mp4", ("video", "audio"), ffprobe)

    files = {}
    for path in sorted(output.iterdir()):
        if path.name == "manifest.json":
            continue
        if path.is_file():
            files[path.name] = _sha256(path)
    manifest = {
        "schema": "listen_app.content-package-roundtrip-fixture.v3",
        "source_repository": "ichthyoplanktonzyh/listen-gen",
        "files": files,
        "media_streams": {
            "sample-media.wav": ["audio"],
            "sample-video.mp4": ["video", "audio"],
        },
    }
    _write(output / "manifest.json", json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    parser.add_argument("--ffprobe", default="ffprobe")
    args = parser.parse_args()
    build(args.output, args.ffmpeg, args.ffprobe)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
