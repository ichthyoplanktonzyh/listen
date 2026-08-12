from __future__ import annotations

import hashlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
sys.path.insert(0, str(ROOT / "tools"))

import release_bundle as rb
from listen_gen import protocol_v2 as protocol

FAKE_COMMIT = "ab12cd34ef56ab12cd34ef56ab12cd34ef56ab12"
VERSION = "0.5.0"
PYZ_NAME = f"listen-gen-{VERSION}.pyz"
MANIFEST_NAME = f"listen-gen-{VERSION}.release.json"
SHEBANG = b"#!/usr/bin/env python3\n"
FIXED_DATE_TIME = (1980, 1, 1, 0, 0, 0)


def canonical_json_bytes(document: object) -> bytes:
    return json.dumps(
        document,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def canonical_json_file_bytes(document: object) -> bytes:
    return canonical_json_bytes(document) + b"\n"


def env_with_src() -> dict[str, str]:
    env = dict(os.environ)
    env["PYTHONPATH"] = str(ROOT / "src")
    return env


def _capability_request_path(directory: Path) -> Path:
    import hashlib

    text = b"Release bundle sample text.\nSecond sentence."
    digest = "sha256:" + hashlib.sha256(text).hexdigest()
    document_path = directory / "sample.txt"
    document_path.write_bytes(text)
    request = {
        "schema": "listen_gen.capability-request.v2",
        "version": 2,
        "created_at_ms": 1786000000000,
        "attempt_id": "attempt-release-bundle",
        "material": {
            "material_id": "material-1",
            "material_revision_id": "revision-1",
            "title": "Release bundle sample",
        },
        "edition": {
            "edition_id": "edition-1",
            "title": "Edition",
            "target_language": "en",
            "support_languages": [],
        },
        "requested_capability": "read",
        "available_renditions": [
            {
                "kind": "document",
                "rendition_id": "sha256:" + "1" * 64,
                "media_type": "text/plain",
                "language": "en",
                "source_asset_id": "sha256:" + "2" * 64,
                "blob": {
                    "digest": digest,
                    "size_bytes": len(text),
                    "path": str(document_path),
                },
            }
        ],
        "available_resources": [],
    }
    request_path = directory / "request.json"
    request_path.write_text(json.dumps(request), encoding="utf-8")
    return request_path


def fixture_argv(output: Path, *, machine: bool) -> list[str]:
    argv = [
        "package", "from-capability",
        str(_capability_request_path(output.parent)),
        "--output", str(output),
    ]
    if machine:
        argv.append("--machine-events")
    return argv


def run_tool(argv: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(ROOT / "tools" / "release_bundle.py"), *argv],
        capture_output=True,
        text=True,
        timeout=120,
    )


def make_malicious_pyz(bad_name: str) -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_STORED) as archive:
        for name in sorted([bad_name, "__main__.py"]):
            info = zipfile.ZipInfo(filename=name, date_time=FIXED_DATE_TIME)
            info.compress_type = zipfile.ZIP_STORED
            info.create_system = 3
            info.external_attr = 0o100644 << 16
            archive.writestr(info, b"payload\n")
    return SHEBANG + buffer.getvalue()


def copy_repo_root(prefix: str) -> Path:
    root = Path(tempfile.mkdtemp(prefix=prefix))
    shutil.copytree(ROOT / "src" / "listen_gen", root / "src" / "listen_gen")
    shutil.copyfile(ROOT / "pyproject.toml", root / "pyproject.toml")
    shutil.copyfile(ROOT / "contracts.lock.json", root / "contracts.lock.json")
    return root


class ReleaseBundleTestBase(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls._class_tmp = tempfile.TemporaryDirectory()
        cls.class_tmp = Path(cls._class_tmp.name)
        cls.output_parent = cls.class_tmp / "dist"
        cls.artifact, cls.manifest = rb.build_release_bundle(
            ROOT, cls.output_parent, FAKE_COMMIT
        )

    @classmethod
    def tearDownClass(cls) -> None:
        cls._class_tmp.cleanup()

    def copy_bundle(self, directory: Path) -> tuple[Path, Path]:
        bundle = directory / f"listen-gen-{VERSION}"
        shutil.copytree(self.artifact.parent, bundle)
        return bundle / PYZ_NAME, bundle / MANIFEST_NAME


class DeterministicBuildTests(ReleaseBundleTestBase):
    def test_same_commit_two_output_parents_byte_identical(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            parent_b = Path(tmp) / "other-dist"
            artifact_b, manifest_b = rb.build_release_bundle(ROOT, parent_b, FAKE_COMMIT)
            self.assertEqual(
                self.artifact.read_bytes(), artifact_b.read_bytes()
            )
            self.assertEqual(self.manifest.read_bytes(), manifest_b.read_bytes())

    def test_checkout_path_independent(self) -> None:
        def make_repo_root(name: str) -> Path:
            root = Path(tempfile.mkdtemp(prefix=name))
            self.addCleanup(shutil.rmtree, root, ignore_errors=True)
            shutil.copytree(ROOT / "src" / "listen_gen", root / "src" / "listen_gen")
            shutil.copyfile(ROOT / "pyproject.toml", root / "pyproject.toml")
            shutil.copyfile(ROOT / "contracts.lock.json", root / "contracts.lock.json")
            return root

        root_a = make_repo_root("repo-a-")
        root_b = make_repo_root("repo-b-")
        with tempfile.TemporaryDirectory() as tmp:
            artifact_a, manifest_a = rb.build_release_bundle(
                root_a, Path(tmp) / "dist-a", FAKE_COMMIT
            )
            artifact_b, manifest_b = rb.build_release_bundle(
                root_b, Path(tmp) / "dist-b", FAKE_COMMIT
            )
            bytes_a = artifact_a.read_bytes()
            bytes_b = artifact_b.read_bytes()
            manifest_bytes_a = manifest_a.read_bytes()
            manifest_bytes_b = manifest_b.read_bytes()
        self.assertEqual(bytes_a, bytes_b)
        self.assertEqual(manifest_bytes_a, manifest_bytes_b)
        self.assertEqual(bytes_a, self.artifact.read_bytes())
        self.assertEqual(manifest_bytes_a, self.manifest.read_bytes())


class ManifestContentTests(ReleaseBundleTestBase):
    def test_manifest_exact_content(self) -> None:
        raw = self.manifest.read_bytes()
        manifest = json.loads(raw.decode("utf-8"))
        self.assertEqual(
            set(manifest),
            {
                "schema",
                "tool",
                "source",
                "machine_protocol",
                "content_package_contract",
                "runtime",
                "runtime_identity",
                "artifact",
            },
        )
        self.assertEqual(set(manifest["tool"]), {"id", "version"})
        self.assertEqual(set(manifest["source"]), {"repository", "commit"})
        self.assertEqual(set(manifest["machine_protocol"]), {"schema", "version"})
        self.assertEqual(
            set(manifest["content_package_contract"]),
            {
                "authority",
                "release_schema_id",
                "package_schema",
                "schema_version",
                "canonical_sha256",
            },
        )
        self.assertEqual(
            set(manifest["content_package_contract"]["authority"]),
            {"repository", "path"},
        )
        self.assertEqual(
            set(manifest["runtime"]), {"python_requires", "provider_requirements"}
        )
        self.assertEqual(
            set(manifest["runtime_identity"]),
            {"schema", "version", "runtime", "toolchain"},
        )
        self.assertEqual(
            set(manifest["runtime_identity"]["runtime"]), {"family", "requires"}
        )
        self.assertEqual(
            set(manifest["runtime_identity"]["toolchain"]),
            {"schema", "version", "tools"},
        )
        self.assertEqual(
            set(manifest["artifact"]),
            {"filename", "format", "entrypoint", "size_bytes", "sha256"},
        )
        self.assertEqual(manifest["schema"], "listen_gen.release-bundle.v1")
        self.assertEqual(manifest["source"]["commit"], FAKE_COMMIT)
        self.assertEqual(manifest["tool"], {
            "id": protocol.TOOL_ID,
            "version": protocol.TOOL_VERSION,
        })
        self.assertEqual(manifest["machine_protocol"], {
            "schema": protocol.MACHINE_EVENT_SCHEMA_V2,
            "version": protocol.MACHINE_PROTOCOL_VERSION,
        })
        runtime_identity = manifest["runtime_identity"]
        self.assertEqual(
            runtime_identity["schema"], rb.RUNTIME_IDENTITY_SCHEMA
        )
        self.assertEqual(runtime_identity["version"], rb.RUNTIME_IDENTITY_VERSION)
        self.assertEqual(runtime_identity["runtime"], {
            "family": rb.RUNTIME_FAMILY,
            "requires": ">=3.11",
        })
        self.assertEqual(
            runtime_identity["toolchain"]["schema"],
            rb.TOOLCHAIN_IDENTITY_SCHEMA,
        )
        self.assertEqual(
            runtime_identity["toolchain"]["version"],
            rb.TOOLCHAIN_IDENTITY_VERSION,
        )
        self.assertEqual(
            runtime_identity["toolchain"]["tools"],
            rb._canonical_toolchain(),
        )
        self.assertEqual(
            runtime_identity["runtime"]["requires"],
            manifest["runtime"]["python_requires"],
        )
        # The toolchain is exactly the union of per-provider requirements and
        # every tool carries a role.
        required_tools = {
            tool
            for tools in manifest["runtime"]["provider_requirements"].values()
            for tool in tools
        }
        self.assertEqual(
            {tool["id"] for tool in runtime_identity["toolchain"]["tools"]},
            required_tools,
        )
        for tool in runtime_identity["toolchain"]["tools"]:
            self.assertEqual(set(tool), {"id", "roles"})
            self.assertEqual(
                tool["roles"], list(rb.TOOLCHAIN_ROLES[tool["id"]])
            )
            self.assertEqual(len(tool["roles"]), len(set(tool["roles"])))
        lock = json.loads((ROOT / "contracts.lock.json").read_text("utf-8"))
        contract = manifest["content_package_contract"]
        self.assertEqual(contract["authority"], {
            "repository": lock["authority"]["repository"],
            "path": lock["authority"]["path"],
        })
        self.assertEqual(
            contract["release_schema_id"], lock["release_schema_id"]
        )
        self.assertEqual(contract["package_schema"], lock["package_schema"])
        self.assertEqual(contract["schema_version"], lock["schema_version"])
        self.assertEqual(contract["canonical_sha256"], "sha256:" + hashlib.sha256(
            canonical_json_bytes(lock)
        ).hexdigest())
        self.assertNotEqual(
            contract["canonical_sha256"],
            "sha256:" + hashlib.sha256(canonical_json_file_bytes(lock)).hexdigest(),
        )
        artifact_bytes = self.artifact.read_bytes()
        self.assertEqual(manifest["artifact"], {
            "filename": PYZ_NAME,
            "format": "python-zipapp",
            "entrypoint": "__main__.py",
            "size_bytes": len(artifact_bytes),
            "sha256": "sha256:" + hashlib.sha256(artifact_bytes).hexdigest(),
        })
        self.assertEqual(raw, canonical_json_file_bytes(manifest))
        self.assertTrue(raw.endswith(b"\n"))
        self.assertFalse(raw.endswith(b"\n\n"))
        text = raw.decode("utf-8")
        self.assertNotIn(str(ROOT), text)
        self.assertNotIn(str(self.output_parent.resolve()), text)

    def test_manifest_filename_must_match_version(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _, manifest = self.copy_bundle(Path(tmp))
            renamed = manifest.parent / "wrong-name.json"
            shutil.copyfile(manifest, renamed)
            with self.assertRaises(rb.ReleaseBundleError) as caught:
                rb.verify_release_bundle(ROOT, renamed)
            self.assertEqual(str(caught.exception), "release manifest is invalid")


class ZipStructureTests(ReleaseBundleTestBase):
    def test_zip_exact_structure(self) -> None:
        data = self.artifact.read_bytes()
        self.assertTrue(data.startswith(SHEBANG))
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            self.assertEqual(archive.comment, b"")
            names = archive.namelist()
            self.assertEqual(names, sorted(names))
            self.assertEqual(len(names), len(set(names)))
            expected_sources = sorted(
                "listen_gen/" + path.relative_to(
                    ROOT / "src" / "listen_gen"
                ).as_posix()
                for path in (ROOT / "src" / "listen_gen").rglob("*.py")
                if not path.is_symlink() and path.is_file()
            )
            self.assertEqual(names, sorted(["__main__.py"] + expected_sources))
            for name in names:
                self.assertNotIn("\\", name)
                self.assertFalse(name.startswith("/"))
                self.assertNotIn("..", name.split("/"))
                self.assertTrue(name.endswith(".py"))
                self.assertNotIn("__pycache__", name)
                self.assertFalse(name.startswith(("tests/", "docs/", "tools/")))
            for info in archive.infolist():
                self.assertEqual(info.date_time, FIXED_DATE_TIME)
                self.assertEqual(info.compress_type, zipfile.ZIP_STORED)
                self.assertEqual(info.create_system, 3)
                self.assertEqual(info.external_attr, 0o100644 << 16)
                self.assertFalse(info.is_dir())
            main = archive.read("__main__.py").decode("utf-8")
            self.assertIn("sys.version_info < (3, 11)", main)
            self.assertIn("from listen_gen.cli import main", main)
            self.assertIn("raise SystemExit(main())", main)
            for name in expected_sources:
                source = (ROOT / "src" / name).read_bytes()
                normalized = source.replace(b"\r\n", b"\n").replace(b"\r", b"\n")
                self.assertEqual(archive.read(name), normalized)

    def test_archive_excludes_repository_metadata(self) -> None:
        with zipfile.ZipFile(io.BytesIO(self.artifact.read_bytes())) as archive:
            names = archive.namelist()
        for name in names:
            self.assertNotIn("pyproject.toml", name)
            self.assertNotIn("contracts.lock.json", name)
            self.assertFalse(name.endswith(".pyc"))


class ZipappRuntimeTests(ReleaseBundleTestBase):
    def test_zipapp_package_bytes_match_source_cli(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            source_output = Path(tmp) / "source.listenpkg"
            completed = subprocess.run(
                [sys.executable, "-m", "listen_gen",
                 *fixture_argv(source_output, machine=False)],
                capture_output=True, text=True, env=env_with_src(), timeout=120,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            pyz_output = Path(tmp) / "pyz.listenpkg"
            completed = subprocess.run(
                [sys.executable, str(self.artifact),
                 *fixture_argv(pyz_output, machine=False)],
                capture_output=True, text=True, timeout=120,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertEqual(
                source_output.read_bytes(), pyz_output.read_bytes()
            )

    def test_zipapp_machine_events(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "machine.listenpkg"
            completed = subprocess.run(
                [sys.executable, str(self.artifact),
                 *fixture_argv(output, machine=True)],
                capture_output=True, text=True, timeout=120,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = [
                json.loads(line)
                for line in completed.stdout.splitlines()
                if line
            ]
            self.assertGreaterEqual(len(events), 2)
            for index, event in enumerate(events):
                self.assertEqual(event["schema"], "listen_gen.machine-event.v2")
                self.assertEqual(event["protocol_version"], 2)
                self.assertEqual(event["tool"], {
                    "id": protocol.TOOL_ID,
                    "version": protocol.TOOL_VERSION,
                })
                self.assertEqual(event["sequence"], index)
            terminals = [
                event for event in events
                if event["event"] in {"completed", "cancelled", "failed"}
            ]
            self.assertEqual(len(terminals), 1)
            terminal = terminals[0]
            self.assertEqual(terminal["event"], "completed")
            self.assertEqual(
                terminal["package_sha256"],
                "sha256:" + hashlib.sha256(output.read_bytes()).hexdigest(),
            )

    def test_zipapp_help_runs_without_executable_bit(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp) / PYZ_NAME
            shutil.copyfile(self.artifact, copy)
            os.chmod(copy, 0o644)
            completed = subprocess.run(
                [sys.executable, str(copy), "--help"],
                capture_output=True, text=True, timeout=120,
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)


class VerifierFailureTests(ReleaseBundleTestBase):
    def test_artifact_tamper_checksum_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            artifact, manifest = self.copy_bundle(Path(tmp))
            data = bytearray(artifact.read_bytes())
            data[len(data) // 2] ^= 0xFF
            artifact.write_bytes(bytes(data))
            completed = run_tool(["verify", str(manifest)])
            self.assertEqual(completed.returncode, 2)
            self.assertEqual(
                completed.stderr.splitlines(),
                ["release bundle error: release artifact checksum mismatch"],
            )

    def test_artifact_size_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            artifact, manifest = self.copy_bundle(Path(tmp))
            artifact.write_bytes(artifact.read_bytes() + b"\x00")
            with self.assertRaises(rb.ReleaseBundleError) as caught:
                rb.verify_release_bundle(ROOT, manifest)
            self.assertEqual(str(caught.exception), "release artifact size mismatch")

    def test_missing_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _, manifest = self.copy_bundle(Path(tmp))
            (manifest.parent / PYZ_NAME).unlink()
            with self.assertRaises(rb.ReleaseBundleError) as caught:
                rb.verify_release_bundle(ROOT, manifest)
            self.assertEqual(str(caught.exception), "release artifact is missing")

    def test_manifest_path_traversal_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _, manifest = self.copy_bundle(Path(tmp))
            parsed = json.loads(manifest.read_bytes())
            parsed["artifact"]["filename"] = f"../{PYZ_NAME}"
            manifest.write_bytes(canonical_json_file_bytes(parsed))
            completed = run_tool(["verify", str(manifest)])
            self.assertEqual(completed.returncode, 2)
            self.assertEqual(
                completed.stderr.splitlines(),
                ["release bundle error: release manifest is invalid"],
            )

    def test_archive_structure_tamper_detected(self) -> None:
        for bad_name in ("../escape.py", "/absolute.py", "listen_gen\\bad.py"):
            with tempfile.TemporaryDirectory() as tmp:
                artifact, manifest = self.copy_bundle(Path(tmp))
                malicious = make_malicious_pyz(bad_name)
                artifact.write_bytes(malicious)
                parsed = json.loads(manifest.read_bytes())
                parsed["artifact"]["size_bytes"] = len(malicious)
                parsed["artifact"]["sha256"] = (
                    "sha256:" + hashlib.sha256(malicious).hexdigest()
                )
                manifest.write_bytes(canonical_json_file_bytes(parsed))
                completed = run_tool(["verify", str(manifest)])
                self.assertEqual(completed.returncode, 2, bad_name)
                self.assertEqual(
                    completed.stderr.splitlines(),
                    ["release bundle error: release archive is invalid"],
                    bad_name,
                )

    def test_verify_success_output(self) -> None:
        completed = run_tool(["verify", str(self.manifest)])
        self.assertEqual(completed.returncode, 0, completed.stderr)
        document = json.loads(completed.stdout)
        self.assertEqual(document["status"], "verified")
        self.assertEqual(document["tool"], {"id": "listen-gen", "version": VERSION})
        self.assertEqual(
            document["artifact_sha256"],
            "sha256:" + hashlib.sha256(self.artifact.read_bytes()).hexdigest(),
        )
        self.assertEqual(
            document["runtime_identity"],
            json.loads(self.manifest.read_bytes())["runtime_identity"],
        )
        self.assertEqual(
            completed.stdout,
            canonical_json_file_bytes(document).decode("utf-8"),
        )


class BuildErrorTests(unittest.TestCase):
    def test_invalid_source_commit(self) -> None:
        invalid = [
            "",
            FAKE_COMMIT.upper(),
            FAKE_COMMIT[:39],
            FAKE_COMMIT + "a",
            "z" + FAKE_COMMIT[1:],
            FAKE_COMMIT + "\n",
            FAKE_COMMIT + " ",
        ]
        with tempfile.TemporaryDirectory() as tmp:
            for commit in invalid:
                with self.assertRaises(rb.ReleaseBundleError) as caught:
                    rb.build_release_bundle(ROOT, Path(tmp), commit)
                self.assertEqual(
                    str(caught.exception),
                    "source commit must be a lowercase 40-character SHA",
                )

    def test_invalid_source_commit_via_cli(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            completed = run_tool([
                "build", "--source-commit", "NOPE", "--output-parent", tmp,
            ])
            self.assertEqual(completed.returncode, 2)
            self.assertEqual(
                completed.stderr.splitlines(),
                ["release bundle error: source commit must be a lowercase 40-character SHA"],
            )

    def test_existing_bundle_directory_immutable(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            output_parent = Path(tmp)
            existing = output_parent / f"listen-gen-{VERSION}"
            existing.mkdir()
            sentinel = existing / "sentinel.txt"
            sentinel.write_text("do not touch\n")
            with self.assertRaises(rb.ReleaseBundleError) as caught:
                rb.build_release_bundle(ROOT, output_parent, FAKE_COMMIT)
            self.assertEqual(
                str(caught.exception), "release bundle directory already exists"
            )
            self.assertEqual(sentinel.read_text(), "do not touch\n")
            self.assertEqual(list(existing.iterdir()), [sentinel])
            leftovers = [
                path.name for path in output_parent.iterdir()
                if ".staging." in path.name
            ]
            self.assertEqual(leftovers, [])

    def test_build_failure_cleanup(self) -> None:
        root = Path(tempfile.mkdtemp(prefix="broken-repo-"))
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        shutil.copytree(ROOT / "src" / "listen_gen", root / "src" / "listen_gen")
        shutil.copyfile(ROOT / "pyproject.toml", root / "pyproject.toml")
        (root / "contracts.lock.json").write_text("{not valid json\n")
        with tempfile.TemporaryDirectory() as tmp:
            output_parent = Path(tmp)
            unrelated = output_parent / "keep.txt"
            unrelated.write_text("keep me\n")
            with self.assertRaises(rb.ReleaseBundleError) as caught:
                rb.build_release_bundle(root, output_parent, FAKE_COMMIT)
            self.assertEqual(
                str(caught.exception), "content package contract lock is invalid"
            )
            self.assertFalse((output_parent / f"listen-gen-{VERSION}").exists())
            leftovers = [
                path.name for path in output_parent.iterdir()
                if ".staging." in path.name
            ]
            self.assertEqual(leftovers, [])
            self.assertEqual(unrelated.read_text(), "keep me\n")

    def test_missing_source_package_cleanup(self) -> None:
        root = Path(tempfile.mkdtemp(prefix="no-src-"))
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        shutil.copyfile(ROOT / "pyproject.toml", root / "pyproject.toml")
        shutil.copyfile(ROOT / "contracts.lock.json", root / "contracts.lock.json")
        with tempfile.TemporaryDirectory() as tmp:
            output_parent = Path(tmp)
            with self.assertRaises(rb.ReleaseBundleError):
                rb.build_release_bundle(root, output_parent, FAKE_COMMIT)
            self.assertFalse((output_parent / f"listen-gen-{VERSION}").exists())
            self.assertEqual(
                [path.name for path in output_parent.iterdir()], []
            )


class CliBuildOutputTests(unittest.TestCase):
    def test_build_success_output_and_layout(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            completed = run_tool([
                "build", "--source-commit", FAKE_COMMIT,
                "--output-parent", tmp,
            ])
            self.assertEqual(completed.returncode, 0, completed.stderr)
            document = json.loads(completed.stdout)
            self.assertEqual(document, {
                "status": "created",
                "artifact": f"listen-gen-{VERSION}/{PYZ_NAME}",
                "manifest": f"listen-gen-{VERSION}/{MANIFEST_NAME}",
            })
            self.assertEqual(
                completed.stdout,
                canonical_json_file_bytes(document).decode("utf-8"),
            )
            bundle = Path(tmp) / f"listen-gen-{VERSION}"
            self.assertEqual(
                sorted(path.name for path in bundle.iterdir()),
                sorted([MANIFEST_NAME, PYZ_NAME]),
            )
            mode = (bundle / PYZ_NAME).stat().st_mode & 0o777
            self.assertEqual(mode, 0o755)
            verify = run_tool(["verify", str(bundle / MANIFEST_NAME)])
            self.assertEqual(verify.returncode, 0, verify.stderr)


class StrictVerifierTests(ReleaseBundleTestBase):
    def assert_manifest_rejected(self, raw: bytes) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _, manifest = self.copy_bundle(Path(tmp))
            manifest.write_bytes(raw)
            with self.assertRaises(rb.ReleaseBundleError) as caught:
                rb.verify_release_bundle(ROOT, manifest)
            self.assertEqual(str(caught.exception), "release manifest is invalid")

    def test_non_canonical_manifest_variants_rejected(self) -> None:
        parsed = json.loads(self.manifest.read_bytes())
        pretty = (
            json.dumps(parsed, ensure_ascii=False, sort_keys=True, indent=2)
            + "\n"
        ).encode("utf-8")
        self.assert_manifest_rejected(pretty)
        self.assert_manifest_rejected(canonical_json_bytes(parsed))
        self.assert_manifest_rejected(canonical_json_file_bytes(parsed) + b"\n")
        self.assert_manifest_rejected(b" " + canonical_json_file_bytes(parsed))
        ordered = {}
        for key in reversed(sorted(parsed)):
            ordered[key] = parsed[key]
        reordered = (
            json.dumps(
                ordered,
                ensure_ascii=False,
                separators=(",", ":"),
                allow_nan=False,
            )
            + "\n"
        ).encode("utf-8")
        self.assertEqual(json.loads(reordered), parsed)
        self.assert_manifest_rejected(reordered)

    def test_duplicate_json_keys_rejected(self) -> None:
        text = self.manifest.read_bytes().decode("utf-8")
        duplicated_root = (
            '{"schema":"listen_gen.release-bundle.v1",' + text[1:]
        ).encode("utf-8")
        self.assertEqual(json.loads(duplicated_root), json.loads(text))
        self.assert_manifest_rejected(duplicated_root)
        parsed = json.loads(text)
        sha = parsed["artifact"]["sha256"]
        needle = f'"sha256":"{sha}"'
        self.assertIn(needle, text)
        duplicated_sha = text.replace(
            needle, f'{needle},"sha256":"{sha}"', 1
        ).encode("utf-8")
        self.assertEqual(json.loads(duplicated_sha), parsed)
        self.assert_manifest_rejected(duplicated_sha)

    def test_invalid_artifact_sha_formats(self) -> None:
        hex64 = hashlib.sha256(b"artifact").hexdigest()
        invalid_values = [
            "sha256:",
            "sha256:abc",
            "sha256:" + hex64[:63],
            "sha256:" + hex64 + "a",
            "sha256:" + hex64.upper(),
            "sha256:" + hex64 + "extra",
        ]
        parsed = json.loads(self.manifest.read_bytes())
        for value in invalid_values:
            with tempfile.TemporaryDirectory() as tmp:
                artifact, manifest = self.copy_bundle(Path(tmp))
                # Removing the artifact proves the format error precedes the
                # checksum stage: it must not report a missing artifact.
                artifact.unlink()
                parsed["artifact"]["sha256"] = value
                manifest.write_bytes(canonical_json_file_bytes(parsed))
                with self.assertRaises(rb.ReleaseBundleError) as caught:
                    rb.verify_release_bundle(ROOT, manifest)
                self.assertEqual(
                    str(caught.exception), "release manifest is invalid", value
                )

    def test_bool_cannot_impersonate_integers(self) -> None:
        mutations = [
            lambda document: document["machine_protocol"].__setitem__("version", True),
            lambda document: document["content_package_contract"].__setitem__(
                "schema_version", True
            ),
            lambda document: document["artifact"].__setitem__("size_bytes", True),
        ]
        for mutate in mutations:
            variant = json.loads(self.manifest.read_bytes())
            mutate(variant)
            self.assert_manifest_rejected(canonical_json_file_bytes(variant))

    def test_manifest_tool_version_must_match_source(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            artifact, manifest = self.copy_bundle(Path(tmp))
            # Forge a 9.9.9 bundle: names stay internally consistent and the
            # artifact bytes, size, and SHA are untouched.
            forged_artifact = artifact.parent / "listen-gen-9.9.9.pyz"
            artifact.rename(forged_artifact)
            parsed = json.loads(manifest.read_bytes())
            parsed["tool"]["version"] = "9.9.9"
            parsed["artifact"]["filename"] = "listen-gen-9.9.9.pyz"
            forged_manifest = artifact.parent / "listen-gen-9.9.9.release.json"
            manifest.rename(forged_manifest)
            forged_manifest.write_bytes(canonical_json_file_bytes(parsed))
            with self.assertRaises(rb.ReleaseBundleError) as caught:
                rb.verify_release_bundle(ROOT, forged_manifest)
            self.assertEqual(str(caught.exception), "release manifest is invalid")


class RuntimeIdentityVerifierTests(ReleaseBundleTestBase):
    def assert_manifest_rejected(self, raw: bytes) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            _, manifest = self.copy_bundle(Path(tmp))
            manifest.write_bytes(raw)
            with self.assertRaises(rb.ReleaseBundleError) as caught:
                rb.verify_release_bundle(ROOT, manifest)
            self.assertEqual(str(caught.exception), "release manifest is invalid")

    def test_bool_cannot_impersonate_identity_versions(self) -> None:
        mutations = [
            lambda document: document["runtime_identity"].__setitem__(
                "version", True
            ),
            lambda document: document["runtime_identity"]["toolchain"].__setitem__(
                "version", True
            ),
        ]
        for mutate in mutations:
            variant = json.loads(self.manifest.read_bytes())
            mutate(variant)
            self.assert_manifest_rejected(canonical_json_file_bytes(variant))

    def test_identity_schema_or_version_tamper_rejected(self) -> None:
        parsed = json.loads(self.manifest.read_bytes())
        variants = []
        identity = parsed["runtime_identity"]
        identity["schema"] = "listen_gen.runtime-identity.v2"
        variants.append(canonical_json_file_bytes(parsed))
        identity["schema"] = "listen_gen.runtime-identity.v1"
        identity["version"] = 2
        variants.append(canonical_json_file_bytes(parsed))
        identity["version"] = 1
        identity["toolchain"]["schema"] = "listen_gen.toolchain-identity.v2"
        variants.append(canonical_json_file_bytes(parsed))
        identity["toolchain"]["schema"] = "listen_gen.toolchain-identity.v1"
        identity["toolchain"]["version"] = 2
        variants.append(canonical_json_file_bytes(parsed))
        for raw in variants:
            self.assert_manifest_rejected(raw)

    def test_runtime_identity_family_or_requires_tamper_rejected(self) -> None:
        parsed = json.loads(self.manifest.read_bytes())
        variants = []
        runtime = parsed["runtime_identity"]["runtime"]
        runtime["family"] = "cpython"
        variants.append(canonical_json_file_bytes(parsed))
        runtime["family"] = "python"
        runtime["requires"] = ">=3.10"
        variants.append(canonical_json_file_bytes(parsed))
        for raw in variants:
            self.assert_manifest_rejected(raw)

    def test_runtime_identity_requires_must_match_runtime(self) -> None:
        parsed = json.loads(self.manifest.read_bytes())
        # The identity requires must stay coherent with the top-level runtime.
        parsed["runtime_identity"]["runtime"]["requires"] = ">=3.12"
        self.assert_manifest_rejected(canonical_json_file_bytes(parsed))

    def test_toolchain_mutation_rejected(self) -> None:
        variants = []
        parsed = json.loads(self.manifest.read_bytes())
        tools = parsed["runtime_identity"]["toolchain"]["tools"]
        tools[0]["id"] = "evil-tool"
        variants.append(canonical_json_file_bytes(parsed))
        tools[0]["id"] = "asr-wrapper"
        tools[0]["roles"] = ["evil"]
        variants.append(canonical_json_file_bytes(parsed))
        tools[0]["roles"] = ["asr"]
        tools[0]["extra"] = True
        variants.append(canonical_json_file_bytes(parsed))
        del tools[0]["roles"]
        variants.append(canonical_json_file_bytes(parsed))
        tools[0] = {"id": "asr-wrapper", "roles": ["asr"]}
        del parsed["runtime_identity"]["toolchain"]["tools"]
        variants.append(canonical_json_file_bytes(parsed))
        for raw in variants:
            self.assert_manifest_rejected(raw)

    def test_toolchain_unsorted_rejected(self) -> None:
        parsed = json.loads(self.manifest.read_bytes())
        tools = parsed["runtime_identity"]["toolchain"]["tools"]
        parsed["runtime_identity"]["toolchain"]["tools"] = list(reversed(tools))
        self.assert_manifest_rejected(canonical_json_file_bytes(parsed))

    def test_canonical_toolchain_matches_provider_requirements(self) -> None:
        # The canonical toolchain is exactly the union of provider tools and
        # every role is a known Gen stage family.
        required = {
            tool
            for tools in rb.PROVIDER_REQUIREMENTS.values()
            for tool in tools
        }
        self.assertEqual(set(rb.TOOLCHAIN_ROLES), required)
        known_roles = set(rb.RUNTIME_ROLE_NAMES)
        for tool_id, roles in rb.TOOLCHAIN_ROLES.items():
            self.assertTrue(tool_id)
            self.assertEqual(len(roles), len(set(roles)))
            self.assertTrue(set(roles) <= known_roles)
        tools = rb._canonical_toolchain()
        self.assertEqual([tool["id"] for tool in tools], sorted(tool["id"] for tool in tools))
        self.assertEqual(
            {tool["id"] for tool in tools}, set(rb.TOOLCHAIN_ROLES)
        )


class ModuleIsolationAndSourceTests(unittest.TestCase):
    def test_repo_root_module_isolation(self) -> None:
        root = copy_repo_root("isolated-repo-")
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        protocol_file = root / "src" / "listen_gen" / "protocol_v2.py"
        with protocol_file.open("a", encoding="utf-8") as handle:
            handle.write('\nTOOL_VERSION = "9.9.9"\n')
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(rb.ReleaseBundleError) as caught:
                rb.build_release_bundle(root, Path(tmp), FAKE_COMMIT)
            self.assertEqual(str(caught.exception), "release manifest is invalid")
        # The test process's cached real modules must be fully restored.
        self.assertEqual(protocol.TOOL_VERSION, VERSION)

    def test_verifier_rejects_project_protocol_version_drift(self) -> None:
        root = copy_repo_root("drift-repo-")
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        pyproject = root / "pyproject.toml"
        pyproject.write_text(
            pyproject.read_text("utf-8").replace(
                'version = "0.5.0"', 'version = "9.9.9"', 1
            )
        )
        # The checkout protocol identity stays at 0.5.0.
        self.assertEqual(protocol.TOOL_VERSION, VERSION)
        with tempfile.TemporaryDirectory() as tmp:
            _, manifest = rb.build_release_bundle(ROOT, Path(tmp), FAKE_COMMIT)
            with self.assertRaises(rb.ReleaseBundleError) as caught:
                rb.verify_release_bundle(root, manifest)
            self.assertEqual(str(caught.exception), "release manifest is invalid")

    def test_non_utf8_python_source_rejected(self) -> None:
        root = copy_repo_root("bad-utf8-repo-")
        self.addCleanup(shutil.rmtree, root, ignore_errors=True)
        (root / "src" / "listen_gen" / "invalid_source.py").write_bytes(b"\xff\xfe")
        with tempfile.TemporaryDirectory() as tmp:
            output_parent = Path(tmp)
            unrelated = output_parent / "keep.txt"
            unrelated.write_text("keep me\n")
            with self.assertRaises(rb.ReleaseBundleError) as caught:
                rb.build_release_bundle(root, output_parent, FAKE_COMMIT)
            self.assertEqual(
                str(caught.exception),
                "release archive content does not match source",
            )
            self.assertFalse((output_parent / f"listen-gen-{VERSION}").exists())
            leftovers = [
                path.name for path in output_parent.iterdir()
                if ".staging." in path.name
            ]
            self.assertEqual(leftovers, [])
            self.assertEqual(unrelated.read_text(), "keep me\n")


if __name__ == "__main__":
    unittest.main()
