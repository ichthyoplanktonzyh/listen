from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from listen_gen.llm_client import (
    AnthropicMessagesClient,
    GeminiClient,
    LlmAdapterKind,
    LlmProviderProfile,
    OpenAiChatClient,
    auto_detect_profile,
    create_llm_client,
)
from listen_gen.rich import AlignmentSentence, AlignmentToken, SenseGroupRequest
from listen_gen.sense_groups import (
    LlmSenseGroupAnalyzer,
    PunctuationSenseGroupBaseline,
    SenseGroupPartitionConfig,
    SyntaxSenseGroupAnalyzer,
    partition_sentence_rule,
)


def _tokens(*texts: str) -> tuple[AlignmentToken, ...]:
    out: list[AlignmentToken] = []
    for index, text in enumerate(texts):
        if text.isalnum():
            kind, normalized = "word", text.casefold()
        elif text in ",.!?;:":
            kind, normalized = "punctuation", None
        else:
            kind, normalized = "whitespace", None
        out.append(AlignmentToken(index, kind, text, normalized, 0, len(text)))
    return tuple(out)


class SenseGroupThreeLayersTests(unittest.TestCase):
    def test_layer1_rule_short_sentence_protection(self) -> None:
        # 3 words: "Don't look back." -> should NOT be split into fragments
        tokens = _tokens("Don", "'", "t", " ", "look", " ", "back", ".")
        sentence = AlignmentSentence("s1", 0, 0, 1000, "Don't look back.", "Don't look back.", tokens)
        groups = partition_sentence_rule(sentence)
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0].start_token_index, 0)
        self.assertEqual(groups[0].end_token_index_exclusive, len(tokens))
        self.assertEqual(groups[0].sources, ("rule",))

    def test_layer1_rule_clause_punctuation_and_length_limit(self) -> None:
        # 10 words with comma: "When you go to the store, remember to buy some milk."
        words = ["When", " ", "you", " ", "go", " ", "to", " ", "the", " ", "store", ",", " ", "remember", " ", "to", " ", "buy", " ", "some", " ", "milk", "."]
        tokens = _tokens(*words)
        sentence = AlignmentSentence("s2", 0, 0, 3000, "When you go to the store, remember to buy some milk.", "When you go to the store, remember to buy some milk.", tokens)
        groups = partition_sentence_rule(sentence)
        self.assertEqual(len(groups), 2)
        # First group ends after the comma and space
        self.assertEqual(groups[0].start_token_index, 0)
        self.assertEqual(groups[0].end_token_index_exclusive, 13)
        self.assertEqual(groups[0].sources, ("punctuation",))
        # Second group covers the rest
        self.assertEqual(groups[1].start_token_index, 13)
        self.assertEqual(groups[1].end_token_index_exclusive, len(tokens))
        self.assertEqual(groups[1].sources, ("rule",))

    def test_layer2_syntax_analyzer_falls_back_when_backend_unavailable(self) -> None:
        analyzer = SyntaxSenseGroupAnalyzer(backend="spacy", model="non_existent_model")
        tokens = _tokens("Hello", " ", "world", "!")
        sentence = AlignmentSentence("s3", 0, 0, 1000, "Hello world!", "Hello world!", tokens)
        result = analyzer.analyze(SenseGroupRequest(language="en-US", sentences=(sentence,)))
        self.assertEqual(len(result.groups), 1)
        self.assertEqual(result.groups[0].start_token_index, 0)
        self.assertEqual(result.groups[0].end_token_index_exclusive, len(tokens))

    def test_layer3_llm_analyzer_boundary_validation_and_fallback(self) -> None:
        analyzer = LlmSenseGroupAnalyzer(api_key="")  # Empty API key triggers graceful fallback
        words = ["First", " ", "part", " ", "here", ",", " ", "second", " ", "part", " ", "there", "."]
        tokens = _tokens(*words)
        sentence = AlignmentSentence("s4", 0, 0, 2000, "First part here, second part there.", "First part here, second part there.", tokens)
        result = analyzer.analyze(SenseGroupRequest(language="en-US", sentences=(sentence,)))
        # Falls back to rule partition cleanly
        self.assertEqual(len(result.groups), 2)
        self.assertEqual(result.groups[0].start_token_index, 0)
        self.assertEqual(result.groups[0].end_token_index_exclusive, 7)
        self.assertEqual(result.groups[1].start_token_index, 7)
        self.assertEqual(result.groups[1].end_token_index_exclusive, len(tokens))

    def test_layer3_llm_spans_from_llm_boundaries(self) -> None:
        analyzer = LlmSenseGroupAnalyzer(api_key="mock")
        words = ["First", " ", "part", " ", "here", ",", " ", "second", " ", "part", " ", "there", "."]
        tokens = _tokens(*words)
        sentence = AlignmentSentence("s5", 0, 0, 2000, "First part here, second part there.", "First part here, second part there.", tokens)
        # Simulate LLM returning boundary after token index 6 (the comma ",")
        groups = analyzer._spans_from_llm_boundaries(sentence, [6])
        self.assertIsNotNone(groups)
        self.assertEqual(len(groups), 2)
        self.assertEqual(groups[0].start_token_index, 0)
        self.assertEqual(groups[0].end_token_index_exclusive, 7)
        self.assertEqual(groups[0].sources, ("language_model",))
        self.assertEqual(groups[1].start_token_index, 7)
        self.assertEqual(groups[1].end_token_index_exclusive, len(tokens))
        self.assertEqual(groups[1].sources, ("language_model",))

    def test_provider_agnostic_profile_auto_detection(self) -> None:
        # Anthropic detection
        profile_anthropic = auto_detect_profile(
            adapter_kind="anthropic_messages",
            api_key="sk-ant-test",
            model_id="claude-3-5-sonnet-20241022",
        )
        self.assertEqual(profile_anthropic.adapter_kind, LlmAdapterKind.ANTHROPIC_MESSAGES)
        client_anthropic = create_llm_client(profile_anthropic)
        self.assertIsInstance(client_anthropic, AnthropicMessagesClient)

        # Gemini detection
        profile_gemini = auto_detect_profile(
            base_url="https://generativelanguage.googleapis.com/v1beta",
            api_key="AIzaSy-test",
            model_id="gemini-1.5-flash",
        )
        self.assertEqual(profile_gemini.adapter_kind, LlmAdapterKind.GEMINI)
        client_gemini = create_llm_client(profile_gemini)
        self.assertIsInstance(client_gemini, GeminiClient)

        # OpenAI / DeepSeek / Qwen default detection
        profile_deepseek = auto_detect_profile(
            base_url="https://api.deepseek.com/v1",
            api_key="sk-deepseek-test",
            model_id="deepseek-chat",
        )
        self.assertEqual(profile_deepseek.adapter_kind, LlmAdapterKind.OPENAI_CHAT)
        client_deepseek = create_llm_client(profile_deepseek)
        self.assertIsInstance(client_deepseek, OpenAiChatClient)

    def test_provider_profile_json_file_loading(self) -> None:
        profile_data = {
            "adapter_kind": "anthropic_messages",
            "base_url": "https://api.anthropic.com",
            "model_id": "claude-3-haiku-20240307",
            "api_key": "sk-ant-file-key",
            "timeout_seconds": 45.0,
        }
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as temp_file:
            json.dump(profile_data, temp_file)
            temp_path = temp_file.name

        try:
            profile = LlmProviderProfile.from_file(temp_path)
            self.assertEqual(profile.adapter_kind, LlmAdapterKind.ANTHROPIC_MESSAGES)
            self.assertEqual(profile.base_url, "https://api.anthropic.com")
            self.assertEqual(profile.model_id, "claude-3-haiku-20240307")
            self.assertEqual(profile.api_key, "sk-ant-file-key")
            self.assertEqual(profile.timeout_seconds, 45.0)

            analyzer = LlmSenseGroupAnalyzer(profile=profile)
            self.assertEqual(analyzer.profile.adapter_kind, LlmAdapterKind.ANTHROPIC_MESSAGES)
        finally:
            Path(temp_path).unlink(missing_ok=True)
