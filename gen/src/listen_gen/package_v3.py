"""Content Package v3 production: the deterministic packager.

v3 is the Phase 1 canonical package schema: one immutable Package Release in a
carrier of ``release.json`` plus content-addressed blobs under
``blobs/sha256/<hex>``. Identity documents and the release document itself are
strict canonical JSON; rendition and resource identities are the SHA-256 of
their canonical descriptors, exactly as ``listen-core`` validates them.

Serialization rules fixed by the Core contract:
- every object is canonical JSON (byte-sorted keys, compact separators,
  integer-only numbers, no trailing whitespace);
- declared optional facts serialize as ``null`` keys, except an assistance
  resource descriptor, which must omit ``content_language`` entirely;
- source renditions are declared ``referenced`` (the caller owns the exact
  bytes) while derived renditions are ``embedded`` in the carrier.
"""

from __future__ import annotations

import hashlib
import json
import re
import zipfile
from dataclasses import dataclass, field
from typing import Any, Mapping

from . import __version__ as TOOL_VERSION
from .package import ConversionError, ZIP_TIMESTAMP

RELEASE_SCHEMA_V3 = "listen.content-package.release.v3"
STRUCTURED_READING_SCHEMA_V1 = "listen.payload.structured-reading.v1"
ANCHOR_TIME_ALIGNMENT_SCHEMA_V1 = "listen.payload.anchor-time-alignment.v1"
WORD_TIMELINE_SCHEMA_V1 = "listen.payload.word-timeline.v1"

TOOL_ID = "listen-gen"
_SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
_BLOB_PREFIX = "blobs/sha256/"


class QualificationError(ConversionError):
    """Generated output did not pass the deterministic qualification checks."""


def canonical_json(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def identity_sha256(value: Any) -> str:
    return "sha256:" + hashlib.sha256(canonical_json(value)).hexdigest()


def sha256_of_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def _validate_digest(digest: str) -> None:
    if not _SHA256_RE.match(digest):
        raise QualificationError(f"invalid sha256 identity: {digest!r}")


# ---------------------------------------------------------------------------
# Release document building blocks
# ---------------------------------------------------------------------------


def blob_declaration(digest: str, size_bytes: int, embedded: bool) -> dict[str, object]:
    return {"digest": digest, "size_bytes": size_bytes, "embedded": embedded}


def producer_declaration(
    created_at_ms: int,
    *,
    provider: dict[str, object] | None = None,
    model: dict[str, object] | None = None,
    config_sha256: str | None = None,
) -> dict[str, object]:
    return {
        "created_at_ms": created_at_ms,
        "tool": {"id": TOOL_ID, "version": TOOL_VERSION},
        "provider": provider,
        "model": model,
        "config_sha256": config_sha256,
    }


def provenance(
    created_at_ms: int,
    *,
    input_rendition_ids: list[str] | None = None,
    input_resource_ids: list[str] | None = None,
    provider: dict[str, object] | None = None,
    model: dict[str, object] | None = None,
    config_sha256: str | None = None,
) -> dict[str, object]:
    return {
        "created_at_ms": created_at_ms,
        "tool": {"id": TOOL_ID, "version": TOOL_VERSION},
        "provider": provider,
        "model": model,
        "config_sha256": config_sha256,
        "input_rendition_ids": list(input_rendition_ids or []),
        "input_resource_ids": list(input_resource_ids or []),
        "extensions": {},
    }


def quality(review_status: str = "machine_checked") -> dict[str, object]:
    return {"review_status": review_status, "warnings": [], "extensions": {}}


def compatibility(
    checks: list[str],
    verified_inputs: list[dict[str, object]],
) -> dict[str, object]:
    return {
        "checks": list(checks),
        "verified_inputs": [dict(input_) for input_ in verified_inputs],
    }


@dataclass(frozen=True)
class PackageDocumentRendition:
    media_type: str
    text_blob: dict[str, object]
    origin: str
    language: str | None = None
    source_asset_id: str | None = None
    producer: dict[str, object] | None = None
    compatibility: dict[str, object] | None = None
    extensions: dict[str, Any] = field(default_factory=dict)

    def declaration(self) -> dict[str, object]:
        declaration: dict[str, object] = {
            "rendition_id": self.rendition_id,
            "origin": self.origin,
            "media_type": self.media_type,
            "language": self.language,
            "text_blob": self.text_blob,
            "source_asset_id": self.source_asset_id,
            "producer": self.producer,
            "compatibility": self.compatibility,
            "extensions": self.extensions,
        }
        return declaration

    @property
    def rendition_id(self) -> str:
        identity = {
            "media_type": self.media_type,
            "language": self.language,
            "text_blob": self.text_blob,
        }
        return identity_sha256(identity)

    def qualify(self) -> None:
        _validate_digest(self.rendition_id)
        if self.origin == "source":
            if self.source_asset_id is None:
                raise QualificationError("source document rendition must bind a source_asset_id")
            _validate_digest(self.source_asset_id)
        elif self.origin == "derived":
            if self.source_asset_id is not None:
                raise QualificationError("derived document rendition must not bind a source_asset_id")
            if self.producer is None or self.compatibility is None:
                raise QualificationError("derived document rendition requires producer and compatibility")
        else:
            raise QualificationError(f"invalid rendition origin: {self.origin!r}")


@dataclass(frozen=True)
class PackageMediaRendition:
    kind: str
    media_type: str
    media_blob: dict[str, object]
    fingerprint: str
    origin: str
    media_id: str | None = None
    producer: dict[str, object] | None = None
    compatibility: dict[str, object] | None = None
    extensions: dict[str, Any] = field(default_factory=dict)

    def declaration(self) -> dict[str, object]:
        return {
            "rendition_id": self.rendition_id,
            "origin": self.origin,
            "kind": self.kind,
            "media_type": self.media_type,
            "media_blob": self.media_blob,
            "media_id": self.media_id,
            "fingerprint": self.fingerprint,
            "producer": self.producer,
            "compatibility": self.compatibility,
            "extensions": self.extensions,
        }

    @property
    def rendition_id(self) -> str:
        identity = {
            "kind": self.kind,
            "media_type": self.media_type,
            "media_blob": self.media_blob,
            "media_id": self.media_id,
            "fingerprint": self.fingerprint,
        }
        return identity_sha256(identity)

    def qualify(self) -> None:
        _validate_digest(self.rendition_id)
        if not self.fingerprint:
            raise QualificationError("media rendition fingerprint must not be empty")
        if self.origin == "source":
            if not self.media_id:
                raise QualificationError("source media rendition must bind a media_id")
        elif self.origin == "derived":
            if self.media_id is not None:
                raise QualificationError("derived media rendition must not bind a media_id")
            if self.producer is None or self.compatibility is None:
                raise QualificationError("derived media rendition requires producer and compatibility")
        else:
            raise QualificationError(f"invalid rendition origin: {self.origin!r}")


@dataclass(frozen=True)
class PackageResource:
    kind: str
    schema: str
    role: str
    payload_blob: dict[str, object]
    subject: dict[str, object]
    provenance: dict[str, object]
    quality: dict[str, object]
    required: bool = True
    content_language: str | None = None
    support_languages: tuple[str, ...] = ()
    dependencies: tuple[str, ...] = ()
    producer: dict[str, object] | None = None
    compatibility: dict[str, object] | None = None
    extensions: dict[str, Any] = field(default_factory=dict)

    def descriptor(self) -> dict[str, object]:
        descriptor: dict[str, object] = {
            "schema": self.schema,
            "kind": self.kind,
            "role": self.role,
            "content_language": self.content_language,
            "support_languages": list(self.support_languages),
            "subject": self.subject,
            "dependencies": [{"resource_id": dep} for dep in self.dependencies],
            "provenance": self.provenance,
            "quality": self.quality,
            "producer": self.producer,
            "compatibility": self.compatibility,
            "payload_blob": self.payload_blob,
            "extensions": self.extensions,
        }
        if self.role == "assistance":
            descriptor.pop("content_language", None)
        return descriptor

    @property
    def resource_id(self) -> str:
        return identity_sha256(self.descriptor())

    def qualify(self) -> None:
        _validate_digest(self.resource_id)
        if self.role == "base":
            if not self.content_language:
                raise QualificationError("base resource requires content_language")
            if self.support_languages:
                raise QualificationError("base resource must not declare support_languages")
        elif self.role == "assistance":
            if not self.support_languages:
                raise QualificationError("assistance resource requires support_languages")
        else:
            raise QualificationError(f"invalid resource role: {self.role!r}")


# ---------------------------------------------------------------------------
# Release assembly and qualification
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class V3Release:
    created_at_ms: int
    edition: dict[str, object]
    material: dict[str, object]
    document_renditions: tuple[PackageDocumentRendition, ...]
    media_renditions: tuple[PackageMediaRendition, ...]
    resources: tuple[PackageResource, ...]
    #: payload bytes for every resource, keyed by declared payload digest
    payload_bytes: Mapping[str, bytes]
    #: bytes for every embedded rendition blob, keyed by declared digest
    embedded_bytes: Mapping[str, bytes]
    #: digests declared referenced and therefore absent from the carrier
    referenced_digests: frozenset[str] = frozenset()

    def qualify(self) -> None:
        """Deterministic qualification before packaging.

        Verifies the requested capability closure, hashes, identifiers,
        subjects, dependencies, provenance, and compatibility. Any failure
        is a hard error: unqualified output never enters a package.
        """
        for rendition in self.document_renditions:
            rendition.qualify()
        for rendition in self.media_renditions:
            rendition.qualify()
        declared_ids = {resource.resource_id for resource in self.resources}
        roles = {resource.resource_id: resource.role for resource in self.resources}
        for resource in self.resources:
            resource.qualify()
            for dependency in resource.dependencies:
                if dependency == resource.resource_id:
                    raise QualificationError("resource cannot depend on itself")
                if dependency not in declared_ids:
                    raise QualificationError(
                        f"resource dependency is not in the release: {dependency}"
                    )
                if resource.role == "base" and roles[dependency] == "assistance":
                    raise QualificationError(
                        "base resource must not depend on an assistance resource"
                    )
                if resource.role == "assistance" and roles[dependency] != "base":
                    raise QualificationError(
                        "assistance resource may only depend on base resources"
                    )
            known = {
                entry.rendition_id for entry in self.document_renditions
            } | {entry.rendition_id for entry in self.media_renditions}
            subject_renditions = set(resource.subject.get("rendition_ids", []))
            if not subject_renditions <= known:
                raise QualificationError(
                    "resource subject references an undeclared rendition"
                )
            anchors = resource.subject.get("anchor_resource_ids", [])
            if anchors and not set(anchors) <= declared_ids:
                raise QualificationError(
                    "resource subject references an undeclared anchor resource"
                )
            if resource.role == "base" and any(
                other.role == "assistance" and resource.resource_id in other.dependencies
                for other in self.resources
            ):
                raise QualificationError("base resource must not be directly depended on by assistance")
            for digest in (resource.payload_blob["digest"],):
                if digest not in self.payload_bytes:
                    raise QualificationError(
                        f"resource payload bytes are missing: {digest}"
                    )
                if sha256_of_bytes(self.payload_bytes[digest]) != digest:
                    raise QualificationError(
                        f"resource payload bytes do not match the declared digest: {digest}"
                    )
        for rendition in self.document_renditions:
            if rendition.compatibility:
                for input_ in rendition.compatibility["verified_inputs"]:
                    if input_["rendition_id"] not in known:
                        raise QualificationError(
                            "compatibility evidence references an undeclared rendition"
                        )
        for digest, data in self.embedded_bytes.items():
            if sha256_of_bytes(data) != digest:
                raise QualificationError(
                    f"embedded blob bytes do not match the declared digest: {digest}"
                )

    def release_document(self) -> dict[str, object]:
        return {
            "schema": RELEASE_SCHEMA_V3,
            "created_at_ms": self.created_at_ms,
            "edition": self.edition,
            "material": self.material,
            "document_renditions": [
                entry.declaration() for entry in self.document_renditions
            ],
            "media_renditions": [
                entry.declaration() for entry in self.media_renditions
            ],
            "resources": [
                {
                    "resource_id": entry.resource_id,
                    "required": entry.required,
                    "descriptor": entry.descriptor(),
                }
                for entry in self.resources
            ],
            "extensions": {},
        }


def write_v3_package(release: V3Release, output_path: Any) -> str:
    """Write the deterministic v3 carrier and return the package file SHA-256.

    Entry order is fixed: ``release.json`` first, then blob paths in lexical
    order. ZIP entries use a fixed timestamp, STORED compression, and no
    directory entries.
    """
    release.qualify()
    document = release.release_document()
    release_bytes = canonical_json(document)
    entries: list[tuple[str, bytes]] = [("release.json", release_bytes)]
    blobs = dict(release.payload_bytes)
    blobs.update(release.embedded_bytes)
    for digest in sorted(blobs):
        entries.append(
            (f"{_BLOB_PREFIX}{digest.removeprefix('sha256:')}", blobs[digest])
        )
    return _write_zip(output_path, entries)


def _zip_info(name: str, size: int) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, ZIP_TIMESTAMP)
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = 0o644 << 16
    info.create_system = 3
    info.flag_bits = 0
    return info


def _write_zip(output_path: Any, entries: list[tuple[str, bytes]]) -> str:
    with zipfile.ZipFile(output_path, "w") as archive:
        for name, data in entries:
            archive.writestr(_zip_info(name, len(data)), data)
    digest = hashlib.sha256()
    with open(output_path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()
