from __future__ import annotations

import json
import tempfile
import unittest
from unittest import mock
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
    LLM_SENSE_GROUP_SYSTEM_PROMPT,
    LlmSenseGroupAnalyzer,
    PunctuationSenseGroupBaseline,
    SenseGroupPartitionConfig,
    SyntaxSenseGroupAnalyzer,
    partition_sentence_rule,
)


def _tokens(*texts: str) -> tuple[AlignmentToken, ...]:
    out: list[AlignmentToken] = []
    offset = 0
    for index, text in enumerate(texts):
        if text.isalnum():
            kind, normalized = "word", text.casefold()
        elif text in ",.!?;:@/":
            kind, normalized = "punctuation", None
        else:
            kind, normalized = "whitespace", None
        out.append(AlignmentToken(index, kind, text, normalized, offset, offset + len(text)))
        offset += len(text)
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

    def test_internal_domain_dot_does_not_create_a_sense_group_boundary(self) -> None:
        words = [
            "We",
            " ",
            "learn",
            " ",
            "at",
            " ",
            "BBCLearningEnglish",
            ".",
            "com",
            " ",
            "today",
            ".",
        ]
        text = "".join(words)
        sentence = AlignmentSentence(
            "domain",
            0,
            0,
            1000,
            text,
            text,
            _tokens(*words),
        )
        groups = partition_sentence_rule(
            sentence,
            config=SenseGroupPartitionConfig(soft_max_words=20, hard_max_words=20),
        )
        self.assertEqual(len(groups), 1)
        self.assertEqual(groups[0].sources, ("rule",))

    def test_email_decimal_and_abbreviation_internal_punctuation_is_protected(self) -> None:
        cases = (
            (
                "Please email CNN10@cnn.com today.",
                [
                    "Please",
                    " ",
                    "email",
                    " ",
                    "CNN10",
                    "@",
                    "cnn",
                    ".",
                    "com",
                    " ",
                    "today",
                    ".",
                ],
            ),
            (
                "The value is 3.14 today.",
                [
                    "The",
                    " ",
                    "value",
                    " ",
                    "is",
                    " ",
                    "3",
                    ".",
                    "14",
                    " ",
                    "today",
                    ".",
                ],
            ),
            (
                "Ask Dr. Smith today.",
                [
                    "Ask",
                    " ",
                    "Dr",
                    ".",
                    " ",
                    "Smith",
                    " ",
                    "today",
                    ".",
                ],
            ),
            (
                "Visit https://example.com. Next.",
                [
                    "Visit",
                    " ",
                    "https",
                    ":",
                    "/",
                    "/",
                    "example",
                    ".",
                    "com",
                    ".",
                    " ",
                    "Next",
                    ".",
                ],
            ),
        )
        for text, words in cases:
            with self.subTest(text=text):
                sentence = AlignmentSentence(
                    text,
                    0,
                    0,
                    1000,
                    text,
                    text,
                    _tokens(*words),
                )
                groups = partition_sentence_rule(
                    sentence,
                    config=SenseGroupPartitionConfig(
                        soft_max_words=20,
                        hard_max_words=20,
                    ),
                )
                expected_groups = 2 if text.startswith("Visit https://") else 1
                self.assertEqual(len(groups), expected_groups)

    def test_real_sentence_period_still_creates_a_boundary(self) -> None:
        text = "It ended. Completely new."
        words = [
            "It",
            " ",
            "ended",
            ".",
            " ",
            "Completely",
            " ",
            "new",
            ".",
        ]
        sentence = AlignmentSentence(
            "real-period",
            0,
            0,
            1000,
            text,
            text,
            _tokens(*words),
        )
        groups = partition_sentence_rule(
            sentence,
            config=SenseGroupPartitionConfig(soft_max_words=20, hard_max_words=20),
        )
        self.assertEqual(len(groups), 2)
        self.assertEqual(groups[0].sources, ("punctuation",))

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

    def test_layer3_llm_meaningful_chunk_standard_examples(self) -> None:
        """Verify LLM boundary mapping follows the working-memory meaningful chunk principles.

        Tests all standard examples from the sense group specification:
        1. "I was looking forward to seeing you again." -> ["I", "was looking forward to", "seeing you again"]
        2. "She takes care of her younger brother after school." -> ["She", "takes care of", "her younger brother", "after school"]
        3. "One of the most important things is learning how to listen." -> ["One of the most important things", "is", "learning how to listen"]
        4. "When I got home, I realized that I had left my phone at work." -> ["When I got home", "I realized", "that I had left my phone", "at work"]
        """
        analyzer = LlmSenseGroupAnalyzer(api_key="mock")

        # Example 1
        w1 = ["I", " ", "was", " ", "looking", " ", "forward", " ", "to", " ", "seeing", " ", "you", " ", "again", "."]
        t1 = _tokens(*w1)
        s1 = AlignmentSentence("s1", 0, 0, 1000, "".join(w1), "".join(w1), t1)
        groups1 = analyzer._spans_from_llm_boundaries(s1, [0, 8])
        self.assertIsNotNone(groups1)
        chunks1 = ["".join(t.text for t in t1[g.start_token_index:g.end_token_index_exclusive]) for g in groups1]
        self.assertEqual(chunks1, ["I ", "was looking forward to ", "seeing you again."])

        # Example 2
        w2 = ["She", " ", "takes", " ", "care", " ", "of", " ", "her", " ", "younger", " ", "brother", " ", "after", " ", "school", "."]
        t2 = _tokens(*w2)
        s2 = AlignmentSentence("s2", 0, 0, 1000, "".join(w2), "".join(w2), t2)
        groups2 = analyzer._spans_from_llm_boundaries(s2, [0, 6, 12])
        self.assertIsNotNone(groups2)
        chunks2 = ["".join(t.text for t in t2[g.start_token_index:g.end_token_index_exclusive]) for g in groups2]
        self.assertEqual(chunks2, ["She ", "takes care of ", "her younger brother ", "after school."])

        # Example 3: single-word predicate "is" preserved as a distinct meaningful chunk
        w3 = ["One", " ", "of", " ", "the", " ", "most", " ", "important", " ", "things", " ", "is", " ", "learning", " ", "how", " ", "to", " ", "listen", "."]
        t3 = _tokens(*w3)
        s3 = AlignmentSentence("s3", 0, 0, 1000, "".join(w3), "".join(w3), t3)
        groups3 = analyzer._spans_from_llm_boundaries(s3, [10, 12])
        self.assertIsNotNone(groups3)
        chunks3 = ["".join(t.text for t in t3[g.start_token_index:g.end_token_index_exclusive]) for g in groups3]
        self.assertEqual(chunks3, ["One of the most important things ", "is ", "learning how to listen."])

        # Example 4
        w4 = ["When", " ", "I", " ", "got", " ", "home", ",", " ", "I", " ", "realized", " ", "that", " ", "I", " ", "had", " ", "left", " ", "my", " ", "phone", " ", "at", " ", "work", "."]
        t4 = _tokens(*w4)
        s4 = AlignmentSentence("s4", 0, 0, 1000, "".join(w4), "".join(w4), t4)
        groups4 = analyzer._spans_from_llm_boundaries(s4, [7, 11, 23])
        self.assertIsNotNone(groups4)
        chunks4 = ["".join(t.text for t in t4[g.start_token_index:g.end_token_index_exclusive]) for g in groups4]
        self.assertEqual(chunks4, ["When I got home, ", "I realized ", "that I had left my phone ", "at work."])

        # Entire sentence as single chunk when empty boundaries returned
        groups_single = analyzer._spans_from_llm_boundaries(s1, [])
        self.assertIsNotNone(groups_single)
        self.assertEqual(len(groups_single), 1)
        self.assertEqual(groups_single[0].start_token_index, 0)
        self.assertEqual(groups_single[0].end_token_index_exclusive, len(t1))

    def test_layer3_llm_prompt_contract_and_user_prompt(self) -> None:
        """Verify LLM client invocation sends the working-memory prompt and indexed tokens."""
        analyzer = LlmSenseGroupAnalyzer(api_key="mock")
        w = ["I", " ", "was", " ", "looking", " ", "forward", " ", "to", " ", "seeing", " ", "you", " ", "again", "."]
        tokens = _tokens(*w)
        sentence = AlignmentSentence("s1", 0, 0, 1000, "".join(w), "".join(w), tokens)

        with mock.patch.object(analyzer.client, "call_structured_json", return_value={"boundary_after_token_indices": [0, 8]}) as mock_call:
            result = analyzer.analyze(SenseGroupRequest(language="en-US", sentences=(sentence,)))
            mock_call.assert_called_once()
            sys_prompt, user_prompt = mock_call.call_args[0][:2]
            self.assertEqual(sys_prompt, LLM_SENSE_GROUP_SYSTEM_PROMPT)
            self.assertIn("Original sentence:\nI was looking forward to seeing you again.", user_prompt)
            self.assertIn("Tokens (index:kind:text):", user_prompt)
            self.assertEqual(len(result.groups), 3)

        # Verify empty boundaries [] does not fall back to rule partition
        with mock.patch.object(analyzer.client, "call_structured_json", return_value={"boundary_after_token_indices": []}) as mock_call:
            result = analyzer.analyze(SenseGroupRequest(language="en-US", sentences=(sentence,)))
            self.assertEqual(len(result.groups), 1)
            self.assertEqual(result.groups[0].sources, ("language_model",))

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

    def test_no_credential_means_no_credential(self) -> None:
        """An unconfigured machine must not end up with a working API key.

        A hardcoded DeepSeek key used to sit at the end of the key-resolution
        chain. Besides shipping a live credential inside a published,
        hash-pinned artifact, it was never empty — so
        `PunctuationSenseGroupBaseline`'s auto-upgrade fired on every machine,
        and `--sense-groups baseline` silently became an LLM run against the
        author's account. That is also how a null `model.version` reached
        listen-core and got the whole package rejected.
        """
        import os
        from unittest import mock

        cleared = {
            key: ""
            for key in (
                "LISTEN_LLM_API_KEY",
                "LISTEN_LLM_PROFILE_PATH",
                "DEEPSEEK_API_KEY",
                "DASHSCOPE_API_KEY",
                "OPENAI_API_KEY",
                "ANTHROPIC_API_KEY",
                "GEMINI_API_KEY",
            )
        }
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as directory, mock.patch(
            # Never let the developer's own configured store decide this.
            "listen_gen.llm_client.DEFAULT_PROFILE_STORE",
            Path(directory) / "absent.json",
        ), mock.patch.dict(os.environ, cleared, clear=False):
            for key in cleared:
                os.environ.pop(key, None)
            self.assertFalse(auto_detect_profile().api_key)
            # And therefore the baseline stays the baseline.
            self.assertIsNone(PunctuationSenseGroupBaseline().llm_analyzer)

    def test_an_explicit_key_still_enables_the_llm_path(self) -> None:
        """The other half of the rule: configured means enabled, by default.

        Removing the hardcoded key must not remove the opt-in — a machine that
        supplies a credential still gets LLM sense groups without passing
        `--sense-groups llm`.
        """
        import os
        from unittest import mock

        with mock.patch.dict(os.environ, {"LISTEN_LLM_API_KEY": "sk-configured"}):
            self.assertEqual(auto_detect_profile().api_key, "sk-configured")
            self.assertIsNotNone(PunctuationSenseGroupBaseline().llm_analyzer)

    def test_the_local_store_supplies_the_credential(self) -> None:
        """One configuration, whichever entry point drives the run.

        The bundled GUI writes `~/.listen-gen/profiles.json`; `auto_detect_profile`
        used to look only at explicit arguments and the environment. A provider
        configured in the GUI therefore did nothing for a CLI-driven capability
        run — and an embedding app launched from Finder, which inherits no shell
        environment, could never supply a credential at all.
        """
        import json
        import os
        import tempfile
        from pathlib import Path
        from unittest import mock

        from listen_gen.llm_client import profile_from_store

        cleared = {
            key: ""
            for key in (
                "LISTEN_LLM_API_KEY",
                "LISTEN_LLM_PROFILE_PATH",
                "DEEPSEEK_API_KEY",
                "DASHSCOPE_API_KEY",
                "OPENAI_API_KEY",
                "ANTHROPIC_API_KEY",
                "GEMINI_API_KEY",
            )
        }
        with tempfile.TemporaryDirectory() as directory:
            store = Path(directory) / "profiles.json"
            store.write_text(
                json.dumps(
                    {
                        "version": 1,
                        "selected_llm": "deepseek",
                        "llm_profiles": {
                            "deepseek": {
                                "adapter_kind": "openai_chat",
                                "base_url": "https://api.deepseek.com/v1",
                                "model_id": "deepseek-v4-flash",
                                "api_key": "sk-from-store",
                            }
                        },
                    }
                ),
                encoding="utf-8",
            )
            stored = profile_from_store(store)
            self.assertIsNotNone(stored)
            self.assertEqual(stored.api_key, "sk-from-store")
            self.assertEqual(stored.model_id, "deepseek-v4-flash")

            with mock.patch(
                "listen_gen.llm_client.DEFAULT_PROFILE_STORE", store
            ), mock.patch.dict(os.environ, cleared, clear=False):
                for key in cleared:
                    os.environ.pop(key, None)
                self.assertEqual(auto_detect_profile().api_key, "sk-from-store")
                # And therefore the default sense-group path upgrades to LLM.
                self.assertIsNotNone(PunctuationSenseGroupBaseline().llm_analyzer)

    def test_a_store_without_a_credential_is_not_a_provider(self) -> None:
        """A configured shape is not a usable provider.

        The GUI seeds empty `api_key` entries for every known vendor, so
        treating "an entry exists" as "a provider is configured" would put
        every machine back on the LLM path with no way to authenticate.
        """
        import json
        import tempfile
        from pathlib import Path

        from listen_gen.llm_client import profile_from_store

        with tempfile.TemporaryDirectory() as directory:
            store = Path(directory) / "profiles.json"
            store.write_text(
                json.dumps(
                    {
                        "selected_llm": "deepseek",
                        "llm_profiles": {"deepseek": {"model_id": "deepseek-chat", "api_key": ""}},
                    }
                ),
                encoding="utf-8",
            )
            self.assertIsNone(profile_from_store(store))

    def test_an_unreadable_store_is_simply_no_provider(self) -> None:
        import tempfile
        from pathlib import Path

        from listen_gen.llm_client import profile_from_store

        with tempfile.TemporaryDirectory() as directory:
            missing = Path(directory) / "absent.json"
            self.assertIsNone(profile_from_store(missing))
            malformed = Path(directory) / "malformed.json"
            malformed.write_text("{not json", encoding="utf-8")
            self.assertIsNone(profile_from_store(malformed))

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
