import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import repo_status as status


def make_repo(root: Path) -> None:
    """一个最小的 core 形状仓库，够 file_at / distance / tag 用。"""
    subprocess.run(["git", "init", "-q", "-b", "main", str(root)], check=True)
    subprocess.run(
        ["git", "-C", str(root), "config", "user.email", "t@example.com"], check=True
    )
    subprocess.run(["git", "-C", str(root), "config", "user.name", "t"], check=True)


def commit(root: Path, files: dict[str, str], message: str) -> str:
    for name, body in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(body)
    subprocess.run(["git", "-C", str(root), "add", "-A"], check=True)
    subprocess.run(["git", "-C", str(root), "commit", "-q", "-m", message], check=True)
    return subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()


def rust_lib(version: str) -> str:
    return (
        "pub const API_VERSION: u16 = 1;\n"
        f'pub const CONTRACT_VERSION: &str = "{version}";\n'
    )


def openapi(version: str) -> str:
    return f"openapi: 3.1.0\ninfo:\n  title: t\n  version: {version}\n"


class ParsingTests(unittest.TestCase):
    def test_reads_contract_version_from_the_pinned_commit_not_the_worktree(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_repo(root)
            old = commit(
                root,
                {
                    "crates/api-http/src/lib.rs": rust_lib("1.0.0"),
                    "contracts/openapi/v1.yaml": openapi("1.0.0"),
                },
                "contract 1.0.0",
            )
            commit(
                root,
                {
                    "crates/api-http/src/lib.rs": rust_lib("1.1.0"),
                    "contracts/openapi/v1.yaml": openapi("1.1.0"),
                },
                "contract 1.1.0",
            )
            core = status.Repo("listen-core", root)

            # 工作区已经是 1.1.0，但被钉的那个 commit 仍然是 1.0.0。
            self.assertEqual(status.contract_version_at(core, old), "1.0.0")
            self.assertEqual(status.openapi_version_at(core, old), "1.0.0")

    def test_missing_file_yields_none_rather_than_raising(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_repo(root)
            sha = commit(root, {"README.md": "hi\n"}, "init")
            core = status.Repo("listen-core", root)
            self.assertIsNone(status.contract_version_at(core, sha))


class GitHelperTests(unittest.TestCase):
    def test_non_repository_returns_none_instead_of_raising(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertIsNone(status.git(Path(tmp), "log", "-1"))

    def test_absent_repo_reports_not_present(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = status.Repo("listen-gen", Path(tmp) / "nope")
            self.assertFalse(repo.present)


class ConsistencyTests(unittest.TestCase):
    def test_missing_core_checkout_degrades_with_one_clear_problem(self):
        with tempfile.TemporaryDirectory() as tmp:
            core = status.Repo("listen-core", Path(tmp) / "absent")
            pins = [status.Pin("listen-app", "deadbeef" * 5, "backend.lock.json")]
            problems = status.check_consistency(core, pins)
            self.assertEqual(len(problems), 1)
            self.assertIn("listen-core", problems[0])

    def test_flags_lock_file_recording_a_version_the_commit_never_declared(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_repo(root)
            sha = commit(
                root,
                {
                    "crates/api-http/src/lib.rs": rust_lib("1.0.0"),
                    "contracts/openapi/v1.yaml": openapi("1.0.0"),
                },
                "contract 1.0.0",
            )
            core = status.Repo("listen-core", root)
            pins = [
                status.Pin(
                    "listen-app",
                    sha,
                    "backend.lock.json",
                    extra={"contract": "1.1.0"},  # lock 抄错了
                )
            ]
            problems = status.check_consistency(core, pins)
            self.assertTrue(
                any("实际声明 CONTRACT_VERSION=1.0.0" in p for p in problems),
                problems,
            )

    def test_flags_core_disagreeing_with_its_own_openapi(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_repo(root)
            sha = commit(
                root,
                {
                    "crates/api-http/src/lib.rs": rust_lib("1.1.0"),
                    "contracts/openapi/v1.yaml": openapi("1.0.0"),  # 内部漂移
                },
                "mismatched",
            )
            core = status.Repo("listen-core", root)
            pins = [
                status.Pin(
                    "listen-app", sha, "backend.lock.json", extra={"contract": "1.1.0"}
                )
            ]
            problems = status.check_consistency(core, pins)
            self.assertTrue(any("自身不一致" in p for p in problems), problems)

    def test_flags_consumers_pinning_different_commits(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_repo(root)
            first = commit(root, {"a.txt": "1\n"}, "first")
            second = commit(root, {"a.txt": "2\n"}, "second")
            core = status.Repo("listen-core", root)
            pins = [
                status.Pin("listen-app", second, "backend.lock.json"),
                status.Pin("listen-gen", first, "contracts.lock.json"),
            ]
            problems = status.check_consistency(core, pins)
            self.assertTrue(
                any("钉着不同的 core commit" in p for p in problems), problems
            )

    def test_agreeing_consumers_produce_no_pin_divergence_problem(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_repo(root)
            sha = commit(root, {"a.txt": "1\n"}, "only")
            core = status.Repo("listen-core", root)
            pins = [
                status.Pin("listen-app", sha, "backend.lock.json"),
                status.Pin("listen-gen", sha, "contracts.lock.json"),
            ]
            problems = status.check_consistency(core, pins)
            self.assertFalse(
                any("钉着不同的 core commit" in p for p in problems), problems
            )

    def test_pin_reachable_only_from_a_second_worktree_is_not_called_behind(self):
        """core 的实际布局：主 checkout 停在功能分支，main 住在另一个 worktree。
        只看主 checkout 会把这误报成「本地落后于消费方」。"""
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "core"
            make_repo(root)
            base = commit(root, {"a.txt": "1\n"}, "base")
            newer = commit(root, {"a.txt": "2\n"}, "newer")
            # 主 checkout 退回旧提交所在的功能分支
            subprocess.run(
                ["git", "-C", str(root), "switch", "-q", "-c", "feature", base],
                check=True,
            )
            # main 仍指向 newer，挂在另一个 worktree 上
            tree = Path(tmp) / "wt"
            subprocess.run(
                ["git", "-C", str(root), "worktree", "add", "-q", str(tree), "main"],
                check=True,
            )
            core = status.Repo("listen-core", root)

            self.assertEqual(core.head[:7], base[:7])  # 主 checkout 确实是旧的
            problems = status.check_consistency(
                core, [status.Pin("listen-app", newer, "backend.lock.json")]
            )
            self.assertFalse(
                any("够不着" in p for p in problems),
                f"main worktree 里就有这个 commit，不该报够不着: {problems}",
            )
            self.assertIn("main", status.locate_pin(core, newer) or "")

    def test_unresolvable_pin_is_reported_not_silently_skipped(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            make_repo(root)
            commit(root, {"a.txt": "1\n"}, "only")
            core = status.Repo("listen-core", root)
            pins = [status.Pin("listen-app", "0" * 40, "backend.lock.json")]
            problems = status.check_consistency(core, pins)
            self.assertTrue(any("解析不到" in p for p in problems), problems)


if __name__ == "__main__":
    unittest.main()
