#!/usr/bin/env python3
"""Local browser GUI for the LLTimeline production pipeline."""

from __future__ import annotations

import hashlib
import html
import json
import os
import shlex
import signal
import subprocess
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


REPO_ROOT = Path(__file__).resolve().parents[2]
PIPELINE = Path(__file__).with_name("production_pipeline.py")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def default_whisperx_bin() -> Path:
    production_root = Path(
        os.environ.get(
            "LLPLAYERNEXT_TIMELINE_PRODUCTION_DIR",
            str(Path.home() / "Library/Caches/LLPlayerNext/research/timeline-production"),
        )
    )
    return production_root / "venv" / "bin" / "whisperx"


def default_output_dir(input_path: Path) -> Path:
    return REPO_ROOT / ".tmp" / "timeline-production-gui" / (input_path.stem or "media")


def default_output_path(input_path: Path, output_dir: Path) -> Path:
    return output_dir / f"{input_path.stem or 'timeline'}.lltimeline.json"


def quote_command(command: list[str]) -> str:
    return " ".join(shlex.quote(part) for part in command)


def _force_kill_group(pgid: int, process: subprocess.Popen[str]) -> None:
    """Escalate to SIGKILL for the whole process group if still alive."""
    try:
        if process.poll() is None:
            try:
                os.killpg(pgid, signal.SIGKILL)
            except ProcessLookupError:
                pass
    except Exception:
        pass


def applescript(script: str) -> str:
    result = subprocess.run(
        ["osascript", "-e", script],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout.strip()


def choose_media_file() -> str:
    return applescript(
        'POSIX path of (choose file with prompt "Select media file" '
        'of type {"mp4", "mkv", "mov", "webm", "m4a", "mp3", "wav", "flac"})'
    )


def choose_folder(prompt: str) -> str:
    escaped = prompt.replace('"', '\\"')
    return applescript(f'POSIX path of (choose folder with prompt "{escaped}")')


class PipelineState:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.logs: list[str] = []
        self.process: subprocess.Popen[str] | None = None
        self.running = False
        self.exit_code: int | None = None
        self.last_command: list[str] = []
        self.cancelled = False
        detected = default_whisperx_bin()
        self.detected_whisperx = str(detected) if detected.exists() else ""

    def append_log(self, text: str) -> None:
        with self.lock:
            self.logs.append(text)
            if len(self.logs) > 4000:
                self.logs = self.logs[-4000:]

    def snapshot(self) -> dict[str, Any]:
        with self.lock:
            return {
                "running": self.running,
                "exit_code": self.exit_code,
                "log": "".join(self.logs),
                "last_command": quote_command(self.last_command) if self.last_command else "",
                "detected_whisperx": self.detected_whisperx,
            }

    def start(self, command: list[str]) -> None:
        with self.lock:
            if self.running:
                raise RuntimeError("pipeline is already running")
            self.logs = ["$ " + quote_command(command) + "\n\n"]
            self.last_command = command
            self.exit_code = None
            self.running = True
        threading.Thread(target=self._run, args=(command,), daemon=True).start()

    def _run(self, command: list[str]) -> None:
        try:
            # start_new_session puts the pipeline and every descendant (whisperx,
            # ffmpeg, MFA, ...) into one process group so cancel() can reap them
            # all instead of orphaning the heavy worker.
            process = subprocess.Popen(
                command,
                cwd=REPO_ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                start_new_session=True,
            )
            with self.lock:
                self.process = process
                self.cancelled = False
            assert process.stdout is not None
            for line in process.stdout:
                self.append_log(line)
            code = process.wait()
        except Exception as error:  # pragma: no cover - surfaced through browser UI
            self.append_log(f"Run failed: {error}\n")
            code = -1
        finally:
            with self.lock:
                self.process = None
                self.running = False
                if self.cancelled and code is None:
                    code = 130  # cancelled, mirror SIGINT exit convention
                self.exit_code = code
            self.append_log(f"\nProcess exited with code {code}\n")

    def cancel(self) -> bool:
        """Terminate the pipeline and all of its child processes.

        Returns True if a running process was signalled.
        """
        with self.lock:
            process = self.process
            if not process or process.poll() is not None or not self.running:
                return False
            self.cancelled = True
            pgid = process.pid
        try:
            # SIGTERM the whole process group first (graceful), then escalate to
            # SIGKILL after a short grace period so stubborn workers (whisperx on
            # CPU/GPU) cannot keep burning resources after the GUI reports cancel.
            os.killpg(pgid, signal.SIGTERM)
        except ProcessLookupError:
            return False
        except Exception:
            try:
                process.terminate()
            except Exception:
                pass
            return True

        # Wait briefly for graceful shutdown; force-kill the group if still alive.
        threading.Timer(
            3.0,
            lambda: _force_kill_group(pgid, process),
        ).start()
        return True


STATE = PipelineState()


def build_command(payload: dict[str, Any], *, resolve_fingerprint: bool = False) -> list[str]:
    input_path = Path(require_text(payload, "input_path", "media file")).expanduser()
    output_dir = Path(require_text(payload, "output_dir", "output directory")).expanduser()
    output_path = Path(require_text(payload, "output_path", "LLTimeline output")).expanduser()
    media_title = require_text(payload, "media_title", "media title")
    fingerprint = str(payload.get("media_fingerprint") or "").strip()
    if resolve_fingerprint and not fingerprint:
        # Real production run: the SHA256 is written into the LLTimeline output,
        # so compute the true value (acceptable cost; the run is long anyway).
        fingerprint = file_sha256(input_path)
    elif not fingerprint:
        # Preview only: never block the HTTP worker hashing a multi-GB file.
        fingerprint = _placeholder_fingerprint(input_path)
    command = [
        sys.executable,
        str(PIPELINE),
        "produce-whisperx",
        "--input",
        str(input_path),
        "--output-dir",
        str(output_dir),
        "--output",
        str(output_path),
        "--media-fingerprint",
        fingerprint,
        "--media-title",
        media_title,
        "--media-path",
        str(input_path),
        "--language",
        str(payload.get("language") or "en").strip() or "en",
        "--model",
        str(payload.get("model") or "large-v3").strip() or "large-v3",
        "--device",
        str(payload.get("device") or "cpu").strip() or "cpu",
        "--compute-type",
        str(payload.get("compute_type") or "float32").strip() or "float32",
        "--batch-size",
        str(int(payload.get("batch_size") or 16)),
        "--post-aligner",
        str(payload.get("post_aligner") or "auto").strip() or "auto",
    ]
    append_optional(command, "--whisperx-bin", payload.get("whisperx_bin"))
    append_optional(command, "--whisperx-command", payload.get("whisperx_command"))
    append_optional(command, "--vocal-isolation-command", payload.get("vocal_isolation_command"))
    if bool(payload.get("dry_run")):
        command.append("--dry-run")
    return command


def _placeholder_fingerprint(input_path: Path) -> str:
    """Cheap, never-blocking placeholder for previewing commands.

    Previewing the command should be instant even for multi-GB media. Computing
    the real SHA256 here would block the HTTP worker for seconds; the real
    fingerprint is computed once via the explicit /fingerprint endpoint (or by
    the pipeline itself at production time), so for preview we substitute a
    stable 64-hex placeholder derived from the path.
    """
    return "preview" + hashlib.sha256(str(input_path).encode("utf-8")).hexdigest()[:57]


def require_text(payload: dict[str, Any], key: str, label: str) -> str:
    value = str(payload.get(key) or "").strip()
    if not value:
        raise ValueError(f"{label} is required")
    return value


def append_optional(command: list[str], flag: str, value: Any) -> None:
    text = str(value or "").strip()
    if text:
        command.extend([flag, text])


class Handler(BaseHTTPRequestHandler):
    server_version = "LLTimelineProductionGUI/1.0"

    def do_GET(self) -> None:
        path = urlparse(self.path).path
        if path == "/":
            self.send_html(INDEX_HTML)
        elif path == "/state":
            self.send_json(STATE.snapshot())
        else:
            self.send_error(404)

    def do_POST(self) -> None:
        path = urlparse(self.path).path
        try:
            if path == "/browse":
                self.send_json(self.handle_browse(self.read_json()))
            elif path == "/fingerprint":
                payload = self.read_json()
                media = Path(require_text(payload, "input_path", "media file")).expanduser()
                self.send_json({"fingerprint": file_sha256(media)})
            elif path == "/command":
                self.send_json({"command": quote_command(build_command(self.read_json()))})
            elif path == "/run":
                command = build_command(self.read_json(), resolve_fingerprint=True)
                output_dir = next(command[i + 1] for i, flag in enumerate(command) if flag == "--output-dir")
                Path(output_dir).mkdir(parents=True, exist_ok=True)
                STATE.start(command)
                self.send_json({"ok": True})
            elif path == "/cancel":
                STATE.cancel()
                self.send_json({"ok": True})
            else:
                self.send_error(404)
        except subprocess.CalledProcessError as error:
            self.send_json({"error": error.stderr.strip() or str(error)}, status=400)
        except Exception as error:
            self.send_json({"error": str(error)}, status=400)

    def handle_browse(self, payload: dict[str, Any]) -> dict[str, Any]:
        kind = payload.get("kind")
        if kind == "media":
            media = Path(choose_media_file())
            output_dir = default_output_dir(media)
            return {
                "path": str(media),
                "media_title": media.stem,
                "output_dir": str(output_dir),
                "output_path": str(default_output_path(media, output_dir)),
            }
        if kind == "output_dir":
            return {"path": choose_folder("Select output directory").rstrip("/")}
        if kind == "output_path_dir":
            folder = Path(choose_folder("Select LLTimeline output folder").rstrip("/"))
            current = Path(str(payload.get("output_path") or "timeline.lltimeline.json"))
            filename = current.name if current.name else "timeline.lltimeline.json"
            return {"path": str(folder / filename)}
        raise ValueError("unknown browse kind")

    def read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("content-length") or 0)
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length).decode("utf-8"))

    def send_json(self, payload: dict[str, Any], status: int = 200) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_html(self, body: str) -> None:
        data = body.encode("utf-8")
        self.send_response(200)
        self.send_header("content-type", "text/html; charset=utf-8")
        self.send_header("content-length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args: Any) -> None:
        return


def _aligner_options_html() -> str:
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    try:
        from aligners import all_aligners
        return "".join(f'<option>{a["name"]}</option>' for a in all_aligners())
    except Exception:
        return "<option>mfa</option><option>mms-fa</option>"


INDEX_HTML = r"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>LLTimeline Production</title>
  <style>
    :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; background: #10151b; color: #e6edf3; }
    main { max-width: 1120px; margin: 0 auto; padding: 24px; }
    h1 { font-size: 22px; margin: 0 0 16px; }
    section { border: 1px solid #26313c; border-radius: 8px; padding: 16px; margin-bottom: 14px; background: #151c24; }
    .grid { display: grid; grid-template-columns: 160px 1fr auto; gap: 10px; align-items: center; }
    .options { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }
    label { color: #aebccd; font-size: 13px; }
    input, select { width: 100%; box-sizing: border-box; background: #0d1117; color: #e6edf3; border: 1px solid #344252; border-radius: 6px; padding: 8px; }
    button { background: #2b7cff; color: white; border: 0; border-radius: 6px; padding: 8px 12px; cursor: pointer; }
    button.secondary { background: #26313c; }
    button.danger { background: #a63d40; }
    button:disabled { opacity: 0.45; cursor: default; }
    .actions { display: flex; gap: 10px; align-items: center; justify-content: flex-end; }
    .status { margin-right: auto; color: #aebccd; }
    pre { min-height: 260px; max-height: 420px; overflow: auto; background: #070a0f; border: 1px solid #26313c; border-radius: 8px; padding: 12px; white-space: pre-wrap; }
    .hint { color: #8fa1b3; font-size: 13px; margin-top: 8px; }
  </style>
</head>
<body>
<main>
  <h1>LLTimeline Production</h1>
  <section>
    <div class="grid">
      <label>Media file</label><input id="input_path"><button onclick="browseMedia()">Browse</button>
      <label>Output dir</label><input id="output_dir"><button onclick="browseOutputDir()">Browse</button>
      <label>LLTimeline output</label><input id="output_path"><button onclick="browseOutputPathDir()">Choose folder</button>
      <label>Media title</label><input id="media_title"><span></span>
      <label>Media fingerprint</label><input id="media_fingerprint"><button onclick="computeFingerprint()">Compute SHA256</button>
    </div>
    <div class="hint">The output path is editable. The button chooses the folder and keeps the filename from this field.</div>
  </section>
  <section class="options">
    <label>Post-aligner<select id="post_aligner"><option>auto</option>""" + _aligner_options_html() + r"""<option>none</option></select></label>
    <label>Device<select id="device"><option>cpu</option><option>cuda</option><option>mps</option></select></label>
    <label>Compute type<select id="compute_type"><option>float32</option><option>float16</option><option>int8</option></select></label>
    <label>Batch size<input id="batch_size" type="number" min="1" max="128" value="16"></label>
    <label>Language<input id="language" value="en"></label>
    <label>Model<input id="model" value="large-v3"></label>
    <label>WhisperX bin<input id="whisperx_bin"></label>
    <label>Dry run<input id="dry_run" type="checkbox"></label>
    <label style="grid-column: 1 / span 2;">WhisperX command<input id="whisperx_command"></label>
    <label style="grid-column: 3 / span 2;">Vocal isolation command<input id="vocal_isolation_command"></label>
  </section>
  <section>
    <div class="actions">
      <span id="status" class="status">Ready</span>
      <button class="secondary" onclick="copyCommand()">Copy command</button>
      <button class="secondary" onclick="previewCommand()">Preview command</button>
      <button id="cancel" class="danger" onclick="cancelRun()" disabled>Cancel</button>
      <button id="run" onclick="runPipeline()">Run</button>
    </div>
    <pre id="log"></pre>
  </section>
</main>
<script>
const ids = ["input_path","output_dir","output_path","media_title","media_fingerprint","language","model","device","compute_type","batch_size","post_aligner","whisperx_bin","whisperx_command","vocal_isolation_command","dry_run"];
const $ = (id) => document.getElementById(id);

function payload() {
  const value = {};
  for (const id of ids) {
    const el = $(id);
    value[id] = el.type === "checkbox" ? el.checked : el.value;
  }
  return value;
}

async function post(path, body = {}) {
  const response = await fetch(path, {method: "POST", headers: {"content-type": "application/json"}, body: JSON.stringify(body)});
  const data = await response.json();
  if (!response.ok || data.error) throw new Error(data.error || response.statusText);
  return data;
}

async function browseMedia() {
  try {
    const data = await post("/browse", {kind: "media"});
    $("input_path").value = data.path;
    if (!$("media_title").value) $("media_title").value = data.media_title;
    if (!$("output_dir").value) $("output_dir").value = data.output_dir;
    if (!$("output_path").value) $("output_path").value = data.output_path;
  } catch (error) { alert(error.message); }
}

async function browseOutputDir() {
  try {
    const data = await post("/browse", {kind: "output_dir"});
    $("output_dir").value = data.path;
  } catch (error) { alert(error.message); }
}

async function browseOutputPathDir() {
  try {
    const data = await post("/browse", {kind: "output_path_dir", output_path: $("output_path").value});
    $("output_path").value = data.path;
  } catch (error) { alert(error.message); }
}

async function computeFingerprint() {
  $("status").textContent = "Computing fingerprint...";
  try {
    const data = await post("/fingerprint", payload());
    $("media_fingerprint").value = data.fingerprint;
    $("status").textContent = "Fingerprint ready";
  } catch (error) { $("status").textContent = "Error"; alert(error.message); }
}

let previewing = false;

async function previewCommand() {
  try {
    const data = await post("/command", payload());
    previewing = true;
    $("log").textContent = "$ " + data.command + "\n";
    $("status").textContent = "Preview";
  } catch (error) { alert(error.message); }
}

async function copyCommand() {
  const data = await post("/command", payload());
  await navigator.clipboard.writeText(data.command);
  $("status").textContent = "Command copied";
}

async function runPipeline() {
  try {
    await post("/run", payload());
    $("status").textContent = "Running...";
  } catch (error) { alert(error.message); }
}

async function cancelRun() {
  await post("/cancel", {});
  $("status").textContent = "Cancelling...";
}

async function poll() {
  const response = await fetch("/state");
  const data = await response.json();
  // A fresh preview should survive until the next run: while the user is
  // inspecting a preview (not running), keep it on screen instead of letting
  // the stale server log overwrite it every 900ms.
  if (data.running || !previewing) {
    $("log").textContent = data.log || "";
  }
  if (data.running) previewing = false;
  $("run").disabled = data.running;
  $("cancel").disabled = !data.running;
  if (data.running) $("status").textContent = "Running...";
  else if (data.exit_code !== null) $("status").textContent = data.exit_code === 0 ? "Completed" : "Failed: " + data.exit_code;
  if (!$("whisperx_bin").value && data.detected_whisperx) $("whisperx_bin").value = data.detected_whisperx;
  setTimeout(poll, 900);
}
poll();
</script>
</body>
</html>
"""


def main() -> int:
    # Ensure the URL line is flushed immediately even when stdout is redirected
    # to a pipe/file (block buffering would otherwise hide the port).
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(line_buffering=True)  # type: ignore[attr-defined]
        except Exception:
            pass
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    host, port = server.server_address
    url = f"http://{host}:{port}/"
    print(f"LLTimeline production GUI: {url}", flush=True)
    threading.Timer(0.25, lambda: webbrowser.open(url)).start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        STATE.cancel()
        return 130
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
