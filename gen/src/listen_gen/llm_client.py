from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass, field, replace
from enum import Enum
from pathlib import Path
from typing import Any


class LlmAdapterKind(str, Enum):
    OPENAI_CHAT = "openai_chat"
    ANTHROPIC_MESSAGES = "anthropic_messages"
    GEMINI = "gemini"


@dataclass(frozen=True)
class LlmProviderProfile:
    """Provider-agnostic LLM configuration matching listen-core LlmProviderProfile."""

    adapter_kind: LlmAdapterKind = LlmAdapterKind.OPENAI_CHAT
    base_url: str = "https://api.openai.com/v1"
    model_id: str = "gpt-4o-mini"
    api_key: str | None = None
    timeout_seconds: float = 30.0
    extra_headers: dict[str, str] = field(default_factory=dict)
    protocol_version: str | None = None  # e.g. "2023-06-01" for Anthropic

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> LlmProviderProfile:
        adapter_raw = data.get("adapter_kind") or data.get("adapter") or "openai_chat"
        try:
            adapter_kind = LlmAdapterKind(adapter_raw)
        except ValueError:
            adapter_kind = LlmAdapterKind.OPENAI_CHAT

        return cls(
            adapter_kind=adapter_kind,
            base_url=str(data.get("base_url") or "https://api.openai.com/v1").rstrip("/"),
            model_id=str(data.get("model_id") or data.get("model") or "gpt-4o-mini"),
            api_key=data.get("api_key") or data.get("secret"),
            timeout_seconds=float(data.get("timeout_seconds") or (data.get("timeout_ms", 30000) / 1000.0)),
            extra_headers=dict(data.get("extra_headers") or {}),
            protocol_version=data.get("protocol_version"),
        )

    @classmethod
    def from_file(cls, path: Path | str) -> LlmProviderProfile:
        content = Path(path).read_text(encoding="utf-8")
        return cls.from_dict(json.loads(content))


#: Where this tool keeps its own provider configuration. The bundled web GUI
#: writes it; every entry point reads it, so configuring a provider once is
#: enough no matter which one drives the run.
DEFAULT_PROFILE_STORE = Path.home() / ".listen-gen" / "profiles.json"


def profile_from_store(
    path: Path | str | None = None,
) -> LlmProviderProfile | None:
    """The selected provider from the local store, or None.

    The GUI and the CLI used to reach credentials by different routes: the GUI
    read this file, while the CLI saw only environment variables and explicit
    flags. A caller that had configured a provider in the GUI still got no LLM
    when the same machine ran a capability from the command line — which is
    exactly how an embedding app, launched from Finder with no shell
    environment, ends up with no provider at all.

    Any malformed or unreadable store is simply "no provider configured".
    Credentials are never logged or raised from here.
    """
    store = Path(path) if path is not None else DEFAULT_PROFILE_STORE
    try:
        data = json.loads(store.read_text(encoding="utf-8"))
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    profiles = data.get("llm_profiles")
    if not isinstance(profiles, dict) or not profiles:
        return None
    selected = data.get("selected_llm")
    entry = profiles.get(selected) if isinstance(selected, str) else None
    if not isinstance(entry, dict):
        # A store naming no usable selection is not a store to guess through.
        return None
    profile = LlmProviderProfile.from_dict(entry)
    # An entry without a credential is a configured *shape*, not a usable
    # provider; saying so here keeps the auto-upgrade honest.
    return profile if profile.api_key else None


def auto_detect_profile(
    *,
    adapter_kind: str | None = None,
    base_url: str | None = None,
    api_key: str | None = None,
    model_id: str | None = None,
    profile_path: Path | str | None = None,
    timeout_seconds: float = 30.0,
) -> LlmProviderProfile:
    """Builds a provider-agnostic profile from explicit args, profile files, or environment."""
    if profile_path and Path(profile_path).is_file():
        return LlmProviderProfile.from_file(profile_path)

    env_profile_path = os.environ.get("LISTEN_LLM_PROFILE_PATH")
    if env_profile_path and Path(env_profile_path).is_file():
        return LlmProviderProfile.from_file(env_profile_path)

    # Explicit arguments and the environment win; the local store is what
    # answers when neither is present, so a provider configured once in the
    # GUI also serves runs driven by the CLI.
    if not any((api_key, adapter_kind, base_url, model_id)) and not any(
        os.environ.get(name)
        for name in (
            "LISTEN_LLM_API_KEY",
            "DEEPSEEK_API_KEY",
            "DASHSCOPE_API_KEY",
            "OPENAI_API_KEY",
            "ANTHROPIC_API_KEY",
            "GEMINI_API_KEY",
        )
    ):
        stored = profile_from_store()
        if stored is not None:
            return replace(stored, timeout_seconds=timeout_seconds)

    # Resolve API Key
    resolved_key = (
        api_key
        or os.environ.get("LISTEN_LLM_API_KEY")
        or os.environ.get("DEEPSEEK_API_KEY")
        or os.environ.get("DASHSCOPE_API_KEY")
        or os.environ.get("OPENAI_API_KEY")
        or os.environ.get("ANTHROPIC_API_KEY")
        or os.environ.get("GEMINI_API_KEY")
    )
    # No hardcoded fallback key. One used to live here, and it did more than
    # leak a credential in a published artifact: because it was never empty,
    # `PunctuationSenseGroupBaseline` auto-upgraded to the LLM path on every
    # machine, including ones that had configured no provider at all. Callers
    # who want LLM sense groups supply a key; callers who do not get the
    # deterministic rule partitioning they asked for.

    # Resolve Adapter Kind
    resolved_adapter = adapter_kind or os.environ.get("LISTEN_LLM_ADAPTER") or os.environ.get("LISTEN_LLM_ADAPTER_KIND")

    # Resolve Base URL and Model
    resolved_base_url = (
        base_url
        or os.environ.get("LISTEN_LLM_BASE_URL")
    )
    resolved_model = (
        model_id
        or os.environ.get("LISTEN_LLM_MODEL")
    )

    # Provider-specific env fallbacks
    if not resolved_adapter:
        if os.environ.get("ANTHROPIC_API_KEY") and not resolved_key:
            resolved_adapter = "anthropic_messages"
            resolved_key = os.environ.get("ANTHROPIC_API_KEY")
            resolved_base_url = resolved_base_url or os.environ.get("ANTHROPIC_BASE_URL", "https://api.anthropic.com")
            resolved_model = resolved_model or os.environ.get("ANTHROPIC_MODEL", "claude-3-5-sonnet-20241022")
        elif os.environ.get("GEMINI_API_KEY") and not resolved_key:
            resolved_adapter = "gemini"
            resolved_key = os.environ.get("GEMINI_API_KEY")
            resolved_base_url = resolved_base_url or os.environ.get("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com/v1beta")
            resolved_model = resolved_model or os.environ.get("GEMINI_MODEL", "gemini-1.5-flash")
        elif os.environ.get("DEEPSEEK_API_KEY") and not resolved_key:
            resolved_adapter = "openai_chat"
            resolved_key = os.environ.get("DEEPSEEK_API_KEY")
            resolved_base_url = resolved_base_url or os.environ.get("DEEPSEEK_BASE_URL", "https://api.deepseek.com/v1")
            resolved_model = resolved_model or os.environ.get("DEEPSEEK_MODEL", "deepseek-chat")
        elif os.environ.get("DASHSCOPE_API_KEY") and not resolved_key:
            resolved_adapter = "openai_chat"
            resolved_key = os.environ.get("DASHSCOPE_API_KEY")
            resolved_base_url = resolved_base_url or os.environ.get("DASHSCOPE_BASE_URL", "https://dashscope.aliyuncs.com/compatible-mode/v1")
            resolved_model = resolved_model or os.environ.get("DASHSCOPE_MODEL", "qwen-plus")
        elif resolved_base_url and "anthropic" in resolved_base_url:
            resolved_adapter = "anthropic_messages"
        elif resolved_base_url and "googleapis.com" in resolved_base_url:
            resolved_adapter = "gemini"
        elif resolved_model and ("claude" in resolved_model.lower()):
            resolved_adapter = "anthropic_messages"
        elif resolved_model and ("gemini" in resolved_model.lower()):
            resolved_adapter = "gemini"
        else:
            resolved_adapter = "openai_chat"

    # Default URLs and Models per adapter if still unspecified
    if resolved_adapter == "anthropic_messages":
        resolved_base_url = resolved_base_url or os.environ.get("ANTHROPIC_BASE_URL") or "https://api.anthropic.com"
        resolved_model = resolved_model or os.environ.get("ANTHROPIC_MODEL") or "claude-3-5-sonnet-20241022"
    elif resolved_adapter == "gemini":
        resolved_base_url = resolved_base_url or os.environ.get("GEMINI_BASE_URL") or "https://generativelanguage.googleapis.com/v1beta"
        resolved_model = resolved_model or os.environ.get("GEMINI_MODEL") or "gemini-1.5-flash"
    else:
        resolved_adapter = "openai_chat"
        resolved_base_url = (
            resolved_base_url
            or os.environ.get("DEEPSEEK_BASE_URL")
            or os.environ.get("OPENAI_BASE_URL")
            or "https://api.deepseek.com/v1"
        )
        resolved_model = (
            resolved_model
            or os.environ.get("DEEPSEEK_MODEL")
            or os.environ.get("OPENAI_MODEL")
            or "deepseek-chat"
        )

    try:
        kind = LlmAdapterKind(resolved_adapter)
    except ValueError:
        kind = LlmAdapterKind.OPENAI_CHAT

    return LlmProviderProfile(
        adapter_kind=kind,
        base_url=resolved_base_url.rstrip("/"),
        model_id=resolved_model,
        api_key=resolved_key,
        timeout_seconds=timeout_seconds,
    )


class BaseLlmClient:
    """Abstract wire client for structured JSON chat completions."""

    #: The model string the endpoint reported on its most recent successful
    #: reply. A profile names the model we *asked* for ("deepseek-chat"); the
    #: response names the one that actually answered, which is often more
    #: specific and is the only version identity provenance can honestly
    #: declare. Stays None until a call succeeds.
    observed_model: str | None = None

    def call_structured_json(
        self,
        system_prompt: str,
        user_prompt: str,
        *,
        timeout_seconds: float | None = None,
    ) -> dict[str, Any] | None:
        raise NotImplementedError


class OpenAiChatClient(BaseLlmClient):
    """Client for OpenAI Chat Completions and any OpenAI-compatible API (DeepSeek, Qwen, Ollama, etc.)."""

    def __init__(self, profile: LlmProviderProfile) -> None:
        self.profile = profile
        self.endpoint = (
            self.profile.base_url
            if self.profile.base_url.endswith("/chat/completions")
            else f"{self.profile.base_url}/chat/completions"
        )

    def call_structured_json(
        self,
        system_prompt: str,
        user_prompt: str,
        *,
        timeout_seconds: float | None = None,
    ) -> dict[str, Any] | None:
        payload = {
            "model": self.profile.model_id,
            "messages": [
                {"role": "system", "content": system_prompt},
                {"role": "user", "content": user_prompt},
            ],
            "response_format": {"type": "json_object"},
            "temperature": 0.0,
            "max_tokens": 1024,
        }
        headers = {
            "Content-Type": "application/json",
            **self.profile.extra_headers,
        }
        if self.profile.api_key:
            headers["Authorization"] = f"Bearer {self.profile.api_key}"

        try:
            req = urllib.request.Request(
                self.endpoint,
                data=json.dumps(payload).encode("utf-8"),
                headers=headers,
                method="POST",
            )
            timeout = timeout_seconds or self.profile.timeout_seconds
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                result_json = json.loads(resp.read().decode("utf-8"))

            reported = result_json.get("model")
            if isinstance(reported, str) and reported:
                self.observed_model = reported
            content = result_json["choices"][0]["message"]["content"]
            if isinstance(content, dict):
                return content
            return json.loads(content)
        except Exception:
            return None


class AnthropicMessagesClient(BaseLlmClient):
    """Client for Anthropic Messages API (Claude 3/3.5)."""

    def __init__(self, profile: LlmProviderProfile) -> None:
        self.profile = profile
        self.endpoint = (
            self.profile.base_url
            if self.profile.base_url.endswith("/v1/messages") or self.profile.base_url.endswith("/messages")
            else f"{self.profile.base_url}/v1/messages"
        )
        self.anthropic_version = self.profile.protocol_version or "2023-06-01"

    def call_structured_json(
        self,
        system_prompt: str,
        user_prompt: str,
        *,
        timeout_seconds: float | None = None,
    ) -> dict[str, Any] | None:
        payload = {
            "model": self.profile.model_id,
            "system": f"{system_prompt}\nYou MUST output valid JSON only. Do NOT output any markdown backticks or explanation.",
            "messages": [
                {"role": "user", "content": user_prompt},
            ],
            "max_tokens": 1024,
            "temperature": 0.0,
        }
        headers = {
            "Content-Type": "application/json",
            "anthropic-version": self.anthropic_version,
            **self.profile.extra_headers,
        }
        if self.profile.api_key:
            headers["x-api-key"] = self.profile.api_key

        try:
            req = urllib.request.Request(
                self.endpoint,
                data=json.dumps(payload).encode("utf-8"),
                headers=headers,
                method="POST",
            )
            timeout = timeout_seconds or self.profile.timeout_seconds
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                result_json = json.loads(resp.read().decode("utf-8"))

            # Content can be text block
            reported = result_json.get("model")
            if isinstance(reported, str) and reported:
                self.observed_model = reported
            content_blocks = result_json.get("content", [])
            for block in content_blocks:
                if block.get("type") == "text":
                    raw_text = block.get("text", "").strip()
                    # Strip any markdown fences if model returned them
                    if raw_text.startswith("```json"):
                        raw_text = raw_text[7:]
                    elif raw_text.startswith("```"):
                        raw_text = raw_text[3:]
                    if raw_text.endswith("```"):
                        raw_text = raw_text[:-3]
                    return json.loads(raw_text.strip())
            return None
        except Exception:
            return None


class GeminiClient(BaseLlmClient):
    """Client for Google Gemini REST API."""

    def __init__(self, profile: LlmProviderProfile) -> None:
        self.profile = profile

    def call_structured_json(
        self,
        system_prompt: str,
        user_prompt: str,
        *,
        timeout_seconds: float | None = None,
    ) -> dict[str, Any] | None:
        endpoint = f"{self.profile.base_url}/models/{self.profile.model_id}:generateContent"
        if self.profile.api_key:
            endpoint += f"?key={self.profile.api_key}"

        payload = {
            "system_instruction": {"parts": [{"text": system_prompt}]},
            "contents": [{"role": "user", "parts": [{"text": user_prompt}]}],
            "generationConfig": {
                "response_mime_type": "application/json",
                "temperature": 0.0,
            },
        }
        headers = {
            "Content-Type": "application/json",
            **self.profile.extra_headers,
        }

        try:
            req = urllib.request.Request(
                endpoint,
                data=json.dumps(payload).encode("utf-8"),
                headers=headers,
                method="POST",
            )
            timeout = timeout_seconds or self.profile.timeout_seconds
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                result_json = json.loads(resp.read().decode("utf-8"))

            reported = result_json.get("modelVersion")
            if isinstance(reported, str) and reported:
                self.observed_model = reported
            candidates = result_json.get("candidates", [])
            if not candidates:
                return None
            parts = candidates[0].get("content", {}).get("parts", [])
            if not parts:
                return None
            text = parts[0].get("text", "")
            return json.loads(text.strip())
        except Exception:
            return None


def create_llm_client(profile: LlmProviderProfile) -> BaseLlmClient:
    """Factory creating provider-specific client conforming to BaseLlmClient."""
    if profile.adapter_kind == LlmAdapterKind.ANTHROPIC_MESSAGES:
        return AnthropicMessagesClient(profile)
    elif profile.adapter_kind == LlmAdapterKind.GEMINI:
        return GeminiClient(profile)
    else:
        return OpenAiChatClient(profile)
