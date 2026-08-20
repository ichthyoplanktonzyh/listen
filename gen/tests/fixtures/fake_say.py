#!/usr/bin/env python3
"""Deterministic fake for the macOS `say` CLI used by SayTtsAdapter tests.

Writes a fixed valid 16 kHz mono 16-bit PCM WAV (one second of silence) to
the `-o` target regardless of input, so the adapter can measure a real
duration and build real cumulative alignment.
"""
import struct
import sys
from pathlib import Path

output = None
args = sys.argv[1:]
while args:
    if args[0] == "-o":
        output = args[1]
        args = args[2:]
    elif args[0] == "-f":
        args = args[2:]
    elif args[0] == "-v":
        args = args[2:]
    else:
        args = args[1:]
if output is None:
    sys.exit(2)

SAMPLE_RATE = 16000
FRAMES = SAMPLE_RATE
DATA = FRAMES * 2
header = b"RIFF" + struct.pack("<I", 36 + DATA) + b"WAVE"
header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SAMPLE_RATE,
                                SAMPLE_RATE * 2, 2, 16)
header += b"data" + struct.pack("<I", DATA)
Path(output).write_bytes(header + b"\x00" * DATA)
