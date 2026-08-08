#!/usr/bin/env python3
"""Cheap source guards for Phase 2.24 ownership and interface decisions."""

from __future__ import annotations

import ast
import re
import sys
import tomllib
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]

# Temporary, exact debt only. Routes stay listed until their public
# request/response types and workflow calls move behind application-owned ports.
# Provider crates are intentionally ineligible for this allowlist.
HTTP_ROUTE_RUNTIME_DEBT: dict[str, dict[str, str]] = {
    "crates/api-http/src/routes/learning_resources.rs": {
        "local_runtime": "maps legacy resource download/status errors",
    },
    "crates/api-http/src/routes/sound_line.rs": {
        "local_runtime": "exposes legacy sound-line job DTOs",
    },
    "crates/api-http/src/routes/speech.rs": {
        "local_runtime": "exposes legacy speech-batch job DTOs",
    },
    "crates/api-http/src/routes/pronunciation.rs": {
        "local_runtime": "selects the legacy pronunciation batch workflow",
    },
    "crates/api-http/src/routes/subtitle_search.rs": {
        "local_runtime": "uses legacy subtitle-search workflow types",
    },
    "crates/api-http/src/routes/tts.rs": {
        "local_runtime": "uses legacy speech-synthesis workflow DTOs",
    },
    "crates/api-http/src/routes/transcription.rs": {
        "local_runtime": "exposes recording transcription and model lifecycle workflow types",
    },
    "crates/api-http/src/routes/phonetic_analysis.rs": {
        "local_runtime": "uses the legacy finding-id parser",
    },
}


def fail(message: str) -> None:
    raise SystemExit(f"architecture coupling guard: {message}")


def rust_sources(root: Path) -> list[Path]:
    return sorted(root.rglob("*.rs"))


def guard_dependency_direction() -> None:
    manifest = (ROOT / "crates/api-http/Cargo.toml").read_text(encoding="utf-8")
    if re.search(r"(?m)^speech-analysis\s*=", manifest):
        fail("api-http must not depend directly on speech-analysis")


def api_http_runtime_dependencies(root: Path) -> dict[str, dict[str, Any]]:
    """Provider/runtime dependencies declared by the HTTP adapter.

    The manifest is the source of truth for aliases: a dependency may rename
    its package, so suffix matching source text alone is not sufficient.
    """
    manifest_path = root / "crates/api-http/Cargo.toml"
    manifest = tomllib.loads(manifest_path.read_text(encoding="utf-8"))
    dependency_tables = [manifest.get("dependencies", {})]
    dependency_tables.extend(
        target.get("dependencies", {})
        for target in manifest.get("target", {}).values()
        if isinstance(target, dict)
    )
    runtime_dependencies: dict[str, dict[str, Any]] = {}
    for dependencies in dependency_tables:
        for alias, raw_spec in dependencies.items():
            spec = raw_spec if isinstance(raw_spec, dict) else {}
            package = spec.get("package", alias)
            if package == "local-runtime" or package.endswith("-provider"):
                runtime_dependencies[alias.replace("-", "_")] = {
                    "package": package,
                    **spec,
                }
    return runtime_dependencies


def rust_code_without_comments_or_strings(source: str) -> str:
    """Remove common Rust non-code regions before cheap token scans."""
    non_code = re.compile(
        r"""
        /\*.*?\*/
        |//[^\n]*
        |b?r(?P<hashes>\#{0,8})".*?"(?P=hashes)
        |b?"(?:\\.|[^"\\])*"
        """,
        re.DOTALL | re.VERBOSE,
    )
    return non_code.sub(" ", source)


def concrete_adapter_types(
    root: Path, dependencies: dict[str, dict[str, Any]]
) -> set[str]:
    """Public concrete provider types reachable from direct dependencies.

    This closes the re-export loophole where a route imports a provider type
    through `crate::...` instead of naming the provider crate directly.
    """
    concrete_suffix = re.compile(
        r"(?:Provider|Adapter|Client|Factory|Manager|Coordinator|Runtime)$"
    )
    public_type = re.compile(
        r"\bpub(?:\s*\([^)]*\))?\s+(?:struct|enum|type)\s+([A-Z][A-Za-z0-9_]*)"
    )
    names: set[str] = set()
    manifest_dir = root / "crates/api-http"
    for spec in dependencies.values():
        if not str(spec["package"]).endswith("-provider"):
            continue
        dependency_path = spec.get("path")
        if not isinstance(dependency_path, str):
            continue
        source_root = (manifest_dir / dependency_path / "src").resolve()
        if not source_root.is_dir():
            continue
        for path in rust_sources(source_root):
            source = rust_code_without_comments_or_strings(
                path.read_text(encoding="utf-8")
            )
            names.update(
                name
                for name in public_type.findall(source)
                if concrete_suffix.search(name)
            )
    return names


def guard_http_adapter_boundaries(
    root: Path = ROOT,
    runtime_debt: dict[str, dict[str, str]] | None = None,
) -> None:
    """Routes adapt transport only; concrete adapters are composed in lib.rs.

    `api-http` may declare provider/local-runtime dependencies because its
    composition root wires concrete implementations. Route modules may not
    import those crates, construct their concrete types through a re-export, or
    call local-runtime workflows directly.
    """
    dependencies = api_http_runtime_dependencies(root)
    runtime_debt = HTTP_ROUTE_RUNTIME_DEBT if runtime_debt is None else runtime_debt
    forbidden_modules = set(dependencies)
    # Also catch an undeclared/new provider module before the manifest parser is
    # updated; the manifest-derived aliases handle renamed dependencies.
    provider_module = re.compile(r"\b[a-z][a-z0-9_]*_provider\s*::")
    concrete_types = concrete_adapter_types(root, dependencies)
    concrete_type_reference = (
        re.compile(rf"\b(?:{'|'.join(map(re.escape, sorted(concrete_types)))})\b")
        if concrete_types
        else None
    )

    observed_debt: set[tuple[str, str]] = set()
    for path in rust_sources(root / "crates/api-http/src/routes"):
        relative = path.relative_to(root).as_posix()
        source = rust_code_without_comments_or_strings(
            path.read_text(encoding="utf-8")
        )
        direct = {
            module
            for module in forbidden_modules
            if re.search(rf"\b{re.escape(module)}\s*::", source)
        }
        suffix_match = provider_module.search(source)
        provider_direct = sorted(
            module
            for module in direct
            if str(dependencies[module]["package"]).endswith("-provider")
        )
        if provider_direct or suffix_match:
            modules = provider_direct or [
                suffix_match.group(0).replace("::", "").strip()
            ]
            fail(
                f"{relative} imports concrete provider crates: "
                f"{modules}; inject an application-owned port from the composition root"
            )
        allowed_runtime = runtime_debt.get(relative, {})
        unapproved_runtime = sorted(direct - set(allowed_runtime))
        if unapproved_runtime:
            fail(
                f"{relative} imports concrete runtime crates: {unapproved_runtime}; "
                "inject an application-owned port or add exact, reviewed debt"
            )
        observed_debt.update((relative, module) for module in direct)
        if concrete_type_reference and (match := concrete_type_reference.search(source)):
            fail(
                f"{relative} references concrete provider type "
                f"{match.group(0).strip()}; construction belongs in api-http/src/lib.rs"
            )

    stale_debt = sorted(
        (relative, module)
        for relative, modules in runtime_debt.items()
        for module in modules
        if (relative, module) not in observed_debt
    )
    if stale_debt:
        fail(f"remove migrated HTTP runtime debt entries: {stale_debt}")


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


def guard_http_blocking_seam() -> None:
    """Keep synchronous application work behind the single transport seam."""
    route_root = ROOT / "crates/api-http/src/routes"
    for path in rust_sources(route_root):
        source = path.read_text(encoding="utf-8")
        if re.search(r"\bstate\s*\.\s*services\b", source, re.DOTALL):
            fail(f"{path.relative_to(ROOT)} bypasses ApplicationExecutor")
        if "spawn_blocking" in source:
            fail(f"{path.relative_to(ROOT)} owns blocking dispatch")

    executor = (ROOT / "crates/api-http/src/application_executor.rs").read_text(
        encoding="utf-8"
    )
    if "spawn_blocking" not in executor:
        fail("ApplicationExecutor no longer owns blocking dispatch")


def guard_event_stream_semantics() -> None:
    """Lag and shutdown are distinct notification conditions."""
    source = (ROOT / "crates/api-http/src/event_stream.rs").read_text(encoding="utf-8")
    required = ["RecvError::Lagged", "RecvError::Closed"]
    missing = [token for token in required if token not in source]
    if missing:
        fail(f"event stream omits explicit receive states: {missing}")


def guard_http_composition_root() -> None:
    """Root composition stays limited to public health, merge, observation and state."""
    source = (ROOT / "crates/api-http/src/lib.rs").read_text(encoding="utf-8")
    if source.count(".route(") > 1:
        fail("api-http lib.rs has regained protected resource route registration")
    if "routes::router::protected_router(&state)" not in source:
        fail("api-http root no longer delegates protected route composition")

    state = source.split("pub struct ApiState {", 1)[1].split("}", 1)[0]
    expected = ["analysis:", "language:", "generative:", "infrastructure:"]
    missing = [field for field in expected if field not in state]
    if missing:
        fail(f"ApiState runtime contexts regressed: {missing}")


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
    guard_http_adapter_boundaries()
    guard_application_public_interface()
    guard_production_rust_wildcards()
    guard_http_runtime_ownership()
    guard_http_blocking_seam()
    guard_event_stream_semantics()
    guard_http_composition_root()
    guard_descriptive_module_names()
    guard_pipeline_entrypoint()
    print("Architecture coupling guards passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
