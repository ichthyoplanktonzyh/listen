#!/usr/bin/env python3
"""Deterministic fake for the macOS `say` CLI used by adapter tests."""
import struct
import sys
from pathlib import Path

output = None
args = sys.argv[1:]
while args:
    if args[0] == "-o":
        output = args[1]
        args = args[2:]
    elif args[0] in ("-f", "-v"):
        args = args[2:]
    else:
        args = args[1:]
if output is None:
    raise SystemExit(2)

sample_rate = 16000
data_size = sample_rate * 2
header = b"RIFF" + struct.pack("<I", 36 + data_size) + b"WAVE"
header += b"fmt " + struct.pack(
    "<IHHIIHH", 16, 1, 1, sample_rate, sample_rate * 2, 2, 16
)
header += b"data" + struct.pack("<I", data_size)
Path(output).write_bytes(header + b"\x00" * data_size)
