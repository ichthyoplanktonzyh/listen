#!/usr/bin/env python3
"""Developer utility for LLTimeline JSON v1 resources."""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


SCHEMA = "llplayer.timeline.v1"


def load_document(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as handle:
        document = json.load(handle)
    validate_document(document)
    return document


def validate_document(document: dict[str, Any]) -> None:
    if document.get("schema") != SCHEMA:
        raise SystemExit(f"unsupported LLTimeline schema: {document.get('schema')!r}")
    metadata = require_object(document, "metadata")
    media = require_object(metadata, "media")
    require_text(media, "id")
    require_text(media, "fingerprint")
    require_text(media, "title")
    segments = require_list(document, "segments")
    if not segments:
        raise SystemExit("LLTimeline document must contain at least one segment")
    for segment in segments:
        if not isinstance(segment, dict):
            raise SystemExit("LLTimeline segment must be an object")
        if int(segment.get("end_ms", 0)) <= int(segment.get("start_ms", 0)):
            raise SystemExit("LLTimeline segment end_ms must be greater than start_ms")
        require_list(segment, "tokens")
    for timeline in require_list(document, "word_timelines"):
        if not isinstance(timeline, dict):
            raise SystemExit("word timeline must be an object")
        require_text(timeline, "id")
        previous_end = None
        for word in require_list(timeline, "words"):
            if not isinstance(word, dict):
                raise SystemExit("word timing must be an object")
            start_ms = int(word.get("start_ms", 0))
            end_ms = int(word.get("end_ms", 0))
            if end_ms <= start_ms:
                raise SystemExit("word timing end_ms must be greater than start_ms")
            if previous_end is not None and start_ms < previous_end:
                raise SystemExit("word timing must be monotonic within each timeline")
            previous_end = end_ms


def require_object(parent: dict[str, Any], key: str) -> dict[str, Any]:
    value = parent.get(key)
    if not isinstance(value, dict):
        raise SystemExit(f"missing object field: {key}")
    return value


def require_list(parent: dict[str, Any], key: str) -> list[Any]:
    value = parent.get(key)
    if not isinstance(value, list):
        raise SystemExit(f"missing list field: {key}")
    return value


def require_text(parent: dict[str, Any], key: str) -> str:
    value = parent.get(key)
    if not isinstance(value, str) or not value.strip():
        raise SystemExit(f"missing text field: {key}")
    return value


def api_json(base_url: str, token: str, method: str, path: str, body: Any | None = None) -> Any:
    data = None if body is None else json.dumps(body).encode("utf-8")
    request = urllib.request.Request(
        base_url.rstrip("/") + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        details = error.read().decode("utf-8", errors="replace")
        raise SystemExit(f"API request failed: HTTP {error.code}: {details}") from error
    except urllib.error.URLError as error:
        raise SystemExit(f"API request failed: {error}") from error


def command_validate(args: argparse.Namespace) -> int:
    document = load_document(Path(args.input))
    print(
        json.dumps(
            {
                "schema": document["schema"],
                "segments": len(document["segments"]),
                "word_timelines": len(document["word_timelines"]),
                "active_word_timeline_id": document.get("active_word_timeline_id"),
            },
            sort_keys=True,
        )
    )
    return 0


def command_export(args: argparse.Namespace) -> int:
    document = api_json(
        args.base_url,
        args.token,
        "GET",
        f"/v1/subtitles/{urllib.parse.quote(args.track_id, safe='')}/lltimeline/export",
    )
    validate_document(document)
    output = json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.output:
        Path(args.output).write_text(output, encoding="utf-8")
    else:
        sys.stdout.write(output)
    return 0


def command_import(args: argparse.Namespace) -> int:
    document = load_document(Path(args.input))
    track = api_json(args.base_url, args.token, "POST", "/v1/lltimeline/import", document)
    print(json.dumps({"track_id": track["id"], "sentences": len(track["sentences"])}, sort_keys=True))
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    subcommands = root.add_subparsers(dest="command", required=True)

    validate = subcommands.add_parser("validate", help="validate a local .lltimeline.json file")
    validate.add_argument("input")
    validate.set_defaults(func=command_validate)

    export = subcommands.add_parser("export", help="export a track from the local API")
    export.add_argument("--base-url", default="http://127.0.0.1:4317")
    export.add_argument("--token", default="dev-token")
    export.add_argument("--track-id", required=True)
    export.add_argument("--output")
    export.set_defaults(func=command_export)

    import_ = subcommands.add_parser("import", help="import a .lltimeline.json file through the local API")
    import_.add_argument("--base-url", default="http://127.0.0.1:4317")
    import_.add_argument("--token", default="dev-token")
    import_.add_argument("input")
    import_.set_defaults(func=command_import)
    return root


def main() -> int:
    args = parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
