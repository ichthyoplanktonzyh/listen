"""Base class for aligner plugins.

Each aligner plugin implements this interface to participate in the
production pipeline's post-alignment chain. Adding a new aligner
requires only creating a new module in this package and calling
``register()`` in ``__init__.py``.
"""

from __future__ import annotations

import shlex
from pathlib import Path
from typing import Any


class AlignerPlugin:
    """Contract that every aligner must satisfy."""

    provider_id: str = "unknown"
    provider_version: str = "unknown"
    supported_languages: list[str] = ["*"]
    priority: int = 100

    def check_available(self) -> bool:
        """Return True when the aligner's external dependencies are present."""
        return False

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
        """Run alignment and return the standard result dict.

        *request_path* is the alignment-request JSON (segments + audio_path).
        The aligner writes its output into *output_dir* and returns a report
        dict that **must** include at minimum::

            {
                "aligner": "<registry name>",
                "aligned_path": "<path to aligned JSON>",
                ...
            }

        On *dry_run* the aligner returns the plan dict without executing.
        """
        raise NotImplementedError

    def supports_language(self, language: str) -> bool:
        if "*" in self.supported_languages:
            return True
        primary = language.split("-")[0] if language else "en"
        return primary in self.supported_languages

    def describe(self) -> dict[str, Any]:
        return {
            "provider_id": self.provider_id,
            "provider_version": self.provider_version,
            "supported_languages": self.supported_languages,
            "available": self.check_available(),
        }

    @staticmethod
    def quote_command(command: list[str]) -> str:
        return " ".join(shlex.quote(part) for part in command)
