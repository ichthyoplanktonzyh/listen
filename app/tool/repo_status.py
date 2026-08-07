#!/usr/bin/env python3
"""三仓协作状态：当场读当场算。

这个脚本刻意不写任何中间状态文件。跨仓状态曾经手抄在 `.planning/STATE.md`
里，抄错了没有任何机制会发现——2026-08-04 的实测里，同一个仓库的 STATE.md 和
backend.lock.json 对 core 的 pin 说了两个不同的 commit 和两个不同的契约版本。
所以这里只有派生，没有存储。

真源：
  listen-app/backend.lock.json      app 消费 core 的哪个不可变产物
  listen-gen/contracts.lock.json    gen 钉着 core 的哪份 content-package schema
  三个仓库的 git 状态本身

只读本地 checkout，不做任何网络操作。core 的本地 checkout 可能落后于远端，
输出里会标出来，但脚本不会替你 fetch。
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SIBLINGS = {
    "listen-app": APP_ROOT,
    "listen-core": APP_ROOT.parent / "listen-core",
    "listen-gen": APP_ROOT.parent / "listen-gen",
}


def git(repo: Path, *args: str) -> str | None:
    """跑一条只读 git 命令。仓库不存在或命令失败时返回 None，不抛。"""
    if not (repo / ".git").exists():
        return None
    try:
        out = subprocess.run(
            ["git", "-C", str(repo), *args],
            capture_output=True,
            text=True,
            timeout=15,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    return out.stdout.strip()


@dataclass
class Repo:
    name: str
    path: Path

    @property
    def present(self) -> bool:
        return (self.path / ".git").exists()

    @property
    def branch(self) -> str:
        return git(self.path, "branch", "--show-current") or "(detached)"

    @property
    def head(self) -> str:
        return git(self.path, "log", "-1", "--format=%h") or "?"

    @property
    def head_date(self) -> str:
        return git(self.path, "log", "-1", "--format=%ai") or "?"

    @property
    def dirty(self) -> bool:
        status = git(self.path, "status", "--porcelain")
        return bool(status)

    @property
    def has_remote(self) -> bool:
        return bool(git(self.path, "remote"))

    def commit_date(self, sha: str) -> str | None:
        return git(self.path, "log", "-1", "--format=%ai", sha)

    def commit_subject(self, sha: str) -> str | None:
        return git(self.path, "log", "-1", "--format=%s", sha)

    def distance(self, frm: str, to: str) -> int | None:
        """frm..to 之间的提交数。任一端解析不了就返回 None。"""
        out = git(self.path, "rev-list", "--count", f"{frm}..{to}")
        if out is None or not out.isdigit():
            return None
        return int(out)

    def latest_tag(self) -> str | None:
        return git(self.path, "describe", "--tags", "--abbrev=0")

    def worktrees(self) -> list[tuple[Path, str, str]]:
        """(路径, 分支, HEAD)。一个仓库可以有很多 checkout——core 目前有 8 个，
        `main` 住在其中一个里。只看主 checkout 会把「主 checkout 停在功能分支上」
        误报成「本地落后于消费方」。"""
        out = git(self.path, "worktree", "list", "--porcelain")
        if not out:
            return []
        trees: list[tuple[Path, str, str]] = []
        path: Path | None = None
        head = ""
        for line in out.splitlines():
            if line.startswith("worktree "):
                path = Path(line[len("worktree ") :])
                head = ""
            elif line.startswith("HEAD "):
                head = line[len("HEAD ") :]
            elif line.startswith("branch ") and path is not None:
                branch = line[len("branch ") :].removeprefix("refs/heads/")
                trees.append((path, branch, head))
                path = None
            elif line == "detached" and path is not None:
                trees.append((path, "(detached)", head))
                path = None
        return trees

    def contains(self, sha: str, ref: str) -> bool:
        """sha 是否可以从 ref 到达。"""
        return (
            git(self.path, "merge-base", "--is-ancestor", sha, ref) is not None
        )

    def file_at(self, sha: str, path: str) -> str | None:
        """读某个 commit 里的文件内容。用来核对 lock 记的版本是否真是那个
        commit 声明的版本——只看工作区会读到「本地 checkout 恰好在哪」，
        那不是被消费的东西。"""
        return git(self.path, "show", f"{sha}:{path}")


CONTRACT_CONST = re.compile(r'CONTRACT_VERSION:\s*&str\s*=\s*"([^"]+)"')
OPENAPI_VERSION = re.compile(r"^\s{2}version:\s*(\S+)", re.MULTILINE)


def contract_version_at(core: Repo, sha: str) -> str | None:
    """某个 core commit 声明的契约版本（以 Rust 常量为准，它是运行时真正报出去的）。"""
    source = core.file_at(sha, "crates/api-http/src/lib.rs")
    if not source:
        return None
    found = CONTRACT_CONST.search(source)
    return found.group(1) if found else None


def openapi_version_at(core: Repo, sha: str) -> str | None:
    source = core.file_at(sha, "contracts/openapi/v1.yaml")
    if not source:
        return None
    found = OPENAPI_VERSION.search(source)
    return found.group(1) if found else None


@dataclass
class Pin:
    """一条「谁钉了 core 的什么」记录。"""

    consumer: str
    sha: str
    source_file: str
    extra: dict[str, str] = field(default_factory=dict)


def read_json(path: Path) -> dict | None:
    try:
        return json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None


def collect_pins(repos: dict[str, Repo]) -> list[Pin]:
    pins: list[Pin] = []

    app = repos["listen-app"]
    lock = read_json(app.path / "backend.lock.json")
    if lock:
        contract = lock.get("contract", {})
        runtime = lock.get("runtime", {})
        extra = {
            "contract": contract.get("version", "?"),
            "runtime": runtime.get("version", "?"),
        }
        # url 留空说明产物不是从 URL 拉的。留一个永远为空的字段会误导下一个读者，
        # 所以这里显式点出来而不是静默跳过。
        empty_urls = [
            key
            for key, block in (("contract", contract), ("runtime", runtime))
            if not block.get("url")
        ]
        if empty_urls:
            extra["url 缺失"] = ", ".join(empty_urls)
        pins.append(
            Pin(
                consumer="listen-app",
                sha=lock.get("core_git_sha", ""),
                source_file="backend.lock.json",
                extra=extra,
            )
        )

    gen = repos["listen-gen"]
    lock = read_json(gen.path / "contracts.lock.json")
    if lock:
        authority = lock.get("authority", {})
        pins.append(
            Pin(
                consumer="listen-gen",
                sha=authority.get("commit", ""),
                source_file="contracts.lock.json",
                extra={
                    "schema": authority.get("path", "?"),
                    "schema_version": str(lock.get("schema_version", "?")),
                },
            )
        )

    return pins


def check_consistency(core: Repo, pins: list[Pin]) -> list[str]:
    """返回需要人看一眼的问题。没问题就返回空列表。"""
    problems: list[str] = []

    if not core.present:
        problems.append(
            "listen-core 本地 checkout 不存在，无法校验任何 pin。"
            "（日常 app 开发不需要它，但这个脚本需要。）"
        )
        return problems

    resolved = [(p, core.commit_date(p.sha)) for p in pins if p.sha]

    for pin, date in resolved:
        if date is None:
            problems.append(
                f"{pin.consumer} 钉的 core commit {pin.sha[:8]} 在本地 core 里解析不到"
                f"（{pin.source_file}）。可能是本地落后，也可能是钉了个不存在的 commit。"
            )

    known = [(p, d) for p, d in resolved if d is not None]

    # 消费方之间是否钉着不同的 core commit
    shas = {p.sha for p, _ in known}
    if len(shas) > 1:
        pairs = sorted(known, key=lambda item: item[1])
        oldest, newest = pairs[0], pairs[-1]
        gap = core.distance(oldest[0].sha, newest[0].sha)
        gap_text = f"，相差 {gap} 个提交" if gap is not None else ""
        problems.append(
            f"消费方钉着不同的 core commit：{oldest[0].consumer} 在 "
            f"{oldest[0].sha[:8]}（{oldest[1][:16]}），{newest[0].consumer} 在 "
            f"{newest[0].sha[:8]}（{newest[1][:16]}）{gap_text}。"
        )

    # lock 里手写的契约版本，是否真是那个 commit 声明的版本
    for pin, _ in known:
        recorded = pin.extra.get("contract")
        if not recorded or recorded == "?":
            continue
        declared = contract_version_at(core, pin.sha)
        if declared and declared != recorded:
            problems.append(
                f"{pin.consumer} 的 {pin.source_file} 记着 contract {recorded}，"
                f"但被钉的 {pin.sha[:8]} 实际声明 CONTRACT_VERSION={declared}。"
            )
        openapi = openapi_version_at(core, pin.sha)
        if declared and openapi and openapi != declared:
            problems.append(
                f"core {pin.sha[:8]} 自身不一致：Rust 常量 CONTRACT_VERSION={declared}，"
                f"而 contracts/openapi/v1.yaml 写 {openapi}。"
            )

    # 被钉的 commit 是否在已发布的 tag 之内
    tag = core.latest_tag()
    if tag:
        for pin, _ in known:
            ahead = core.distance(tag, pin.sha)
            if ahead:
                problems.append(
                    f"{pin.consumer} 钉的 {pin.sha[:8]} 领先最新 tag {tag} {ahead} 个提交——"
                    f"消费的是未打 tag 的 commit，不可变性只靠 sha256 兜着。"
                )

    # 被钉的 commit 在本地任何一个 checkout 里都够不着，才算真的落后。
    trees = core.worktrees()
    for pin, _ in known:
        if any(core.contains(pin.sha, head or branch) for _, branch, head in trees):
            continue
        problems.append(
            f"{pin.consumer} 钉的 {pin.sha[:8]} 在本地任何 checkout 里都够不着——"
            f"先 git fetch，再看它是否真的存在于 core。"
        )

    return problems


def locate_pin(core: Repo, sha: str) -> str | None:
    """被钉的 commit 落在哪个本地 checkout 上。优先报告 HEAD 恰好等于它的那个。"""
    if not core.present or not sha:
        return None
    # 多个 worktree 可能停在同一个 commit 上。优先报 main——「app 钉的就是 main」
    # 比「app 钉的等于某个功能分支的当前位置」有用得多。
    trees = sorted(core.worktrees(), key=lambda t: t[1] != "main")
    for path, branch, head in trees:
        if head == sha:
            return f"{branch} @ {path.name}"
    for path, branch, head in trees:
        if core.contains(sha, head or branch):
            ahead = core.distance(sha, head or branch)
            gap = f"，该分支已前进 {ahead} 个提交" if ahead else ""
            return f"包含于 {branch} @ {path.name}{gap}"
    return None


def render_text(repos: dict[str, Repo], pins: list[Pin], problems: list[str]) -> str:
    lines = [f"listen 三仓状态  ({datetime.now():%Y-%m-%d %H:%M})", ""]

    for repo in repos.values():
        if not repo.present:
            lines.append(f"  {repo.name:<14} (本地不存在: {repo.path})")
            continue
        flags = []
        if repo.dirty:
            flags.append("dirty")
        if not repo.has_remote:
            flags.append("无 remote")
        extra_trees = len(repo.worktrees()) - 1
        if extra_trees > 0:
            flags.append(f"另有 {extra_trees} 个 worktree")
        suffix = f"  [{', '.join(flags)}]" if flags else ""
        lines.append(
            f"  {repo.name:<14} {repo.branch:<34} {repo.head}  "
            f"{repo.head_date[:16]}{suffix}"
        )

    core = repos["listen-core"]
    lines += ["", "契约 pin（→ listen-core）"]
    if not pins:
        lines.append("  (没找到任何 lock 文件)")
    for pin in pins:
        date = core.commit_date(pin.sha) if core.present and pin.sha else None
        subject = core.commit_subject(pin.sha) if core.present and pin.sha else None
        when = date[:16] if date else "解析不到"
        detail = "  ".join(f"{k} {v}" for k, v in pin.extra.items())
        lines.append(f"  {pin.consumer:<12} {pin.sha[:8]}  {when}  {detail}")
        if subject:
            lines.append(f"  {'':<12} └ {subject}")
        where = locate_pin(core, pin.sha)
        if where:
            lines.append(f"  {'':<12}   本地: {where}")
        lines.append(f"  {'':<12}   源: {pin.source_file}")

    lines += ["", "一致性"]
    if problems:
        lines += [f"  ⚠ {p}" for p in problems]
    else:
        lines.append("  ✓ 未发现问题")

    return "\n".join(lines)


def render_markdown(
    repos: dict[str, Repo], pins: list[Pin], problems: list[str]
) -> str:
    core = repos["listen-core"]
    lines = [
        f"## listen 三仓状态 ({datetime.now():%Y-%m-%d %H:%M})",
        "",
        "| 仓库 | 分支 | HEAD | 时间 | 备注 |",
        "| --- | --- | --- | --- | --- |",
    ]
    for repo in repos.values():
        if not repo.present:
            lines.append(f"| `{repo.name}` | — | — | — | 本地不存在 |")
            continue
        flags = []
        if repo.dirty:
            flags.append("dirty")
        if not repo.has_remote:
            flags.append("无 remote")
        lines.append(
            f"| `{repo.name}` | `{repo.branch}` | `{repo.head}` | "
            f"{repo.head_date[:16]} | {', '.join(flags) or '—'} |"
        )

    lines += ["", "### 契约 pin（→ listen-core）", ""]
    lines += ["| 消费方 | core commit | 时间 | 详情 | 源 |", "| --- | --- | --- | --- | --- |"]
    for pin in pins:
        date = core.commit_date(pin.sha) if core.present and pin.sha else None
        detail = ", ".join(f"{k} {v}" for k, v in pin.extra.items())
        lines.append(
            f"| `{pin.consumer}` | `{pin.sha[:8]}` | {date[:16] if date else '解析不到'} "
            f"| {detail} | `{pin.source_file}` |"
        )

    lines += ["", "### 一致性", ""]
    lines += [f"- ⚠ {p}" for p in problems] if problems else ["- ✓ 未发现问题"]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--markdown", action="store_true", help="输出 markdown，便于贴进 issue"
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="发现一致性问题时以非零码退出",
    )
    args = parser.parse_args()

    repos = {name: Repo(name, path) for name, path in DEFAULT_SIBLINGS.items()}
    pins = collect_pins(repos)
    problems = check_consistency(repos["listen-core"], pins)

    render = render_markdown if args.markdown else render_text
    print(render(repos, pins, problems))

    return 1 if (args.strict and problems) else 0


if __name__ == "__main__":
    sys.exit(main())
