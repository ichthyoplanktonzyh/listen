"""Capability production request model for the Slice 3 machine protocol.

The request is the caller-owned, typed boundary of one generation operation:
an exact Material Revision, its document/audio/video Renditions, and one
requested Material Capability. Provider selection and secrets never enter the
request; they are CLI/environment configuration.

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
_BARE_SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
_IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9._:-]{1,200}$")
_MIME_RE = re.compile(r"^[A-Za-z0-9!#$&^_.+-]+/[A-Za-z0-9!#$&^_.+-]+$")
SUPPORTED_DOCUMENT_MEDIA_TYPES = frozenset(
    {
        "application/epub+zip",
        "application/pdf",
        "text/html",
        "text/markdown",
        "text/plain",
    }
)


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
        size_bytes = _required(document, "size_bytes", "int")
        if size_bytes <= 0:
            raise ConversionError("capability request blob size_bytes must be positive")
        return cls(
            digest=_sha256_id(document, "digest"),
            size_bytes=size_bytes,
            path=Path(path) if path is not None else None,
        )


@dataclass(frozen=True)
class AvailableDocumentRendition:
    rendition_id: str
    media_type: str
    language: str | None
    source_asset_id: str
    blob: BlobSource

    @classmethod
    def from_document(cls, document: dict[str, Any]) -> "AvailableDocumentRendition":
        rendition_id = _sha256_id(document, "rendition_id")
        media_type = _required(document, "media_type")
        if not _MIME_RE.match(media_type):
            raise ConversionError(
                f"capability request rendition media_type is invalid: {media_type!r}"
            )
        if media_type not in SUPPORTED_DOCUMENT_MEDIA_TYPES:
            raise ConversionError(
                f"unsupported document media type: {media_type!r}"
            )
        language = _optional_string(document, "language")
        if language:
            language = _language_tag(language)
        else:
            language = None
        source_asset_id = _required(document, "source_asset_id")
        if not _BARE_SHA256_RE.fullmatch(source_asset_id):
            raise ConversionError(
                "capability request source_asset_id must be a raw lowercase 64-character Core id (without sha256:)"
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
class CapabilityRequest:
    schema: str
    version: int
    created_at_ms: int
    material: MaterialIdentity
    edition: EditionIdentity
    requested_capability: str
    document_renditions: tuple[AvailableDocumentRendition, ...]
    media_renditions: tuple[AvailableMediaRendition, ...]
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
        seen_ids = {entry.rendition_id for entry in document_renditions}
        seen_ids.update(entry.rendition_id for entry in media_renditions)
        if len(seen_ids) != len(document_renditions) + len(media_renditions):
            raise ConversionError(
                "capability request rendition ids must be unique"
            )
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

    def documents_with_media_type(
        self, media_type: str
    ) -> tuple[AvailableDocumentRendition, ...]:
        return tuple(
            rendition
            for rendition in self.document_renditions
            if rendition.media_type == media_type
        )
