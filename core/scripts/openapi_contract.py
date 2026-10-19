#!/usr/bin/env python3
"""Fast structural checks and one-time repair for the canonical OpenAPI document."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
PATH_HEADING = re.compile(r"^  (/v1/[^:]+):$")
PLACEHOLDER = re.compile(r"\{([A-Za-z0-9_]+)\}")
PARAMETER_NAME = re.compile(r"^\s+-?\s*name:\s*([A-Za-z0-9_]+)\s*$")
INLINE_PARAMETER_NAME = re.compile(r"^\s*-\s+\{\s*name:\s*([A-Za-z0-9_]+),")
PARAMETER_REF = re.compile(
    r'^\s*-\s+\$ref:\s+"#/components/parameters/([A-Za-z0-9_]+)"\s*$'
)


def component_parameter_names(lines: list[str]) -> dict[str, str]:
    names = {}
    in_parameters = False
    current = None
    for line in lines:
        if line == "  parameters:":
            in_parameters = True
            continue
        if in_parameters and line.startswith("  ") and not line.startswith("    "):
            break
        if not in_parameters:
            continue
        if line.startswith("    ") and line.endswith(":") and not line.startswith("      "):
            current = line.strip()[:-1]
            continue
        if current and (match := PARAMETER_NAME.match(line)):
            names[current] = match.group(1)
    return names


def path_blocks(lines: list[str]) -> list[tuple[int, int, str]]:
    starts = []
    for index, line in enumerate(lines):
        if match := PATH_HEADING.match(line):
            starts.append((index, match.group(1)))
    return [
        (start, starts[offset + 1][0] if offset + 1 < len(starts) else len(lines), path)
        for offset, (start, path) in enumerate(starts)
    ]


def declared_parameters(
    block: list[str], component_names: dict[str, str]
) -> set[str]:
    names = {
        match.group(1)
        for line in block
        if (match := PARAMETER_NAME.match(line) or INLINE_PARAMETER_NAME.match(line))
        is not None
    }
    for line in block:
        if match := PARAMETER_REF.match(line):
            if match.group(1) in component_names:
                names.add(component_names[match.group(1)])
    return names


def missing_path_parameters(lines: list[str]) -> list[tuple[int, str, list[str]]]:
    component_names = component_parameter_names(lines)
    missing = []
    for start, end, path in path_blocks(lines):
        placeholders = set(PLACEHOLDER.findall(path))
        undeclared = sorted(
            placeholders - declared_parameters(lines[start + 1 : end], component_names)
        )
        if undeclared:
            missing.append((start, path, undeclared))
    return missing


def repair(lines: list[str]) -> list[str]:
    missing = missing_path_parameters(lines)
    if not missing:
        return lines
    additions = {start: names for start, _, names in missing}
    result = []
    for index, line in enumerate(lines):
        result.append(line)
        names = additions.get(index)
        if names:
            result.append("    parameters:")
            for name in names:
                result.append(
                    "      - { name: "
                    f"{name}, in: path, required: true, schema: {{ type: string }} }}"
                )
    return result


def check(path: Path) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    missing = missing_path_parameters(lines)
    if missing:
        details = "\n".join(
            f"{route}: {', '.join(names)}" for _, route, names in missing
        )
        raise SystemExit(f"OpenAPI path parameters are undeclared:\n{details}")
    print(f"OpenAPI path parameters are declared for {len(path_blocks(lines))} paths.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("check", "repair"))
    parser.add_argument("--input", default=ROOT / "contracts/openapi/v1.yaml")
    args = parser.parse_args()
    path = Path(args.input)
    if args.command == "repair":
        repaired = repair(path.read_text(encoding="utf-8").splitlines())
        path.write_text("\n".join(repaired) + "\n", encoding="utf-8")
    check(path)


if __name__ == "__main__":
    main()
