"""Montreal Forced Aligner plugin."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from .base import AlignerPlugin

REPO_ROOT = Path(__file__).resolve().parents[3]


def _default_mfa_bin() -> str:
    research_root = Path(
        os.environ.get(
            "LLPLAYERNEXT_MFA_DIR",
            str(Path.home() / "Library/Caches/LLPlayerNext/research/mfa"),
        )
    )
    candidate = research_root / "env" / "bin" / "mfa"
    return str(candidate) if candidate.exists() else "mfa"


def _default_mfa_root_dir() -> str:
    if "LLPLAYERNEXT_MFA_ROOT_DIR" in os.environ:
        return os.environ["LLPLAYERNEXT_MFA_ROOT_DIR"]
    research_root = Path(
        os.environ.get(
            "LLPLAYERNEXT_MFA_DIR",
            str(Path.home() / "Library/Caches/LLPlayerNext/research/mfa"),
        )
    )
    return str(research_root / "root")


class MfaAligner(AlignerPlugin):
    provider_id = "montreal-forced-aligner"
    provider_version = "mfa-research-v1"
    supported_languages = ["en"]
    priority = 10

    def check_available(self) -> bool:
        mfa_bin = _default_mfa_bin()
        return Path(mfa_bin).exists() or _which(mfa_bin) is not None

    def align(
        self,
        request_path: Path,
        audio_path: Path,
        output_dir: Path,
        language: str,
        *,
        dry_run: bool = False,
        config: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        cfg = config or {}
        aligned_path = output_dir / "mfa-aligned.json"
        work_dir = output_dir / "mfa-work"
        mfa_script = Path(
            cfg.get("mfa_align_cli")
            or str(REPO_ROOT / "scripts" / "forced-align" / "mfa-align-cli.py")
        )
        command = [
            sys.executable,
            str(mfa_script),
            "--input",
            str(request_path),
            "--work-dir",
            str(work_dir),
            "--output",
            str(aligned_path),
            "--mfa-bin",
            cfg.get("mfa_bin") or _default_mfa_bin(),
            "--mfa-root-dir",
            cfg.get("mfa_root_dir") or _default_mfa_root_dir(),
            "--dictionary",
            cfg.get("mfa_dictionary", "english_us_arpa"),
            "--acoustic-model",
            cfg.get("mfa_acoustic_model", "english_us_arpa"),
            "--strategy",
            cfg.get("mfa_strategy", "align"),
            "--jobs",
            str(cfg.get("mfa_jobs", 4)),
        ]
        if cfg.get("mfa_quiet"):
            command.append("--quiet")

        if dry_run:
            return {
                "aligner": "mfa",
                "dry_run": True,
                "command": self.quote_command(command),
                "request_path": str(request_path),
                "aligned_path": str(aligned_path),
                "work_dir": str(work_dir),
            }

        output_dir.mkdir(parents=True, exist_ok=True)
        subprocess.run(command, check=True)
        aligned = json.loads(aligned_path.read_text(encoding="utf-8"))
        return {
            "aligner": "mfa",
            "request_path": str(request_path),
            "aligned_path": str(aligned_path),
            "aligned": aligned,
            "algorithm_id": cfg.get("post_algorithm_id", "whisperx-transcript-mfa"),
            "algorithm_version": cfg.get("post_algorithm_version", "large-v3-mfa-arpa-align"),
        }


def _which(name: str) -> str | None:
    import shutil
    return shutil.which(name)
