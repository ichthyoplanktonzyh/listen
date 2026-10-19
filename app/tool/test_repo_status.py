import argparse
import hashlib
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import repo_status as status


RELEASE_SCHEMA = '{"title":"content package v3 release"}\n'
RELEASE_SCHEMA_SHA = "sha256:" + hashlib.sha256(RELEASE_SCHEMA.encode()).hexdigest()


def make_repo(root: Path) -> None:
    subprocess.run(["git", "init", "-q", "-b", "main", str(root)], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.email", "t@example.com"], check=True)
    subprocess.run(["git", "-C", str(root), "config", "user.name", "t"], check=True)


def commit(root: Path, files: dict[str, str], message: str = "fixture") -> str:
    for name, body in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)
    subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(root), "commit", "-q", "-m", message], check=True)
    return subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()


def contract_lock() -> dict:
    return {
        "authority": {"path": "contracts/content-package/v3", "repository": "owner/listen-core"},
        "package_schema": "listen.content-package.release.v3",
        "release_schema_id": "listen.content-package.release.v3",
        "schema_version": 3,
    }


def write_locks(app: Path, core_sha: str, gen_sha: str, contract: dict) -> None:
    (app / "backend.lock.json").write_text(json.dumps({
        "core_git_sha": core_sha,
        "contract": {"version": "1.1.0"},
        "runtime": {"version": "0.7.0"},
    }))
    (app / "listen_gen.lock.json").write_text(json.dumps({
        "source_git_sha": gen_sha,
        "tool": {"version": "0.2.0"},
        "content_package_contract": {
            **contract,
            "contract_version": "1.1.0",
            "canonical_sha256": RELEASE_SCHEMA_SHA,
        },
    }))


def write_app_requirements(app: Path) -> None:
    target = app / "lib/services/api_service.dart"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(
        "const supportedContractMajor = 4;\n"
        "const supportedContractMinor = 0;\n"
    )


class DiscoveryTests(unittest.TestCase):
    def test_worktree_discovers_siblings_beside_canonical_checkout(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            main = root / "listen-app"
            make_repo(main)
            commit(main, {"README.md": "app\n"})
            worktree = root / "worktrees" / "feature"
            worktree.parent.mkdir()
            subprocess.run(["git", "-C", str(main), "worktree", "add", "-q", "-b", "feature", str(worktree)], check=True)
            paths = status.discover_repositories(worktree)
            self.assertEqual(paths["listen-core"], (root / "listen-core").resolve())
            self.assertEqual(paths["listen-gen"], (root / "listen-gen").resolve())

    def test_normal_checkout_discovers_ordinary_siblings(self):
        with tempfile.TemporaryDirectory() as tmp:
            app = Path(tmp) / "listen-app"
            make_repo(app)
            commit(app, {"README.md": "app\n"})
            paths = status.discover_repositories(app)
            self.assertEqual(paths["listen-core"], (Path(tmp) / "listen-core").resolve())

    def test_cli_overrides_environment_and_environment_overrides_discovery(self):
        args = argparse.Namespace(app_repo="/cli/app", core_repo="/cli/core", gen_repo=None)
        with mock.patch.dict(os.environ, {
            "LISTEN_APP_REPO": "/env/app",
            "LISTEN_CORE_REPO": "/env/core",
            "LISTEN_GEN_REPO": "/env/gen",
        }):
            paths = status.resolve_repository_paths(args)
        self.assertEqual(paths["listen-app"], Path("/cli/app"))
        self.assertEqual(paths["listen-core"], Path("/cli/core"))
        self.assertEqual(paths["listen-gen"], Path("/env/gen"))


class ContractTests(unittest.TestCase):
    def test_gen_contract_lock_fields_match_without_conflating_schema_digest(self):
        lock = contract_lock()
        self.assertEqual(status.compare_contract_locks({
            **lock, "canonical_sha256": RELEASE_SCHEMA_SHA
        }, lock), [])

    def test_contract_lock_field_mismatches_are_reported(self):
        gen = contract_lock()
        app = {**gen, "schema_version": 2, "canonical_sha256": RELEASE_SCHEMA_SHA}
        problems = status.compare_contract_locks(app, gen)
        self.assertTrue(any("schema_version" in problem for problem in problems))

    def test_real_shaped_locks_and_resolvable_pins_are_consistent(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app, core, gen = root / "listen-app", root / "listen-core", root / "listen-gen"
            app.mkdir()
            make_repo(app)
            write_app_requirements(app)
            commit(app, {"README.md": "app\n"})
            make_repo(core)
            core_sha = commit(core, {
                "crates/api-http/src/lib.rs": 'pub const CONTRACT_VERSION: &str = "1.1.0";\n',
                "contracts/openapi/v1.yaml": "info:\n  version: 1.1.0\n",
                "contracts/content-package/v3/release.schema.json": RELEASE_SCHEMA,
            })
            make_repo(gen)
            lock = contract_lock()
            gen_sha = commit(gen, {"contracts.lock.json": json.dumps(lock)})
            write_locks(app, core_sha, gen_sha, lock)
            repos = {name: status.Repo(name, path) for name, path in {
                "listen-app": app, "listen-core": core, "listen-gen": gen,
            }.items()}
            _, release, requirements, integrity, runnable = status.inspect(repos)
            self.assertEqual(release.sha, gen_sha)
            self.assertEqual(integrity, [])
            self.assertTrue(
                any("Core contract" in problem for problem in runnable)
            )

    def test_contract_lock_is_compared_against_the_pinned_commit_not_head(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app, core, gen = root / "listen-app", root / "listen-core", root / "listen-gen"
            app.mkdir()
            make_repo(core)
            core_sha = commit(core, {
                "crates/api-http/src/lib.rs": 'pub const CONTRACT_VERSION: &str = "1.1.0";\n',
                "contracts/openapi/v1.yaml": "info:\n  version: 1.1.0\n",
                "contracts/content-package/v3/release.schema.json": RELEASE_SCHEMA,
            })
            make_repo(gen)
            pinned_lock = contract_lock()
            gen_sha = commit(gen, {"contracts.lock.json": json.dumps(pinned_lock)})
            write_locks(app, core_sha, gen_sha, pinned_lock)
            changed = {**pinned_lock, "schema_version": 2}
            commit(gen, {"contracts.lock.json": json.dumps(changed)}, "head drift")
            repos = {name: status.Repo(name, path) for name, path in {
                "listen-app": app, "listen-core": core, "listen-gen": gen,
            }.items()}
            _, release, _, integrity, _ = status.inspect(repos)
            self.assertEqual(release.sha, gen_sha)
            self.assertEqual(integrity, [])

    def test_app_lock_mismatching_the_pinned_gen_contract_is_an_integrity_problem(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app, core, gen = root / "listen-app", root / "listen-core", root / "listen-gen"
            app.mkdir()
            make_repo(core)
            core_sha = commit(core, {
                "crates/api-http/src/lib.rs": 'pub const CONTRACT_VERSION: &str = "1.1.0";\n',
                "contracts/openapi/v1.yaml": "info:\n  version: 1.1.0\n",
                "contracts/content-package/v3/release.schema.json": RELEASE_SCHEMA,
            })
            make_repo(gen)
            pinned_lock = contract_lock()
            gen_sha = commit(gen, {"contracts.lock.json": json.dumps(pinned_lock)})
            drifted = {**pinned_lock, "schema_version": 2}
            write_locks(app, core_sha, gen_sha, drifted)
            repos = {name: status.Repo(name, path) for name, path in {
                "listen-app": app, "listen-core": core, "listen-gen": gen,
            }.items()}
            _, _, _, integrity, _ = status.inspect(repos)
            self.assertTrue(
                any("schema_version" in problem for problem in integrity)
            )

    def test_machine_protocol_mismatch_is_a_runnable_problem_not_integrity(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            app, core, gen = root / "listen-app", root / "listen-core", root / "listen-gen"
            app.mkdir()
            make_repo(app)
            commit(app, {"README.md": "app\n"})
            make_repo(core)
            core_sha = commit(core, {
                "crates/api-http/src/lib.rs": 'pub const CONTRACT_VERSION: &str = "1.1.0";\n',
                "contracts/openapi/v1.yaml": "info:\n  version: 1.1.0\n",
                "contracts/content-package/v3/release.schema.json": RELEASE_SCHEMA,
            })
            make_repo(gen)
            lock = contract_lock()
            gen_sha = commit(gen, {"contracts.lock.json": json.dumps(lock)})
            commit(app, {
                "lib/services/listen_gen_release_service.dart": (
                    "class _ {\n"
                    "  static const _machineSchema = 'listen_gen.machine-event.v2';\n"
                    "  static const _machineVersion = 2;\n"
                    "}\n"
                ),
            }, "requirements")
            write_locks(app, core_sha, gen_sha, lock)
            repos = {name: status.Repo(name, path) for name, path in {
                "listen-app": app, "listen-core": core, "listen-gen": gen,
            }.items()}
            _, _, _, integrity, runnable = status.inspect(repos)
            self.assertEqual(integrity, [])
            self.assertTrue(
                any("machine protocol" in problem for problem in runnable)
            )

    def test_gen_checkout_must_contain_release_pin(self):
        with tempfile.TemporaryDirectory() as tmp:
            gen = Path(tmp) / "gen"
            make_repo(gen)
            pinned = commit(gen, {"a": "one"}, "pin")
            subprocess.run(["git", "-C", str(gen), "switch", "-q", "--orphan", "unrelated"], check=True)
            commit(gen, {"b": "two"}, "unrelated")
            repo = status.Repo("listen-gen", gen)
            self.assertIsNotNone(repo.commit_date(pinned))
            self.assertFalse(repo.contains(pinned))


class GitHelperTests(unittest.TestCase):
    def test_non_repository_is_not_present(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertFalse(status.Repo("missing", Path(tmp)).present)


if __name__ == "__main__":
    unittest.main()
