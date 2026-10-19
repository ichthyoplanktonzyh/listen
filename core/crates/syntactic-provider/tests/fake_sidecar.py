#!/usr/bin/env python3
import argparse
import json
import sys
import time


parser = argparse.ArgumentParser()
parser.add_argument("--provider", required=True)
parser.add_argument("--model", required=True)
parser.add_argument("--model-dir")
args = parser.parse_args()

def respond(request):
  if args.model == "slow":
    time.sleep(1)
  if args.model == "malformed":
    print("not-json", flush=True)
    return
  if args.model in {"missing", "corrupt"}:
    kind = "model_missing" if args.model == "missing" else "model_corrupt"
    print(
        json.dumps(
            {
                "protocol_version": 1,
                "request_id": request["request_id"],
                "operation": request["operation"],
                "ok": False,
                "error": {"kind": kind, "detail": f"fixture model {args.model}"},
            }
        )
    , flush=True)
    return

  descriptor = {
    "provider_id": args.provider,
    "provider_version": "fake-v1",
    "runtime_id": "fake-python",
    "runtime_version": "1",
    "model_id": "fixture",
    "model_version": "1",
    "model_checksum_sha256": "c" * 64,
  }
  if args.model == "invalid" and request["operation"] == "analyze":
    print(
        json.dumps(
            {
                "protocol_version": 1,
                "request_id": request["request_id"],
                "operation": "analyze",
                "ok": False,
                "error": {"kind": "invalid_output", "detail": "fixture invalid tree"},
            }
        )
    , flush=True)
    return
  if request["operation"] == "probe":
    print(
        json.dumps(
            {
                "protocol_version": 1,
                "request_id": request["request_id"],
                "operation": "probe",
                "ok": True,
                "capability": {"status": "ready", "descriptor": descriptor},
            }
        )
    , flush=True)
    return

  sentences = []
  for source in request["sentences"]:
    syntactic_tokens = []
    root_index = next(
        index
        for index, token in enumerate(source["subtitle_tokens"])
        if token["kind"] == "word"
    )
    parser_index_by_subtitle = {}
    for source_token in source["subtitle_tokens"]:
        if source_token["kind"] == "whitespace":
            continue
        parser_index = len(syntactic_tokens)
        parser_index_by_subtitle[source_token["index"]] = parser_index
        is_root = source_token["index"] == root_index
        syntactic_tokens.append(
            {
                "parser_token_index": parser_index,
                "surface": source_token["text"],
                "lemma": source_token["text"].lower(),
                "upos": "PUNCT" if source_token["kind"] == "punctuation" else "X",
                "xpos": None,
                "features": {},
                "head_parser_token_index": None if is_root else 0,
                "dependency_relation": "root" if is_root else "dep",
                "start_char": source_token["start_char"],
                "end_char": source_token["end_char"],
                "subtitle_token_indices": [source_token["index"]],
                "alignment_status": "exact",
                "confidence": None,
            }
        )
    sentences.append(
        {
            "sentence_id": source["sentence_id"],
            "source_text": source["text"],
            "source_char_count": len(source["text"]),
            "tokens": syntactic_tokens,
            "unaligned_subtitle_token_indices": [],
            "lexical_alignment_coverage": 1.0,
        }
    )

  print(
    json.dumps(
        {
            "protocol_version": 1,
            "request_id": request["request_id"],
            "operation": "analyze",
            "ok": True,
            "analysis": {"descriptor": descriptor, "sentences": sentences},
        }
    )
  , flush=True)


for line in sys.stdin:
    if line.strip():
        respond(json.loads(line))
