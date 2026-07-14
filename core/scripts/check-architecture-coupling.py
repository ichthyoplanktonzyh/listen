#!/usr/bin/env python3
"""Cheap source guards for Phase 2.24 ownership and interface decisions."""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"architecture coupling guard: {message}")


def rust_sources(root: Path) -> list[Path]:
    return sorted(root.rglob("*.rs"))


def guard_dependency_direction() -> None:
    manifest = (ROOT / "crates/api-http/Cargo.toml").read_text(encoding="utf-8")
    if re.search(r"(?m)^speech-analysis\s*=", manifest):
        fail("api-http must not depend directly on speech-analysis")


def guard_application_public_interface() -> None:
    public_item = re.compile(r"\bpub\s+(?:async\s+)?fn\b[^\{;]*", re.DOTALL)
    for path in rust_sources(ROOT / "crates/application/src"):
        source = path.read_text(encoding="utf-8")
        for item in public_item.findall(source):
            if "speech_analysis::" in item:
                fail(f"application public interface leaks speech-analysis in {path.relative_to(ROOT)}")


def guard_production_rust_wildcards() -> None:
    """Keep production dependencies explicit; test preludes may use `super::*`."""
    wildcard = re.compile(r"(?m)^\s*use\s+(?!super::)[^;]+::\*\s*;")
    offenders: list[Path] = []
    for path in rust_sources(ROOT / "crates"):
        relative = path.relative_to(ROOT)
        if "tests" in relative.parts or path.name == "tests.rs":
            continue
        source = path.read_text(encoding="utf-8")
        production_source = source.split("#[cfg(test)]", 1)[0]
        if wildcard.search(production_source):
            offenders.append(relative)
    if offenders:
        fail(f"production Rust wildcard imports remain: {offenders}")


def guard_http_runtime_ownership() -> None:
    forbidden = {
        "tokio::process": "process execution",
        "std::process::Command": "process execution",
        "reqwest::": "network provider implementation",
    }
    for path in rust_sources(ROOT / "crates/api-http/src/routes"):
        source = path.read_text(encoding="utf-8")
        for token, responsibility in forbidden.items():
            if token in source:
                fail(f"{path.relative_to(ROOT)} owns {responsibility} ({token})")


def guard_flutter_transport_parsing() -> None:
    roots = [
        ROOT / "apps/desktop/lib/controllers",
        ROOT / "apps/desktop/lib/widgets",
        ROOT / "apps/desktop/lib/screens",
        ROOT / "apps/desktop/lib/main.dart",
    ]
    patterns = [
        re.compile(r"\.fromJson\(\s*await\s+(?:api|service|widget\.api)\.", re.DOTALL),
        re.compile(r"await\s+(?:api|service|widget\.api)\.[^;\n]+\s+as\s+Map<String,\s*dynamic>", re.DOTALL),
    ]
    paths: list[Path] = []
    for root in roots:
        paths.extend([root] if root.is_file() else sorted(root.rglob("*.dart")))
    for path in paths:
        source = path.read_text(encoding="utf-8")
        if any(pattern.search(source) for pattern in patterns):
            fail(f"Flutter caller parses HTTP wire shape in {path.relative_to(ROOT)}")


def guard_flutter_raw_api_allowlist() -> None:
    """Make raw transport DTO debt explicit and monotonically removable."""
    signature = re.compile(
        r"Future<(?:Map<String, dynamic>|List<Map<String, dynamic>>)?>?\s*(\w+)\s*\("
    )
    actual: set[str] = set()
    api_root = ROOT / "apps/desktop/lib/services/api"
    for path in sorted(api_root.glob("*.dart")):
        source = path.read_text(encoding="utf-8")
        actual.update(f"{path.name}:{match.group(1)}" for match in signature.finditer(source))

    allowlist_path = ROOT / "scripts/flutter-raw-api-allowlist.txt"
    allowed = {
        line.strip()
        for line in allowlist_path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    }
    additions = sorted(actual - allowed)
    stale = sorted(allowed - actual)
    if additions:
        fail(f"unreviewed raw Flutter API returns: {additions}")
    if stale:
        fail(f"remove migrated Flutter API allowlist entries: {stale}")


def guard_descriptive_module_names() -> None:
    ambiguous = [
        ROOT / "crates/api-http/src/m18.rs",
        ROOT / "apps/desktop/lib/m18_ui.dart",
        ROOT / "apps/desktop/test/m18_ui_test.dart",
    ]
    existing = [path.relative_to(ROOT) for path in ambiguous if path.exists()]
    if existing:
        fail(f"milestone-coded module names remain: {existing}")


def guard_pipeline_entrypoint() -> None:
    path = ROOT / "scripts/timeline-production/production_pipeline.py"
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    allowed = {"add_mfa_options", "add_mms_fa_options", "list_aligners", "doctor", "parser", "main"}
    functions = {node.name for node in tree.body if isinstance(node, ast.FunctionDef)}
    unexpected = sorted(functions - allowed)
    if unexpected:
        fail(f"production_pipeline.py owns non-entrypoint functions: {unexpected}")


def main() -> int:
    guard_dependency_direction()
    guard_application_public_interface()
    guard_production_rust_wildcards()
    guard_http_runtime_ownership()
    guard_flutter_transport_parsing()
    guard_flutter_raw_api_allowlist()
    guard_descriptive_module_names()
    guard_pipeline_entrypoint()
    print("Architecture coupling guards passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
