#!/usr/bin/env python3
"""Run one or more Phase 2.17 sound-line QA cases through the local API.

The runner consumes `testdata/sound-line-real-media/manifest.jsonl`, reads each
case's local-only `.lltimeline.json` artifact, strips generated PhoneTimeline
resources, imports the baseline through api-http, creates CTC phonetic-analysis
jobs for subtitle sentences, and exports the refreshed LLTimeline back to the
case's `lltimeline.local_path`.

This intentionally keeps generated timelines under ignored `.tmp/` paths rather
than committing local-only derived benchmark/media artifacts.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from collections import deque
from pathlib import Path
from typing import Any, Deque

CTC_MODEL_ID = "wav2vec2-ctc-phoneme:fb-espeak-cv-ft@v1"
ApiLog = Deque[str]


def expand_path(raw: str, repo_root: Path) -> Path:
    path = Path(raw).expanduser()
    if path.is_absolute():
        return path
    return repo_root / path


def load_manifest(path: Path) -> list[dict[str, Any]]:
    return [
        json.loads(line)
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip()
    ]


def http_json(
    method: str,
    base_url: str,
    token: str,
    path: str,
    payload: Any | None = None,
) -> Any:
    data = None
    headers = {"Authorization": f"Bearer {token}"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(
        f"{base_url}{path}",
        data=data,
        headers=headers,
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            body = response.read()
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {path} failed: HTTP {error.code}: {body}") from error
    if not body:
        return None
    return json.loads(body)


def start_api(
    repo_root: Path,
    db_path: Path,
    token: str,
) -> tuple[subprocess.Popen[str], str, ApiLog]:
    cargo = resolve_cargo()
    env = os.environ.copy()
    cargo_dir = str(Path(cargo).parent)
    env["PATH"] = f"{cargo_dir}{os.pathsep}{env.get('PATH', '')}"
    env["LLPLAYERNEXT_DB"] = str(db_path)
    env["LLPLAYERNEXT_API_TOKEN"] = token
    env["RUST_BACKTRACE"] = env.get("RUST_BACKTRACE", "1")
    process = subprocess.Popen(
        [cargo, "run", "--quiet", "-p", "api-http"],
        cwd=repo_root,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None
    deadline = time.time() + 45
    startup_log: list[str] = []
    api_log: ApiLog = deque(maxlen=200)
    while time.time() < deadline:
        line = process.stdout.readline()
        if not line:
            if process.poll() is not None:
                raise RuntimeError(
                    f"api-http exited early with status {process.returncode}\n"
                    + "".join(startup_log[-40:])
                )
            continue
        startup_log.append(line)
        api_log.append(line)
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("event") == "api.started":
            drain_process_output(process, api_log)
            return process, f"http://{event['address']}", api_log
    process.send_signal(signal.SIGINT)
    raise RuntimeError("api-http did not start within 45s")


def drain_process_output(process: subprocess.Popen[str], api_log: ApiLog) -> None:
    def drain() -> None:
        assert process.stdout is not None
        for line in process.stdout:
            api_log.append(line)

    threading.Thread(target=drain, daemon=True).start()


def recent_api_log(api_log: ApiLog) -> str:
    if not api_log:
        return "<no api stdout captured>"
    return "".join(api_log)


def resolve_cargo() -> str:
    candidates = [
        os.environ.get("CARGO"),
        shutil.which("cargo"),
        "/opt/homebrew/opt/rustup/bin/cargo",
        str(Path.home() / ".cargo/bin/cargo"),
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return candidate
    raise RuntimeError("cargo not found")


def stop_api(process: subprocess.Popen[str]) -> None:
    if process.poll() is not None:
        return
    process.send_signal(signal.SIGINT)
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=5)


def baseline_document(document: dict[str, Any]) -> dict[str, Any]:
    value = json.loads(json.dumps(document))
    value["phone_timelines"] = []
    value["active_phone_timeline_id"] = None
    artifacts = value.get("artifacts")
    if isinstance(artifacts, list):
        value["artifacts"] = [
            item for item in artifacts
            if not (
                isinstance(item, dict)
                and "phone" in str(item.get("kind", "")).lower()
            )
        ]
    return value


def register_media(base_url: str, token: str, document: dict[str, Any], case_id: str) -> str:
    media = document.get("metadata", {}).get("media", {})
    media_path = media.get("path")
    if not isinstance(media_path, str) or not media_path:
        raise RuntimeError(f"{case_id}: timeline metadata.media.path is missing")
    if not Path(media_path).expanduser().exists():
        raise RuntimeError(f"{case_id}: media path does not exist: {media_path}")
    response = http_json(
        "POST",
        base_url,
        token,
        "/v1/media",
        {
            "path": media_path,
            "fingerprint": media.get("fingerprint") or f"{case_id}-media",
            "title": media.get("title") or case_id,
            "kind": "audio",
        },
    )
    return response["id"]


def wait_job(base_url: str, token: str, job_id: str, api_log: ApiLog) -> dict[str, Any]:
    deadline = time.time() + 240
    last: dict[str, Any] | None = None
    while time.time() < deadline:
        current = http_json("GET", base_url, token, f"/v1/phonetic-analysis/jobs/{job_id}")
        last = current
        status = current.get("status")
        if status == "completed":
            return current
        if status in {"failed", "cancelled"}:
            raise RuntimeError(
                f"phonetic job {job_id} ended with {status}: {current}\n"
                f"recent api log:\n{recent_api_log(api_log)}"
            )
        time.sleep(0.5)
    raise RuntimeError(
        f"phonetic job {job_id} timed out; last={last}\n"
        f"recent api log:\n{recent_api_log(api_log)}"
    )


def run_case(repo_root: Path, manifest_case: dict[str, Any], sentence_limit: int | None) -> None:
    case_id = manifest_case["case_id"]
    llt = manifest_case["lltimeline"]
    local_path = llt.get("local_path") or llt.get("path")
    if not isinstance(local_path, str) or not local_path:
        raise RuntimeError(f"{case_id}: missing lltimeline.local_path")
    timeline_path = expand_path(local_path, repo_root)
    if not timeline_path.is_file():
        raise RuntimeError(f"{case_id}: local timeline not found: {timeline_path}")

    document = json.loads(timeline_path.read_text(encoding="utf-8"))
    baseline = baseline_document(document)
    token = f"p217-{os.getpid()}"
    with tempfile.TemporaryDirectory(prefix=f"{case_id}-") as tmp:
        db_path = Path(tmp) / "qa.sqlite"
        process, base_url, api_log = start_api(repo_root, db_path, token)
        try:
            media_id = register_media(base_url, token, baseline, case_id)
            track = http_json(
                "POST",
                base_url,
                token,
                f"/v1/media/{media_id}/lltimeline/import?allow_mismatch=true",
                baseline,
            )
            track_id = track["id"]
            sentences = track.get("sentences") or []
            if sentence_limit is not None:
                sentences = sentences[:sentence_limit]
            if not sentences:
                raise RuntimeError(f"{case_id}: imported track has no sentences")
            print(f"{case_id}: imported {len(sentences)} sentence(s)", flush=True)
            for index, sentence in enumerate(sentences, start=1):
                job = http_json(
                    "POST",
                    base_url,
                    token,
                    "/v1/phonetic-analysis/jobs",
                    {
                        "track_id": track_id,
                        "sentence_id": sentence["id"],
                        "model_id": CTC_MODEL_ID,
                    },
                )
                wait_job(base_url, token, job["id"], api_log)
                print(
                    f"{case_id}: phonetic job {index}/{len(sentences)} completed",
                    flush=True,
                )
            exported = http_json(
                "GET",
                base_url,
                token,
                f"/v1/subtitles/{track_id}/lltimeline/export",
            )
            timeline_path.parent.mkdir(parents=True, exist_ok=True)
            timeline_path.write_text(
                json.dumps(exported, ensure_ascii=False, separators=(",", ":")),
                encoding="utf-8",
            )
            print(f"{case_id}: wrote {timeline_path}", flush=True)
        finally:
            stop_api(process)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--manifest",
        default="testdata/sound-line-real-media/manifest.jsonl",
    )
    parser.add_argument("--case-id", action="append", required=True)
    parser.add_argument("--sentence-limit", type=int, default=None)
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    cases = {case["case_id"]: case for case in load_manifest(repo_root / args.manifest)}
    for case_id in args.case_id:
        if case_id not in cases:
            raise SystemExit(f"unknown case_id: {case_id}")
        run_case(repo_root, cases[case_id], args.sentence_limit)
    return 0


if __name__ == "__main__":
    sys.exit(main())
