"""Capability derivation planning for the Slice 3 production engine.

The planner turns one bounded CapabilityRequest into the smallest derivation
graph: which exact input Renditions feed which derivations, and which
provider kinds each derivation needs. Planning is deterministic and pure; no
processes run and no bytes are read here.

The plan is honest by construction: an already-satisfied capability yields an
empty plan (a minimal package still documents the available source), and a
capability that no supported derivation can produce raises
:class:`UnsupportedCapability` before anything runs.

Compatible resources are reused without suppressing generation: a Structured
Reading is reusable only when it is a base resource whose declared language
and Material Revision both match this request. A resource that is unknown,
stale, or language-incompatible never suppresses a planned derivation — the
run generates rather than silently reusing the wrong input.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from .capability import CapabilityRequest, AvailableResource
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
    """One planned step: exact inputs, one provider-kind requirement.

    ``input_resource_ids`` carries already-available Resources the derivation
    consumes (for example a compatible Structured Reading that must not be
    regenerated). An empty tuple means the run produces the resource itself.
    """

    kind: DerivationKind
    input_rendition_ids: tuple[str, ...]
    provider: str
    label: str
    input_resource_ids: tuple[str, ...] = ()

    def describe(self) -> dict[str, object]:
        return {
            "kind": self.kind.value,
            "input_rendition_ids": list(self.input_rendition_ids),
            "input_resource_ids": list(self.input_resource_ids),
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


def _target_language(request: CapabilityRequest) -> str:
    """The exact language the derivation must produce.

    The rendition's declared language is authoritative for the source
    document; the edition target language is the fallback when the rendition
    carries none.
    """
    for entry in request.document_renditions:
        if entry.language:
            return entry.language
    return request.edition.target_language


def _compatible_reading(
    request: CapabilityRequest,
) -> AvailableResource | None:
    """The available Structured Reading this request can safely reuse.

    Reuse requires an exact match of both facts the planner can verify: the
    resource's declared language equals the target language, and its subject
    names this exact Material Revision. A resource missing either fact is not
    treated as compatible — unknown never suppresses generation.
    """
    target = _target_language(request)
    for entry in request.resources:
        if entry.kind != "structured_reading" or entry.role != "base":
            continue
        if entry.content_language is None or entry.content_language != target:
            continue
        if (
            entry.material_revision_id is None
            or entry.material_revision_id != request.material.material_revision_id
        ):
            continue
        return entry
    return None


def _document_listen_derivations(
    request: CapabilityRequest,
) -> list[Derivation]:
    """The smallest derivation chain for document-to-listen.

    A compatible Structured Reading is reused as the TTS input; otherwise the
    run first derives the reading and then synthesizes from it in the same
    run.
    """
    rendition = _document_input(request)
    compatible = _compatible_reading(request)
    derivations: list[Derivation] = []
    if compatible is None:
        derivations.append(
            Derivation(
                kind=DerivationKind.DOCUMENT_READ,
                input_rendition_ids=(rendition.rendition_id,),
                provider="extraction",
                label="extract the structured reading from the document",
            )
        )
        derivations.append(
            Derivation(
                kind=DerivationKind.DOCUMENT_LISTEN,
                input_rendition_ids=(rendition.rendition_id,),
                provider="tts",
                label="synthesize speech audio and align reading anchors",
            )
        )
    else:
        derivations.append(
            Derivation(
                kind=DerivationKind.DOCUMENT_LISTEN,
                input_rendition_ids=(rendition.rendition_id,),
                provider="tts",
                label="synthesize speech audio from the existing structured reading",
                input_resource_ids=(compatible.resource_id,),
            )
        )
    return derivations


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
            if _compatible_reading(request) is not None:
                return ProductionPlan((), capability)
            rendition = _document_input(request)
            derivations.append(
                Derivation(
                    kind=DerivationKind.DOCUMENT_READ,
                    input_rendition_ids=(rendition.rendition_id,),
                    provider="extraction",
                    label="extract the structured reading from the document",
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
            return ProductionPlan(
                tuple(_document_listen_derivations(request)), capability
            )
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
            return ProductionPlan(
                tuple(_document_listen_derivations(request)), capability
            )
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
