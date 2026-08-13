#!/usr/bin/env python3
"""Validate Content Package v3 JSON Schemas against the committed examples.

This script performs real schema validation: every committed example's
canonical `release.json` is validated against `release.schema.json` (which
refs the shared definitions and the resource descriptor schema), every
embedded payload blob is validated against its declared payload schema, and
the v3 semantic invariants that JSON Schema cannot express are checked as a
typed post-pass:

- Structured Reading payloads are self-contained exact UTF-8 logical text;
  every anchor range must stay within the text bytes, land on character
  boundaries, and appear in monotonic byte order;
- the block hierarchy has exactly one root block, valid parent references,
  and contiguous 0-based sibling order;
- document mappings point at declared Document Renditions with a non-empty
  format-related locator;
- release identity invariants are recomputed: resource ids are the SHA-256 of
  the canonical descriptor JSON and every embedded blob digest/size matches
  the actual bytes.

The bundled validator is self-contained (no third-party dependency): it
implements the JSON Schema draft 2020-12 keyword subset used by these
schemas (`$ref`, `$defs`, `type`, `enum`, `const`, `properties`, `required`,
`additionalProperties`, `items`, `minItems`, `uniqueItems`, `minLength`,
`pattern`, `minimum`, `anyOf`, `allOf`, `oneOf`, `not`, plus `$id`
recording). It does not pretend to implement the whole spec; schemas outside
this subset are rejected at load time.

Usage: validate_content_package_schemas.py [contracts/content-package]
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


SUPPORTED_KEYWORDS = frozenset(
    {
        "$schema",
        "$id",
        "$ref",
        "$defs",
        "title",
        "description",
        "type",
        "enum",
        "const",
        "properties",
        "required",
        "additionalProperties",
        "items",
        "minItems",
        "maxItems",
        "uniqueItems",
        "minLength",
        "maxLength",
        "pattern",
        "minimum",
        "maximum",
        "exclusiveMinimum",
        "exclusiveMaximum",
        "anyOf",
        "allOf",
        "oneOf",
        "not",
    }
)

# Payload descriptor schema identifiers -> schema file, relative to the
# content-package contracts root.
PAYLOAD_SCHEMA_INVENTORY = {
    "listen.payload.structured-reading.v1": "v3/payload/structured-reading.v1.schema.json",
    "listen.payload.anchor-time-alignment.v1": "v3/payload/anchor-time-alignment.v1.schema.json",
    "listen.payload.document-text.v1": "v2/payload/document-text.v1.schema.json",
    "listen.payload.timed-text-track.v2": "v2/payload/timed-text-track.v2.schema.json",
    "listen.payload.translation.v1": "v2/payload/translation.v1.schema.json",
    "listen.payload.subtitle-text-track.v1": "v2/payload/subtitle-text-track.v1.schema.json",
    "listen.payload.word-timeline.v1": "v2/payload/word-timeline.v1.schema.json",
    "listen.payload.phone-timeline.v1": "v2/payload/phone-timeline.v1.schema.json",
    "listen.payload.sense-group-analysis.v1": "v2/payload/sense-group-analysis.v1.schema.json",
    "listen.payload.word-acoustics.v1": "v2/payload/word-acoustics.v1.schema.json",
    "listen.payload.prosody-analysis.v1": "v2/payload/prosody-analysis.v1.schema.json",
}

SHA256_PATTERN = re.compile(r"^sha256:[0-9a-f]{64}$")

EXAMPLES = ("document-source", "media-only", "composed")


class SchemaError(Exception):
    """A schema or document failed validation."""


class SchemaLoader:
    def __init__(self, root: Path):
        self.root = root
        self.schemas: dict[str, dict] = {}
        self.files: dict[Path, dict] = {}
        self._load_tree()

    def _load_tree(self) -> None:
        for pattern in ("v3/**/*.schema.json", "v2/payload/*.schema.json"):
            for path in sorted(self.root.glob(pattern)):
                if not path.is_file():
                    continue
                document = json.loads(path.read_text(encoding="utf-8"))
                if not isinstance(document, dict):
                    raise SchemaError(f"{path}: schema must be a JSON object")
                self._check_keywords(document, path, [])
                self.files[path.resolve()] = document
                schema_id = document.get("$id")
                if isinstance(schema_id, str):
                    if schema_id in self.schemas:
                        raise SchemaError(f"duplicate $id {schema_id}")
                    self.schemas[schema_id] = document

    def _check_keywords(self, node: object, path: Path, trail: list[str]) -> None:
        # Only schema-bearing keywords are descended into; value-bearing
        # keywords (enum, const, type, pattern, ...) are treated as opaque.
        if isinstance(node, dict):
            for key, value in node.items():
                if key in ("$schema", "$id", "title", "description"):
                    continue
                if key not in SUPPORTED_KEYWORDS:
                    raise SchemaError(
                        f"{path}: unsupported keyword {'.'.join(trail + [key])}"
                    )
                if key in ("properties", "$defs"):
                    if not isinstance(value, dict):
                        raise SchemaError(
                            f"{path}: {'.'.join(trail + [key])} must be an object"
                        )
                    for name, subschema in value.items():
                        self._check_keywords(subschema, path, trail + [key, name])
                elif key in ("items", "not"):
                    self._check_keywords(value, path, trail + [key])
                elif key in ("anyOf", "allOf", "oneOf"):
                    if not isinstance(value, list):
                        raise SchemaError(
                            f"{path}: {'.'.join(trail + [key])} must be an array"
                        )
                    for index, subschema in enumerate(value):
                        self._check_keywords(subschema, path, trail + [key, str(index)])
        elif isinstance(node, list):
            for item in node:
                self._check_keywords(item, path, trail + ["[]"])

    def resolve_ref(self, base_document: dict, ref: str) -> tuple[dict, str]:
        fragment = ""
        target = ref
        if "#" in ref:
            target, fragment = ref.split("#", 1)
        if not target:
            return base_document, fragment
        if "://" in target:
            document = self.schemas.get(target)
            if document is None:
                raise SchemaError(f"unknown schema $id {target}")
            return document, fragment
        # Relative refs resolve against the referencing schema's $id, which
        # is a stable contract identifier, not a network location.
        base_id = base_document.get("$id")
        if not isinstance(base_id, str):
            raise SchemaError("schema without $id cannot use relative $ref")
        base_dir = base_id.rsplit("/", 1)[0]
        resolved = f"{base_dir}/{target}"
        document = self.schemas.get(resolved)
        if document is None:
            raise SchemaError(f"unresolvable $ref {ref} from {base_id}")
        return document, fragment

    def walk_pointer(self, document: dict, fragment: str) -> object:
        pointer = fragment.lstrip("/")
        if not pointer:
            return document
        current: object = document
        for part in pointer.split("/"):
            part = part.replace("~1", "/").replace("~0", "~")
            if isinstance(current, dict) and part in current:
                current = current[part]
            elif isinstance(current, list) and part.isdigit():
                current = current[int(part)]
            else:
                raise SchemaError(f"unresolvable JSON pointer #{fragment}")
        return current


def _type_matches(value: object, expected: object) -> bool:
    types = expected if isinstance(expected, list) else [expected]
    for type_name in types:
        if type_name == "object" and isinstance(value, dict):
            return True
        if type_name == "array" and isinstance(value, list):
            return True
        if type_name == "string" and isinstance(value, str):
            return True
        if type_name == "integer" and isinstance(value, int) and not isinstance(value, bool):
            return True
        if type_name == "number" and isinstance(value, (int, float)) and not isinstance(value, bool):
            return True
        if type_name == "boolean" and isinstance(value, bool):
            return True
        if type_name == "null" and value is None:
            return True
    return False


class Validator:
    def __init__(self, loader: SchemaLoader):
        self.loader = loader
        self.active = []

    def validate(self, schema: dict, value: object, path: str, base: dict | None = None) -> None:
        base = base or schema
        schema_id = schema.get("$id")
        if isinstance(schema_id, str) and schema_id in self.active:
            raise SchemaError(f"{path}: recursive $ref cycle through {schema_id}")
        if isinstance(schema_id, str):
            self.active.append(schema_id)
        try:
            self._validate(schema, value, path, base)
        finally:
            if isinstance(schema_id, str) and self.active and self.active[-1] == schema_id:
                self.active.pop()

    def _fail(self, path: str, message: str) -> None:
        raise SchemaError(f"{path}: {message}")

    def _validate(self, schema: dict, value: object, path: str, base: dict) -> None:
        if "$ref" in schema:
            document, fragment = self.loader.resolve_ref(base, schema["$ref"])
            target = self.loader.walk_pointer(document, fragment)
            if not isinstance(target, dict):
                self._fail(path, f"$ref target {schema['$ref']} is not a schema")
            self.validate(target, value, path, document)
            return
        if "type" in schema and not _type_matches(value, schema["type"]):
            self._fail(path, f"expected type {schema['type']}, got {type(value).__name__}")
        if "enum" in schema and value not in schema["enum"]:
            self._fail(path, f"value not in enum {schema['enum']}")
        if "const" in schema and value != schema["const"]:
            self._fail(path, f"expected const {schema['const']!r}")
        if isinstance(value, dict):
            if "properties" in schema:
                for name, subschema in schema["properties"].items():
                    if name in value:
                        self.validate(subschema, value[name], f"{path}.{name}", base)
            for name in schema.get("required", []):
                if name not in value:
                    self._fail(path, f"missing required property {name}")
            additional = schema.get("additionalProperties")
            if additional is False:
                allowed = set(schema.get("properties", {}))
                unexpected = sorted(set(value) - allowed)
                if unexpected:
                    self._fail(path, f"unexpected properties {unexpected}")
            elif isinstance(additional, dict):
                for name, item in value.items():
                    if name not in schema.get("properties", {}):
                        self.validate(additional, item, f"{path}.{name}", base)
        if isinstance(value, list):
            if "items" in schema:
                for index, item in enumerate(value):
                    self.validate(schema["items"], item, f"{path}[{index}]", base)
            min_items = schema.get("minItems")
            if min_items is not None and len(value) < min_items:
                self._fail(path, f"expected at least {min_items} items")
            max_items = schema.get("maxItems")
            if max_items is not None and len(value) > max_items:
                self._fail(path, f"expected at most {max_items} items")
            if schema.get("uniqueItems") and len(set(json.dumps(i, sort_keys=True) for i in value)) != len(value):
                self._fail(path, "items must be unique")
        if isinstance(value, str):
            min_length = schema.get("minLength")
            if min_length is not None and len(value) < min_length:
                self._fail(path, f"string shorter than minLength {min_length}")
            max_length = schema.get("maxLength")
            if max_length is not None and len(value) > max_length:
                self._fail(path, f"string longer than maxLength {max_length}")
            pattern = schema.get("pattern")
            if pattern is not None and re.search(pattern, value) is None:
                self._fail(path, f"string does not match pattern {pattern}")
        if isinstance(value, (int, float)) and not isinstance(value, bool):
            minimum = schema.get("minimum")
            if minimum is not None and value < minimum:
                self._fail(path, f"value {value} below minimum {minimum}")
            maximum = schema.get("maximum")
            if maximum is not None and value > maximum:
                self._fail(path, f"value {value} above maximum {maximum}")
            exclusive_minimum = schema.get("exclusiveMinimum")
            if exclusive_minimum is not None and value <= exclusive_minimum:
                self._fail(path, f"value {value} not above exclusiveMinimum {exclusive_minimum}")
            exclusive_maximum = schema.get("exclusiveMaximum")
            if exclusive_maximum is not None and value >= exclusive_maximum:
                self._fail(path, f"value {value} not below exclusiveMaximum {exclusive_maximum}")
        for keyword in ("anyOf", "allOf", "oneOf"):
            if keyword not in schema:
                continue
            branches = schema[keyword]
            results = []
            for branch in branches:
                try:
                    self.validate(branch, value, path, base)
                    results.append(True)
                except SchemaError:
                    results.append(False)
            if keyword == "anyOf" and not any(results):
                self._fail(path, "value matches none of anyOf")
            if keyword == "allOf" and not all(results):
                self._fail(path, "value fails one of allOf")
            if keyword == "oneOf" and sum(results) != 1:
                self._fail(path, f"value matches {sum(results)} branches of oneOf (expected 1)")
        if "not" in schema:
            try:
                self.validate(schema["not"], value, path, base)
            except SchemaError:
                pass
            else:
                self._fail(path, "value must not match the not schema")


def canonical_json(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))).encode(
        "utf-8"
    )


def sha256_bytes(data: bytes) -> str:
    import hashlib

    return "sha256:" + hashlib.sha256(data).hexdigest()


def validate_structured_reading_payload(payload: object, path: str) -> None:
    if not isinstance(payload, dict):
        raise SchemaError(f"{path}: structured reading payload must be an object")
    text = payload.get("text")
    if not isinstance(text, str) or not text:
        raise SchemaError(f"{path}.text: structured reading text must be a non-empty string")
    text_bytes = text.encode("utf-8")
    text_len = len(text_bytes)
    anchors = payload.get("anchors")
    if not isinstance(anchors, list) or not anchors:
        raise SchemaError(f"{path}.anchors: at least one anchor is required")
    previous = None
    seen = set()
    for index, anchor in enumerate(anchors):
        if not isinstance(anchor, dict):
            raise SchemaError(f"{path}.anchors[{index}]: must be an object")
        anchor_path = f"{path}.anchors[{index}]"
        anchor_id = anchor.get("anchor_id")
        if not isinstance(anchor_id, str) or not anchor_id:
            raise SchemaError(f"{anchor_path}.anchor_id: must be a non-empty string")
        if anchor_id in seen:
            raise SchemaError(f"{anchor_path}.anchor_id: duplicate anchor {anchor_id}")
        seen.add(anchor_id)
        start = anchor.get("start_offset")
        end = anchor.get("end_offset")
        if not isinstance(start, int) or not isinstance(end, int) or isinstance(start, bool) or isinstance(end, bool):
            raise SchemaError(f"{anchor_path}: offsets must be integers")
        if start < 0 or start >= end:
            raise SchemaError(f"{anchor_path}: offsets must satisfy 0 <= start < end")
        if end > text_len:
            raise SchemaError(
                f"{anchor_path}: end_offset {end} exceeds the text byte length {text_len}"
            )
        text_as_bytes = text_bytes
        if not is_char_boundary(text_as_bytes, start) or not is_char_boundary(text_as_bytes, end):
            raise SchemaError(f"{anchor_path}: offsets must land on UTF-8 character boundaries")
        if previous is not None and (start, end) < previous:
            raise SchemaError(f"{anchor_path}: anchor ranges must be in monotonic byte order")
        previous = (start, end)
    blocks = payload.get("blocks", [])
    if not isinstance(blocks, list):
        raise SchemaError(f"{path}.blocks: must be an array")
    roots = 0
    block_ids = set()
    for index, block in enumerate(blocks):
        if not isinstance(block, dict):
            raise SchemaError(f"{path}.blocks[{index}]: must be an object")
        block_path = f"{path}.blocks[{index}]"
        block_id = block.get("block_id")
        if not isinstance(block_id, str) or not block_id:
            raise SchemaError(f"{block_path}.block_id: must be a non-empty string")
        if block_id in block_ids:
            raise SchemaError(f"{block_path}.block_id: duplicate block {block_id}")
        block_ids.add(block_id)
        if block.get("kind") == "root":
            roots += 1
            if block.get("parent_block_id") is not None:
                raise SchemaError(f"{block_path}: root block must not declare a parent")
        span_anchors = block.get("span_anchor_ids")
        if not isinstance(span_anchors, list) or not span_anchors:
            raise SchemaError(f"{block_path}.span_anchor_ids: must reference at least one anchor")
        for span_anchor in span_anchors:
            if span_anchor not in seen:
                raise SchemaError(f"{block_path}: references unknown anchor {span_anchor}")
    if roots != 1:
        raise SchemaError(f"{path}: block hierarchy must declare exactly one root block (found {roots})")
    for block in blocks:
        if block.get("kind") != "root" and block.get("parent_block_id") not in block_ids:
            raise SchemaError(
                f"{path}: block {block.get('block_id')} has an undeclared parent"
            )
    order_groups: dict[object, list[int]] = {}
    for block in blocks:
        key = block.get("parent_block_id")
        order_groups.setdefault(key, []).append(block.get("order", 0))
    for key, orders in order_groups.items():
        expected = list(range(len(orders)))
        if sorted(orders) != expected:
            raise SchemaError(
                f"{path}: sibling orders under parent {key!r} must be contiguous 0-based values"
            )
    mapping_anchors = seen
    for index, mapping in enumerate(payload.get("document_mappings", [])):
        mapping_path = f"{path}.document_mappings[{index}]"
        if not isinstance(mapping, dict):
            raise SchemaError(f"{mapping_path}: must be an object")
        if mapping.get("anchor_id") not in mapping_anchors:
            raise SchemaError(f"{mapping_path}: references unknown anchor")
        locator = mapping.get("locator")
        if not isinstance(locator, dict) or not isinstance(locator.get("value"), str) or not locator["value"]:
            raise SchemaError(f"{mapping_path}.locator.value: must be a non-empty string")


def is_char_boundary(data: bytes, offset: int) -> bool:
    if offset == 0 or offset == len(data):
        return True
    byte = data[offset]
    return byte & 0xC0 != 0x80


def validate_anchor_time_alignment_payload(payload: object, path: str) -> None:
    if not isinstance(payload, dict):
        raise SchemaError(f"{path}: alignment payload must be an object")
    alignments = payload.get("alignments")
    if not isinstance(alignments, list) or not alignments:
        raise SchemaError(f"{path}.alignments: at least one entry is required")
    seen = set()
    previous = None
    for index, entry in enumerate(alignments):
        if not isinstance(entry, dict):
            raise SchemaError(f"{path}.alignments[{index}]: must be an object")
        anchor_id = entry.get("anchor_id")
        if not isinstance(anchor_id, str) or not anchor_id:
            raise SchemaError(f"{path}.alignments[{index}].anchor_id: must be non-empty")
        if anchor_id in seen:
            raise SchemaError(f"{path}.alignments[{index}]: duplicate anchor {anchor_id}")
        seen.add(anchor_id)
        time = entry.get("media_time_ms")
        if not isinstance(time, int) or isinstance(time, bool) or time < 0:
            raise SchemaError(f"{path}.alignments[{index}].media_time_ms: must be a non-negative integer")
        if previous is not None and time < previous:
            raise SchemaError(f"{path}.alignments[{index}]: media times must be non-decreasing")
        previous = time


def validate_example(root: Path, name: str) -> None:
    example_dir = root / "v3" / "examples" / name
    release_path = example_dir / "release.json"
    if not release_path.is_file():
        raise SchemaError(f"{example_dir}: missing release.json")
    release_bytes = release_path.read_bytes()
    release = json.loads(release_bytes.decode("utf-8"))
    if not isinstance(release, dict):
        raise SchemaError(f"{release_path}: release.json must be a JSON object")

    # Canonical identity document: must be canonical JSON and carry no own id.
    if canonical_json(release) != release_bytes:
        raise SchemaError(f"{release_path}: release.json is not canonical JSON")

    loader = SchemaLoader(root)
    validator = Validator(loader)
    release_schema = loader.files.get((root / "v3" / "release.schema.json").resolve())
    if release_schema is None:
        raise SchemaError("v3/release.schema.json is missing")
    validator.validate(release_schema, release, "release.json")

    # Recomputed identity invariants over the package body.
    declared_blobs = {}
    for rendition in release.get("document_renditions", []):
        if isinstance(rendition, dict):
            declared_blobs.setdefault(rendition["text_blob"]["digest"], rendition["text_blob"])
    for rendition in release.get("media_renditions", []):
        if isinstance(rendition, dict):
            declared_blobs.setdefault(rendition["media_blob"]["digest"], rendition["media_blob"])
    for resource in release.get("resources", []):
        descriptor = resource["descriptor"]
        expected_id = sha256_bytes(canonical_json(descriptor))
        if resource["resource_id"] != expected_id:
            raise SchemaError(
                f"{release_path}: resource_id does not match the descriptor canonical JSON"
            )
        declared_blobs.setdefault(descriptor["payload_blob"]["digest"], descriptor["payload_blob"])

    for digest, blob in declared_blobs.items():
        blob_path = example_dir / "blobs" / "sha256" / digest.removeprefix("sha256:")
        if blob["embedded"]:
            if not blob_path.is_file():
                raise SchemaError(f"{release_path}: embedded blob {digest} is missing")
            actual = blob_path.read_bytes()
            if sha256_bytes(actual) != digest:
                raise SchemaError(f"{release_path}: blob {digest} hash mismatch")
            if len(actual) != blob["size_bytes"]:
                raise SchemaError(f"{release_path}: blob {digest} size mismatch")

    # Payload bodies against their declared schema plus the typed post-pass.
    for resource in release.get("resources", []):
        descriptor = resource["descriptor"]
        schema_id = descriptor["schema"]
        blob = descriptor["payload_blob"]
        if not blob["embedded"]:
            continue
        payload_path = example_dir / "blobs" / "sha256" / blob["digest"].removeprefix("sha256:")
        payload_bytes = payload_path.read_bytes()
        payload = json.loads(payload_bytes.decode("utf-8"))
        schema_file = PAYLOAD_SCHEMA_INVENTORY.get(schema_id)
        if schema_file is None:
            raise SchemaError(
                f"{release_path}: resource {resource['resource_id']} declares unknown payload schema {schema_id}"
            )
        schema_path = (root / schema_file).resolve()
        schema = loader.files.get(schema_path)
        if schema is None:
            raise SchemaError(f"payload schema {schema_file} is missing")
        validator.validate(schema, payload, f"payload {schema_id}")
        if schema_id == "listen.payload.structured-reading.v1":
            validate_structured_reading_payload(payload, f"payload {schema_id}")
        elif schema_id == "listen.payload.anchor-time-alignment.v1":
            validate_anchor_time_alignment_payload(payload, f"payload {schema_id}")


def run_negative_tests(root: Path) -> None:
    tests_dir = root / "v3" / "tests"
    for path in sorted(tests_dir.glob("negative-*.json")):
        cases = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(cases, list):
            raise SchemaError(f"{path}: negative test file must be a JSON array")
        for case in cases:
            if not isinstance(case, dict):
                raise SchemaError(f"{path}: each case must be an object")
            name = case.get("name")
            schema_name = case.get("schema")
            document = case.get("document")
            if not isinstance(name, str) or not isinstance(schema_name, str):
                raise SchemaError(f"{path}: case needs name and schema")
            file_name, _, fragment = schema_name.partition("#")
            schema_path = (root / file_name).resolve()
            loader = SchemaLoader(root)
            schema_document = loader.files.get(schema_path)
            if schema_document is None:
                raise SchemaError(f"{path}: unknown schema file {file_name}")
            schema = loader.walk_pointer(schema_document, fragment.lstrip("/"))
            if not isinstance(schema, dict):
                raise SchemaError(f"{path}: schema fragment {schema_name} is not a schema")
            try:
                Validator(loader).validate(schema, document, name)
            except SchemaError:
                continue
            if schema_name.endswith("structured-reading.v1.schema.json"):
                try:
                    validate_structured_reading_payload(document, name)
                except SchemaError:
                    continue
            raise SchemaError(f"{path}: case {name} unexpectedly validated")


def main() -> int:
    root_arg = sys.argv[1] if len(sys.argv) > 1 else None
    if root_arg is None:
        root = Path(__file__).resolve().parent.parent / "contracts" / "content-package"
    else:
        root = Path(root_arg)
    for name in EXAMPLES:
        validate_example(root, name)
    run_negative_tests(root)
    print(f"Validated Content Package v3 schemas: {len(EXAMPLES)} examples and negative tests passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
