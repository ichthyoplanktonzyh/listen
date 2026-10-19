import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import repo_status as status


def git(root: Path, *args: str, capture: bool = False) -> str:
    result = subprocess.run(
        ["git", "-C", str(root), *args],
        check=True,
        capture_output=capture,
        text=True,
    )
    return result.stdout.strip() if capture else ""


def make_monorepo(root: Path) -> None:
    for tree, file, body in (
        ("app", "pubspec.yaml", "name: listen_app\n"),
        ("core", "Cargo.toml", "[workspace]\n"),
        ("gen", "pyproject.toml", "[project]\nname='listen-gen'\n"),
    ):
        path = root / tree / file
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)
    git(root, "init", "-q", "-b", "main")
    git(root, "config", "user.email", "t@example.com")
    git(root, "config", "user.name", "t")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "fixture")


class DiscoveryTests(unittest.TestCase):
    def test_finds_the_root_from_app_directory(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "listen"
            make_monorepo(root)
            self.assertEqual(status.discover_source_root(root / "app"), root.resolve())

    def test_worktree_reports_its_own_unified_root(self):
        with tempfile.TemporaryDirectory() as tmp:
            parent = Path(tmp)
            root = parent / "listen"
            make_monorepo(root)
            worktree = parent / "worktrees/feature"
            worktree.parent.mkdir()
            git(root, "worktree", "add", "-q", "-b", "feature", str(worktree))
            self.assertEqual(status.discover_source_root(worktree), worktree.resolve())


class StatusTests(unittest.TestCase):
    def test_single_git_root_and_all_source_trees_are_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "listen"
            make_monorepo(root)
            state = status.inspect(root)
            self.assertEqual(state.branch, "main")
            self.assertIsNotNone(state.head)
            self.assertFalse(state.dirty)
            self.assertEqual(state.problems, ())
            rendered = status.render(state, markdown=False)
            for tree in ("app", "core", "gen"):
                self.assertIn(f"{root}/{tree}/", rendered)
            self.assertNotIn("listen-core", rendered)
            self.assertNotIn("listen-gen", rendered)

    def test_dirty_workspace_is_reported_without_failing_structure(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "listen"
            make_monorepo(root)
            (root / "app/pubspec.yaml").write_text("name: changed\n")
            state = status.inspect(root)
            self.assertTrue(state.dirty)
            self.assertEqual(state.problems, ())

    def test_nested_tree_checkout_and_missing_tree_fail_strict_status(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "listen"
            make_monorepo(root)
            core = root / "core"
            git(core, "init", "-q", "-b", "nested")
            state = status.inspect(root)
            self.assertTrue(any("core/ is a separate Git checkout" in item for item in state.problems))
            (root / "gen/pyproject.toml").unlink()
            self.assertEqual(status.main(["--source-root", str(root), "--strict"]), 1)

    def test_old_multi_repository_options_are_gone(self):
        with self.assertRaises(SystemExit):
            status.parse_args(["--core-repo", "/tmp/core"])


if __name__ == "__main__":
    unittest.main()
