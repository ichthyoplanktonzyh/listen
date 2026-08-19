"""Audio-backed package-native Phone Timeline production."""

from __future__ import annotations

import hashlib
import json
import re
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Callable, Protocol

from . import __version__ as TOOL_VERSION
from .command_identity import command_identity_sha256, compose_config_sha256
from .package import ConversionError
from .package_v3 import (
    PackageResource,
    blob_declaration,
    canonical_json,
    provenance,
    quality,
    sha256_of_bytes,
)
from .process import ProcessOutputTooLarge, ProcessTimedOut, run_argv
from .rich import RichContext, RichStageFailure, RichWord

PHONE_TIMELINE_SCHEMA = "listen.payload.phone-timeline.v1"

PHONE_RESULT_SCHEMA = "listen_gen.phone-result.v1"
PHONE_STDOUT_LIMIT_BYTES = 16 * 1024 * 1024
SHA256_RE = re.compile(r"sha256:[0-9a-f]{64}")


@dataclass(frozen=True)
class DetectedPhone:
    symbol: str
    start_ms: int
    end_ms: int
    confidence: float | None = None
    display_ipa: str | None = None


@dataclass(frozen=True)
class PhoneResult:
    phones: tuple[DetectedPhone, ...]
    phone_set: str
    provider_id: str
    provider_version: str
    model_id: str | None = None
    model_version: str | None = None
    config_sha256: str | None = None


@dataclass(frozen=True)
class PhoneRequest:
    audio_path: Path
    words: tuple[RichWord, ...]


class PhoneAnalyzer(Protocol):
    def analyze(self, request: PhoneRequest) -> PhoneResult: ...


def _failure(code: str) -> RichStageFailure:
    return RichStageFailure("phone", code)


def _parse_result(raw: Any) -> PhoneResult:
    try:
        if not isinstance(raw, dict) or raw.get("schema") != PHONE_RESULT_SCHEMA:
            raise ValueError
        provider = raw.get("provider")
        if not isinstance(provider, dict):
            raise ValueError
        provider_id, provider_version = provider.get("id"), provider.get("version")
        if not all(isinstance(item, str) and item.strip() for item in (provider_id, provider_version)):
            raise ValueError
        phone_set = raw.get("phone_set")
        if not isinstance(phone_set, str) or not phone_set.strip():
            raise ValueError
        model_id = model_version = None
        model = raw.get("model")
        if model is not None:
            if not isinstance(model, dict):
                raise ValueError
            model_id, model_version = model.get("id"), model.get("version")
            if not all(isinstance(item, str) and item.strip() for item in (model_id, model_version)):
                raise ValueError
        config_sha256 = raw.get("config_sha256")
        if config_sha256 is not None and (
            not isinstance(config_sha256, str) or not SHA256_RE.fullmatch(config_sha256)
        ):
            raise ValueError
        entries = raw.get("phones")
        if not isinstance(entries, list) or not entries:
            raise ValueError
        phones: list[DetectedPhone] = []
        previous_end = 0
        for entry in entries:
            if not isinstance(entry, dict):
                raise ValueError
            symbol, start_ms, end_ms = entry.get("symbol"), entry.get("start_ms"), entry.get("end_ms")
            confidence = entry.get("confidence")
            display_ipa = entry.get("display_ipa")
            if (
                not isinstance(symbol, str)
                or not symbol.strip()
                or not isinstance(start_ms, int)
                or isinstance(start_ms, bool)
                or not isinstance(end_ms, int)
                or isinstance(end_ms, bool)
                or start_ms < previous_end
                or end_ms <= start_ms
            ):
                raise ValueError
            if confidence is not None and (
                not isinstance(confidence, (int, float))
                or isinstance(confidence, bool)
                or not 0 <= confidence <= 1
            ):
                raise ValueError
            if display_ipa is not None and (
                not isinstance(display_ipa, str) or not display_ipa.strip()
            ):
                raise ValueError
            phones.append(DetectedPhone(symbol, start_ms, end_ms, confidence, display_ipa))
            previous_end = end_ms
        return PhoneResult(
            tuple(phones), phone_set, provider_id, provider_version,
            model_id, model_version, config_sha256,
        )
    except (TypeError, ValueError) as error:
        raise _failure("output_invalid") from error


class FixturePhoneAdapter:
    def __init__(self, path: Path):
        if not path.is_file():
            raise ValueError("phone fixture must be a regular file")
        self.path = path

    def analyze(self, request: PhoneRequest) -> PhoneResult:
        try:
            return _parse_result(json.loads(self.path.read_text(encoding="utf-8")))
        except RichStageFailure:
            raise
        except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("output_invalid") from error


def _run(argv: list[str], timeout_seconds: float) -> bytes:
    try:
        completed = run_argv(
            argv,
            timeout_seconds=timeout_seconds,
            stdout_limit_bytes=PHONE_STDOUT_LIMIT_BYTES,
        )
    except ProcessTimedOut as error:
        raise _failure("timeout") from error
    except ProcessOutputTooLarge as error:
        raise _failure("output_too_large") from error
    except OSError as error:
        raise _failure("start_failed") from error
    if completed.returncode != 0:
        raise _failure("failed")
    return completed.stdout


class CommandPhoneAdapter:
    def __init__(self, executable: str, arguments: list[str], timeout_seconds: float):
        if not executable.strip():
            raise ValueError("phone command executable must be non-empty")
        if sum(argument == "{media}" for argument in arguments) != 1:
            raise ValueError("phone command arguments must contain exactly one {media} placeholder")
        if timeout_seconds <= 0:
            raise ValueError("phone command timeout must be positive")
        self.executable = executable
        self.arguments = tuple(arguments)
        self.timeout_seconds = timeout_seconds

    def analyze(self, request: PhoneRequest) -> PhoneResult:
        argv = [
            self.executable,
            *(str(request.audio_path) if item == "{media}" else item for item in self.arguments),
        ]
        try:
            before = command_identity_sha256(
                self.executable,
                self.arguments,
                frozenset({"{media}"}),
                self.timeout_seconds,
            )
        except OSError as error:
            raise _failure("start_failed") from error
        raw = _run(argv, self.timeout_seconds)
        try:
            after = command_identity_sha256(
                self.executable,
                self.arguments,
                frozenset({"{media}"}),
                self.timeout_seconds,
            )
        except OSError as error:
            raise _failure("failed") from error
        if after != before:
            raise _failure("failed")
        try:
            result = _parse_result(json.loads(raw))
            return replace(
                result,
                config_sha256=compose_config_sha256(
                    result.config_sha256, before
                ),
            )
        except RichStageFailure:
            raise
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("output_invalid") from error


def _file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return f"sha256:{digest.hexdigest()}"


def _tree_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    files = sorted(item for item in path.rglob("*") if item.is_file())
    if not files:
        raise ValueError("wav2vec2 model directory must contain files")
    for item in files:
        digest.update(item.relative_to(path).as_posix().encode())
        digest.update(b"\0")
        digest.update(_file_sha256(item).encode())
        digest.update(b"\0")
    return f"sha256:{digest.hexdigest()}"


class Wav2Vec2CtcPhoneAdapter:
    """First-class wrapper for the existing wav2vec2 phoneme sidecar protocol."""

    def __init__(
        self,
        python: Path,
        sidecar: Path,
        model_dir: Path,
        model_id: str,
        model_revision: str,
        timeout_seconds: float,
    ):
        if not python.is_file() or not sidecar.is_file() or not model_dir.is_dir():
            raise ValueError("wav2vec2 phone runtime inputs must exist")
        if not model_id.strip() or not model_revision.strip() or timeout_seconds <= 0:
            raise ValueError("wav2vec2 phone arguments are invalid")
        self.python, self.sidecar, self.model_dir = python, sidecar, model_dir
        self.model_id, self.model_revision = model_id, model_revision
        self.timeout_seconds = timeout_seconds

    def _identity(self) -> tuple[str, str, str]:
        return _file_sha256(self.python), _file_sha256(self.sidecar), _tree_sha256(self.model_dir)

    def analyze(self, request: PhoneRequest) -> PhoneResult:
        before = self._identity()
        raw = _run(
            [
                str(self.python), str(self.sidecar), "--model-dir", str(self.model_dir),
                "--audio", str(request.audio_path), "--start-ms", "0",
                "--end-ms", str(max(word.end_ms for word in request.words)),
            ],
            self.timeout_seconds,
        )
        after = self._identity()
        if after != before:
            raise _failure("failed")
        try:
            core = json.loads(raw)
            phones = core.get("phones") if isinstance(core, dict) else None
            config = {
                "schema": "listen_gen.wav2vec2-phone-config.v1",
                "python_sha256": before[0], "sidecar_sha256": before[1],
                "model_sha256": before[2],
            }
            normalized = {
                "schema": PHONE_RESULT_SCHEMA,
                "provider": {"id": "wav2vec2-ctc-phoneme", "version": "fb-espeak-v1"},
                "model": {"id": self.model_id, "version": self.model_revision},
                "config_sha256": "sha256:" + hashlib.sha256(
                    json.dumps(config, sort_keys=True, separators=(",", ":")).encode()
                ).hexdigest(),
                "phone_set": "ipa",
                "phones": phones,
            }
            return _parse_result(normalized)
        except RichStageFailure:
            raise
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise _failure("output_invalid") from error


def _anchor_phones(
    result: PhoneResult, words: tuple[RichWord, ...]
) -> tuple[dict[str, Any], ...]:
    if not words:
        raise _failure("upstream_missing")
    anchored: list[dict[str, Any]] = []
    for phone in result.phones:
        overlaps = [
            (max(0, min(phone.end_ms, word.end_ms) - max(phone.start_ms, word.start_ms)), word)
            for word in words
        ]
        overlap, word = max(overlaps, key=lambda item: (item[0], -item[1].start_ms))
        phone_dur = max(1, phone.end_ms - phone.start_ms)
        if overlap <= 0 or (overlap / phone_dur) < 0.5:
            continue
        # A phone anchored to a word is that word's sound: its time must lie
        # inside the word's window, which itself lies inside the subtitle
        # sentence window the package contract validates against. The overlap
        # guard above already ensures the clamped window is non-empty.
        start_ms = max(phone.start_ms, word.start_ms)
        end_ms = min(phone.end_ms, word.end_ms)
        if end_ms <= start_ms:
            continue
        entry: dict[str, Any] = {
            "symbol": phone.symbol,
            "start_ms": start_ms,
            "end_ms": end_ms,
            "word_ref": {"sentence_id": word.sentence_id, "token_index": word.token_index},
        }
        if phone.display_ipa is not None:
            entry["display_ipa"] = phone.display_ipa
        if phone.confidence is not None:
            entry["confidence"] = phone.confidence
        anchored.append(entry)
    if not anchored or len(anchored) / len(result.phones) < 0.6:
        raise _failure("qualification_failed")
    return tuple(anchored)


def run_phone(
    *, analyzer: PhoneAnalyzer, audio_path: Path, words: tuple[RichWord, ...],
    context: RichContext, dependencies: tuple[str, ...],
    progress: Callable[[str], None] | None = None,
) -> tuple[str, PackageResource | None, bytes | None, list[dict[str, str]]]:
    if progress is not None:
        progress("analyzing_phones")
    try:
        result = analyzer.analyze(PhoneRequest(audio_path, words))
        phones = _anchor_phones(result, words)
        payload = {
            "phone_set": result.phone_set,
            "precision": "detected",
            "phones": list(phones),
        }
        payload_bytes = canonical_json(payload)
        model = None
        if result.model_id is not None:
            model = {"id": result.model_id, "version": result.model_version}
        resource = PackageResource(
            kind="phone_timeline",
            schema=PHONE_TIMELINE_SCHEMA,
            role="base",
            content_language=context.language,
            payload_blob=blob_declaration(
                sha256_of_bytes(payload_bytes), len(payload_bytes), True
            ),
            subject=context.subject,
            dependencies=dependencies,
            provenance=provenance(
                context.created_at_ms,
                input_rendition_ids=[context.rendition_id],
                input_resource_ids=list(dependencies),
                provider={"id": result.provider_id, "version": result.provider_version},
                model=model,
                config_sha256=result.config_sha256,
            ),
            quality=quality(),
            required=False,
        )
        return "produced", resource, payload_bytes, []
    except RichStageFailure as error:
        return "degraded", None, None, [{"code": error.code, "message": str(error)}]
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        failure = _failure("failed")
        return "degraded", None, None, [{"code": failure.code, "message": str(failure)}]
