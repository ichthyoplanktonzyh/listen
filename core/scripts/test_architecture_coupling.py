#!/usr/bin/env python3
"""Regression tests for architecture coupling guard false negatives."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check-architecture-coupling.py")
SPEC = importlib.util.spec_from_file_location("architecture_guard", SCRIPT)
assert SPEC and SPEC.loader
architecture_guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(architecture_guard)


class HttpAdapterBoundaryTests(unittest.TestCase):
    def fixture(self, route_source: str, root_source: str = "") -> Path:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        root = Path(temp.name)
        api = root / "crates/api-http"
        routes = api / "src/routes"
        provider = root / "crates/realtime-provider/src"
        routes.mkdir(parents=True)
        provider.mkdir(parents=True)
        (api / "Cargo.toml").write_text(
            """
[package]
name = "api-http"
version = "0.1.0"
publish = false

[dependencies]
realtime-provider = { path = "../realtime-provider" }
local-runtime = { path = "../local-runtime" }
""".strip(),
            encoding="utf-8",
        )
        (routes / "example.rs").write_text(route_source, encoding="utf-8")
        (api / "src/lib.rs").write_text(root_source, encoding="utf-8")
        (provider / "lib.rs").write_text(
            "pub struct VendorRealtimeAdapter;\n",
            encoding="utf-8",
        )
        return root

    def assert_guard_fails(self, root: Path, expected: str) -> None:
        with self.assertRaisesRegex(SystemExit, expected):
            architecture_guard.guard_http_adapter_boundaries(root, {})

    def test_rejects_direct_provider_import_from_route(self) -> None:
        root = self.fixture(
            "use realtime_provider::VendorRealtimeAdapter;\n"
            "fn route() { let _ = VendorRealtimeAdapter::new(); }\n"
        )
        self.assert_guard_fails(root, "imports concrete provider crates")

    def test_rejects_renamed_provider_dependency_from_route(self) -> None:
        root = self.fixture(
            "use realtime::VendorRealtimeAdapter;\n"
            "fn route() { let _ = VendorRealtimeAdapter::new(); }\n"
        )
        (root / "crates/api-http/Cargo.toml").write_text(
            """
[dependencies]
realtime = { package = "realtime-provider", path = "../realtime-provider" }
""".strip(),
            encoding="utf-8",
        )
        self.assert_guard_fails(root, "imports concrete provider crates")

    def test_rejects_local_runtime_workflow_from_route(self) -> None:
        root = self.fixture(
            "fn route(state: &State) { "
            "local_runtime::SpeechBatchCoordinator::new(state.clone()); }\n"
        )
        self.assert_guard_fails(root, "imports concrete runtime crates")

    def test_rejects_concrete_provider_hidden_behind_root_reexport(self) -> None:
        root = self.fixture(
            "use crate::VendorRealtimeAdapter;\n"
            "fn route() { let _ = VendorRealtimeAdapter::with_vendor_defaults(); }\n",
            "pub use realtime_provider::VendorRealtimeAdapter;\n",
        )
        self.assert_guard_fails(root, "references concrete provider type")

    def test_rejects_concrete_provider_type_annotation_hidden_behind_reexport(self) -> None:
        root = self.fixture(
            "use crate::VendorRealtimeAdapter;\n"
            "fn route() { let _adapter: VendorRealtimeAdapter = Default::default(); }\n",
            "pub use realtime_provider::VendorRealtimeAdapter;\n",
        )
        self.assert_guard_fails(root, "references concrete provider type")

    def test_allows_concrete_construction_in_composition_root(self) -> None:
        root = self.fixture(
            "fn route(state: &State) { state.application.execute(); }\n",
            "use realtime_provider::VendorRealtimeAdapter;\n"
            "fn compose() { let _ = VendorRealtimeAdapter::new(); }\n",
        )
        architecture_guard.guard_http_adapter_boundaries(root, {})

    def test_allows_only_explicit_local_runtime_debt(self) -> None:
        root = self.fixture(
            "fn route() { local_runtime::SpeechBatchCoordinator::new(); }\n"
        )
        architecture_guard.guard_http_adapter_boundaries(
            root,
            {
                "crates/api-http/src/routes/example.rs": {
                    "local_runtime": "legacy test workflow",
                }
            },
        )

    def test_provider_dependency_cannot_be_allowlisted(self) -> None:
        root = self.fixture(
            "fn route() { realtime_provider::VendorRealtimeAdapter::new(); }\n"
        )
        with self.assertRaisesRegex(SystemExit, "imports concrete provider crates"):
            architecture_guard.guard_http_adapter_boundaries(
                root,
                {
                    "crates/api-http/src/routes/example.rs": {
                        "realtime_provider": "providers are never debt",
                    }
                },
            )


if __name__ == "__main__":
    unittest.main()
