"""Capability derivation planning for the Slice 3 production engine.

The planner turns one bounded CapabilityRequest into the smallest derivation
graph: which exact input Renditions feed which derivations, and which
provider kinds each derivation needs. Planning is deterministic and pure; no
processes run and no bytes are read here.

The plan is honest by construction: an already-satisfied capability yields an
empty plan (a minimal package still documents the available source), and a
capability that no supported derivation can produce raises
:class:`UnsupportedCapability` before anything runs.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from .capability import CapabilityRequest
from .package import ConversionError


class UnsupportedCapability(ConversionError):
    """The requested capability cannot be derived from the available inputs.

    This is a request-shape fact decided during planning, before any provider
    runs: no supported derivation can reach the capability from the declared
    Renditions and Resources.
    """


class DerivationKind(str, Enum):
    DOCUMENT_READ = "document_to_structured_reading"
    DOCUMENT_LISTEN = "document_to_listen"
    MEDIA_READ = "media_to_structured_reading"


#: Input kinds each derivation kind selects among.
REQUIRES_DOCUMENT = frozenset(
    {DerivationKind.DOCUMENT_READ, DerivationKind.DOCUMENT_LISTEN}
)
REQUIRES_MEDIA = frozenset({DerivationKind.MEDIA_READ})


@dataclass(frozen=True)
class Derivation:
    """One planned step: exact inputs, one provider-kind requirement."""

    kind: DerivationKind
    input_rendition_ids: tuple[str, ...]
    provider: str
    label: str

    def describe(self) -> dict[str, object]:
        return {
            "kind": self.kind.value,
            "input_rendition_ids": list(self.input_rendition_ids),
            "provider": self.provider,
            "label": self.label,
        }


@dataclass(frozen=True)
class ProductionPlan:
    derivations: tuple[Derivation, ...]
    requested_capability: str

    @property
    def empty(self) -> bool:
        return not self.derivations

    @property
    def requires_ocr(self) -> bool:
        return any(derivation.provider == "ocr" for derivation in self.derivations)

    def describe(self) -> dict[str, object]:
        return {
            "requested_capability": self.requested_capability,
            "derivations": [derivation.describe() for derivation in self.derivations],
        }


def _document_input(request: CapabilityRequest) -> CapabilityRequest.AvailableDocumentRendition:  # type: ignore[name-defined]
    """Select the exact Document Rendition the derivations must consume.

    The request names exact available Renditions; the planner selects the
    single source Document Rendition by preference: the one whose text is
    already usable for the request. Text families are preferred for reading
    derivations because they need no extraction; binary documents (PDF) are
    selected only when they are the only document input.
    """

    from .capability import AvailableDocumentRendition

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
    raise UnsupportedCapability(
        "no usable Document Rendition is available for the requested derivation"
    )


def _media_input(request: CapabilityRequest):
    """Select the exact Media Rendition the derivation must consume."""

    from .capability import AvailableMediaRendition

    if len(request.media_renditions) == 1:
        return request.media_renditions[0]
    if request.media_renditions:
        return request.media_renditions[0]
    raise UnsupportedCapability(
        "no usable Media Rendition is available for the requested derivation"
    )


def _already_readable(request: CapabilityRequest) -> bool:
    """A compatible Structured Reading resource already satisfies reading."""
    return any(
        entry.kind == "structured_reading" and entry.role == "base"
        for entry in request.resources
    )


def plan(request: CapabilityRequest) -> ProductionPlan:
    """Plan the smallest derivation graph for one capability request.

    Deterministic and side-effect free. Raises :class:`UnsupportedCapability`
    when no supported derivation can produce the requested capability.
    Existing compatible resources are reused: a request that is already
    satisfied plans no derivation.
    """
    capability = request.requested_capability
    derivations: list[Derivation] = []

    if capability == "read":
        if request.document_renditions:
            if _already_readable(request):
                return ProductionPlan((), capability)
            rendition = _document_input(request)
            derivations.append(
                Derivation(
                    kind=DerivationKind.DOCUMENT_READ,
                    input_rendition_ids=(rendition.rendition_id,),
                    provider="document_text",
                    label="extract structured reading from the document",
                )
            )
        elif request.media_renditions:
            rendition = _media_input(request)
            derivations.append(
                Derivation(
                    kind=DerivationKind.MEDIA_READ,
                    input_rendition_ids=(rendition.rendition_id,),
                    provider="asr",
                    label="transcribe and align the media",
                )
            )
        else:
            raise UnsupportedCapability("read requires a Document or Media Rendition")
        return ProductionPlan(tuple(derivations), capability)

    if capability == "listen":
        if request.document_renditions:
            rendition = _document_input(request)
            derivations.append(
                Derivation(
                    kind=DerivationKind.DOCUMENT_LISTEN,
                    input_rendition_ids=(rendition.rendition_id,),
                    provider="tts",
                    label="synthesize speech audio from the document text",
                )
            )
            return ProductionPlan(tuple(derivations), capability)
        if request.media_renditions:
            return ProductionPlan((), capability)
        raise UnsupportedCapability("listen requires a Document or Media Rendition")

    if capability == "watch":
        if request.document_renditions:
            raise UnsupportedCapability(
                "watch cannot be derived from a document-only Material"
            )
        return ProductionPlan((), capability)

    if capability == "synchronized_read_listen":
        if request.document_renditions:
            rendition = _document_input(request)
            derivations.append(
                Derivation(
                    kind=DerivationKind.DOCUMENT_LISTEN,
                    input_rendition_ids=(rendition.rendition_id,),
                    provider="tts",
                    label="synthesize speech audio and align reading anchors",
                )
            )
            return ProductionPlan(tuple(derivations), capability)
        if request.media_renditions:
            rendition = _media_input(request)
            derivations.append(
                Derivation(
                    kind=DerivationKind.MEDIA_READ,
                    input_rendition_ids=(rendition.rendition_id,),
                    provider="asr",
                    label="transcribe, align, and structure the media",
                )
            )
            return ProductionPlan(tuple(derivations), capability)
        raise UnsupportedCapability(
            "synchronized read-and-listen requires a Document or Media Rendition"
        )

    raise UnsupportedCapability(f"unsupported capability: {capability!r}")
