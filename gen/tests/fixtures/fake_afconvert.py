#!/usr/bin/env python3
"""Deterministic fake for the macOS `afconvert` CLI used by SayTtsAdapter.

Copies the input bytes to the `-o` target so the adapter sees a
self-consistent converted audio file.
"""
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
        if input_path is None:
            input_path = args[0]
        args = args[1:]
if input_path is None or output_path is None:
    sys.exit(2)
shutil.copyfile(input_path, output_path)
