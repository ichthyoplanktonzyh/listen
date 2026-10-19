#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
import time
from pathlib import Path


media = json.loads(Path(sys.argv[-1]).read_text(encoding="utf-8"))
mode = media.get("probe_mode", "success")
if mode == "sleep":
    time.sleep(2)
elif mode == "fail":
    print("probe-secret-must-not-leak", file=sys.stderr)
    raise SystemExit(19)
elif mode == "invalid":
    print('{"private_path":"/must/not/leak"')
else:
    print(json.dumps({"streams": media["streams"]}, sort_keys=True))
