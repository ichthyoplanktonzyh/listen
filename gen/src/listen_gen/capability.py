"""Capability production request model for the Slice 3 machine protocol.

The request is the caller-owned, typed boundary of one generation operation:
an exact Material Revision, the exact Renditions and Resources available to
the run, and one requested Material Capability. Provider selection and
secrets never enter the request; they are CLI/environment configuration.

Request documents are not canonical identity documents; payload and rendition
bytes are addressed by their declared digests.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .package import ConversionError

CAPABILITY_REQUEST_SCHEMA = "listen_gen.capability-request.v2"
REQUEST_VERSION = 2

CAPABILITIES = ("read", "listen", "watch", "synchronized_read_listen")

_SHA256_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
_IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9._:-]{1,200}$")
_MIME_RE = re.compile(r"^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$")


def _required(document: dict[str, Any], name: str, kind: str = "str") -> Any:
    if name not in document:
        raise ConversionError(f"capability request is missing {name!r}")
    value = document[name]
    if kind == "str" and not isinstance(value, str):
        raise ConversionError(f"capability request {name!r} must be a string")
    if kind == "int" and (not isinstance(value, int) or isinstance(value, bool)):
        raise ConversionError(f"capability request {name!r} must be an integer")
    return value


def _identifier(document: dict[str, Any], name: str) -> str:
    value = _required(document, name)
    if not _IDENTIFIER_RE.match(value):
        raise ConversionError(
            f"capability request {name!r} is not a stable identifier"
        )
    return value


def _sha256_id(document: dict[str, Any], name: str) -> str:
    value = _required(document, name)
    if not _SHA256_RE.match(value):
        raise ConversionError(
            f"capability request {name!r} must be a lowercase sha256 id"
        )
    return value


def _optional_string(document: dict[str, Any], name: str) -> str | None:
    value = document.get(name)
    if value is None:
        return None
    if not isinstance(value, str):
        raise ConversionError(f"capability request {name!r} must be a string")
    return value


def _language_tag(value: str) -> str:
    if not re.match(r"^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$", value):
        raise ConversionError(f"invalid BCP47 language tag: {value!r}")
    return value


@dataclass(frozen=True)
class MaterialIdentity:
    material_id: str
    material_revision_id: str
    title: str

    @classmethod
    def from_document(cls, document: dict[str, Any]) -> "MaterialIdentity":
        return cls(
            material_id=_identifier(document, "material_id"),
            material_revision_id=_identifier(document, "material_revision_id"),
            title=_required(document, "title"),
        )


@dataclass(frozen=True)
class EditionIdentity:
    edition_id: str
    title: str
    target_language: str
    support_languages: tuple[str, ...]

    @classmethod
    def from_document(cls, document: dict[str, Any]) -> "EditionIdentity":
        target = _language_tag(_required(document, "target_language"))
        support = document.get("support_languages", [])
        if not isinstance(support, list) or not all(
            isinstance(item, str) for item in support
        ):
            raise ConversionError(
                "capability request support_languages must be a list of strings"
            )
        tags = [_language_tag(item) for item in support]
        if len(set(tags)) != len(tags):
            raise ConversionError("capability request support_languages must be unique")
        if target in tags:
            raise ConversionError(
                "capability request support_languages must not repeat the target language"
            )
        return cls(
            edition_id=_identifier(document, "edition_id"),
            title=_required(document, "title"),
            target_language=target,
            support_languages=tuple(tags),
        )


@dataclass(frozen=True)
class BlobSource:
    digest: str
    size_bytes: int
    path: Path | None = None

    @classmethod
    def from_document(cls, document: dict[str, Any]) -> "BlobSource":
        path = _optional_string(document, "path")
        if path is not None and not Path(path).is_absolute():
            raise ConversionError(
                "capability request blob path must be absolute"
            )
        return cls(
            digest=_sha256_id(document, "digest"),
            size_bytes=_required(document, "size_bytes", "int"),
            path=Path(path) if path is not None else None,
        )


@dataclass(frozen=True)
class AvailableDocumentRendition:
    rendition_id: str
    media_type: str
    language: str | None
    source_asset_id: str | None
    blob: BlobSource

    @classmethod
    def from_document(cls, document: dict[str, Any]) -> "AvailableDocumentRendition":
        rendition_id = _sha256_id(document, "rendition_id")
        media_type = _required(document, "media_type")
        if not _MIME_RE.match(media_type):
            raise ConversionError(
                f"capability request rendition media_type is invalid: {media_type!r}"
            )
        language = _optional_string(document, "language")
        if not language:
            # An empty tag is the same fact as an absent one: the rendition is
            # untagged. Core projects an empty string for a material without a
            # language fact, and the planner already treats both as "carries
            # none".
            language = None
        else:
            language = _language_tag(language)
        source_asset_id = _optional_string(document, "source_asset_id")
        if source_asset_id is not None and not _SHA256_RE.match(source_asset_id):
            raise ConversionError(
                "capability request source_asset_id must be a lowercase sha256 id"
            )
        blob = BlobSource.from_document(_required(document, "blob", "dict"))
        return cls(
            rendition_id=rendition_id,
            media_type=media_type,
            language=language,
            source_asset_id=source_asset_id,
            blob=blob,
        )


@dataclass(frozen=True)
class AvailableMediaRendition:
    rendition_id: str
    media_kind: str
    media_type: str
    media_id: str | None
    fingerprint: str
    blob: BlobSource

    @classmethod
    def from_document(cls, document: dict[str, Any]) -> "AvailableMediaRendition":
        rendition_id = _sha256_id(document, "rendition_id")
        media_kind = _required(document, "media_kind")
        if media_kind not in ("audio", "video"):
            raise ConversionError(
                f"capability request media_kind is invalid: {media_kind!r}"
            )
        media_type = _required(document, "media_type")
        if not _MIME_RE.match(media_type):
            raise ConversionError(
                f"capability request rendition media_type is invalid: {media_type!r}"
            )
        if not media_type.startswith(f"{media_kind}/"):
            raise ConversionError(
                "capability request media_type must agree with the media kind"
            )
        media_id = _optional_string(document, "media_id")
        fingerprint = _required(document, "fingerprint")
        if not fingerprint:
            raise ConversionError("capability request fingerprint must not be empty")
        blob = BlobSource.from_document(_required(document, "blob", "dict"))
        return cls(
            rendition_id=rendition_id,
            media_kind=media_kind,
            media_type=media_type,
            media_id=media_id,
            fingerprint=fingerprint,
            blob=blob,
        )


@dataclass(frozen=True)
class AvailableResource:
    resource_id: str
    kind: str
    schema: str
    role: str
    blob: BlobSource
    content_language: str | None = None
    material_revision_id: str | None = None

    @classmethod
    def from_document(cls, document: dict[str, Any]) -> "AvailableResource":
        role = _required(document, "role")
        if role not in ("base", "assistance"):
            raise ConversionError(f"capability request resource role is invalid: {role!r}")
        content_language = _optional_string(document, "content_language")
        if content_language is not None:
            content_language = _language_tag(content_language)
        material_revision_id = _optional_string(document, "material_revision_id")
        if material_revision_id is not None and not _IDENTIFIER_RE.match(
            material_revision_id
        ):
            raise ConversionError(
                "capability request resource material_revision_id is not a stable identifier"
            )
        return cls(
            resource_id=_sha256_id(document, "resource_id"),
            kind=_required(document, "kind"),
            schema=_required(document, "schema"),
            role=role,
            blob=BlobSource.from_document(_required(document, "blob", "dict")),
            content_language=content_language,
            material_revision_id=material_revision_id,
        )


@dataclass(frozen=True)
class CapabilityRequest:
    schema: str
    version: int
    created_at_ms: int
    material: MaterialIdentity
    edition: EditionIdentity
    requested_capability: str
    document_renditions: tuple[AvailableDocumentRendition, ...]
    media_renditions: tuple[AvailableMediaRendition, ...]
    resources: tuple[AvailableResource, ...]
    attempt_id: str | None = None
    extensions: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_document(cls, document: dict[str, Any]) -> "CapabilityRequest":
        schema = _required(document, "schema")
        if schema != CAPABILITY_REQUEST_SCHEMA:
            raise ConversionError(
                f"unsupported capability request schema: {schema!r}"
            )
        version = document.get("version")
        if version != REQUEST_VERSION:
            raise ConversionError(
                f"unsupported capability request version: {version!r}"
            )
        requested = _required(document, "requested_capability")
        if requested not in CAPABILITIES:
            raise ConversionError(
                f"unsupported requested capability: {requested!r}"
            )
        renditions = document.get("available_renditions", [])
        if not isinstance(renditions, list):
            raise ConversionError(
                "capability request available_renditions must be a list"
            )
        document_renditions: list[AvailableDocumentRendition] = []
        media_renditions: list[AvailableMediaRendition] = []
        for entry in renditions:
            if not isinstance(entry, dict):
                raise ConversionError(
                    "capability request available_renditions entries must be objects"
                )
            kind = entry.get("kind")
            if kind == "document":
                document_renditions.append(
                    AvailableDocumentRendition.from_document(entry)
                )
            elif kind == "media":
                media_renditions.append(AvailableMediaRendition.from_document(entry))
            else:
                raise ConversionError(
                    f"capability request rendition kind is invalid: {kind!r}"
                )
        resources = document.get("available_resources", [])
        if not isinstance(resources, list):
            raise ConversionError(
                "capability request available_resources must be a list"
            )
        parsed_resources = [
            AvailableResource.from_document(entry)
            for entry in resources
            if isinstance(entry, dict)
        ]
        if len(parsed_resources) != len(resources):
            raise ConversionError(
                "capability request available_resources entries must be objects"
            )
        seen_ids = {entry.rendition_id for entry in document_renditions}
        seen_ids |= {entry.rendition_id for entry in media_renditions}
        if len(seen_ids) != len(document_renditions) + len(media_renditions):
            raise ConversionError(
                "capability request rendition ids must be unique"
            )
        resource_ids = {entry.resource_id for entry in parsed_resources}
        if len(resource_ids) != len(parsed_resources):
            raise ConversionError("capability request resource ids must be unique")
        extensions = document.get("extensions", {})
        if not isinstance(extensions, dict):
            raise ConversionError("capability request extensions must be an object")
        attempt_id = _optional_string(document, "attempt_id")
        return cls(
            schema=schema,
            version=version,
            created_at_ms=_required(document, "created_at_ms", "int"),
            material=MaterialIdentity.from_document(
                _required(document, "material", "dict")
            ),
            edition=EditionIdentity.from_document(_required(document, "edition", "dict")),
            requested_capability=requested,
            document_renditions=tuple(document_renditions),
            media_renditions=tuple(media_renditions),
            resources=tuple(parsed_resources),
            attempt_id=attempt_id,
            extensions=dict(extensions),
        )

    @classmethod
    def from_json_file(cls, path: Path) -> "CapabilityRequest":
        try:
            raw = path.read_bytes()
        except OSError as error:
            raise ConversionError(f"capability request could not be read: {path}") from error
        try:
            document = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as error:
            raise ConversionError("capability request is not valid UTF-8 JSON") from error
        if not isinstance(document, dict):
            raise ConversionError("capability request must be a JSON object")
        return cls.from_document(document)

    def documents_with_media_type(self, media_type: str) -> tuple[AvailableDocumentRendition, ...]:
        return tuple(
            entry
            for entry in self.document_renditions
            if entry.media_type == media_type
        )
