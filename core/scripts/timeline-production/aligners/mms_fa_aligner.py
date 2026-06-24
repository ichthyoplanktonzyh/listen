"""MMS Forced Aligner (torchaudio CTC) plugin."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any

from .base import AlignerPlugin

REPO_ROOT = Path(__file__).resolve().parents[3]


def _default_mms_fa_python() -> str:
    research_root = Path(
        os.environ.get(
            "LLPLAYERNEXT_FA_DIR",
            str(Path.home() / "Library/Caches/LLPlayerNext/research/forced-align"),
        )
    )
    candidate = research_root / "venv" / "bin" / "python"
    return str(candidate) if candidate.exists() else sys.executable


class MmsFaAligner(AlignerPlugin):
    provider_id = "torchaudio-ctc-forced-aligner"
    provider_version = "mms-fa-v1"
    supported_languages = ["*"]
    priority = 20

    def check_available(self) -> bool:
        python = _default_mms_fa_python()
        return Path(python).exists()

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
        aligned_path = output_dir / "mms-fa-aligned.json"
        align_script = Path(
            cfg.get("mms_fa_align_cli")
            or str(REPO_ROOT / "scripts" / "forced-align" / "align-cli.py")
        )
        python = cfg.get("mms_fa_python") or _default_mms_fa_python()
        command = [python, str(align_script)]

        if dry_run:
            return {
                "aligner": "mms-fa",
                "dry_run": True,
                "command": self.quote_command(command),
                "request_path": str(request_path),
                "aligned_path": str(aligned_path),
            }

        request = json.loads(request_path.read_text(encoding="utf-8"))
        output_dir.mkdir(parents=True, exist_ok=True)
        completed = subprocess.run(
            command,
            input=json.dumps(request),
            text=True,
            capture_output=True,
            check=True,
        )
        aligned = json.loads(completed.stdout)
        aligned["provider_id"] = self.provider_id
        aligned["provider_version"] = self.provider_version
        aligned_path.write_text(
            json.dumps(aligned, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return {
            "aligner": "mms-fa",
            "request_path": str(request_path),
            "aligned_path": str(aligned_path),
            "aligned": aligned,
            "algorithm_id": "whisperx-transcript-mms-fa",
            "algorithm_version": "large-v3-mms-fa-v1",
        }
