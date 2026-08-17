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
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request
import webbrowser
from dataclasses import asdict, dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable

from . import __version__ as TOOL_VERSION
from .capability import (
    AvailableDocumentRendition,
    AvailableMediaRendition,
    CapabilityRequest,
    EditionIdentity,
    MaterialIdentity,
)
from .llm_client import (
    LlmAdapterKind,
    LlmProviderProfile,
    create_llm_client,
)
from .package_v3 import sha256_of_bytes
from .produce import ProduceConfig, produce
from .protocol_v2 import MachineEventV2Emitter
from .rich_stages import RichStages

DEFAULT_CONFIG_DIR = Path.home() / ".listen-gen"
DEFAULT_CONFIG_FILE = DEFAULT_CONFIG_DIR / "profiles.json"
UPLOAD_DIR = DEFAULT_CONFIG_DIR / "uploads"


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
            "provider": "say" if sys.platform == "darwin" else "none",
            "voice": "",
            "say_executable": "say",
            "afconvert_executable": "afconvert",
            "timeout_seconds": 600.0,
        },
        "syntax": {
            "backend": "spacy",
            "model": "en_core_web_sm",
        },
    }


def load_config(path: Path = DEFAULT_CONFIG_FILE) -> dict[str, Any]:
    """Loads configuration from file, falling back to defaults."""
    default = get_default_config()
    if not path.is_file():
        return default
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        for key, value in default.items():
            if key not in data:
                data[key] = value
            elif isinstance(value, dict) and isinstance(data[key], dict):
                for sub_key, sub_value in value.items():
                    if sub_key not in data[key]:
                        data[key][sub_key] = sub_value
        return data
    except Exception:
        return default


def save_config(config: dict[str, Any], path: Path = DEFAULT_CONFIG_FILE) -> None:
    """Saves configuration to file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config, indent=2, ensure_ascii=False), encoding="utf-8")


@dataclass
class GenerationTask:
    task_id: str
    created_at: float
    status: str  # "running", "completed", "failed"
    request_doc: dict[str, Any]
    output_path: Path
    events: list[dict[str, Any]]
    error: str | None = None
    event_queue: queue.Queue | None = None


class TaskManager:
    """In-memory task manager for background generation jobs."""

    def __init__(self) -> None:
        self.tasks: dict[str, GenerationTask] = {}
        self.lock = threading.Lock()

    def create_task(self, task_id: str, request_doc: dict[str, Any], output_path: Path) -> GenerationTask:
        task = GenerationTask(
            task_id=task_id,
            created_at=time.time(),
            status="running",
            request_doc=request_doc,
            output_path=output_path,
            events=[],
            event_queue=queue.Queue(),
        )
        with self.lock:
            self.tasks[task_id] = task
        return task

    def get_task(self, task_id: str) -> GenerationTask | None:
        with self.lock:
            return self.tasks.get(task_id)

    def record_event(self, task_id: str, event: dict[str, Any]) -> None:
        task = self.get_task(task_id)
        if task:
            task.events.append(event)
            if task.event_queue:
                task.event_queue.put(event)

    def complete_task(self, task_id: str, success: bool, error: str | None = None) -> None:
        task = self.get_task(task_id)
        if task:
            task.status = "completed" if success else "failed"
            task.error = error
            terminal_event = {
                "type": "terminal",
                "status": task.status,
                "error": error,
                "package_path": str(task.output_path) if success else None,
                "timestamp": time.time(),
            }
            task.events.append(terminal_event)
            if task.event_queue:
                task.event_queue.put(terminal_event)


_GLOBAL_TASK_MANAGER = TaskManager()


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

        if path.startswith("/api/tasks/") and path.endswith("/events"):
            task_id = path.split("/")[3]
            task = _GLOBAL_TASK_MANAGER.get_task(task_id)
            if not task:
                self._send_error_json("Task not found", 404)
                return

            self.send_response(HTTPStatus.OK)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()

            for event in list(task.events):
                data = f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
                self.wfile.write(data.encode("utf-8"))
            self.wfile.flush()

            while task.status == "running" or not task.event_queue.empty():
                try:
                    event = task.event_queue.get(timeout=1.0)
                    data = f"data: {json.dumps(event, ensure_ascii=False)}\n\n"
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
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length > 0 else b"{}"

        try:
            data = json.loads(body.decode("utf-8"))
        except Exception:
            data = {}

        if path == "/api/config":
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
            self._handle_upload(data)
            return

        if path == "/api/inspect-file":
            self._handle_inspect_file(data)
            return

        if path == "/api/produce":
            self._handle_produce(data)
            return

        self._send_error_json("Endpoint not found", 404)

    def _handle_upload(self, data: dict[str, Any]) -> None:
        """Handles local file upload via base64 encoded content."""
        filename = data.get("filename")
        content_b64 = data.get("content_base64")
        if not filename or not content_b64:
            self._send_error_json("Missing filename or content_base64", 400)
            return

        try:
            UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
            safe_name = os.path.basename(filename)
            target_path = UPLOAD_DIR / safe_name
            raw_bytes = base64.b64decode(content_b64)
            target_path.write_bytes(raw_bytes)

            media_type = data.get("type") or detect_media_type(filename)
            digest = sha256_of_bytes(raw_bytes)

            preview_text = None
            if media_type.startswith("text/") or filename.endswith((".md", ".txt", ".json", ".srt", ".vtt")):
                try:
                    preview_text = raw_bytes[:10000].decode("utf-8", errors="replace")
                except Exception:
                    pass

            self._send_json({
                "status": "ok",
                "filename": safe_name,
                "path": str(target_path),
                "size_bytes": len(raw_bytes),
                "media_type": media_type,
                "digest": digest,
                "preview_text": preview_text,
            })
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

    def _handle_produce(self, payload: dict[str, Any]) -> None:
        """Executes a capability generation run asynchronously."""
        task_id = f"task-{int(time.time()*1000)}"
        temp_dir = Path(tempfile.mkdtemp(prefix="listen_gen_run_"))
        output_zip = temp_dir / f"package-{task_id}.zip"

        try:
            req_data = payload.get("request")
            if not req_data:
                self._send_error_json("Missing request document", 400)
                return

            # 1. Document input (from local file or raw text)
            if payload.get("document_path") and Path(payload["document_path"]).is_file():
                doc_path = Path(payload["document_path"])
                doc_bytes = doc_path.read_bytes()
                media_type = payload.get("document_media_type") or detect_media_type(doc_path.name)
                req_data.setdefault("document_renditions", [])
                req_data["document_renditions"] = [
                    {
                        "rendition_id": "doc-0",
                        "media_type": media_type,
                        "digest": sha256_of_bytes(doc_bytes),
                        "path": str(doc_path.resolve()),
                    }
                ]
            elif payload.get("document_text"):
                doc_text = payload["document_text"]
                doc_bytes = doc_text.encode("utf-8")
                doc_file = temp_dir / "input_document.md"
                doc_file.write_bytes(doc_bytes)
                digest = sha256_of_bytes(doc_bytes)

                req_data.setdefault("document_renditions", [])
                req_data["document_renditions"] = [
                    {
                        "rendition_id": "doc-0",
                        "media_type": payload.get("document_media_type", "text/markdown"),
                        "digest": digest,
                        "path": str(doc_file),
                    }
                ]

            # 2. Audio/Video media input
            if payload.get("media_path") and Path(payload["media_path"]).is_file():
                media_path = Path(payload["media_path"])
                media_bytes = media_path.read_bytes()
                media_type = payload.get("media_type") or detect_media_type(media_path.name)
                req_data.setdefault("media_renditions", [])
                req_data["media_renditions"] = [
                    {
                        "rendition_id": "media-0",
                        "media_type": media_type,
                        "digest": sha256_of_bytes(media_bytes),
                        "path": str(media_path.resolve()),
                    }
                ]

            req = CapabilityRequest.from_document(req_data)
        except Exception as exc:
            self._send_error_json(f"Invalid capability request: {exc}", 400)
            return

        task = _GLOBAL_TASK_MANAGER.create_task(task_id, req_data, output_zip)

        cfg_data = payload.get("config", load_config())
        subtitle_path = Path(payload["subtitle_path"]) if payload.get("subtitle_path") and Path(payload["subtitle_path"]).is_file() else None

        thread = threading.Thread(
            target=_run_produce_worker,
            args=(task_id, req, cfg_data, output_zip, subtitle_path),
            daemon=True,
        )
        thread.start()

        self._send_json({
            "task_id": task_id,
            "status": "started",
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
) -> None:
    """Worker function running produce in a background thread and emitting events."""
    emitter = MachineEventV2Emitter(
        lambda event: _GLOBAL_TASK_MANAGER.record_event(task_id, asdict(event)),
        request=request,
    )

    try:
        emitter.emit_started()

        # 1. TTS Adapter
        tts_cfg = config_dict.get("tts", {})
        tts_adapter = None
        tts_provider = tts_cfg.get("provider", "none")
        if tts_provider == "say" and sys.platform == "darwin":
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
                progress=lambda msg: None,
            )
            asr_adapter = PreprocessingAsrAdapter(
                whisper_adapter,
                asr_preprocessor,
                progress=lambda msg: None,
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
            asr=asr_adapter,
            asr_preprocessor=asr_preprocessor,
            rich=rich,
            subtitle=subtitle_path,
        )

        outcome = produce(
            request,
            produce_cfg,
            output=output_path,
            progress=lambda msg: None,
        )

        for w in outcome.warnings:
            emitter.emit_warning(w.get("code", "warning"), w.get("message", ""))

        if outcome.release:
            emitter.emit_committed(
                release_doc=outcome.release.manifest_document,
                package_sha256=outcome.package_sha256,
            )
            emitter.emit_completed(
                package_sha256=outcome.package_sha256,
                artifact_path=output_path,
            )
            _GLOBAL_TASK_MANAGER.complete_task(task_id, success=True)
        else:
            _GLOBAL_TASK_MANAGER.complete_task(task_id, success=False, error="Produce completed without release")
    except Exception as exc:
        emitter.emit_failed(type(exc).__name__, str(exc))
        _GLOBAL_TASK_MANAGER.complete_task(task_id, success=False, error=str(exc))


def run_gui_server(
    host: str = "127.0.0.1",
    port: int = 8420,
    open_browser: bool = True,
) -> None:
    """Starts the GUI HTTP server and optionally launches default web browser."""
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
