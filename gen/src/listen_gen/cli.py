from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .asr import CommandAsrAdapter, FixtureAsrAdapter, package_media
from .package import ConversionError, package_from_lltimeline


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="listen-gen")
    commands = root.add_subparsers(dest="command", required=True)
    package = commands.add_parser("package", help="build a Listen content package")
    package_commands = package.add_subparsers(dest="package_command", required=True)
    native = package_commands.add_parser(
        "from-media", help="transcribe media and emit native v1 resources"
    )
    native.add_argument("input", type=Path)
    native.add_argument("--output", required=True, type=Path)
    native.add_argument("--provider", required=True, choices=["fixture", "command"])
    native.add_argument("--fixture", type=Path, help="normalized JSON for the fixture provider")
    native.add_argument("--command", help="external ASR wrapper executable; no shell is used")
    native.add_argument(
        "--command-arg",
        action="append",
        default=[],
        help="one argv item for the command provider; include {media} exactly once",
    )
    native.add_argument("--command-timeout-seconds", type=float, default=3600.0)
    native.add_argument("--title", required=True)
    native.add_argument("--media-kind", required=True, choices=["audio", "video"])
    native.add_argument("--duration-ms", required=True, type=int)
    native.add_argument("--created-at-ms", required=True, type=int)
    legacy = package_commands.add_parser(
        "from-lltimeline", help="convert an LLTimeline v1 document"
    )
    legacy.add_argument("input", type=Path)
    legacy.add_argument("--output", required=True, type=Path)
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.package_command == "from-media":
            if args.provider == "fixture":
                if args.fixture is None:
                    raise ConversionError("--fixture is required for the fixture provider")
                adapter = FixtureAsrAdapter(args.fixture)
            else:
                if args.command is None:
                    raise ConversionError("--command is required for the command provider")
                adapter = CommandAsrAdapter(
                    args.command, args.command_arg, args.command_timeout_seconds
                )
            result = package_media(
                args.input,
                args.output,
                adapter,
                title=args.title,
                media_kind=args.media_kind,
                duration_ms=args.duration_ms,
                created_at_ms=args.created_at_ms,
            )
        else:
            result = package_from_lltimeline(args.input, args.output)
    except (ConversionError, OSError, json.JSONDecodeError) as error:
        print(
            json.dumps(
                {"status": "failed", "error": str(error)},
                ensure_ascii=False,
                sort_keys=True,
            ),
            file=sys.stderr,
        )
        return 2
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0
