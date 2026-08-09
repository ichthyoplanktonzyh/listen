"""Content Package v2 production for the from-media pipeline.

The v2 carrier is built strictly from the caller-owned release specification
and the already-qualified v1 learning resources: no material equivalence,
delivery URL, or media path is ever inferred or serialized. The six v1 payload
shapes are preserved verbatim as raw-byte hashed payload blobs under
``blobs/sha256/<hex>``.

Identity rules (matching ``listen-core/contracts/content-package/v2``):

* every identity JSON document is sorted-key compact UTF-8 with no trailing
  newline and integer-only numbers;
* a resource ID is the SHA-256 of its canonical resource descriptor;
* a rendition ID is the SHA-256 of its canonical rendition descriptor;
* the release ID is the SHA-256 of the raw canonical ``release.json`` bytes and
  is carried inside ``delivery.json`` (it cannot live inside the document it
  hashes);
* the deterministic ZIP profile is ``release.json``, ``delivery.json``, then
  blob paths sorted; STORE; fixed 1980-01-01 timestamp; Unix creation system;
  0644 regular files; no directory entries, comments, or extras.

Media delivery: ``referenced`` (the default) ships only the generated payload
blobs and honestly classifies the carrier as ``hybrid``; ``embedded`` also
includes the exact original media bytes and classifies it as ``embedded``.
The rendition ``media_type`` is caller-owned (``ReleaseSpec.media_type``), is
validated as a parameter-free MIME ``type/subtype`` whose top-level prefix must
agree exactly with the media kind, and is used unchanged in the rendition
descriptor and therefore in the rendition identity. Embedded media is carried
as an internal file-backed entry and streamed into the archive in bounded
chunks; the full media bytes are never retained in memory.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .package import ConversionError, ResourceFile, _zip_info, LANGUAGE_RE

RELEASE_SCHEMA = "listen.content-package.release.v2"
DELIVERY_SCHEMA = "listen.content-package.delivery.v2"
RENDITION_AUDIO_SCHEMA = "listen.rendition.audio.v1"
RENDITION_VIDEO_SCHEMA = "listen.rendition.video.v1"

# The v2 payload identifiers consumed by Core's payload decoder. Each Gen
# family keeps the exact v1 payload subobject; only the envelope and identity
# scheme change.
V2_RESOURCE_SCHEMAS = {
    "subtitle_text_track": "listen.payload.subtitle-text-track.v1",
    "word_timeline": "listen.payload.word-timeline.v1",
    "phone_timeline": "listen.payload.phone-timeline.v1",
    "sense_group_analysis": "listen.payload.sense-group-analysis.v1",
    "word_acoustics": "listen.payload.word-acoustics.v1",
    "prosody_analysis": "listen.payload.prosody-analysis.v1",
}

# A MIME type must be a parameter-free ``type/subtype`` pair of RFC 2045 token
# characters. The token class excludes whitespace and the tspecials, so
# parameters (``;``), spaces, quotes, and extra slashes are rejected. There is
# no container sniffing or registry lookup: the caller-owned media kind is the
# only cross-check, and the top-level prefix must agree exactly with it.
_MIME_TOKEN = r"[A-Za-z0-9!#$%&'*+\-.^_`|~]+"
MIME_TYPE_RE = re.compile(rf"^{_MIME_TOKEN}/{_MIME_TOKEN}$")

# Exactly ``sha256:`` followed by 64 lowercase hex digits; anything shorter,
# longer, uppercased, or prefixless is not a valid media fingerprint.
SHA256_DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")

# Deterministic entrypoint ids: one for the Media Rendition and one for the
# primary transcript (the required Subtitle Text Track resource).
RENDITION_ENTRYPOINT_ID = "rendition"
TRANSCRIPT_ENTRYPOINT_ID = "transcript"

# Every Gen from-media resource is a base-role target-language resource with no
# support languages (so the descriptor omits ``support_languages`` entirely).
BASE_ROLE = "base"

MEDIA_DELIVERY_CHOICES = ("referenced", "embedded")
DELIVERY_PROFILES = ("embedded", "hybrid")

SHA256_PREFIX = "sha256:"
BLOB_PATH_PREFIX = "blobs/sha256/"
# Bounded chunk size for streaming file-backed media into the archive.
STREAM_CHUNK_BYTES = 1024 * 1024


def _canonical_json(value: Any) -> bytes:
    """Sorted-key compact UTF-8 JSON with no trailing newline.

    ``allow_nan=False`` keeps every identity document serializable, and the
    integer-only identity values never produce floating-point literals.
    """
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
        allow_nan=False,
    ).encode("utf-8")


def _sha256_hex(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _digest_ref(data: bytes) -> str:
    return f"{SHA256_PREFIX}{_sha256_hex(data)}"


def identity_sha256(value: Any) -> str:
    """The v2 identity digest of a document (used by tests and callers)."""
    return _digest_ref(_canonical_json(value))


def _validate_id(value: Any, name: str) -> None:
    if not isinstance(value, str) or not value.strip():
        raise ConversionError(f"{name} must be a non-empty string")


def _validate_language(value: Any, name: str) -> None:
    if not isinstance(value, str) or not LANGUAGE_RE.fullmatch(value):
        raise ConversionError(f"{name} must be a valid BCP47 language tag")


def _validate_media_type(value: Any) -> None:
    if not isinstance(value, str) or not value.strip():
        raise ConversionError("media type must be a non-empty MIME type string")
    if not MIME_TYPE_RE.fullmatch(value):
        raise ConversionError(
            "media type must be a parameter-free MIME type token like audio/wav"
        )


@dataclass(frozen=True)
class ReleaseSpec:
    """Caller-owned v2 release specification for one from-media package.

    Every semantic input is required from the caller; Gen never infers edition,
    material, language, media type, or delivery choices. IDs must be non-empty,
    every language must be BCP47-shaped, and the media type must be a
    parameter-free MIME ``type/subtype`` token. Support languages are explicit
    and repeatable (an empty tuple is valid).
    """

    edition_id: str
    title: str
    material_id: str
    material_revision_id: str
    target_language: str
    media_type: str
    support_languages: tuple[str, ...] = ()
    media_delivery: str = "referenced"

    def __post_init__(self) -> None:
        _validate_id(self.edition_id, "edition id")
        _validate_id(self.title, "edition title")
        _validate_id(self.material_id, "material id")
        _validate_id(self.material_revision_id, "material revision id")
        _validate_language(self.target_language, "target language")
        _validate_media_type(self.media_type)
        for language in self.support_languages:
            _validate_language(language, "support language")
        if len(set(self.support_languages)) != len(self.support_languages):
            raise ConversionError("support languages must be unique")
        if self.media_delivery not in MEDIA_DELIVERY_CHOICES:
            raise ConversionError("media delivery must be referenced or embedded")


def _payload_blob(resource: ResourceFile) -> tuple[dict[str, Any], bytes, str]:
    """Extract the exact v1 payload and serialize it as the v2 payload blob.

    The payload dict is loaded from the emitted v1 envelope and re-serialized
    deterministically (no trailing newline), preserving the six v1 payload
    shapes verbatim while making the blob content stable and raw-byte hashed.
    """
    envelope = json.loads(resource.body)
    payload = envelope["payload"]
    blob = _canonical_json(payload)
    digest = _digest_ref(blob)
    return {"digest": digest, "size_bytes": len(blob)}, blob, digest


def _v2_dependencies(
    envelope: dict[str, Any], v1_to_v2: dict[str, str]
) -> list[str]:
    """Map the v1 dependency edges onto declared v2 resource IDs.

    The v1 resources are emitted in topological order, so every dependency
    must already have a v2 ID; a violation means the v2 DAG is not closed.
    Duplicate references are collapsed deterministically in first-seen order.
    """
    dependency_ids: list[str] = []
    for dependency in envelope["dependencies"]:
        v1_id = dependency.get("resource_id")
        if not isinstance(v1_id, str) or v1_id not in v1_to_v2:
            raise ConversionError("v2 resource dependencies are not closed")
        v2_id = v1_to_v2[v1_id]
        if v2_id not in dependency_ids:
            dependency_ids.append(v2_id)
    return dependency_ids


def _blob_path(digest: str) -> str:
    return f"{BLOB_PATH_PREFIX}{digest.removeprefix(SHA256_PREFIX)}"


@dataclass(frozen=True)
class BlobEntry:
    """One deterministic archive blob: in-memory payload or file-backed media.

    In-memory ``body`` holds the small JSON payload blobs; ``source_path`` is
    the internal file-backed source for the exact original media bytes. Exactly
    one of the two is set. The writer streams ``source_path`` in bounded chunks
    and verifies the observed digest and byte count against the declared
    identity before the atomic replace, so a media file that changed during
    processing fails honestly instead of silently corrupting the carrier.
    """

    name: str
    digest: str
    size_bytes: int
    body: bytes | None = None
    source_path: Path | None = None


def build_v2_carrier(
    *,
    resources: list[ResourceFile],
    media_sha256: str,
    media_size: int,
    media_kind: str,
    media_source: Path | None,
    spec: ReleaseSpec,
    created_at_ms: int,
) -> dict[str, Any]:
    """Assemble the v2 release, delivery, and carrier blob entries.

    ``resources`` are the already-qualified v1 :class:`ResourceFile` objects in
    release order. ``media_sha256`` is the exact SHA-256 of the original media
    bytes (never a normalized WAV). ``media_source`` is the internal file-backed
    source for embedded delivery and must be absent for referenced delivery.
    Returns a dict with ``release``, ``delivery``, ``release_id``, and
    ``entries`` (an ordered list of :class:`BlobEntry` objects ready for the
    deterministic ZIP writer).
    """
    if media_kind not in {"audio", "video"}:
        raise ConversionError("media kind must be audio or video")
    if not isinstance(media_size, int) or isinstance(media_size, bool) or media_size < 1:
        raise ConversionError("media size must be a positive integer")
    if not isinstance(media_sha256, str) or not SHA256_DIGEST_RE.fullmatch(media_sha256):
        raise ConversionError("media fingerprint must be a lowercase SHA-256 identity")
    if spec.media_type.split("/", 1)[0] != media_kind:
        raise ConversionError(
            f"media type {spec.media_type!r} does not agree with media kind "
            f"{media_kind!r}"
        )
    if spec.media_delivery == "embedded":
        if media_source is None:
            raise ConversionError(
                "embedded media delivery requires the media source path"
            )
        if not media_source.exists():
            raise ConversionError("embedded media source does not exist")
        if not media_source.is_file():
            raise ConversionError("embedded media source is not a regular file")
    elif media_source is not None:
        raise ConversionError(
            "referenced media delivery does not accept a media source path"
        )

    rendition_descriptor = {
        "schema": (
            RENDITION_AUDIO_SCHEMA if media_kind == "audio" else RENDITION_VIDEO_SCHEMA
        ),
        "kind": media_kind,
        "media_type": spec.media_type,
        "material_revision_id": spec.material_revision_id,
        "media_blob": {"digest": media_sha256, "size_bytes": media_size},
        "extensions": {},
    }
    rendition_id = _digest_ref(_canonical_json(rendition_descriptor))

    v1_to_v2: dict[str, str] = {}
    release_resources: list[dict[str, Any]] = []
    payload_blobs: list[tuple[str, bytes]] = []
    subtitle_resource_id: str | None = None

    for resource in resources:
        envelope = json.loads(resource.body)
        kind = envelope.get("kind")
        if kind not in V2_RESOURCE_SCHEMAS:
            raise ConversionError(f"unsupported v2 resource kind: {kind!r}")
        dependency_ids = _v2_dependencies(envelope, v1_to_v2)
        payload_ref, blob_bytes, blob_digest = _payload_blob(resource)
        payload_blobs.append((blob_digest, blob_bytes))

        provenance: dict[str, Any] = {
            "created_at_ms": envelope["provenance"]["created_at_ms"],
            "tool": envelope["provenance"]["tool"],
            "input_resource_ids": list(dependency_ids),
            "extensions": {"media_fingerprint": media_sha256},
        }
        for optional_key in ("provider", "model", "config_sha256"):
            if optional_key in envelope["provenance"]:
                provenance[optional_key] = envelope["provenance"][optional_key]

        descriptor = {
            "schema": V2_RESOURCE_SCHEMAS[kind],
            "kind": kind,
            "role": BASE_ROLE,
            "subject": {
                "material_revision_id": spec.material_revision_id,
                "rendition_ids": [rendition_id],
                "anchor_resource_ids": list(dependency_ids),
            },
            "dependencies": [
                {"resource_id": dependency_id} for dependency_id in dependency_ids
            ],
            "provenance": provenance,
            "quality": {
                "review_status": envelope["quality"]["review_status"],
                "warnings": envelope["quality"].get("warnings", []),
                "extensions": {},
            },
            "content_language": spec.target_language,
            "payload_blob": payload_ref,
            "extensions": {},
        }
        resource_id = _digest_ref(_canonical_json(descriptor))
        v1_to_v2[resource.resource_id] = resource_id
        release_resources.append(
            {
                "resource_id": resource_id,
                "required": resource.required,
                "descriptor": descriptor,
            }
        )
        if kind == "subtitle_text_track":
            subtitle_resource_id = resource_id

    if subtitle_resource_id is None:
        raise ConversionError("v2 release requires the subtitle transcript resource")

    release = {
        "schema": RELEASE_SCHEMA,
        "created_at_ms": created_at_ms,
        "edition": {
            "edition_id": spec.edition_id,
            "title": spec.title,
            "target_language": spec.target_language,
            "support_languages": list(spec.support_languages),
        },
        "material": {
            "material_id": spec.material_id,
            "material_revision_id": spec.material_revision_id,
            "title": spec.title,
        },
        "entrypoints": [
            {
                "entrypoint_id": RENDITION_ENTRYPOINT_ID,
                "rendition_id": rendition_id,
            },
            {
                "entrypoint_id": TRANSCRIPT_ENTRYPOINT_ID,
                "resource_id": subtitle_resource_id,
            },
        ],
        "resources": release_resources,
        "renditions": [
            {"rendition_id": rendition_id, "descriptor": rendition_descriptor}
        ],
        "extensions": {},
    }
    release_bytes = _canonical_json(release)
    release_id = _digest_ref(release_bytes)

    # Delivered blobs: the media blob first when embedded, then the payload
    # blobs in release resource order, deduplicated by digest while preserving
    # first-seen deterministic order. Multiple resource descriptors may
    # legitimately reference identical payload bytes; delivery.blobs must never
    # contain duplicate digests and the ZIP must contain one blob path per
    # digest. Reusing a digest with non-identical bytes or a different size is
    # a contradiction and fails instead of silently overwriting. The list
    # declares every blob actually carried in the archive — a subset of the
    # blobs referenced by the release; the delivery schema permits a subset and
    # uses it as hints. The carrier is honestly hybrid because the media blob
    # is absent from the archive while every payload blob is present; omitting
    # the media from this list is a consequence of that, not the cause.
    delivered: list[BlobEntry] = []
    seen: dict[str, BlobEntry] = {}

    def record(entry: BlobEntry) -> None:
        previous = seen.get(entry.digest)
        if previous is not None:
            if previous.size_bytes != entry.size_bytes:
                raise ConversionError("blob digest reused with a different size")
            if (
                previous.body is not None
                and entry.body is not None
                and previous.body != entry.body
            ):
                raise ConversionError("blob digest reused with different bytes")
            return
        seen[entry.digest] = entry
        delivered.append(entry)

    if spec.media_delivery == "embedded":
        assert media_source is not None
        record(
            BlobEntry(
                name=_blob_path(media_sha256),
                digest=media_sha256,
                size_bytes=media_size,
                source_path=media_source,
            )
        )
    for digest, blob in payload_blobs:
        record(
            BlobEntry(
                name=_blob_path(digest),
                digest=digest,
                size_bytes=len(blob),
                body=blob,
            )
        )

    delivery = {
        "schema": DELIVERY_SCHEMA,
        "release_id": release_id,
        "profile": "embedded" if spec.media_delivery == "embedded" else "hybrid",
        "blobs": [
            {"digest": entry.digest, "size_bytes": entry.size_bytes, "hints": []}
            for entry in delivered
        ],
        "extensions": {},
    }

    entries: list[BlobEntry] = [
        BlobEntry(name="release.json", digest="", size_bytes=0, body=release_bytes),
        BlobEntry(
            name="delivery.json", digest="", size_bytes=0, body=_canonical_json(delivery)
        ),
    ]
    entries.extend(sorted(delivered, key=lambda entry: entry.name))

    return {
        "release": release,
        "delivery": delivery,
        "release_id": release_id,
        "entries": entries,
    }


def _write_streamed_entry(
    archive: zipfile.ZipFile, info: zipfile.ZipInfo, entry: BlobEntry
) -> None:
    """Stream one file-backed blob into the archive and verify its identity.

    The declared ``file_size`` is set on the ZipInfo before the stream handle
    is opened so Python's ZIP64 selection sees the true media size (media
    beyond the ZIP32 limit must use ZIP64 local headers) and knows the expected
    byte count up front. The source is then copied in bounded chunks while the
    observed SHA-256 and byte count are accumulated. If either differs from
    the declared identity the media must have changed during processing: the
    caller raises :class:`ConversionError` before the atomic replace, deletes
    the temporary package, and preserves any preexisting output.
    """
    info.file_size = entry.size_bytes
    observed_digest = hashlib.sha256()
    observed_size = 0
    with archive.open(info, "w") as writer:
        assert entry.source_path is not None
        with entry.source_path.open("rb") as source:
            for chunk in iter(lambda: source.read(STREAM_CHUNK_BYTES), b""):
                observed_size += len(chunk)
                observed_digest.update(chunk)
                writer.write(chunk)
    if observed_size != entry.size_bytes or (
        f"{SHA256_PREFIX}{observed_digest.hexdigest()}" != entry.digest
    ):
        raise ConversionError("media input changed during processing")


def write_v2_package(output_path: Path, carrier: dict[str, Any]) -> str:
    """Write the v2 carrier using the deterministic ZIP profile.

    ``carrier`` is the dict returned by :func:`build_v2_carrier`. The archive
    holds release.json first, delivery.json second, then blob paths sorted;
    every entry is STORED with the fixed timestamp, Unix creation system, and
    0644 attributes, and no directory entries, comments, or extras are written.
    File-backed media entries are streamed in bounded chunks and verified
    against their declared digest and size before the atomic replace; a
    mismatch fails the run, deletes the temporary package, and preserves any
    preexisting output. The final package replaces the output atomically after
    fsync.
    """
    output_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        dir=output_path.parent,
        prefix=f".{output_path.name}.",
        suffix=".tmp",
    )
    os.close(descriptor)
    temporary_path = Path(temporary_name)
    try:
        with zipfile.ZipFile(
            temporary_path,
            "w",
            compression=zipfile.ZIP_STORED,
            allowZip64=True,
        ) as archive:
            for entry in carrier["entries"]:
                info = _zip_info(entry.name)
                if entry.source_path is not None:
                    _write_streamed_entry(archive, info, entry)
                else:
                    assert entry.body is not None
                    archive.writestr(info, entry.body)
        digest = hashlib.sha256()
        with temporary_path.open("rb") as package:
            for chunk in iter(lambda: package.read(STREAM_CHUNK_BYTES), b""):
                digest.update(chunk)
            os.fsync(package.fileno())
        os.replace(temporary_path, output_path)
        directory_descriptor = os.open(output_path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
        return digest.hexdigest()
    finally:
        temporary_path.unlink(missing_ok=True)


def read_v2_details(package_path: Path) -> dict[str, object]:
    """Read the v2 carrier facts needed by completed/introspection paths.

    Returns ``package_version``, ``release_id`` (from delivery.json),
    ``delivery_profile``, ``media_fingerprint`` (the rendition media blob
    digest, equal to the original media SHA-256), and the release ``resources``
    in release order with their review statuses.
    """
    with zipfile.ZipFile(package_path) as archive:
        names = archive.namelist()
        if "release.json" not in names or "delivery.json" not in names:
            raise ConversionError("package is not a v2 carrier")
        release = json.loads(archive.read("release.json"))
        delivery = json.loads(archive.read("delivery.json"))
    if not isinstance(release, dict) or release.get("schema") != RELEASE_SCHEMA:
        raise ConversionError("package release document is invalid")
    if not isinstance(delivery, dict) or delivery.get("schema") != DELIVERY_SCHEMA:
        raise ConversionError("package delivery document is invalid")
    renditions = release.get("renditions")
    if not isinstance(renditions, list) or len(renditions) != 1:
        raise ConversionError("v2 carrier must declare exactly one media rendition")
    media_fingerprint = renditions[0]["descriptor"]["media_blob"]["digest"]
    resources = [
        {
            "resource_id": entry["resource_id"],
            "kind": entry["descriptor"]["kind"],
            "review_status": entry["descriptor"]["quality"]["review_status"],
        }
        for entry in release["resources"]
    ]
    return {
        "package_version": 2,
        "release_id": delivery["release_id"],
        "delivery_profile": delivery["profile"],
        "media_fingerprint": media_fingerprint,
        "resources": resources,
    }
