#!/usr/bin/env python3
"""Deterministic fake `say` that writes garbage bytes (unmeasurable audio).

Used to verify that SayTtsAdapter honestly abstains from alignment when the
produced audio cannot be measured.
"""
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
Path(output).write_bytes(b"GARBAGE")
