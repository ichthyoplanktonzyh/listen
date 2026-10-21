#!/usr/bin/env python3
"""Wait for owned Core processes to exit and release their SQLite lock."""

import argparse
import errno
import fcntl
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path


def process_is_running(pid):
    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "stat="],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return False
    return not result.stdout.strip().startswith("Z")


def lock_is_available(path):
    try:
        descriptor = os.open(path, os.O_RDWR)
    except FileNotFoundError:
        return True
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return False
        except OSError as error:
            if error.errno in (errno.EACCES, errno.EAGAIN):
                return False
            raise
        return True
    finally:
        os.close(descriptor)


def wait_for_shutdown(lock_file, pids, timeout_seconds, interval_seconds):
    deadline = time.monotonic() + timeout_seconds
    while True:
        running = [pid for pid in pids if process_is_running(pid)]
        lock_available = lock_is_available(lock_file)
        if not running and lock_available:
            print("Core sidecars exited and the smoke database lock is available.")
            return 0

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            print(
                "Timed out waiting for Core shutdown: "
                f"live_pids={running}, database_lock="
                f"{'held' if not lock_available else 'available'}",
                file=sys.stderr,
            )
            return 1
        time.sleep(min(interval_seconds, remaining))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock-file", required=True, type=Path)
    parser.add_argument(
        "--pids",
        default="",
        help="space-separated Core PIDs previously identified as owned by this smoke",
    )
    parser.add_argument("--timeout-seconds", type=float, required=True)
    parser.add_argument("--interval-seconds", type=float, default=0.1)
    args = parser.parse_args()
    if args.timeout_seconds <= 0 or args.interval_seconds <= 0:
        parser.error("timeout and interval must be greater than zero")
    if shutil.which("ps") is None:
        parser.error("ps is required to verify Core process shutdown")
    try:
        pids = sorted({int(value) for value in args.pids.split()})
    except ValueError:
        parser.error("--pids must contain only process IDs")
    if any(pid <= 1 for pid in pids):
        parser.error("--pids may contain only process IDs greater than 1")
    try:
        return wait_for_shutdown(
            args.lock_file,
            pids,
            args.timeout_seconds,
            args.interval_seconds,
        )
    except OSError as error:
        print(f"Could not verify Core shutdown: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
