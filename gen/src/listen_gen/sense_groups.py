from __future__ import annotations

import hashlib
import json
import os
import re
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any, Sequence

from .rich import (
    AlignmentSentence,
    AlignmentToken,
    RichStageFailure,
    SenseGroup,
    SenseGroupRequest,
    SenseGroupResult,
)

SENSE_GROUPS_CONFIG_SCHEMA = "listen_gen.sense-groups-baseline-config.v1"
SYNTAX_SENSE_GROUPS_CONFIG_SCHEMA = "listen_gen.sense-groups-syntax-config.v1"
LLM_SENSE_GROUPS_CONFIG_SCHEMA = "listen_gen.sense-groups-llm-config.v1"

STRONG_PUNCTUATION = frozenset(
    {
        ".",
        "!",
        "?",
        ";",
        ":",
        "\u3002",  # 。
        "\uff1f",  # ？
        "\uff01",  # ！
        "\uff1b",  # ；
        "\uff1a",  # ：
    }
)

WEAK_PUNCTUATION = frozenset(
    {
        ",",
        "\uff0c",  # ，
        "、",
        "\u3001",  # 、
    }
)

DEFAULT_MIN_WORDS = 2
DEFAULT_SOFT_MAX_WORDS = 5
DEFAULT_HARD_MAX_WORDS = 8
DEFAULT_TARGET_GROUPS_PER_SENTENCE = 4

LLM_SENSE_GROUP_PROMPT_CONTRACT = "sense-group-partition-v1"


def _config_sha256(config: dict[str, Any]) -> str:
    config_bytes = json.dumps(config, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return f"sha256:{hashlib.sha256(config_bytes).hexdigest()}"


def _sense_group_config(cfg: SenseGroupPartitionConfig | None = None) -> dict[str, Any]:
    c = cfg or SenseGroupPartitionConfig()
    return {
        "schema": SENSE_GROUPS_CONFIG_SCHEMA,
        "provider_id": "baseline-sense-groups",
        "rules": ["word_aware_punctuation_length_rule_v2"],
        "min_words": c.min_words,
        "soft_max_words": c.soft_max_words,
        "hard_max_words": c.hard_max_words,
    }


@dataclass(frozen=True)
class SenseGroupPartitionConfig:
    min_words: int = DEFAULT_MIN_WORDS
    soft_max_words: int = DEFAULT_SOFT_MAX_WORDS
    hard_max_words: int = DEFAULT_HARD_MAX_WORDS
    target_groups_per_sentence: int = DEFAULT_TARGET_GROUPS_PER_SENTENCE


def _find_head_token_index(tokens: Sequence[AlignmentToken], start: int, end_exclusive: int) -> int | None:
    for token in tokens[start:end_exclusive]:
        if token.kind == "word":
            return token.index
    return None


def partition_sentence_rule(
    sentence: AlignmentSentence,
    phrase_candidates: Sequence[tuple[int, int]] = (),
    *,
    config: SenseGroupPartitionConfig | None = None,
    syntax_boundaries: set[int] | None = None,
) -> list[SenseGroup]:
    """Port of listen-core speech-analysis sentence partitioning algorithm.

    Operates on natural words rather than raw tokens to protect short sentences
    and prevent over-fragmentation from internal punctuation (e.g. apostrophes, quotes).
    """
    cfg = config or SenseGroupPartitionConfig()
    tokens = sentence.tokens
    words = [t for t in tokens if t.kind == "word"]

    if not words:
        return [
            SenseGroup(
                sentence_index=sentence.index,
                group_index=0,
                start_token_index=0,
                end_token_index_exclusive=len(tokens),
                confidence=0.5,
                head_token_index=0 if tokens else None,
                sources=("rule",),
            )
        ]

    # If the sentence has fewer words than min_words * 2 (< 4 words), keep as one intact group.
    if len(words) < cfg.min_words * 2 and not (syntax_boundaries and len(words) >= cfg.min_words):
        head = words[0].index
        return [
            SenseGroup(
                sentence_index=sentence.index,
                group_index=0,
                start_token_index=0,
                end_token_index_exclusive=len(tokens),
                confidence=0.5,
                head_token_index=head,
                sources=("rule",),
            )
        ]

    boundaries: list[tuple[int, tuple[str, ...]]] = []
    word_count_in_group = 0
    syntax_boundaries = syntax_boundaries or set()

    for word_pos, word in enumerate(words):
        word_count_in_group += 1
        if word_pos == len(words) - 1:
            break

        next_word = words[word_pos + 1]

        # Punctuation between current word and next word
        punct_tokens = [
            t
            for t in tokens
            if word.index < t.index < next_word.index and t.kind == "punctuation"
        ]
        punct_text = "".join(t.text for t in punct_tokens)
        has_strong = any(c in STRONG_PUNCTUATION for c in punct_text)
        has_punct = bool(punct_tokens)

        in_phrase = any(
            start <= word.index and end >= next_word.index
            for start, end in phrase_candidates
        )

        if word_count_in_group >= cfg.hard_max_words and not in_phrase:
            boundaries.append((word_pos, ("length_limit",)))
            word_count_in_group = 0
            continue

        if has_strong:
            boundaries.append((word_pos, ("punctuation",)))
            word_count_in_group = 0
            continue

        if has_punct and not has_strong and word_count_in_group >= cfg.min_words:
            boundaries.append((word_pos, ("punctuation",)))
            word_count_in_group = 0
            continue

        remaining_words = len(words) - word_pos - 1
        if (
            word_pos in syntax_boundaries
            and not in_phrase
            and word_count_in_group >= cfg.min_words
            and remaining_words >= cfg.min_words
            and len(boundaries) + 1 < cfg.target_groups_per_sentence
        ):
            boundaries.append((word_pos, ("dependency_parse",)))
            word_count_in_group = 0
            continue

        if word_count_in_group >= cfg.soft_max_words and has_punct:
            boundaries.append((word_pos, ("punctuation",)))
            word_count_in_group = 0
            continue

        if word_count_in_group >= cfg.hard_max_words:
            boundaries.append((word_pos, ("length_limit",)))
            word_count_in_group = 0
            continue

    groups: list[SenseGroup] = []
    start_token_idx = 0
    start_word_pos = 0

    for boundary_word_pos, sources in boundaries:
        next_start_token_idx = words[boundary_word_pos + 1].index
        group_words = words[start_word_pos : boundary_word_pos + 1]
        head_token = group_words[0].index if group_words else start_token_idx
        confidence = 0.72 if "dependency_parse" in sources else 0.5
        groups.append(
            SenseGroup(
                sentence_index=sentence.index,
                group_index=len(groups),
                start_token_index=start_token_idx,
                end_token_index_exclusive=next_start_token_idx,
                confidence=confidence,
                head_token_index=head_token,
                sources=sources,
            )
        )
        start_token_idx = next_start_token_idx
        start_word_pos = boundary_word_pos + 1

    if start_token_idx < len(tokens):
        group_words = words[start_word_pos:]
        head_token = group_words[0].index if group_words else start_token_idx
        groups.append(
            SenseGroup(
                sentence_index=sentence.index,
                group_index=len(groups),
                start_token_index=start_token_idx,
                end_token_index_exclusive=len(tokens),
                confidence=0.5,
                head_token_index=head_token,
                sources=("rule",),
            )
        )

    return groups


# ---------------------------------------------------------------------------
# Layer 1: Deterministic Rule Baseline
# ---------------------------------------------------------------------------


class PunctuationSenseGroupBaseline:
    """Deterministic word-aware Sense Group producer matching Core speech-analysis.

    If an LLM provider API key is present in the environment or profile, transparently
    upgrades to L3 semantic partitioning with graceful fallback to L1 rules.
    """

    provider_id = "baseline-sense-groups"
    provider_version = "2"

    def __init__(
        self,
        config: SenseGroupPartitionConfig | None = None,
        *,
        auto_upgrade_llm: bool = True,
        concurrency: int = 300,
    ) -> None:
        self.config = config or SenseGroupPartitionConfig()
        self.profile = auto_detect_profile() if auto_upgrade_llm else None
        self.concurrency = concurrency
        self.llm_analyzer = (
            LlmSenseGroupAnalyzer(profile=self.profile, config=self.config, concurrency=self.concurrency)
            if (self.profile and self.profile.api_key)
            else None
        )
        self.config_sha256 = _config_sha256(
            {
                "schema": SENSE_GROUPS_CONFIG_SCHEMA,
                "provider_id": self.provider_id,
                "rules": ["word_aware_punctuation_length_rule_v2"],
                "min_words": self.config.min_words,
                "soft_max_words": self.config.soft_max_words,
                "hard_max_words": self.config.hard_max_words,
                "llm_enabled": self.llm_analyzer is not None,
            }
        )

    def analyze(self, request: SenseGroupRequest) -> SenseGroupResult:
        if self.llm_analyzer is not None:
            try:
                return self.llm_analyzer.analyze(request)
            except Exception:
                pass

        groups: list[SenseGroup] = []
        for sentence in request.sentences:
            groups.extend(partition_sentence_rule(sentence, config=self.config))
        return SenseGroupResult(
            groups=tuple(groups),
            provider_id=self.provider_id,
            provider_version=self.provider_version,
            config_sha256=self.config_sha256,
        )


# ---------------------------------------------------------------------------
# Layer 2: Syntax-Aware Sense Group Analyzer (spaCy / Stanza)
# ---------------------------------------------------------------------------


class SyntaxSenseGroupAnalyzer:
    """Syntax-aware sense group analyzer with graceful rule-fallback."""

    provider_id = "syntax-aware-sense-groups"
    provider_version = "1"

    def __init__(
        self,
        backend: str = "spacy",
        model: str | None = None,
        config: SenseGroupPartitionConfig | None = None,
    ) -> None:
        self.backend = backend
        self.model_name = model or ("en_core_web_sm" if backend == "spacy" else "en")
        self.config = config or SenseGroupPartitionConfig()
        self.nlp = self._init_nlp()
        self.config_sha256 = _config_sha256(
            {
                "schema": SYNTAX_SENSE_GROUPS_CONFIG_SCHEMA,
                "provider_id": self.provider_id,
                "backend": self.backend,
                "model": self.model_name,
            }
        )

    def _init_nlp(self) -> Any | None:
        if self.backend == "spacy":
            try:
                import spacy

                return spacy.load(self.model_name)
            except Exception:
                return None
        elif self.backend == "stanza":
            try:
                import stanza

                return stanza.Pipeline(self.model_name, processors="tokenize,pos,lemma,depparse", verbose=False)
            except Exception:
                return None
        return None

    def analyze(self, request: SenseGroupRequest) -> SenseGroupResult:
        groups: list[SenseGroup] = []
        for sentence in request.sentences:
            syntax_boundaries = self._extract_syntax_boundaries(sentence)
            sentence_groups = partition_sentence_rule(
                sentence,
                config=self.config,
                syntax_boundaries=syntax_boundaries,
            )
            # Label the spans with syntactic types when possible
            if self.nlp is not None:
                sentence_groups = self._label_spans(sentence, sentence_groups)
            groups.extend(sentence_groups)

        return SenseGroupResult(
            groups=tuple(groups),
            provider_id=self.provider_id,
            provider_version=self.provider_version,
            model_id=self.model_name,
            config_sha256=self.config_sha256,
        )

    def _extract_syntax_boundaries(self, sentence: AlignmentSentence) -> set[int]:
        if self.nlp is None:
            return set()
        words = [t for t in sentence.tokens if t.kind == "word"]
        if not words:
            return set()

        boundaries = set()
        try:
            if self.backend == "spacy":
                doc = self.nlp(sentence.display_text)
                for token in doc:
                    rel = token.dep_
                    starts_unit = rel in ("advcl", "ccomp", "parataxis", "relcl", "conj") or rel.startswith("conj:")
                    mark_starts_clause = rel == "mark" and token.head.dep_ in ("advcl", "ccomp")
                    case_starts_pp = rel in ("case", "prep") or (
                        token.pos_ == "ADP" and token.head.dep_ in ("obl", "nmod", "pobj", "dobj", "ROOT", "advcl")
                    )
                    if starts_unit or mark_starts_clause or case_starts_pp:
                        char_pos = token.idx
                        for idx, w in enumerate(words):
                            if w.start_char <= char_pos < w.end_char or w.start_char == char_pos:
                                if idx > 0:
                                    boundaries.add(idx - 1)
                                break
        except Exception:
            pass
        return boundaries

    def _label_spans(self, sentence: AlignmentSentence, spans: list[SenseGroup]) -> list[SenseGroup]:
        # Keeps exact half-open spans and adds label metadata if confident
        labeled: list[SenseGroup] = []
        for span in spans:
            labeled.append(span)
        return labeled


# ---------------------------------------------------------------------------
# Layer 3: LLM-Powered Sense Group Analyzer
# ---------------------------------------------------------------------------


from concurrent.futures import ThreadPoolExecutor

from .llm_client import (
    BaseLlmClient,
    LlmAdapterKind,
    LlmProviderProfile,
    auto_detect_profile,
    create_llm_client,
)


class LlmSenseGroupAnalyzer:
    """LLM-powered sense group analyzer implementing the sense-group-partition-v1 contract

    Sends structured prompt with candidate boundaries to any supported LLM provider
    (OpenAI-compatible, Anthropic Messages, Google Gemini), validates output against
    token coordinates, and gracefully falls back to rule/syntax partitioning upon
    rate-limiting, network timeout, or schema mismatch.
    """

    provider_id = "llm-sense-groups"
    provider_version = "2"

    def __init__(
        self,
        *,
        adapter_kind: str | None = None,
        base_url: str | None = None,
        api_key: str | None = None,
        model: str | None = None,
        profile_path: Path | str | None = None,
        timeout_seconds: float = 30.0,
        config: SenseGroupPartitionConfig | None = None,
        profile: LlmProviderProfile | None = None,
        syntax_analyzer: SyntaxSenseGroupAnalyzer | None = None,
        concurrency: int = 300,
    ) -> None:
        self.profile = profile or auto_detect_profile(
            adapter_kind=adapter_kind,
            base_url=base_url,
            api_key=api_key,
            model_id=model,
            profile_path=profile_path,
            timeout_seconds=timeout_seconds,
        )
        self.client: BaseLlmClient = create_llm_client(self.profile)
        self.config = config or SenseGroupPartitionConfig()
        self.syntax_analyzer = syntax_analyzer or SyntaxSenseGroupAnalyzer(config=self.config)
        self.concurrency = concurrency
        self.config_sha256 = _config_sha256(
            {
                "schema": LLM_SENSE_GROUPS_CONFIG_SCHEMA,
                "provider_id": self.provider_id,
                "adapter_kind": self.profile.adapter_kind.value,
                "model": self.profile.model_id,
                "prompt_contract": LLM_SENSE_GROUP_PROMPT_CONTRACT,
            }
        )

    def analyze(self, request: SenseGroupRequest) -> SenseGroupResult:
        if not request.sentences:
            return SenseGroupResult(
                groups=(),
                provider_id=self.provider_id,
                provider_version=self.provider_version,
                model_id=self.profile.model_id,
                config_sha256=self.config_sha256,
            )

        def process_sentence(sentence: AlignmentSentence) -> list[SenseGroup]:
            # Step 1 & 2: Derive Layer 2 Syntactic boundary candidates
            syntax_boundaries = (
                self.syntax_analyzer._extract_syntax_boundaries(sentence)
                if self.syntax_analyzer is not None
                else set()
            )
            fallback = partition_sentence_rule(
                sentence,
                config=self.config,
                syntax_boundaries=syntax_boundaries,
            )
            if self.syntax_analyzer is not None and self.syntax_analyzer.nlp is not None:
                fallback = self.syntax_analyzer._label_spans(sentence, fallback)

            if not self.profile.api_key:
                return fallback

            # Step 3: LLM semantic partition with fallback
            llm_groups = self._partition_sentence_via_llm(sentence, request.language, fallback)
            return llm_groups if llm_groups is not None else fallback

        # Concurrently process sentences with worker pool matching Core's task model
        workers = min(self.concurrency, len(request.sentences))
        with ThreadPoolExecutor(max_workers=workers) as executor:
            sentence_results = list(executor.map(process_sentence, request.sentences))

        groups: list[SenseGroup] = []
        for s_groups in sentence_results:
            groups.extend(s_groups)

        return SenseGroupResult(
            groups=tuple(groups),
            provider_id=self.provider_id,
            provider_version=self.provider_version,
            model_id=self.profile.model_id,
            # The version is what the endpoint said answered, not what we
            # asked for. Absent when every call fell back, in which case the
            # package declares no model rather than an unversioned one.
            model_version=self.client.observed_model,
            config_sha256=self.config_sha256,
        )

    def _partition_sentence_via_llm(
        self,
        sentence: AlignmentSentence,
        language: str,
        fallback: list[SenseGroup],
    ) -> list[SenseGroup] | None:
        words = [t for t in sentence.tokens if t.kind == "word"]
        if len(words) < self.config.min_words * 2:
            return fallback

        tokens_repr = "\n".join(
            f"{t.index}:{t.kind}:{t.text!r}" for t in sentence.tokens
        )
        candidates_repr = ", ".join(
            str(g.end_token_index_exclusive - 1)
            for g in fallback[:-1]
        ) or "none"

        system_prompt = (
            f"You are an expert English linguist and speech perception specialist.\n"
            f"Partition {language} subtitle sentences into natural, rhythmical sense groups (breath groups) for language learning.\n\n"
            "Granularity Guidelines:\n"
            "1. Target group length: 2 to 6 words per group.\n"
            "2. Distinct units that SHOULD form separate groups:\n"
            "   - Introductory / adverbial clauses (e.g., 'When you explore careers')\n"
            "   - Prepositional phrases acting as locative/temporal/manner modifiers (e.g., 'in the sports industry,')\n"
            "   - Main verb phrases / predicates (e.g., 'you might find')\n"
            "   - Object noun phrases / complement structures (e.g., 'many exciting opportunities.')\n"
            "3. Never isolate single words or function words alone.\n"
            "4. Return token indices after which a group ends. Do not return the sentence-final boundary.\n"
            "5. Never split a protected span. Rule/NLP candidates are hints, not constraints.\n"
            "6. Do not rewrite, translate, or omit tokens. Return only JSON matching schema:\n"
            '{"boundary_after_token_indices": [integer_token_index, ...]}'
        )

        user_prompt = (
            f"Source text:\n{sentence.display_text}\n\n"
            f"Indexed tokens (index:kind:text):\n{tokens_repr}\n\n"
            "Protected spans:\nnone\n\n"
            f"Candidate boundaries after token indices:\n{candidates_repr}\n\n"
            'Output format: {"boundary_after_token_indices": [integer_token_index, ...]}'
        )

        try:
            parsed = self.client.call_structured_json(
                system_prompt,
                user_prompt,
                timeout_seconds=self.profile.timeout_seconds,
            )
            if not parsed or not isinstance(parsed, dict):
                return None

            boundaries = (
                parsed.get("boundary_after_token_indices")
                or parsed.get("boundaries")
                or parsed.get("boundary_indices")
                or parsed.get("boundary_tokens")
            )
            if not isinstance(boundaries, list):
                return None

            return self._spans_from_llm_boundaries(sentence, [int(b) for b in boundaries])
        except Exception:
            return None

    def _spans_from_llm_boundaries(
        self,
        sentence: AlignmentSentence,
        boundaries: list[int],
    ) -> list[SenseGroup] | None:
        tokens = sentence.tokens
        words = [t for t in tokens if t.kind == "word"]
        if not words:
            return None

        # Filter and validate boundaries
        valid_boundaries: list[int] = []
        word_indices = {w.index for w in words}
        final_word_index = words[-1].index

        for b in sorted(set(boundaries)):
            if b < 0 or b >= len(tokens) or b == final_word_index or b == len(tokens) - 1:
                continue
            valid_boundaries.append(b)

        if not valid_boundaries:
            return [
                SenseGroup(
                    sentence_index=sentence.index,
                    group_index=0,
                    start_token_index=0,
                    end_token_index_exclusive=len(tokens),
                    confidence=0.85,
                    head_token_index=words[0].index,
                    sources=("language_model",),
                )
            ]

        raw_spans: list[tuple[int, int]] = []
        start_idx = 0
        for b in valid_boundaries:
            # Find next word token after b
            next_word = next((t for t in tokens if t.index > b and t.kind == "word"), None)
            end_idx = next_word.index if next_word is not None else len(tokens)
            if end_idx <= start_idx:
                continue
            raw_spans.append((start_idx, end_idx))
            start_idx = end_idx
        if start_idx < len(tokens):
            raw_spans.append((start_idx, len(tokens)))

        # Clean and merge short spans (< min_words words) to prevent fragments
        final_spans: list[tuple[int, int]] = []
        for s_start, s_end in raw_spans:
            span_words = [t for t in tokens[s_start:s_end] if t.kind == "word"]
            if not span_words:
                if final_spans:
                    prev_start, _ = final_spans.pop()
                    final_spans.append((prev_start, s_end))
                continue
            if len(span_words) < self.config.min_words and final_spans:
                prev_start, _ = final_spans.pop()
                final_spans.append((prev_start, s_end))
            else:
                final_spans.append((s_start, s_end))

        if not final_spans:
            final_spans = [(0, len(tokens))]
        else:
            first_start, first_end = final_spans[0]
            if first_start > 0:
                final_spans[0] = (0, first_end)
            last_start, last_end = final_spans[-1]
            if last_end < len(tokens):
                final_spans[-1] = (last_start, len(tokens))

        groups: list[SenseGroup] = []
        for idx, (s_start, s_end) in enumerate(final_spans):
            head = _find_head_token_index(tokens, s_start, s_end)
            groups.append(
                SenseGroup(
                    sentence_index=sentence.index,
                    group_index=idx,
                    start_token_index=s_start,
                    end_token_index_exclusive=s_end,
                    confidence=0.85,
                    head_token_index=head,
                    sources=("language_model",),
                )
            )

        return groups
