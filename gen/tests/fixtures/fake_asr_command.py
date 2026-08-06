from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path


def main() -> int:
    mode = sys.argv[1]
    media_path = Path(sys.argv[2])
    fixture_path = Path(sys.argv[3])
    observation_path = Path(sys.argv[4])
    observation_path.write_text(str(media_path), encoding="utf-8")
    if mode == "fail":
        print("provider-secret-must-not-leak", file=sys.stderr)
        print('{"raw_response":"must-not-leak"}')
        return 23
    if mode == "sleep":
        time.sleep(2)
        return 0
    if mode == "hang":
        observation_path.write_text(
            json.dumps({"media_path": str(media_path), "pid": os.getpid()}),
            encoding="utf-8",
        )
        while True:
            time.sleep(3600)
    if mode == "invalid-json":
        print('{"provider_raw":"must-not-leak-invalid-json"')
        return 0
    if mode == "flood":
        sys.stdout.buffer.write(b"x" * (17 * 1024 * 1024))
        return 0
    if mode == "spawn-child":
        child_marker = observation_path.with_suffix(".child")
        subprocess.Popen([
            sys.executable,
            "-c",
            "import pathlib,sys,time; time.sleep(0.4); pathlib.Path(sys.argv[1]).write_text('leaked')",
            str(child_marker),
        ])
        time.sleep(2)
        return 0
    value = json.loads(fixture_path.read_text(encoding="utf-8"))
    print(json.dumps(value, ensure_ascii=False, sort_keys=True))
    return 0


raise SystemExit(main())
