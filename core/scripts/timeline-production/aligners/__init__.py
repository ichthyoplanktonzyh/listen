"""Aligner plugin registry.

Adding a new aligner:
    1. Create ``aligners/my_aligner.py`` implementing ``AlignerPlugin``.
    2. Import and register it below.

The pipeline discovers available aligners through this registry.
"""

from __future__ import annotations

from typing import Any

from .base import AlignerPlugin
from .mfa_aligner import MfaAligner
from .mms_fa_aligner import MmsFaAligner

REGISTRY: dict[str, type[AlignerPlugin]] = {}


def register(name: str, cls: type[AlignerPlugin]) -> None:
    REGISTRY[name] = cls


def get_aligner(name: str, **kwargs: Any) -> AlignerPlugin:
    if name not in REGISTRY:
        raise KeyError(f"unknown aligner: {name!r}; registered: {sorted(REGISTRY)}")
    return REGISTRY[name](**kwargs)


def available_aligners(language: str = "en") -> list[str]:
    """Return names of aligners that support *language* and whose deps are present.

    Results are sorted by priority (lower = preferred).
    """
    results: list[tuple[int, str]] = []
    for name, cls in REGISTRY.items():
        instance = cls()
        if instance.supports_language(language) and instance.check_available():
            results.append((instance.priority, name))
    results.sort()
    return [name for _, name in results]


def all_aligners() -> list[dict[str, Any]]:
    """Describe every registered aligner (for ``doctor`` / ``list-aligners``)."""
    descriptions = []
    for name, cls in sorted(REGISTRY.items()):
        instance = cls()
        info = instance.describe()
        info["name"] = name
        descriptions.append(info)
    return descriptions


register("mfa", MfaAligner)
register("mms-fa", MmsFaAligner)
