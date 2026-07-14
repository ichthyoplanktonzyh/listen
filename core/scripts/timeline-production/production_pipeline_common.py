from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path
from typing import Any

def now_ms() -> int:
    return int(time.time() * 1000)


def stable_id(namespace: str, value: str) -> str:
    return hashlib.sha256(f"{namespace}:{value}".encode("utf-8")).hexdigest()


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def active_word_timeline(document: dict[str, Any]) -> dict[str, Any] | None:
    timelines = document.get("word_timelines") or []
    active_id = document.get("active_word_timeline_id")
    if active_id:
        for timeline in timelines:
            if isinstance(timeline, dict) and timeline.get("id") == active_id:
                return timeline
    for timeline in timelines:
        if isinstance(timeline, dict) and timeline.get("status") == "active":
            return timeline
    return timelines[0] if timelines and isinstance(timelines[0], dict) else None


