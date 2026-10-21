#!/usr/bin/env python3
"""Deterministic fake for macOS `afconvert`; copies the audio fixture."""
import shutil
import sys
from pathlib import Path

input_path = None
output_path = None
args = sys.argv[1:]
while args:
    if args[0] == "-o":
        output_path = args[1]
        args = args[2:]
    elif args[0] in ("-f", "-d"):
        args = args[2:]
    elif args[0].startswith("-"):
        args = args[1:]
    else:
        input_path = input_path or args[0]
        args = args[1:]
if input_path is None or output_path is None:
    raise SystemExit(2)
shutil.copyfile(input_path, output_path)
