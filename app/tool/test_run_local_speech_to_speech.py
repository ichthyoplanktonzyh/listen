#!/usr/bin/env python3
"""Unit tests for tool/run_local_speech_to_speech.py.

Run with the repository gate:

    python3 -m unittest discover -s tool -p 'test_*.py'
"""

import json
import unittest
from unittest import mock

import run_local_speech_to_speech as launcher


class BuildCommandTests(unittest.TestCase):
    def test_defaults_stay_on_loopback_with_the_mac_preset(self):
        command = launcher.build_command(executable="/bin/true")
        self.assertEqual(
            command,
            [
                "/bin/true",
                "--mode",
                "realtime",
                "--host",
                "127.0.0.1",
                "--port",
                "8765",
                "--mac-optimal-settings",
                "--stt",
                launcher.DEFAULT_STT,
                "--llm_backend",
                launcher.DEFAULT_LLM_BACKEND,
                "--tts",
                launcher.DEFAULT_TTS,
                "--model_name",
                launcher.DEFAULT_LLM_MODEL,
            ],
        )

    def test_explicit_overrides_replace_defaults(self):
        command = launcher.build_command(
            executable="/bin/true",
            host="localhost",
            port=9000,
            stt="paraformer",
            llm_backend="transformers",
            model="Qwen/Qwen3-4B-Instruct-2507",
            tts="qwen3",
            speaker="Vivian",
            language="chinese",
            instruct="speak calmly",
            mac_optimal=False,
        )
        self.assertIn("--mode", command)
        self.assertEqual(command[command.index("--host") + 1], "localhost")
        self.assertEqual(command[command.index("--port") + 1], "9000")
        self.assertEqual(command[command.index("--stt") + 1], "paraformer")
        self.assertEqual(
            command[command.index("--llm_backend") + 1], "transformers"
        )
        self.assertEqual(
            command[command.index("--model_name") + 1],
            "Qwen/Qwen3-4B-Instruct-2507",
        )
        self.assertEqual(command[command.index("--qwen3_tts_speaker") + 1], "Vivian")
        self.assertEqual(
            command[command.index("--qwen3_tts_language") + 1], "chinese"
        )
        self.assertEqual(
            command[command.index("--qwen3_tts_instruct") + 1], "speak calmly"
        )
        self.assertNotIn("--mac-optimal-settings", command)

    def test_non_loopback_host_is_refused(self):
        with self.assertRaises(ValueError):
            launcher.build_command(executable="/bin/true", host="0.0.0.0")
        with self.assertRaises(ValueError):
            launcher.build_command(executable="/bin/true", host="example.com")

    def test_cascade_never_emits_the_legacy_local_mac_flag(self):
        command = launcher.build_command(executable="/bin/true")
        self.assertNotIn("--local_mac_optimal_settings", command)
        self.assertIn("--mac-optimal-settings", command)


class InstallCommandTests(unittest.TestCase):
    def test_default_install_targets_the_venv_from_git_head(self):
        command = launcher.install_command()
        self.assertIn("local-speech-venv", command[0])
        self.assertEqual(command[-1], f"{launcher.PACKAGE} @ git+{launcher.PINNED_REPO}")

    def test_venv_prefers_a_supported_interpreter_over_the_running_one(self):
        with mock.patch.object(
            launcher.shutil,
            "which",
            side_effect=lambda name: {
                "python3.12": "python3.12",
                "python3.11": "python3.11",
            }.get(name),
        ):
            self.assertEqual(launcher._venv_python(), "python3.12")
        with mock.patch.object(launcher.shutil, "which", return_value=None):
            self.assertEqual(launcher._venv_python(), launcher.sys.executable)


    def test_pinned_revision_is_appended_as_an_at_pin(self):
        command = launcher.install_command(revision="cc37fe84")
        self.assertTrue(command[-1].endswith("@cc37fe84"))


class ManagedModeTests(unittest.TestCase):
    def test_managed_args_never_own_mode_host_or_port(self):
        args = launcher.managed_args()
        self.assertNotIn("--mode", args)
        self.assertNotIn("--host", args)
        self.assertNotIn("--port", args)
        self.assertNotIn("--ws_host", args)
        self.assertNotIn("--ws_port", args)
        self.assertEqual(args[args.index("--stt") + 1], launcher.DEFAULT_STT)

    def test_managed_environment_names_core_vars_and_json_args(self):
        with mock.patch.object(
            launcher, "resolve_executable", return_value="/opt/bin/speech-to-speech"
        ):
            env = launcher.managed_environment()
        self.assertEqual(
            env["LLPLAYERNEXT_LOCAL_REALTIME_EXECUTABLE"],
            "/opt/bin/speech-to-speech",
        )
        args = json.loads(env["LLPLAYERNEXT_LOCAL_REALTIME_ARGS_JSON"])
        self.assertEqual(args[args.index("--model_name") + 1], launcher.DEFAULT_LLM_MODEL)

    def test_managed_launch_command_prefixes_env_and_keeps_app_last(self):
        command = launcher.managed_launch_command(
            "/Applications/Listen.app/Contents/MacOS/listen",
            {"LLPLAYERNEXT_LOCAL_REALTIME_EXECUTABLE": "/opt/bin/s2s"},
        )
        self.assertEqual(command[0], "env")
        self.assertIn(
            "LLPLAYERNEXT_LOCAL_REALTIME_EXECUTABLE=/opt/bin/s2s", command
        )
        self.assertEqual(command[-1].endswith("listen"), True)


class LocalModelsTests(unittest.TestCase):
    def test_resolve_local_model_paths_detects_layout_subdirectories(self):
        with mock.patch("pathlib.Path.is_dir", autospec=True) as mock_is_dir:
            mock_is_dir.side_effect = lambda self: str(self).endswith(
                ("/models", "/models/stt/parakeet", "/models/llm/qwen3-4b", "/models/tts/qwen3-6bit")
            )
            paths = launcher.resolve_local_model_paths("/models")
            self.assertEqual(paths.get("stt_parakeet"), "/models/stt/parakeet")
            self.assertEqual(paths.get("llm_qwen3"), "/models/llm/qwen3-4b")
            self.assertEqual(paths.get("tts_qwen3"), "/models/tts/qwen3-6bit")

    def test_build_command_injects_local_model_flags(self):
        with mock.patch.object(
            launcher,
            "resolve_local_model_paths",
            return_value={
                "stt_parakeet": "/custom/stt",
                "llm_qwen3": "/custom/llm",
                "tts_qwen3": "/custom/tts",
            },
        ):
            command = launcher.build_command(
                executable="/bin/true",
                models_dir="/custom",
            )
            self.assertIn("--parakeet_tdt_model_name", command)
            self.assertEqual(command[command.index("--parakeet_tdt_model_name") + 1], "/custom/stt")
            self.assertEqual(command[command.index("--model_name") + 1], "/custom/llm")
            self.assertIn("--qwen3_tts_model_name", command)
            self.assertEqual(command[command.index("--qwen3_tts_model_name") + 1], "/custom/tts")

    def test_managed_args_injects_local_model_flags(self):
        with mock.patch.object(
            launcher,
            "resolve_local_model_paths",
            return_value={
                "stt_parakeet": "/custom/stt",
                "llm_qwen3": "/custom/llm",
                "tts_qwen3": "/custom/tts",
            },
        ):
            args = launcher.managed_args(models_dir="/custom")
            self.assertIn("--parakeet_tdt_model_name", args)
            self.assertEqual(args[args.index("--parakeet_tdt_model_name") + 1], "/custom/stt")
            self.assertEqual(args[args.index("--model_name") + 1], "/custom/llm")
            self.assertIn("--qwen3_tts_model_name", args)
            self.assertEqual(args[args.index("--qwen3_tts_model_name") + 1], "/custom/tts")


class ResolveExecutableTests(unittest.TestCase):
    def test_missing_executable_raises_with_install_hint(self):
        with mock.patch.object(
            launcher, "venv_executable", return_value=launcher.VENV_DIR / "missing"
        ):
            with mock.patch.object(launcher.shutil, "which", return_value=None):
                with self.assertRaises(FileNotFoundError) as context:
                    launcher.resolve_executable()
        self.assertIn("--install", str(context.exception))


if __name__ == "__main__":
    unittest.main()