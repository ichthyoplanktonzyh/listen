"""Shared contract vocabulary and conversion errors.

The v1/v2 package writers were removed in the Slice 3 cutover; this module
now carries only the vocabulary shared by the surviving modules.
"""

from __future__ import annotations

import re

#: Language tag pattern used by the ASR providers.
LANGUAGE_RE = re.compile(r"^[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*$")
#: Closed set of typed word-timing sources.
TIMING_SOURCES = {
    "asr_reported",
    "asr_aligned",
    "forced_aligned",
    "estimated",
    "user_adjusted",
}
SHA256_RE = re.compile(r"^(?:sha256:)?([0-9a-fA-F]{64})$")
#: Fixed ZIP timestamp for deterministic carriers.
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)


class ConversionError(ValueError):
    """A request, input, or output cannot be represented safely."""
