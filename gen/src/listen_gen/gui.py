"""listen-gen GUI: built-in web server and API for managing model providers and generation runs.

Provides a lightweight, zero-external-dependency local HTTP server with REST APIs
and Server-Sent Events (SSE) for streaming machine events to the GUI.
"""

from __future__ import annotations

import base64
import json
import mimetypes
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request
import webbrowser
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable

from . import __version__ as TOOL_VERSION
from .capability import (
    CAPABILITY_REQUEST_SCHEMA,
    REQUEST_VERSION,
    AvailableDocumentRendition,
    AvailableMediaRendition,
    CapabilityRequest,
    EditionIdentity,
    MaterialIdentity,
)
from .cli import CancellationRequested, _classify_error, _default_attempt_id
from .llm_client import (
    LlmAdapterKind,
    LlmProviderProfile,
    create_llm_client,
)
from .package_v3 import sha256_of_bytes
from .plan import plan as plan_request
from .produce import ProduceConfig, produce
from .protocol_v2 import (
    TERMINAL_EVENTS,
    MachineEventV2Emitter,
    protocol_capabilities_v2,
)
from .rich_stages import RichStages

DEFAULT_CONFIG_DIR = Path.home() / ".listen-gen"
DEFAULT_CONFIG_FILE = DEFAULT_CONFIG_DIR / "profiles.json"
UPLOAD_DIR = DEFAULT_CONFIG_DIR / "uploads"
ARTIFACTS_DIR = DEFAULT_CONFIG_DIR / "artifacts"
SOURCES_DIR = DEFAULT_CONFIG_DIR / "sources"  # durable text inputs (for reruns)
TASKS_FILE = DEFAULT_CONFIG_DIR / "tasks.json"
MAX_TASK_HISTORY = 100
MAX_UPLOAD_BYTES = 2 * 1024 * 1024 * 1024  # 2 GiB per upload
UPLOAD_MAX_AGE_SECONDS = 7 * 24 * 3600  # prune uploads older than 7 days
MAX_CONCURRENT_RUNS = max(1, int(os.environ.get("LISTEN_GEN_MAX_CONCURRENT_RUNS", "2")))

SUPPORTED_CAPABILITIES = ("read", "listen", "watch", "synchronized_read_listen")


def detect_media_type(filename_or_path: str) -> str:
    """Detects MIME type for supported document, media, and subtitle files."""
    path_lower = filename_or_path.lower()
    if path_lower.endswith((".md", ".markdown")):
        return "text/markdown"
    if path_lower.endswith(".txt"):
        return "text/plain"
    if path_lower.endswith((".html", ".htm")):
        return "text/html"
    if path_lower.endswith(".epub"):
        return "application/epub+zip"
    if path_lower.endswith(".pdf"):
        return "application/pdf"
    if path_lower.endswith((".mp4", ".m4v", ".mov", ".mkv")):
        return "video/mp4"
    if path_lower.endswith(".mp3"):
        return "audio/mpeg"
    if path_lower.endswith(".wav"):
        return "audio/wav"
    if path_lower.endswith(".m4a"):
        return "audio/mp4"
    if path_lower.endswith(".srt"):
        return "text/srt"
    if path_lower.endswith(".vtt"):
        return "text/vtt"
    guessed, _ = mimetypes.guess_type(filename_or_path)
    return guessed or "application/octet-stream"


def get_default_config() -> dict[str, Any]:
    """Returns the default configuration dictionary."""
    return {
        "version": 1,
        "selected_llm": "deepseek",
        "llm_profiles": {
            "deepseek": {
                "name": "DeepSeek",
                "adapter_kind": "openai_chat",
                "base_url": "https://api.deepseek.com/v1",
                "model_id": "deepseek-chat",
                "api_key": os.environ.get("DEEPSEEK_API_KEY", ""),
                "timeout_seconds": 30.0,
                "concurrency": 100,
            },
            "openai": {
                "name": "OpenAI",
                "adapter_kind": "openai_chat",
                "base_url": "https://api.openai.com/v1",
                "model_id": "gpt-4o-mini",
                "api_key": os.environ.get("OPENAI_API_KEY", ""),
                "timeout_seconds": 30.0,
                "concurrency": 50,
            },
            "anthropic": {
                "name": "Claude (Anthropic)",
                "adapter_kind": "anthropic_messages",
                "base_url": "https://api.anthropic.com",
                "model_id": "claude-3-5-sonnet-20241022",
                "api_key": os.environ.get("ANTHROPIC_API_KEY", ""),
                "timeout_seconds": 30.0,
                "concurrency": 20,
            },
            "gemini": {
                "name": "Google Gemini",
                "adapter_kind": "gemini",
                "base_url": "https://generativelanguage.googleapis.com/v1beta",
                "model_id": "gemini-1.5-flash",
                "api_key": os.environ.get("GEMINI_API_KEY", ""),
                "timeout_seconds": 30.0,
                "concurrency": 50,
            },
            "custom": {
                "name": "Custom / Ollama / Local",
                "adapter_kind": "openai_chat",
                "base_url": "http://localhost:11434/v1",
                "model_id": "qwen2.5:7b",
                "api_key": "",
                "timeout_seconds": 30.0,
                "concurrency": 10,
            },
        },
        "asr": {
            "provider": "whisper-cpp",
            "whisper_cli": "whisper-cli",
            "whisper_model": "",
            "whisper_model_id": "ggml-base.en.bin",
            "whisper_language": "auto",
            "whisper_translate_to_english": False,
            "timeout_seconds": 3600.0,
        },
        "phones": {
            "provider": "baseline",
            "wav2vec2_python": sys.executable,
            "wav2vec2_sidecar": "",
            "wav2vec2_model_dir": "",
            "wav2vec2_model_id": "facebook/wav2vec2-base-960h",
            "wav2vec2_model_revision": "main",
            "timeout_seconds": 600.0,
        },
        "aligner": {
            "provider": "none",
            "aligner_python": sys.executable,
            "aligner_script": "",
            "timeout_seconds": 600.0,
        },
        "tts": {
            "provider": "kokoro" if sys.platform == "darwin" else "none",
            "voice": "af_bella",
            "speed": 1.0,
            "lang_code": "a",
            "say_executable": "say",
            "afconvert_executable": "afconvert",
            "timeout_seconds": 600.0,
        },
        "ocr": {
            "provider": "none",
            "langs": "en,zh",
            "device": "mps" if sys.platform == "darwin" else "cpu",
            "timeout_seconds": 600.0,
        },
        "syntax": {
            "backend": "spacy",
            "model": "en_core_web_sm",
        },
    }


def _deep_merge(base: dict[str, Any], incoming: dict[str, Any]) -> dict[str, Any]:
    """Recursively merge ``incoming`` into ``base`` (returns a new dict).

    Nested dictionaries are merged key-by-key so default sub-fields survive
    partial updates; scalar values from ``incoming`` always win.
    """
    out = dict(base)
    for key, value in incoming.items():
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = _deep_merge(out[key], value)
        else:
            out[key] = value
    return out


def _merge_config(default: dict[str, Any], stored: dict[str, Any]) -> dict[str, Any]:
    """Merge a stored config over the defaults.

    ``llm_profiles`` is special-cased: existing profiles get default fields
    restored, but profiles the user deleted are NOT resurrected (respecting
    deletions is important for provider management).
    """
    merged = dict(default)
    for key, value in stored.items():
        if key == "llm_profiles" and isinstance(value, dict):
            merged_profiles: dict[str, Any] = {}
            for profile_key, profile_value in value.items():
                base_profile = default.get("llm_profiles", {}).get(profile_key, {})
                if isinstance(profile_value, dict):
                    merged_profiles[profile_key] = _deep_merge(base_profile, profile_value)
                else:
                    merged_profiles[profile_key] = profile_value
            merged["llm_profiles"] = merged_profiles
        elif isinstance(value, dict) and isinstance(merged.get(key), dict):
            merged[key] = _deep_merge(merged[key], value)
        else:
            merged[key] = value
    return merged


def validate_config(config: dict[str, Any]) -> list[str]:
    """Returns a list of configuration problems (empty when valid)."""
    problems: list[str] = []

    selected = config.get("selected_llm")
    profiles = config.get("llm_profiles", {})
    if selected and selected not in profiles:
        problems.append(f"selected_llm '{selected}' has no matching llm_profiles entry")
    for key, prof in profiles.items():
        if not isinstance(prof, dict):
            problems.append(f"llm_profiles.{key} must be an object")
            continue
        base_url = prof.get("base_url")
        if base_url and not str(base_url).startswith(("http://", "https://")):
            problems.append(f"llm_profiles.{key}.base_url must start with http:// or https://")
        timeout = prof.get("timeout_seconds")
        if timeout is not None and (not isinstance(timeout, (int, float)) or timeout <= 0):
            problems.append(f"llm_profiles.{key}.timeout_seconds must be a positive number")

    tts_provider = config.get("tts", {}).get("provider")
    if tts_provider not in ("say", "fake", "fixture", "kokoro", "none"):
        problems.append(f"tts.provider must be one of say/fake/fixture/kokoro/none, got {tts_provider!r}")
    ocr_provider = config.get("ocr", {}).get("provider")
    if ocr_provider not in ("surya", "rapidocr", "fixture", "none"):
        problems.append(f"ocr.provider must be one of surya/rapidocr/fixture/none, got {ocr_provider!r}")
    asr_provider = config.get("asr", {}).get("provider")
    if asr_provider not in ("whisper-cpp", "none"):
        problems.append(f"asr.provider must be whisper-cpp or none, got {asr_provider!r}")
    phones_provider = config.get("phones", {}).get("provider")
    if phones_provider not in ("baseline", "wav2vec2", "none"):
        problems.append(f"phones.provider must be baseline/wav2vec2/none, got {phones_provider!r}")
    aligner_provider = config.get("aligner", {}).get("provider")
    if aligner_provider not in ("none", "torchaudio"):
        problems.append(f"aligner.provider must be none or torchaudio, got {aligner_provider!r}")
    return problems


def load_config(path: Path = DEFAULT_CONFIG_FILE) -> dict[str, Any]:
    """Loads configuration from file, deep-merging stored values over defaults."""
    default = get_default_config()
    if not path.is_file():
        return default
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            return default
        return _merge_config(default, data)
    except Exception:
        return default


def save_config(config: dict[str, Any], path: Path = DEFAULT_CONFIG_FILE) -> None:
    """Validates and saves configuration to file.

    Raises ``ValueError`` listing every problem when the config is invalid;
    nothing is written in that case.
    """
    problems = validate_config(config)
    if problems:
        raise ValueError("Configuration validation failed:\n- " + "\n- ".join(problems))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config, indent=2, ensure_ascii=False), encoding="utf-8")


@dataclass
class GenerationTask:
    task_id: str
    created_at: float
    status: str  # "queued", "running", "completed", "failed", "cancelled"
    request_doc: dict[str, Any]
    output_path: Path
    events: list[dict[str, Any]]
    error: str | None = None
    completed_at: float | None = None
    cancel_requested: bool = False
    config: dict[str, Any] | None = None
    event_queue: queue.Queue | None = None

    def to_dict(self) -> dict[str, Any]:
        """Serializable snapshot (event_queue is runtime-only)."""
        return {
            "task_id": self.task_id,
            "created_at": self.created_at,
            "status": self.status,
            "request_doc": self.request_doc,
            "output_path": str(self.output_path),
            "events": self.events,
            "error": self.error,
            "completed_at": self.completed_at,
            "cancel_requested": self.cancel_requested,
            "config": self.config,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> "GenerationTask":
        return cls(
            task_id=data["task_id"],
            created_at=data.get("created_at", 0.0),
            status=data.get("status", "failed"),
            request_doc=data.get("request_doc", {}),
            output_path=Path(data.get("output_path", "")),
            events=list(data.get("events", [])),
            error=data.get("error"),
            completed_at=data.get("completed_at"),
            cancel_requested=bool(data.get("cancel_requested", False)),
            config=data.get("config"),
        )


class TaskManager:
    """Persistent task registry for background generation jobs.

    Every task is mirrored to ``tasks.json`` so history survives restarts.
    Tasks that were still running when the process exited are restored as
    ``failed`` with an honest ``server_restarted`` error.  Events carry a
    monotonically increasing ``seq`` per task so SSE clients can resume a
    stream from an arbitrary point (``Last-Event-ID``).
    """

    def __init__(
        self,
        store_path: Path = TASKS_FILE,
        max_history: int = MAX_TASK_HISTORY,
    ) -> None:
        self.tasks: dict[str, GenerationTask] = {}
        self.lock = threading.Lock()
        self.store_path = store_path
        self.max_history = max_history
        self._last_save = 0.0
        self._load()

    # -- persistence -------------------------------------------------

    def _load(self) -> None:
        try:
            data = json.loads(self.store_path.read_text(encoding="utf-8"))
        except Exception:
            return
        restored_failed = 0
        for entry in data.get("tasks", []):
            try:
                task = GenerationTask.from_dict(entry)
            except Exception:
                continue
            if task.status in ("running", "queued"):
                # A running or queued task cannot survive a process restart;
                # mark it failed honestly instead of leaving a zombie row.
                task.status = "failed"
                task.cancel_requested = False
                task.error = "server restarted while the task was running"
                task.completed_at = time.time()
                terminal = {
                    "type": "terminal",
                    "status": "failed",
                    "error": task.error,
                    "task_id": task.task_id,
                    "timestamp": task.completed_at,
                }
                terminal["seq"] = len(task.events)
                task.events.append(terminal)
                restored_failed += 1
            self.tasks[task.task_id] = task
        if restored_failed:
            self._save()

    def _save(self) -> None:
        """Writes a snapshot atomically; failures are non-fatal for the GUI."""
        try:
            self.store_path.parent.mkdir(parents=True, exist_ok=True)
            payload = {"version": 1, "tasks": [t.to_dict() for t in self.tasks.values()]}
            tmp = self.store_path.with_suffix(".json.tmp")
            tmp.write_text(
                json.dumps(payload, ensure_ascii=False, indent=1), encoding="utf-8"
            )
            os.replace(tmp, self.store_path)
        except Exception:
            pass

    def _maybe_persist(self, event: dict[str, Any] | None = None) -> None:
        """Throttled persistence: always on terminal events, else ~1/s."""
        now = time.time()
        if event is None:
            self._save()
            self._last_save = now
            return
        is_terminal = event.get("type") == "terminal" or event.get("event") in TERMINAL_EVENTS
        if is_terminal or now - self._last_save >= 1.0:
            self._save()
            self._last_save = now

    # -- lifecycle ---------------------------------------------------

    def create_task(
        self,
        task_id: str,
        request_doc: dict[str, Any],
        output_path: Path,
        status: str = "running",
        config: dict[str, Any] | None = None,
    ) -> GenerationTask:
        task = GenerationTask(
            task_id=task_id,
            created_at=time.time(),
            status=status,
            request_doc=request_doc,
            output_path=output_path,
            events=[],
            config=config,
            event_queue=queue.Queue(),
        )
        with self.lock:
            self.tasks[task_id] = task
            self._trim_history_locked()
            self._save()
            self._last_save = time.time()
        return task

    def mark_running(self, task_id: str) -> GenerationTask | None:
        """Transitions a queued task to running (no-op otherwise)."""
        with self.lock:
            task = self.tasks.get(task_id)
            if task and task.status == "queued":
                task.status = "running"
                self._save()
                self._last_save = time.time()
            return task

    def get_task(self, task_id: str) -> GenerationTask | None:
        with self.lock:
            return self.tasks.get(task_id)

    def list_tasks(self) -> list[GenerationTask]:
        with self.lock:
            return sorted(self.tasks.values(), key=lambda t: t.created_at, reverse=True)

    def cancel_task(self, task_id: str) -> GenerationTask | None:
        """Requests cancellation of a queued or running task (idempotent)."""
        with self.lock:
            task = self.tasks.get(task_id)
            if task and task.status in ("queued", "running"):
                task.cancel_requested = True
                self._save()
                self._last_save = time.time()
            return task

    def check_cancelled(self, task_id: str) -> None:
        """Called from the produce worker between stages; raises on cancel."""
        task = self.get_task(task_id)
        if task and task.cancel_requested:
            raise CancellationRequested(None)

    def record_event(self, task_id: str, event: dict[str, Any]) -> None:
        with self.lock:
            task = self.tasks.get(task_id)
            if not task:
                return
            if isinstance(event, dict) and "recorded_at" not in event:
                event["recorded_at"] = time.time()
            event["seq"] = len(task.events)
            task.events.append(event)
            if task.event_queue:
                task.event_queue.put(event)
            self._maybe_persist(event)

    def complete_task(
        self,
        task_id: str,
        success: bool,
        error: str | None = None,
        status: str | None = None,
    ) -> None:
        """Closes a task with a terminal event; ``status`` overrides the default."""
        task = self.get_task(task_id)
        if not task:
            return
        final_status = status or ("completed" if success else "failed")
        task.status = final_status
        task.error = error
        task.cancel_requested = False
        task.completed_at = time.time()
        terminal_event = {
            "type": "terminal",
            "status": final_status,
            "error": error,
            "task_id": task_id,
            "package_path": str(task.output_path) if final_status == "completed" else None,
            "download_url": f"/api/download/{task_id}" if final_status == "completed" else None,
            "timestamp": task.completed_at,
            "recorded_at": task.completed_at,
        }
        with self.lock:
            terminal_event["seq"] = len(task.events)
            task.events.append(terminal_event)
            if task.event_queue:
                task.event_queue.put(terminal_event)
            self._save()
            self._last_save = time.time()

    def _trim_history_locked(self) -> None:
        """Keeps at most ``max_history`` tasks, never dropping queued/running ones."""
        if len(self.tasks) <= self.max_history:
            return
        live_ids = {
            t.task_id for t in self.tasks.values() if t.status in ("queued", "running")
        }
        candidates = sorted(
            (t for t in self.tasks.values() if t.status not in ("queued", "running")),
            key=lambda t: t.created_at,
        )
        overflow = len(self.tasks) - self.max_history
        for task in candidates[:overflow]:
            if task.task_id in live_ids:
                continue
            self.tasks.pop(task.task_id, None)


_GLOBAL_TASK_MANAGER = TaskManager()


class RunScheduler:
    """FIFO runner that starts at most ``max_concurrent_runs`` workers.

    Tasks submitted while slots are full stay ``queued`` (with an event in
    their stream) until a worker frees a slot; a queued task can be removed
    before it starts.  This prevents a burst of clicks from spawning many
    heavy subprocesses (``say`` / ``whisper.cpp``) at once.
    """

    def __init__(self, max_concurrent_runs: int = MAX_CONCURRENT_RUNS) -> None:
        self.max_concurrent_runs = max(1, int(max_concurrent_runs))
        self.lock = threading.Lock()
        self.pending: list[str] = []
        self.running: set[str] = set()
        self._fns: dict[str, Callable[[], None]] = {}

    def submit(self, task_id: str, fn: Callable[[], None]) -> None:
        with self.lock:
            self._fns[task_id] = fn
            self.pending.append(task_id)
        self._pump()

    def remove_pending(self, task_id: str) -> bool:
        """Removes a not-yet-started task from the queue; returns True if removed."""
        with self.lock:
            if task_id in self.pending:
                self.pending.remove(task_id)
                self._fns.pop(task_id, None)
                return True
        return False

    def running_count(self) -> int:
        with self.lock:
            return len(self.running)

    def pending_count(self) -> int:
        with self.lock:
            return len(self.pending)

    def queue_position(self, task_id: str) -> int | None:
        with self.lock:
            try:
                return self.pending.index(task_id) + 1
            except ValueError:
                return None

    def _pump(self) -> None:
        with self.lock:
            while len(self.running) < self.max_concurrent_runs and self.pending:
                task_id = self.pending.pop(0)
                self.running.add(task_id)
                threading.Thread(
                    target=self._run_slot, args=(task_id,), daemon=True
                ).start()

    def _run_slot(self, task_id: str) -> None:
        fn = self._fns.pop(task_id, None)
        try:
            task = _GLOBAL_TASK_MANAGER.get_task(task_id)
            if fn is None or task is None or task.status in ("cancelled", "failed", "completed"):
                return  # cancelled while queued: already closed by the cancel route
            _GLOBAL_TASK_MANAGER.mark_running(task_id)
            fn()
        finally:
            with self.lock:
                self.running.discard(task_id)
            self._pump()


_RUN_SCHEDULER = RunScheduler()


class _TaskEventSink:
    """TextIO-shaped sink that records serialized machine-event lines.

    ``MachineEventV2Emitter`` writes NDJSON lines to its ``stream``; this sink
    parses each line back into a dict and records it on the task so the GUI
    monitor and the persisted event log see the same structured events.
    """

    def __init__(self, task_id: str) -> None:
        self.task_id = task_id

    def write(self, line: str) -> int:
        try:
            event = json.loads(line)
        except Exception:
            return 0
        _GLOBAL_TASK_MANAGER.record_event(self.task_id, event)
        return len(line)

    def flush(self) -> None:  # pragma: no cover - emitter compatibility
        pass


def test_llm_connection(profile_data: dict[str, Any]) -> dict[str, Any]:
    """Tests LLM provider connectivity with a lightweight structured JSON call."""
    start_time = time.time()
    try:
        profile = LlmProviderProfile.from_dict(profile_data)
        client = create_llm_client(profile)
        system_prompt = "You are an API connectivity test probe. Reply with valid JSON strictly matching: {\"status\": \"ok\"}."
        user_prompt = "Ping test."
        result = client.call_structured_json(system_prompt, user_prompt, timeout_seconds=profile.timeout_seconds)
        latency_ms = round((time.time() - start_time) * 1000, 1)
        if result is not None and isinstance(result, dict):
            return {
                "success": True,
                "latency_ms": latency_ms,
                "response": result,
                "message": f"Connection succeeded ({latency_ms}ms)",
            }
        else:
            return {
                "success": False,
                "latency_ms": latency_ms,
                "message": "Model responded but output was not valid JSON or response was empty.",
            }
    except Exception as exc:
        latency_ms = round((time.time() - start_time) * 1000, 1)
        return {
            "success": False,
            "latency_ms": latency_ms,
            "message": f"Connection failed: {str(exc)}",
        }


def check_toolchain() -> dict[str, Any]:
    """Inspects available system tools and sidecar dependencies."""
    tools = {}

    for tool in ("ffmpeg", "ffprobe"):
        path = shutil.which(tool)
        version = None
        if path:
            try:
                out = subprocess.run([tool, "-version"], capture_output=True, text=True, timeout=3)
                first_line = out.stdout.splitlines()[0] if out.stdout else ""
                version = first_line
            except Exception:
                pass
        tools[tool] = {"available": path is not None, "path": path, "version": version}

    say_path = shutil.which("say")
    voices = []
    if say_path and sys.platform == "darwin":
        try:
            out = subprocess.run(["say", "-v", "?"], capture_output=True, text=True, timeout=3)
            for line in out.stdout.splitlines():
                parts = line.strip().split()
                if parts:
                    voices.append(parts[0])
        except Exception:
            pass
    tools["say"] = {
        "available": say_path is not None,
        "path": say_path,
        "voices": voices[:30],
    }

    tools["python"] = {
        "available": True,
        "path": sys.executable,
        "version": f"Python {sys.version.split()[0]}",
    }

    spacy_avail = False
    spacy_models = []
    try:
        import spacy
        spacy_avail = True
        for m in ("en_core_web_sm", "en_core_web_md", "zh_core_web_sm"):
            if spacy.util.is_package(m):
                spacy_models.append(m)
    except ImportError:
        pass
    tools["spacy"] = {
        "available": spacy_avail,
        "installed_models": spacy_models,
    }

    return tools


def _parse_multipart(body: bytes, content_type: str) -> dict[str, tuple[str | None, str | None, bytes]]:
    """Parses a multipart/form-data body.

    Returns ``{field_name: (filename, content_type, payload)}``.  This is a
    small dependency-free parser that works on Python 3.11+ (the stdlib
    ``cgi`` module was removed in 3.13).
    """
    match = re.search(r'boundary="?([^";]+)"?', content_type)
    if not match:
        raise ValueError("multipart/form-data boundary missing from Content-Type")
    boundary = match.group(1).encode("utf-8")
    fields: dict[str, tuple[str | None, str | None, bytes]] = {}
    for segment in body.split(b"--" + boundary):
        if segment.startswith(b"--"):
            continue  # the closing delimiter (or a stray marker)
        segment = segment.lstrip(b"\r\n")  # separating CRLF after the boundary
        if not segment:
            continue
        header_blob, sep, payload = segment.partition(b"\r\n\r\n")
        if not sep:
            continue
        headers: dict[str, str] = {}
        for line in header_blob.split(b"\r\n"):
            name, _, value = line.partition(b":")
            headers[name.decode("latin-1").strip().lower()] = value.decode("latin-1").strip()
        disposition = headers.get("content-disposition", "")
        field_name: str | None = None
        filename: str | None = None
        for token in disposition.split(";"):
            token = token.strip()
            if token.lower().startswith("name="):
                field_name = token[5:].strip('"')
            elif token.lower().startswith("filename="):
                filename = token[9:].strip('"')
        if field_name:
            fields[field_name] = (filename, headers.get("content-type"), payload)
    if not fields:
        raise ValueError("multipart body contained no parts")
    return fields


def _commit_upload(
    filename: str,
    raw_bytes: bytes,
    media_type: str | None = None,
) -> dict[str, Any]:
    """Stores an uploaded file and returns the standard upload response.

    Shared by the JSON/base64 and multipart upload paths.
    """
    UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    safe_name = os.path.basename(filename or "upload.bin")
    target_path = UPLOAD_DIR / safe_name
    target_path.write_bytes(raw_bytes)

    resolved_type = media_type or detect_media_type(safe_name)
    digest = sha256_of_bytes(raw_bytes)

    preview_text = None
    if resolved_type.startswith("text/") or safe_name.endswith((".md", ".txt", ".json", ".srt", ".vtt")):
        try:
            preview_text = raw_bytes[:10000].decode("utf-8", errors="replace")
        except Exception:
            pass

    return {
        "status": "ok",
        "filename": safe_name,
        "path": str(target_path),
        "size_bytes": len(raw_bytes),
        "media_type": resolved_type,
        "digest": digest,
        "preview_text": preview_text,
    }


def _prune_uploads(max_age_seconds: int = UPLOAD_MAX_AGE_SECONDS) -> int:
    """Deletes stale uploads and durable text sources; returns removed count."""
    cutoff = time.time() - max_age_seconds
    removed = 0
    for directory in (UPLOAD_DIR, SOURCES_DIR):
        if not directory.is_dir():
            continue
        for entry in directory.iterdir():
            try:
                if entry.is_file() and entry.stat().st_mtime < cutoff:
                    entry.unlink(missing_ok=True)
                    removed += 1
            except OSError:
                continue
    return removed


def _validate_produce_payload(req_data: dict[str, Any], payload: dict[str, Any]) -> list[dict[str, str]]:
    """Structured pre-flight validation for a produce request.

    Returns a list of ``{"field": ..., "message": ...}`` problems; an empty
    list means the request is structurally acceptable.
    """
    problems: list[dict[str, str]] = []
    material = req_data.get("material") if isinstance(req_data.get("material"), dict) else {}
    edition = req_data.get("edition") if isinstance(req_data.get("edition"), dict) else {}
    material_id = str(material.get("material_id", "")).strip()
    title = str(material.get("title") or edition.get("title") or req_data.get("title") or "").strip()

    if not material_id:
        problems.append({"field": "material_id", "message": "素材唯一 ID (material_id) 不能为空"})
    elif not re.match(r"^[A-Za-z0-9._:-]{1,200}$", material_id):
        problems.append({"field": "material_id", "message": "material_id 只能包含字母/数字/._:-，长度不超过 200"})
    if not title:
        problems.append({"field": "title", "message": "素材标题 (title) 不能为空"})

    capability = req_data.get("requested_capability")
    if capability not in SUPPORTED_CAPABILITIES:
        problems.append({
            "field": "requested_capability",
            "message": f"不支持的能力 {capability!r}，可选: {', '.join(SUPPORTED_CAPABILITIES)}",
        })

    renditions = req_data.get("available_renditions", [])
    has_document = any(isinstance(r, dict) and r.get("kind") == "document" for r in renditions)
    has_media = any(isinstance(r, dict) and r.get("kind") == "media" for r in renditions)
    has_document = has_document or bool(payload.get("document_text"))
    if not has_document and not has_media:
        problems.append({"field": "input", "message": "需要至少一份文档或音视频素材"})
    if capability == "listen" and not has_document:
        problems.append({"field": "input", "message": "listen 能力需要文档输入（文本/文件）"})
    return problems


class GuiRequestHandler(BaseHTTPRequestHandler):
    """HTTP request handler providing REST APIs, SSE, and static web assets."""

    server_version = f"ListenGenGUI/{TOOL_VERSION}"

    def _send_json(self, data: Any, status: int = 200) -> None:
        payload = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(payload)

    def _send_error_json(self, message: str, status: int = 400) -> None:
        self._send_json({"error": message}, status=status)

    def do_OPTIONS(self) -> None:
        self.send_response(HTTPStatus.NO_CONTENT)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/api/health":
            self._send_json({"status": "ok", "version": TOOL_VERSION})
            return

        if path == "/api/config":
            self._send_json(load_config())
            return

        if path == "/api/toolchain/status":
            self._send_json(check_toolchain())
            return

        if path == "/api/tasks":
            entries = []
            for task in _GLOBAL_TASK_MANAGER.list_tasks():
                entries.append({
                    "task_id": task.task_id,
                    "status": task.status,
                    "created_at": task.created_at,
                    "completed_at": task.completed_at,
                    "error": task.error,
                    "material_id": ((task.request_doc or {}).get("material") or {}).get("material_id"),
                    "title": (
                        ((task.request_doc or {}).get("material") or {}).get("title")
                        or ((task.request_doc or {}).get("edition") or {}).get("title")
                        or ""
                    ),
                    "capability": (task.request_doc or {}).get("requested_capability"),
                    "event_count": len(task.events),
                    "queued_position": (
                        _RUN_SCHEDULER.queue_position(task.task_id)
                        if task.status == "queued"
                        else None
                    ),
                    "download_url": f"/api/download/{task.task_id}" if task.status == "completed" else None,
                })
            self._send_json({"tasks": entries})
            return

        if path.startswith("/api/tasks/") and path.endswith("/events/export"):
            task_id = path.split("/")[3]
            task = _GLOBAL_TASK_MANAGER.get_task(task_id)
            if not task:
                self._send_error_json("Task not found", 404)
                return
            blob = json.dumps(
                {"task": task.to_dict()}, ensure_ascii=False, indent=2
            ).encode("utf-8")
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header(
                "Content-Disposition",
                f'attachment; filename="task-{task_id}-events.json"',
            )
            self.send_header("Content-Length", str(len(blob)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(blob)
            return

        if path.startswith("/api/tasks/") and path.endswith("/events"):
            task_id = path.split("/")[3]
            task = _GLOBAL_TASK_MANAGER.get_task(task_id)
            if not task:
                self._send_error_json("Task not found", 404)
                return

            # Resume support: reconnecting clients send Last-Event-ID and we
            # replay events with a strictly greater seq (see index.html).
            try:
                resume_seq = int(self.headers.get("Last-Event-ID", "-1"))
            except ValueError:
                resume_seq = -1

            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()

            for event in list(task.events):
                if event.get("seq", 0) <= resume_seq:
                    continue
                data = f"id: {event.get('seq', 0)}\ndata: {json.dumps(event, ensure_ascii=False)}\n\n"
                self.wfile.write(data.encode("utf-8"))
            self.wfile.flush()

            while task.status == "running" or not task.event_queue.empty():
                try:
                    event = task.event_queue.get(timeout=1.0)
                    data = f"id: {event.get('seq', 0)}\ndata: {json.dumps(event, ensure_ascii=False)}\n\n"
                    self.wfile.write(data.encode("utf-8"))
                    self.wfile.flush()
                    if event.get("type") == "terminal":
                        break
                except queue.Empty:
                    self.wfile.write(b": heartbeat\n\n")
                    self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError):
                    break
            return

        if re.fullmatch(r"/api/tasks/[^/]+", path):
            task_id = path.split("/")[3]
            task = _GLOBAL_TASK_MANAGER.get_task(task_id)
            if not task:
                self._send_error_json("Task not found", 404)
                return
            self._send_json({"task": task.to_dict()})
            return

        if path.startswith("/api/download/"):
            task_id = path.split("/")[3]
            task = _GLOBAL_TASK_MANAGER.get_task(task_id)
            if not task or not task.output_path.is_file():
                self._send_error_json("Artifact not found", 404)
                return

            content = task.output_path.read_bytes()
            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Disposition", f'attachment; filename="package-{task_id}.zip"')
            self.send_header("Content-Length", str(len(content)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(content)
            return

        self._serve_static(path)

    def do_POST(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        content_type = self.headers.get("Content-Type", "")

        # Multipart uploads bypass JSON parsing entirely.
        if path == "/api/upload" and "multipart/form-data" in content_type:
            self._handle_upload_multipart()
            return

        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length > 0 else b"{}"

        try:
            data = json.loads(body.decode("utf-8"))
        except Exception:
            data = {}

        if path == "/api/config":
            problems = validate_config(data)
            if problems:
                self._send_json(
                    {
                        "status": "error",
                        "message": "配置校验失败",
                        "errors": problems,
                    },
                    status=400,
                )
                return
            try:
                save_config(data)
                self._send_json({"status": "saved", "config": load_config()})
            except Exception as exc:
                self._send_error_json(f"Failed to save config: {exc}", 500)
            return

        if path == "/api/test/llm":
            res = test_llm_connection(data)
            self._send_json(res)
            return

        if path == "/api/test/tts":
            provider = data.get("provider", "kokoro")
            voice = data.get("voice", "af_bella")
            if provider == "kokoro":
                try:
                    import kokoro  # type: ignore
                    self._send_json({"ok": True, "message": f"Kokoro (PyTorch) 已就绪，默认声音: {voice}"})
                except ImportError:
                    try:
                        import kokoro_onnx  # type: ignore
                        self._send_json({"ok": True, "message": f"Kokoro-ONNX 已就绪，默认声音: {voice}"})
                    except ImportError:
                        self._send_json({
                            "ok": False,
                            "message": "未检测到 Kokoro 库。可运行: pip install kokoro soundfile 或 pip install kokoro-onnx",
                        })
            elif provider == "say":
                say_bin = shutil.which(data.get("say_executable", "say"))
                if say_bin:
                    self._send_json({"ok": True, "message": f"macOS say 命令可用: {say_bin}"})
                else:
                    self._send_json({"ok": False, "message": "未找到 say 可执行文件"})
            else:
                self._send_json({"ok": True, "message": f"TTS 提供者已选择: {provider}"})
            return

        if path == "/api/test/ocr":
            provider = data.get("provider", "surya")
            if provider == "surya":
                try:
                    import surya  # type: ignore
                    self._send_json({"ok": True, "message": "Surya OCR 已就绪 (版面分析与阅读顺序重构)"})
                except ImportError:
                    self._send_json({
                        "ok": False,
                        "message": "未检测到 Surya OCR。可运行: pip install surya-ocr pypdfium2 pillow",
                    })
            elif provider == "rapidocr":
                try:
                    import rapidocr_onnxruntime  # type: ignore
                    self._send_json({"ok": True, "message": "RapidOCR (ONNX) 已就绪"})
                except ImportError:
                    self._send_json({
                        "ok": False,
                        "message": "未检测到 RapidOCR。可运行: pip install rapidocr-onnxruntime pypdfium2 pillow",
                    })
            else:
                self._send_json({"ok": True, "message": f"OCR 提供者已选择: {provider}"})
            return

        if path == "/api/test/whisper":
            cli_path = data.get("whisper_cli", "whisper-cli")
            model_path = data.get("whisper_model", "")
            resolved_cli = shutil.which(cli_path)
            model_exists = Path(model_path).is_file() if model_path else False
            self._send_json({
                "cli_available": resolved_cli is not None,
                "cli_path": resolved_cli,
                "model_exists": model_exists,
                "model_path": model_path,
                "message": (
                    "Whisper CLI and model ready"
                    if resolved_cli and model_exists
                    else "Missing CLI executable or model file"
                ),
            })
            return

        if path == "/api/upload":
            self._store_upload_response(data)
            return

        if path == "/api/inspect-file":
            self._handle_inspect_file(data)
            return

        if path == "/api/produce":
            self._handle_produce(data)
            return

        if re.fullmatch(r"/api/tasks/[^/]+/cancel", path):
            task_id = path.split("/")[3]
            task = _GLOBAL_TASK_MANAGER.get_task(task_id)
            if not task:
                self._send_error_json("Task not found", 404)
                return
            if task.status == "running":
                _GLOBAL_TASK_MANAGER.cancel_task(task_id)
                self._send_json({
                    "status": "cancelling",
                    "task_id": task_id,
                    "message": "已发送取消请求，任务将在当前阶段结束后停止",
                })
                return
            if task.status == "queued":
                _RUN_SCHEDULER.remove_pending(task_id)
                _GLOBAL_TASK_MANAGER.complete_task(
                    task_id,
                    success=False,
                    status="cancelled",
                    error="cancelled while queued",
                )
                self._send_json({
                    "status": "cancelled",
                    "task_id": task_id,
                    "message": "任务已在队列中取消",
                })
                return
            self._send_json({
                "status": "idle",
                "message": f"任务已处于 {task.status} 状态，无需取消",
            })
            return

        if re.fullmatch(r"/api/tasks/[^/]+/rerun", path):
            self._handle_rerun(path.split("/")[3])
            return

        self._send_error_json("Endpoint not found", 404)

    def _store_upload_response(self, data: dict[str, Any]) -> None:
        """Refactored JSON/base64 upload path (kept for older clients)."""
        filename = data.get("filename")
        content_b64 = data.get("content_base64")
        if not filename or not content_b64:
            self._send_error_json("Missing filename or content_base64", 400)
            return

        try:
            raw_bytes = base64.b64decode(content_b64)
            if len(raw_bytes) > MAX_UPLOAD_BYTES:
                self._send_error_json(f"Upload exceeds the {MAX_UPLOAD_BYTES} byte limit", 413)
                return
            media_type = data.get("type")
            self._send_json(_commit_upload(filename, raw_bytes, media_type))
        except Exception as exc:
            self._send_error_json(f"Upload failed: {exc}", 500)

    def _handle_upload_multipart(self) -> None:
        """Handles streaming multipart/form-data file uploads (no base64 overhead)."""
        try:
            length = int(self.headers.get("Content-Length", 0))
            if length > MAX_UPLOAD_BYTES:
                self._send_error_json(f"Upload exceeds the {MAX_UPLOAD_BYTES} byte limit", 413)
                return
            body = self.rfile.read(length) if length else b""
            fields = _parse_multipart(body, self.headers.get("Content-Type", ""))
            file_field = fields.get("file")
            if not file_field or not file_field[0]:
                self._send_error_json("Missing file part in multipart upload", 400)
                return
            filename, media_type, raw_bytes = file_field
            self._send_json(_commit_upload(filename, raw_bytes, media_type))
        except ValueError as exc:
            self._send_error_json(str(exc), 400)
        except Exception as exc:
            self._send_error_json(f"Upload failed: {exc}", 500)

    def _handle_inspect_file(self, data: dict[str, Any]) -> None:
        """Inspects an existing file on the local filesystem."""
        file_path_str = data.get("path")
        if not file_path_str:
            self._send_error_json("Missing path", 400)
            return

        p = Path(file_path_str)
        if not p.is_file():
            self._send_error_json(f"File not found: {file_path_str}", 404)
            return

        try:
            raw_bytes = p.read_bytes()
            media_type = detect_media_type(p.name)
            digest = sha256_of_bytes(raw_bytes)
            preview_text = None
            if media_type.startswith("text/") or p.name.endswith((".md", ".txt", ".srt", ".vtt")):
                try:
                    preview_text = raw_bytes[:10000].decode("utf-8", errors="replace")
                except Exception:
                    pass

            self._send_json({
                "status": "ok",
                "filename": p.name,
                "path": str(p.resolve()),
                "size_bytes": len(raw_bytes),
                "media_type": media_type,
                "digest": digest,
                "preview_text": preview_text,
            })
        except Exception as exc:
            self._send_error_json(f"Failed reading file: {exc}", 500)

    def _handle_rerun(self, task_id: str) -> None:
        """Re-submits a finished task from its persisted request/config snapshot.

        The stored rendition blob paths are re-verified on disk and their
        digests/sizes recomputed so the new run advertises honest inputs.
        """
        task = _GLOBAL_TASK_MANAGER.get_task(task_id)
        if not task:
            self._send_error_json("Task not found", 404)
            return
        req_data = task.request_doc or {}
        if not req_data:
            self._send_error_json("任务没有可用的请求快照", 400)
            return

        renditions: list[dict[str, Any]] = []
        for entry in req_data.get("available_renditions", []):
            if not isinstance(entry, dict):
                continue
            blob = entry.get("blob") or {}
            path = blob.get("path")
            if not path or not Path(path).is_file():
                self._send_error_json(
                    f"原始素材已不在磁盘（{entry.get('kind')} {path}），请回到生成工作台重新选择",
                    409,
                )
                return
            raw = Path(path).read_bytes()
            digest = sha256_of_bytes(raw)
            new_entry = dict(entry)
            new_entry["blob"] = {"digest": digest, "size_bytes": len(raw), "path": path}
            if new_entry.get("kind") == "document":
                new_entry["rendition_id"] = digest
                new_entry["source_asset_id"] = digest
            elif new_entry.get("kind") == "media":
                new_entry["rendition_id"] = digest
                new_entry["fingerprint"] = digest
            renditions.append(new_entry)
        if not renditions:
            self._send_error_json("请求快照中没有可用的输入素材", 400)
            return

        created_at_ms = int(time.time() * 1000)
        material = req_data.get("material") or {}
        edition = req_data.get("edition") or {}
        new_req_data = {
            "schema": CAPABILITY_REQUEST_SCHEMA,
            "version": REQUEST_VERSION,
            "created_at_ms": created_at_ms,
            "material": {
                "material_id": material.get("material_id") or "rerun-material",
                "material_revision_id": f"rev-{created_at_ms}",
                "title": material.get("title") or "Rerun",
            },
            "edition": edition,
            "requested_capability": req_data.get("requested_capability"),
            "available_renditions": renditions,
            "available_resources": list(req_data.get("available_resources") or []),
            "extensions": {},
        }

        problems = _validate_produce_payload(new_req_data, {})
        if problems:
            self._send_json({"error": "请求校验未通过", "errors": problems}, status=400)
            return
        try:
            request = CapabilityRequest.from_document(new_req_data)
        except Exception as exc:
            self._send_error_json(f"Invalid capability request: {exc}", 400)
            return

        new_task_id = f"task-{int(time.time() * 1000)}"
        ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
        output_zip = ARTIFACTS_DIR / f"package-{new_task_id}.zip"
        cfg_data = task.config if isinstance(task.config, dict) else load_config()

        _GLOBAL_TASK_MANAGER.create_task(
            new_task_id, new_req_data, output_zip, status="queued", config=cfg_data
        )
        _GLOBAL_TASK_MANAGER.record_event(new_task_id, {
            "type": "queued",
            "message": f"一键重跑自 {task_id}，已进入生成队列",
        })
        _RUN_SCHEDULER.submit(
            new_task_id,
            lambda: _run_produce_worker(
                new_task_id, request, cfg_data, output_zip, None
            ),
        )
        self._send_json({
            "task_id": new_task_id,
            "status": "queued",
            "rerun_of": task_id,
            "events_url": f"/api/tasks/{new_task_id}/events",
            "download_url": f"/api/download/{new_task_id}",
        })

    def _handle_produce(self, payload: dict[str, Any]) -> None:
        """Executes a capability generation run asynchronously."""
        task_id = f"task-{int(time.time()*1000)}"
        ARTIFACTS_DIR.mkdir(parents=True, exist_ok=True)
        SOURCES_DIR.mkdir(parents=True, exist_ok=True)
        output_zip = ARTIFACTS_DIR / f"package-{task_id}.zip"

        try:
            req_meta = payload.get("request")
            if not req_meta:
                self._send_error_json("Missing request document", 400)
                return

            created_at_ms = int(time.time() * 1000)

            # 1. Document input (from local file or raw text) → v2 rendition
            available_renditions: list[dict[str, Any]] = []
            if payload.get("document_path") and Path(payload["document_path"]).is_file():
                doc_path = Path(payload["document_path"])
                doc_bytes = doc_path.read_bytes()
                media_type = payload.get("document_media_type") or detect_media_type(doc_path.name)
                digest = sha256_of_bytes(doc_bytes)
                available_renditions.append({
                    "kind": "document",
                    "rendition_id": digest,
                    "media_type": media_type,
                    "source_asset_id": digest,
                    "blob": {
                        "digest": digest,
                        "size_bytes": len(doc_bytes),
                        "path": str(doc_path.resolve()),
                    },
                })
            elif payload.get("document_text"):
                # Text inputs are persisted under ~/.listen-gen/sources so a
                # one-click rerun can read them back later; they are pruned on
                # the same schedule as uploads.
                doc_text = payload["document_text"]
                doc_bytes = doc_text.encode("utf-8")
                doc_file = SOURCES_DIR / f"doc-{task_id}.md"
                doc_file.write_bytes(doc_bytes)
                digest = sha256_of_bytes(doc_bytes)
                media_type = payload.get("document_media_type", "text/markdown")
                available_renditions.append({
                    "kind": "document",
                    "rendition_id": digest,
                    "media_type": media_type,
                    "source_asset_id": digest,
                    "blob": {
                        "digest": digest,
                        "size_bytes": len(doc_bytes),
                        "path": str(doc_file),
                    },
                })

            # 2. Audio/Video media input → v2 media rendition
            if payload.get("media_path") and Path(payload["media_path"]).is_file():
                media_path = Path(payload["media_path"])
                media_bytes = media_path.read_bytes()
                media_type = payload.get("media_type") or detect_media_type(media_path.name)
                digest = sha256_of_bytes(media_bytes)
                available_renditions.append({
                    "kind": "media",
                    "rendition_id": digest,
                    "media_kind": "audio" if media_type.startswith("audio/") else "video",
                    "media_type": media_type,
                    "fingerprint": digest,
                    "blob": {
                        "digest": digest,
                        "size_bytes": len(media_bytes),
                        "path": str(media_path.resolve()),
                    },
                })

            # 3. Build the canonical v2 capability-request document.
            material_id = str(req_meta.get("material_id") or "").strip()
            title = str(req_meta.get("title") or "").strip()
            req_data = {
                "schema": CAPABILITY_REQUEST_SCHEMA,
                "version": REQUEST_VERSION,
                "created_at_ms": created_at_ms,
                "material": {
                    "material_id": material_id,
                    "material_revision_id": str(
                        req_meta.get("material_revision_id") or f"rev-{created_at_ms}"
                    ),
                    "title": title,
                },
                "edition": {
                    "edition_id": str(
                        req_meta.get("edition_id") or f"ed-{material_id or 'material'}"
                    ),
                    "title": title,
                    "target_language": str(req_meta.get("target_language") or "en-US"),
                    "support_languages": list(req_meta.get("support_languages") or []),
                },
                "requested_capability": req_meta.get("requested_capability"),
                "available_renditions": available_renditions,
                "available_resources": list(req_meta.get("available_resources") or []),
                "extensions": {},
            }

            # Structured pre-flight validation with per-field feedback.
            problems = _validate_produce_payload(req_data, payload)
            if problems:
                self._send_json(
                    {
                        "error": "请求校验未通过",
                        "errors": problems,
                    },
                    status=400,
                )
                return

            req = CapabilityRequest.from_document(req_data)
        except Exception as exc:
            self._send_error_json(f"Invalid capability request: {exc}", 400)
            return

        cfg_data = payload.get("config", load_config())
        subtitle_path = Path(payload["subtitle_path"]) if payload.get("subtitle_path") and Path(payload["subtitle_path"]).is_file() else None

        task = _GLOBAL_TASK_MANAGER.create_task(
            task_id, req_data, output_zip, status="queued", config=cfg_data
        )
        _GLOBAL_TASK_MANAGER.record_event(task_id, {
            "type": "queued",
            "message": "已进入生成队列，等待空闲运行槽位",
        })
        _RUN_SCHEDULER.submit(
            task_id,
            lambda: _run_produce_worker(
                task_id, req, cfg_data, output_zip, subtitle_path
            ),
        )

        self._send_json({
            "task_id": task_id,
            "status": "queued",
            "events_url": f"/api/tasks/{task_id}/events",
            "download_url": f"/api/download/{task_id}",
        })

    def _serve_static(self, path: str) -> None:
        """Serves embedded or disk-based web assets."""
        if path in ("", "/"):
            path = "/index.html"

        assets_dir = Path(__file__).parent / "web_assets"
        target = assets_dir / path.lstrip("/")

        if not target.is_file():
            target = assets_dir / "index.html"

        if not target.is_file():
            self._send_json({"error": "Web assets not found."}, 404)
            return

        content_type, _ = mimetypes.guess_type(str(target))
        content = target.read_bytes()

        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type or "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(content)))
        self.end_headers()
        self.wfile.write(content)


def _run_produce_worker(
    task_id: str,
    request: CapabilityRequest,
    config_dict: dict[str, Any],
    output_path: Path,
    subtitle_path: Path | None = None,
    run_dir: Path | None = None,
) -> None:
    """Worker function running produce in a background thread.

    Emits the full v2 machine protocol (protocol → accepted → planned →
    running/warning… → completed|cancelled|failed) plus a task-level
    ``terminal`` event that drives the GUI monitor.  Cancellation is honored
    between derivation stages via ``check_cancelled``.  ``run_dir`` (the
    staging directory holding ephemeral text inputs) is removed when the run
    finishes or aborts.
    """
    record = _TaskEventSink(task_id)
    emitter = MachineEventV2Emitter(record)  # type: ignore[arg-type]
    task_mgr = _GLOBAL_TASK_MANAGER

    def check_cancelled() -> None:
        task_mgr.check_cancelled(task_id)

    def progress(stage: str) -> None:
        check_cancelled()
        emitter.running(stage)

    try:
        emitter.protocol(protocol_capabilities_v2())
    except Exception:
        # A second attempt against the same task should never happen.
        task_mgr.complete_task(task_id, success=False, error="internal task error")
        if run_dir:
            shutil.rmtree(run_dir, ignore_errors=True)
        return

    try:
        emitter.accepted(request.attempt_id or _default_attempt_id(request))
        production_plan = plan_request(request)
        emitter.planned(production_plan.describe())

        # 1. TTS Adapter
        tts_cfg = config_dict.get("tts", {})
        tts_adapter = None
        tts_provider = tts_cfg.get("provider", "none")
        if tts_provider == "kokoro":
            from .tts import KokoroTtsAdapter
            tts_adapter = KokoroTtsAdapter(
                voice=tts_cfg.get("voice", "af_bella"),
                speed=float(tts_cfg.get("speed", 1.0)),
                lang_code=tts_cfg.get("lang_code", "a"),
                afconvert_executable=tts_cfg.get("afconvert_executable", "afconvert"),
                timeout_seconds=float(tts_cfg.get("timeout_seconds", 600.0)),
            )
        elif tts_provider == "say" and sys.platform == "darwin":
            from .tts import SayTtsAdapter
            tts_adapter = SayTtsAdapter(
                voice=tts_cfg.get("voice") or None,
                say_executable=tts_cfg.get("say_executable", "say"),
                afconvert_executable=tts_cfg.get("afconvert_executable", "afconvert"),
                timeout_seconds=float(tts_cfg.get("timeout_seconds", 600.0)),
            )
        elif tts_provider == "fake":
            from .tts import FakeTtsAdapter
            tts_adapter = FakeTtsAdapter()

        # 1b. OCR Provider (for scanned PDF document extraction)
        ocr_cfg = config_dict.get("ocr", {})
        ocr_adapter = None
        ocr_provider = ocr_cfg.get("provider", "none")
        if ocr_provider == "surya":
            from .document import SuryaOcrProvider
            langs = [item.strip() for item in ocr_cfg.get("langs", "en,zh").split(",") if item.strip()]
            ocr_adapter = SuryaOcrProvider(
                langs=langs,
                device=ocr_cfg.get("device") or None,
            )
        elif ocr_provider == "rapidocr":
            from .document import RapidOcrProvider
            ocr_adapter = RapidOcrProvider()

        # 2. ASR Adapter (for media or audio derivations)
        asr_adapter = None
        asr_preprocessor = None
        asr_cfg = config_dict.get("asr", {})
        if asr_cfg.get("provider") == "whisper-cpp" and asr_cfg.get("whisper_model"):
            from .media import FfmpegAudioPreprocessor
            from .asr import PreprocessingAsrAdapter
            from .whisper_cpp import WhisperCppAsrAdapter

            whisper_adapter = WhisperCppAsrAdapter(
                asr_cfg.get("whisper_cli", "whisper-cli"),
                Path(asr_cfg["whisper_model"]),
                asr_cfg.get("whisper_model_id", "ggml-model"),
                asr_cfg.get("whisper_language", "auto"),
                asr_cfg.get("whisper_translate_to_english", False),
                float(asr_cfg.get("timeout_seconds", 3600.0)),
            )
            asr_preprocessor = FfmpegAudioPreprocessor(
                timeout_seconds=300.0,
                progress=progress,
            )
            asr_adapter = PreprocessingAsrAdapter(
                whisper_adapter,
                asr_preprocessor,
                progress=progress,
            )

        # 3. Rich stages (Sense groups, Phones, Aligner)
        sense_groups_adapter = None
        selected_llm_key = config_dict.get("selected_llm", "deepseek")
        llm_profiles = config_dict.get("llm_profiles", {})
        llm_profile_dict = llm_profiles.get(selected_llm_key)

        if config_dict.get("enable_sense_groups", True):
            if llm_profile_dict and llm_profile_dict.get("api_key"):
                from .sense_groups import LlmSenseGroupAnalyzer
                prof = LlmProviderProfile.from_dict(llm_profile_dict)
                sense_groups_adapter = LlmSenseGroupAnalyzer(
                    adapter_kind=prof.adapter_kind.value,
                    base_url=prof.base_url,
                    api_key=prof.api_key,
                    model=prof.model_id,
                    timeout_seconds=prof.timeout_seconds,
                    concurrency=int(llm_profile_dict.get("concurrency", 50)),
                )
            else:
                from .rich_baselines import PunctuationSenseGroupBaseline
                sense_groups_adapter = PunctuationSenseGroupBaseline()

        phone_adapter = None
        phone_cfg = config_dict.get("phones", {})
        if config_dict.get("enable_phones", False) and phone_cfg.get("provider") == "wav2vec2":
            from .phone import Wav2Vec2CtcPhoneAdapter
            if phone_cfg.get("wav2vec2_sidecar") and Path(phone_cfg["wav2vec2_sidecar"]).is_file():
                phone_adapter = Wav2Vec2CtcPhoneAdapter(
                    Path(phone_cfg.get("wav2vec2_python", sys.executable)),
                    Path(phone_cfg["wav2vec2_sidecar"]),
                    Path(phone_cfg.get("wav2vec2_model_dir", "")),
                    phone_cfg.get("wav2vec2_model_id", "facebook/wav2vec2-base-960h"),
                    phone_cfg.get("wav2vec2_model_revision", "main"),
                    float(phone_cfg.get("timeout_seconds", 600.0)),
                )

        aligner_adapter = None
        aligner_cfg = config_dict.get("aligner", {})
        if aligner_cfg.get("provider") == "torchaudio" and aligner_cfg.get("aligner_script"):
            from .align import TorchaudioAlignAdapter
            aligner_adapter = TorchaudioAlignAdapter(
                Path(aligner_cfg.get("aligner_python", sys.executable)),
                Path(aligner_cfg["aligner_script"]),
                float(aligner_cfg.get("timeout_seconds", 600.0)),
            )

        rich = RichStages(
            sense_groups=sense_groups_adapter,
            phone=phone_adapter,
            aligner=aligner_adapter,
        )

        produce_cfg = ProduceConfig(
            tts=tts_adapter,
            ocr=ocr_adapter,
            asr=asr_adapter,
            asr_preprocessor=asr_preprocessor,
            rich=rich,
            subtitle=subtitle_path,
        )

        outcome = produce(
            request,
            output_path,
            config=produce_cfg,
            progress=progress,
            check_cancelled=check_cancelled,
        )

        for w in outcome.warnings:
            emitter.warning(w.get("code", "warning"), w.get("message", ""))

        if outcome.release:
            release = outcome.release
            emitter.completed(
                package_sha256=(
                    f"sha256:{outcome.package_sha256}" if outcome.package_sha256 else None
                ),
                document_renditions=[
                    {"rendition_id": e.rendition_id, "origin": e.origin}
                    for e in release.document_renditions
                ],
                media_renditions=[
                    {"rendition_id": e.rendition_id, "origin": e.origin}
                    for e in release.media_renditions
                ],
                resources=[
                    {"resource_id": e.resource_id, "kind": e.kind}
                    for e in release.resources
                ],
                warnings=list(outcome.warnings),
            )
            task_mgr.complete_task(task_id, success=True)
        else:
            task_mgr.complete_task(
                task_id, success=False, error="produce completed without a release"
            )
    except CancellationRequested:
        try:
            emitter.cancelled()
        except Exception:
            pass
        task_mgr.complete_task(
            task_id, success=False, status="cancelled", error="cancelled by user"
        )
    except Exception as exc:
        code, _ = _classify_error(exc)
        try:
            emitter.failed(code=code, message=str(exc))
        except Exception:
            pass
        task_mgr.complete_task(task_id, success=False, error=str(exc))
    finally:
        if run_dir:
            shutil.rmtree(run_dir, ignore_errors=True)


def run_gui_server(
    host: str = "127.0.0.1",
    port: int = 8420,
    open_browser: bool = True,
) -> None:
    """Starts the GUI HTTP server and optionally launches default web browser."""
    pruned = _prune_uploads()
    if pruned:
        print(f"  Pruned {pruned} stale upload/source file(s)")
    server = ThreadingHTTPServer((host, port), GuiRequestHandler)
    url = f"http://{host}:{port}"
    print(f"\n=======================================================")
    print(f"  Listen Gen GUI running at: {url}")
    print(f"  Press Ctrl+C to stop.")
    print(f"=======================================================\n")

    if open_browser:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping GUI server...")
    finally:
        server.server_close()
