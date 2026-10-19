#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path


arguments = sys.argv[1:]
media_path = Path(arguments[arguments.index("-i") + 1])
output_path = Path(arguments[-1])
media = json.loads(media_path.read_text(encoding="utf-8"))
observation = os.environ.get("LISTEN_GEN_TEST_FFMPEG_OBSERVATION")
if observation:
    Path(observation).write_text(json.dumps(arguments), encoding="utf-8")
mode = media.get("ffmpeg_mode", "success")
if mode == "sleep":
    time.sleep(2)
elif mode == "fail":
    print("transcode-secret-must-not-leak", file=sys.stderr)
    raise SystemExit(29)
elif mode == "missing":
    pass
else:
    output_path.write_bytes(b"RIFFfake-16khz-mono-pcm")
