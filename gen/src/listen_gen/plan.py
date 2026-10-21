"""Capability derivation planning for the Slice 3 production engine.

The planner turns one bounded CapabilityRequest into the smallest derivation
graph: which exact input Renditions feed which derivations, and which
provider kinds each derivation needs. Planning is deterministic and pure; no
processes run and no bytes are read here.

The plan is honest by construction: an already-satisfied capability yields an
empty plan (a minimal package still documents the available source), and a
capability that no supported derivation can produce raises
:class:`UnsupportedCapability` before anything runs.

The only derivation is media-to-structured-reading. Listen and watch are
already satisfied by a declared audio or video rendition.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum

from .capability import AvailableMediaRendition, CapabilityRequest
from .package import ConversionError


class UnsupportedCapability(ConversionError):
    """The requested capability cannot be derived from the available inputs.

    This is a request-shape fact decided during planning, before any provider
    runs: no supported derivation can reach the capability from the declared
    media renditions.
    """


class DerivationKind(str, Enum):
    MEDIA_READ = "media_to_structured_reading"


@dataclass(frozen=True)
class Derivation:
    """One planned step: exact inputs, one provider-kind requirement.

    The derivation consumes the exact source media rendition.
    """

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

    def describe(self) -> dict[str, object]:
        return {
            "requested_capability": self.requested_capability,
            "derivations": [derivation.describe() for derivation in self.derivations],
        }


def _media_input(request: CapabilityRequest) -> AvailableMediaRendition:
    """Select the exact Media Rendition the derivation must consume."""

    if len(request.media_renditions) == 1:
        return request.media_renditions[0]
    if request.media_renditions:
        return request.media_renditions[0]
    raise UnsupportedCapability(
        "no usable Media Rendition is available for the requested derivation"
    )


def plan(request: CapabilityRequest) -> ProductionPlan:
    """Plan the smallest derivation graph for one capability request.

    Deterministic and side-effect free. Raises :class:`UnsupportedCapability`
    when no supported derivation can produce the requested capability.
    Listen and watch require no derivation from an existing media source.
    """
    capability = request.requested_capability
    derivations: list[Derivation] = []

    if capability == "read":
        if request.media_renditions:
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
            raise UnsupportedCapability("read requires audio or video media")
        return ProductionPlan(tuple(derivations), capability)

    if capability == "listen":
        if request.media_renditions:
            return ProductionPlan((), capability)
        raise UnsupportedCapability("listen requires audio or video media")

    if capability == "watch":
        if request.media_renditions:
            return ProductionPlan((), capability)
        raise UnsupportedCapability("watch requires audio or video media")

    if capability == "synchronized_read_listen":
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
            "synchronized read-and-listen requires audio or video media"
        )

    raise UnsupportedCapability(f"unsupported capability: {capability!r}")
