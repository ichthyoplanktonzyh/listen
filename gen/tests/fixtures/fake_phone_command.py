#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

mode = os.environ.get("LISTEN_GEN_TEST_PHONE_MODE", "normalized")
observed = os.environ.get("LISTEN_GEN_TEST_PHONE_OBSERVED")
if observed:
    Path(observed).write_text(json.dumps({"pid": os.getpid()}), encoding="utf-8")
if mode == "hang":
    while True:
        time.sleep(3600)
elif mode == "sleep":
    time.sleep(3)
elif mode == "fail":
    print("phone-secret-must-not-leak", file=sys.stderr)
    raise SystemExit(23)
elif mode == "invalid":
    print('{"private_path":"/must/not/leak"')
elif mode == "core":
    model_dir = Path(sys.argv[sys.argv.index("--model-dir") + 1])
    if os.environ.get("LISTEN_GEN_TEST_PHONE_MUTATE") == "1":
        (model_dir / "weights.bin").write_bytes(b"changed")
    print(json.dumps({
        "phones": [
            {"symbol": "l", "start_ms": 120, "end_ms": 220, "confidence": 0.9}
        ]
    }, ensure_ascii=False))
else:
    if mode == "mutate-self":
        path = Path(__file__)
        path.write_text(path.read_text(encoding="utf-8") + "\n# mutated\n", encoding="utf-8")
    print((Path(__file__).parent / "phone-result.json").read_text(encoding="utf-8"))
