#!/usr/bin/env python3
"""Wait for a scalar SQLite readback to reach an expected value."""

import argparse
from contextlib import closing
import sqlite3
import sys
import time
from pathlib import Path


RETRYABLE_SQLITE_ERRORS = (
    "database is locked",
    "unable to open database file",
    "no such table:",
)


def read_scalar(database: Path, query: str):
    uri = f"{database.resolve().as_uri()}?mode=ro"
    with closing(sqlite3.connect(uri, uri=True, timeout=0.25)) as connection:
        row = connection.execute(query).fetchone()
    if row is None or len(row) != 1:
        raise ValueError("query must return exactly one row with one column")
    return row[0]


def wait_for_value(
    database: Path,
    query: str,
    expected: str,
    timeout_seconds: float,
    interval_seconds: float,
    description: str,
) -> int:
    deadline = time.monotonic() + timeout_seconds
    last_value = "unavailable"
    last_error = None

    while True:
        try:
            value = read_scalar(database, query)
            last_error = None
            last_value = str(value)
            if last_value == expected:
                print(f"{description} reached {expected} ({database})")
                return 0
        except sqlite3.OperationalError as error:
            message = str(error).lower()
            if not any(retryable in message for retryable in RETRYABLE_SQLITE_ERRORS):
                print(f"Could not read {description}: {error}", file=sys.stderr)
                return 2
            last_error = str(error)
        except (OSError, ValueError) as error:
            print(f"Could not read {description}: {error}", file=sys.stderr)
            return 2

        remaining = deadline - time.monotonic()
        if remaining <= 0:
            detail = f"last value: {last_value}"
            if last_error is not None:
                detail += f"; last SQLite error: {last_error}"
            print(
                f"Timed out waiting for {description} to reach {expected} "
                f"within {timeout_seconds:g}s ({detail})",
                file=sys.stderr,
            )
            return 1
        time.sleep(min(interval_seconds, remaining))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("query")
    parser.add_argument("expected")
    parser.add_argument("--timeout-seconds", type=float, required=True)
    parser.add_argument("--interval-seconds", type=float, default=0.2)
    parser.add_argument("--description", default="SQLite value")
    args = parser.parse_args()
    if args.timeout_seconds <= 0 or args.interval_seconds <= 0:
        parser.error("timeout and interval must be greater than zero")
    return wait_for_value(
        args.database,
        args.query,
        args.expected,
        args.timeout_seconds,
        args.interval_seconds,
        args.description,
    )


if __name__ == "__main__":
    raise SystemExit(main())
