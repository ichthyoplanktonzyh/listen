"""Capability derivation planning for the Slice 3 production engine.

The planner turns one bounded CapabilityRequest into the smallest derivation
graph: which exact input Renditions feed which derivations, and which
provider kinds each derivation needs. Planning is deterministic and pure; no
processes run and no bytes are read here.

Audio/video Read keeps the subtitle-backed or ASR transcript path. Document
Read extracts structured text; document Listen extracts that text and then
synthesizes aligned audio. Listen on media requires an existing audio
rendition, and Watch requires video.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from enum import Enum

from .capability import (
    AvailableDocumentRendition,
    AvailableMediaRendition,
    CapabilityRequest,
)
from .package import ConversionError


class UnsupportedCapability(ConversionError):
    """The requested capability cannot be derived from the available inputs."""


class DerivationKind(str, Enum):
    DOCUMENT_READ = "document_to_structured_reading"
    DOCUMENT_LISTEN = "document_to_listen"
    MEDIA_READ = "media_to_structured_reading"


_SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")


@dataclass(frozen=True)
class Derivation:
    """One planned step: exact inputs and one provider-kind requirement."""

    kind: DerivationKind
    input_rendition_ids: tuple[str, ...]
    provider: str
    label: str
    subtitle_sha256: str | None = None

    def describe(self) -> dict[str, object]:
        result: dict[str, object] = {
            "kind": self.kind.value,
            "input_rendition_ids": list(self.input_rendition_ids),
            "provider": self.provider,
            "label": self.label,
        }
        if self.subtitle_sha256 is not None:
            result["subtitle_sha256"] = self.subtitle_sha256
        return result


@dataclass(frozen=True)
class ProductionPlan:
    derivations: tuple[Derivation, ...]
    requested_capability: str

    @property
    def empty(self) -> bool:
        return not self.derivations

    def describe(self) -> dict[str, object]:
        return {
            "requested_capability": self.requested_capability,
            "derivations": [derivation.describe() for derivation in self.derivations],
        }


def _document_input(request: CapabilityRequest) -> AvailableDocumentRendition:
    """Choose the best exact source document rendition for extraction."""
    text_families = (
        "text/plain",
        "text/markdown",
        "text/html",
        "application/epub+zip",
    )
    for family in text_families:
        matches = request.documents_with_media_type(family)
        if matches:
            return matches[0]
    if len(request.document_renditions) == 1:
        return request.document_renditions[0]
    if request.document_renditions:
        return request.document_renditions[0]
    raise UnsupportedCapability("no usable Document Rendition is available")


def _media_input(request: CapabilityRequest) -> AvailableMediaRendition:
    if len(request.media_renditions) == 1:
        return request.media_renditions[0]
    if request.media_renditions:
        return request.media_renditions[0]
    raise UnsupportedCapability("no usable Media Rendition is available")


def _document_listen_derivations(
    request: CapabilityRequest,
) -> list[Derivation]:
    rendition = _document_input(request)
    return [
        Derivation(
            kind=DerivationKind.DOCUMENT_READ,
            input_rendition_ids=(rendition.rendition_id,),
            provider="extraction",
            label="extract the structured reading from the document",
        ),
        Derivation(
            kind=DerivationKind.DOCUMENT_LISTEN,
            input_rendition_ids=(rendition.rendition_id,),
            provider="tts",
            label="synthesize speech audio and align reading anchors",
        ),
    ]


def plan(
    request: CapabilityRequest,
    *,
    subtitle_sha256: str | None = None,
) -> ProductionPlan:
    """Build the smallest deterministic derivation graph for one request."""
    capability = request.requested_capability
    derivations: list[Derivation] = []

    if capability == "read":
        if request.media_renditions:
            if subtitle_sha256 is not None and not _SHA256_RE.fullmatch(subtitle_sha256):
                raise ConversionError("subtitle_sha256 must be a lowercase sha256 id")
            rendition = _media_input(request)
            subtitle_mode = subtitle_sha256 is not None
            derivations.append(
                Derivation(
                    kind=DerivationKind.MEDIA_READ,
                    input_rendition_ids=(rendition.rendition_id,),
                    provider="subtitle" if subtitle_mode else "asr",
                    label=(
                        "structure the media from the supplied SRT/VTT subtitle track"
                        if subtitle_mode
                        else "transcribe and align the media"
                    ),
                    subtitle_sha256=subtitle_sha256,
                )
            )
        elif request.document_renditions:
            rendition = _document_input(request)
            derivations.append(
                Derivation(
                    kind=DerivationKind.DOCUMENT_READ,
                    input_rendition_ids=(rendition.rendition_id,),
                    provider="extraction",
                    label="extract the structured reading from the document",
                )
            )
        else:
            raise UnsupportedCapability("read requires a Document or Media Rendition")
        return ProductionPlan(tuple(derivations), capability)

    if capability == "listen":
        if any(entry.media_kind == "audio" for entry in request.media_renditions):
            return ProductionPlan((), capability)
        if request.document_renditions:
            return ProductionPlan(tuple(_document_listen_derivations(request)), capability)
        raise UnsupportedCapability("listen requires an audio rendition or source document")

    if capability == "watch":
        if not any(entry.media_kind == "video" for entry in request.media_renditions):
            raise UnsupportedCapability("watch requires video media")
        return ProductionPlan((), capability)

    if capability == "synchronized_read_listen":
        if request.media_renditions:
            if subtitle_sha256 is not None and not _SHA256_RE.fullmatch(subtitle_sha256):
                raise ConversionError("subtitle_sha256 must be a lowercase sha256 id")
            rendition = _media_input(request)
            subtitle_mode = subtitle_sha256 is not None
            derivations.append(
                Derivation(
                    kind=DerivationKind.MEDIA_READ,
                    input_rendition_ids=(rendition.rendition_id,),
                    provider="subtitle" if subtitle_mode else "asr",
                    label=(
                        "structure the media from the supplied SRT/VTT subtitle track"
                        if subtitle_mode
                        else "transcribe, align, and structure the media"
                    ),
                    subtitle_sha256=subtitle_sha256,
                )
            )
            return ProductionPlan(tuple(derivations), capability)
        if request.document_renditions:
            return ProductionPlan(tuple(_document_listen_derivations(request)), capability)
        raise UnsupportedCapability(
            "synchronized read-and-listen requires a Document or Media Rendition"
        )

    raise UnsupportedCapability(f"unsupported capability: {capability!r}")
