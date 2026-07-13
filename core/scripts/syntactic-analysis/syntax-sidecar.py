#!/usr/bin/env python3
"""Provider-neutral JSONL syntactic-analysis research sidecar.

The process is intentionally long-lived: each stdin line is one request and
each stdout line is exactly one response. Diagnostics go to stderr. Heavy
provider imports are lazy so `probe` can report a closed missing-runtime/model
status and contract tests can run without Stanza, spaCy, or PyTorch installed.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import importlib.metadata
import importlib.util
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


PROTOCOL_VERSION = 1
PROVIDER_VERSION = "jsonl-v1"
PROCESSORS = "tokenize,mwt,pos,lemma,depparse"
SUPPORTED_LANGUAGES = {"en"}


class ProviderFailure(Exception):
    def __init__(self, kind: str, detail: str) -> None:
        super().__init__(detail)
        self.kind = kind
        self.detail = detail


def _directory_sha256(path: Path) -> str:
    if not path.exists():
        raise ProviderFailure("model_missing", f"model path does not exist: {path}")
    hasher = hashlib.sha256()
    files = sorted(candidate for candidate in path.rglob("*") if candidate.is_file())
    if not files:
        raise ProviderFailure("model_corrupt", f"model path has no files: {path}")
    for candidate in files:
        relative = candidate.relative_to(path).as_posix().encode("utf-8")
        hasher.update(len(relative).to_bytes(8, "little"))
        hasher.update(relative)
        with candidate.open("rb") as handle:
            while chunk := handle.read(1024 * 1024):
                hasher.update(chunk)
    return hasher.hexdigest()


def _parse_feats(value: str | None) -> dict[str, str]:
    if not value or value == "_":
        return {}
    result: dict[str, str] = {}
    for item in value.split("|"):
        key, separator, feature_value = item.partition("=")
        if separator and key and feature_value:
            result[key] = feature_value
    return result


def _normalize_for_overlap(value: str) -> str:
    return "".join(character.casefold() for character in value if not character.isspace())


def _alignment_status(
    token: dict[str, Any], subtitle_tokens: dict[int, dict[str, Any]], indices: list[int], text: str
) -> str:
    if len(indices) == 1:
        subtitle = subtitle_tokens[indices[0]]
        if token["start_char"] == subtitle["start_char"] and token["end_char"] == subtitle["end_char"]:
            source = text[token["start_char"] : token["end_char"]]
            return "exact" if source == token["surface"] else "normalized_overlap"
        return "split"
    source = text[token["start_char"] : token["end_char"]]
    if _normalize_for_overlap(source) == _normalize_for_overlap(token["surface"]):
        return "merged"
    return "normalized_overlap"


def align_tokens(
    text: str, raw_tokens: list[dict[str, Any]], subtitle_tokens: list[dict[str, Any]]
) -> tuple[list[dict[str, Any]], list[int], float]:
    char_count = len(text)
    subtitle_by_index = {int(token["index"]): token for token in subtitle_tokens}
    if len(subtitle_by_index) != len(subtitle_tokens):
        raise ProviderFailure("invalid_output", "duplicate SubtitleToken index in request")
    mapped_words: set[int] = set()
    aligned: list[dict[str, Any]] = []
    for parser_index, raw in enumerate(raw_tokens):
        start = int(raw["start_char"])
        end = int(raw["end_char"])
        if not 0 <= start < end <= char_count:
            raise ProviderFailure(
                "invalid_output", f"parser token {parser_index} has invalid span [{start}, {end})"
            )
        indices: list[int] = []
        for subtitle in subtitle_tokens:
            if subtitle.get("kind") == "whitespace":
                continue
            subtitle_start = int(subtitle["start_char"])
            subtitle_end = int(subtitle["end_char"])
            if start < subtitle_end and subtitle_start < end:
                subtitle_index = int(subtitle["index"])
                indices.append(subtitle_index)
                if subtitle.get("kind") == "word":
                    mapped_words.add(subtitle_index)
        if not indices:
            raise ProviderFailure(
                "invalid_output", f"parser token {parser_index} does not overlap a source token"
            )
        token = dict(raw)
        token["parser_token_index"] = parser_index
        token["subtitle_token_indices"] = indices
        token["alignment_status"] = _alignment_status(token, subtitle_by_index, indices, text)
        token.setdefault("confidence", None)
        aligned.append(token)
    word_indices = [
        int(token["index"]) for token in subtitle_tokens if token.get("kind") == "word"
    ]
    unaligned = [index for index in word_indices if index not in mapped_words]
    coverage = len(mapped_words) / len(word_indices) if word_indices else 1.0
    return aligned, unaligned, coverage


@dataclass
class ProviderConfig:
    provider: str
    model: str
    model_dir: Path | None


class ProviderAdapter:
    def __init__(self, config: ProviderConfig) -> None:
        self.config = config
        self._pipeline: Any = None
        self._descriptor: dict[str, str] | None = None

    def descriptor(self, language: str) -> dict[str, str]:
        self._load(language)
        assert self._descriptor is not None
        return self._descriptor

    def analyze(self, language: str, sentence: dict[str, Any]) -> dict[str, Any]:
        raise NotImplementedError

    def _load(self, language: str) -> None:
        raise NotImplementedError


class StanzaAdapter(ProviderAdapter):
    def _load(self, language: str) -> None:
        if self._pipeline is not None:
            return
        if importlib.util.find_spec("stanza") is None:
            raise ProviderFailure("runtime_missing", "Python package stanza is not installed")
        if language not in SUPPORTED_LANGUAGES:
            raise ProviderFailure("unsupported_language", language)
        stanza = importlib.import_module("stanza")
        model_root = self.config.model_dir or Path(
            os.environ.get("STANZA_RESOURCES_DIR", str(Path.home() / "stanza_resources"))
        )
        language_path = model_root / language
        if not language_path.exists():
            raise ProviderFailure("model_missing", f"Stanza language model is absent: {language_path}")
        try:
            self._pipeline = stanza.Pipeline(
                lang=language,
                package=self.config.model,
                processors=PROCESSORS,
                dir=str(model_root),
                tokenize_no_ssplit=True,
                download_method=stanza.DownloadMethod.NONE,
                use_gpu=False,
                verbose=False,
            )
        except Exception as error:  # provider exceptions are not stable APIs
            message = str(error)
            kind = "model_missing" if "not found" in message.casefold() else "model_corrupt"
            raise ProviderFailure(kind, f"Stanza model load failed: {message}") from error
        runtime_version = importlib.metadata.version("stanza")
        self._descriptor = {
            "provider_id": "stanza",
            "provider_version": PROVIDER_VERSION,
            "runtime_id": "python-stanza",
            "runtime_version": runtime_version,
            "model_id": f"{language}_{self.config.model}",
            "model_version": runtime_version,
            "model_checksum_sha256": _directory_sha256(language_path),
        }

    def analyze(self, language: str, sentence: dict[str, Any]) -> dict[str, Any]:
        self._load(language)
        document = self._pipeline(sentence["text"])
        words = [word for parsed_sentence in document.sentences for word in parsed_sentence.words]
        token_span_by_word_id: dict[int, tuple[int, int]] = {}
        for parsed_sentence in document.sentences:
            for token in parsed_sentence.tokens:
                token_ids = token.id if isinstance(token.id, tuple) else (token.id, token.id)
                for word_id in range(int(token_ids[0]), int(token_ids[-1]) + 1):
                    token_span_by_word_id[word_id] = (int(token.start_char), int(token.end_char))
        word_id_to_index = {int(word.id): index for index, word in enumerate(words)}
        raw_tokens: list[dict[str, Any]] = []
        for word in words:
            word_id = int(word.id)
            span = token_span_by_word_id.get(word_id)
            start = getattr(word, "start_char", None)
            end = getattr(word, "end_char", None)
            if start is None or end is None:
                if span is None:
                    raise ProviderFailure("invalid_output", f"Stanza word {word_id} lacks source offsets")
                start, end = span
            head = int(word.head)
            raw_tokens.append(
                {
                    "surface": word.text,
                    "lemma": word.lemma or word.text,
                    "upos": word.upos or "X",
                    "xpos": word.xpos,
                    "features": _parse_feats(word.feats),
                    "head_parser_token_index": None if head == 0 else word_id_to_index.get(head),
                    "dependency_relation": word.deprel or ("root" if head == 0 else "dep"),
                    "start_char": int(start),
                    "end_char": int(end),
                    "confidence": None,
                }
            )
        aligned, unaligned, coverage = align_tokens(
            sentence["text"], raw_tokens, sentence["subtitle_tokens"]
        )
        return _sentence_response(sentence, aligned, unaligned, coverage)


SPACY_DEPENDENCY_MAP = {
    "ROOT": "root",
    "acl": "acl",
    "acomp": "xcomp",
    "advcl": "advcl",
    "advmod": "advmod",
    "agent": "obl:agent",
    "amod": "amod",
    "appos": "appos",
    "attr": "xcomp",
    "aux": "aux",
    "auxpass": "aux:pass",
    "case": "case",
    "cc": "cc",
    "ccomp": "ccomp",
    "compound": "compound",
    "conj": "conj",
    "cop": "cop",
    "csubj": "csubj",
    "dative": "iobj",
    "dep": "dep",
    "det": "det",
    "dobj": "obj",
    "expl": "expl",
    "intj": "discourse",
    "mark": "mark",
    "meta": "dep",
    "neg": "advmod",
    "nmod": "nmod",
    "npadvmod": "obl:npmod",
    "nsubj": "nsubj",
    "nsubjpass": "nsubj:pass",
    "nummod": "nummod",
    "oprd": "xcomp",
    "parataxis": "parataxis",
    "pcomp": "ccomp",
    "poss": "nmod:poss",
    "preconj": "cc:preconj",
    "predet": "det:predet",
    "prt": "compound:prt",
    "punct": "punct",
    "quantmod": "advmod",
    "relcl": "acl:relcl",
    "xcomp": "xcomp",
}


class SpacyAdapter(ProviderAdapter):
    def _load(self, language: str) -> None:
        if self._pipeline is not None:
            return
        if importlib.util.find_spec("spacy") is None:
            raise ProviderFailure("runtime_missing", "Python package spacy is not installed")
        if language not in SUPPORTED_LANGUAGES:
            raise ProviderFailure("unsupported_language", language)
        spacy = importlib.import_module("spacy")
        try:
            self._pipeline = spacy.load(self.config.model)
        except OSError as error:
            raise ProviderFailure("model_missing", f"spaCy model is absent: {self.config.model}") from error
        except Exception as error:
            raise ProviderFailure("model_corrupt", f"spaCy model load failed: {error}") from error
        model_module = importlib.import_module(self.config.model)
        model_path = Path(model_module.__file__).resolve().parent
        self._descriptor = {
            "provider_id": "spacy",
            "provider_version": PROVIDER_VERSION,
            "runtime_id": "python-spacy",
            "runtime_version": importlib.metadata.version("spacy"),
            "model_id": self.config.model,
            "model_version": str(self._pipeline.meta.get("version", "unknown")),
            "model_checksum_sha256": _directory_sha256(model_path),
        }

    def analyze(self, language: str, sentence: dict[str, Any]) -> dict[str, Any]:
        self._load(language)
        document = self._pipeline(sentence["text"])
        prep_objects: dict[int, int] = {}
        for token in document:
            if token.dep_ == "pobj" and token.head.dep_ == "prep":
                prep_objects[token.head.i] = token.i
        raw_tokens: list[dict[str, Any]] = []
        for token in document:
            head: int | None
            dependency = SPACY_DEPENDENCY_MAP.get(token.dep_, "dep")
            if token.dep_ == "ROOT" or token.head.i == token.i:
                head = None
                dependency = "root"
            elif token.dep_ == "prep" and token.i in prep_objects:
                head = prep_objects[token.i]
                dependency = "case"
            elif token.dep_ == "pobj" and token.head.dep_ == "prep":
                head = token.head.head.i
                dependency = "obl"
            else:
                head = token.head.i
            raw_tokens.append(
                {
                    "surface": token.text,
                    "lemma": token.lemma_ or token.text,
                    "upos": token.pos_ or "X",
                    "xpos": token.tag_ or None,
                    "features": token.morph.to_dict(),
                    "head_parser_token_index": head,
                    "dependency_relation": dependency,
                    "start_char": token.idx,
                    "end_char": token.idx + len(token.text),
                    "confidence": None,
                }
            )
        aligned, unaligned, coverage = align_tokens(
            sentence["text"], raw_tokens, sentence["subtitle_tokens"]
        )
        return _sentence_response(sentence, aligned, unaligned, coverage)


def _sentence_response(
    sentence: dict[str, Any], tokens: list[dict[str, Any]], unaligned: list[int], coverage: float
) -> dict[str, Any]:
    return {
        "sentence_id": sentence["sentence_id"],
        "source_text": sentence["text"],
        "source_char_count": len(sentence["text"]),
        "tokens": tokens,
        "unaligned_subtitle_token_indices": unaligned,
        "lexical_alignment_coverage": coverage,
    }


def build_adapter(config: ProviderConfig) -> ProviderAdapter:
    if config.provider == "stanza":
        return StanzaAdapter(config)
    if config.provider == "spacy":
        return SpacyAdapter(config)
    raise ProviderFailure("protocol", f"unknown provider: {config.provider}")


def _validate_request(request: dict[str, Any], configured_provider: str) -> tuple[str, str]:
    if request.get("protocol_version") != PROTOCOL_VERSION:
        raise ProviderFailure("protocol", "unsupported protocol_version")
    request_id = request.get("request_id")
    if not isinstance(request_id, str) or not request_id:
        raise ProviderFailure("protocol", "request_id is required")
    if request.get("provider") != configured_provider:
        raise ProviderFailure("protocol", "request provider does not match process provider")
    operation = request.get("operation")
    if operation not in {"probe", "analyze"}:
        raise ProviderFailure("protocol", f"unsupported operation: {operation}")
    return request_id, operation


def handle_request(adapter: ProviderAdapter, request: dict[str, Any]) -> dict[str, Any]:
    request_id, operation = _validate_request(request, adapter.config.provider)
    language = request.get("language")
    if not isinstance(language, str):
        raise ProviderFailure("protocol", "language is required")
    if operation == "probe":
        descriptor = adapter.descriptor(language)
        return {
            "protocol_version": PROTOCOL_VERSION,
            "request_id": request_id,
            "operation": operation,
            "ok": True,
            "capability": {"status": "ready", "descriptor": descriptor},
        }
    sentences = request.get("sentences")
    if not isinstance(sentences, list) or not sentences:
        raise ProviderFailure("protocol", "analyze requires a non-empty sentences array")
    results = []
    for sentence in sentences:
        if not isinstance(sentence, dict) or not isinstance(sentence.get("text"), str):
            raise ProviderFailure("protocol", "each sentence requires text")
        if not isinstance(sentence.get("subtitle_tokens"), list):
            raise ProviderFailure("protocol", "each sentence requires subtitle_tokens")
        results.append(adapter.analyze(language, sentence))
    return {
        "protocol_version": PROTOCOL_VERSION,
        "request_id": request_id,
        "operation": operation,
        "ok": True,
        "analysis": {"descriptor": adapter.descriptor(language), "sentences": results},
    }


def error_response(request_id: Any, operation: Any, error: ProviderFailure) -> dict[str, Any]:
    return {
        "protocol_version": PROTOCOL_VERSION,
        "request_id": request_id if isinstance(request_id, str) else None,
        "operation": operation if isinstance(operation, str) else None,
        "ok": False,
        "error": {"kind": error.kind, "detail": error.detail},
    }


def run_jsonl(adapter: ProviderAdapter, lines: Iterable[str]) -> int:
    for line_number, raw in enumerate(lines, 1):
        if not raw.strip():
            continue
        request: Any = None
        try:
            request = json.loads(raw)
            if not isinstance(request, dict):
                raise ProviderFailure("protocol", "request must be a JSON object")
            response = handle_request(adapter, request)
        except json.JSONDecodeError as error:
            failure = ProviderFailure("protocol", f"invalid JSON: {error.msg}")
            print(f"syntax-sidecar line {line_number}: {failure.detail}", file=sys.stderr)
            response = error_response(None, None, failure)
        except ProviderFailure as error:
            print(f"syntax-sidecar line {line_number}: {error.kind}: {error.detail}", file=sys.stderr)
            response = error_response(
                request.get("request_id") if isinstance(request, dict) else None,
                request.get("operation") if isinstance(request, dict) else None,
                error,
            )
        except Exception as error:  # keep unexpected provider failures closed and protocol-safe
            failure = ProviderFailure("process", f"unexpected provider failure: {type(error).__name__}")
            print(f"syntax-sidecar line {line_number}: {error!r}", file=sys.stderr)
            response = error_response(
                request.get("request_id") if isinstance(request, dict) else None,
                request.get("operation") if isinstance(request, dict) else None,
                failure,
            )
        sys.stdout.write(json.dumps(response, ensure_ascii=False, separators=(",", ":")) + "\n")
        sys.stdout.flush()
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--provider", required=True, choices=("stanza", "spacy"))
    parser.add_argument("--model")
    parser.add_argument("--model-dir", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    model = args.model or ("ewt" if args.provider == "stanza" else "en_core_web_sm")
    adapter = build_adapter(ProviderConfig(args.provider, model, args.model_dir))
    return run_jsonl(adapter, sys.stdin)


if __name__ == "__main__":
    raise SystemExit(main())
