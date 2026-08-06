from __future__ import annotations

import hashlib
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
TERMINAL_EVENTS = {"completed", "failed", "cancelled"}

from listen_gen.cli import main


def _env(**overrides: str) -> dict[str, str]:
    env = dict(os.environ)
    env["PYTHONPATH"] = str(ROOT / "src")
    env.update(overrides)
    return env


def run_cli(
    argv: list[str],
    env: dict[str, str] | None = None,
    timeout: float = 60,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-m", "listen_gen", *argv],
        capture_output=True,
        text=True,
        env=_env() if env is None else env,
        timeout=timeout,
    )


def parse_events(stdout: str) -> list[dict[str, object]]:
    return [json.loads(line) for line in stdout.splitlines() if line]


class WhisperCppProviderTests(unittest.TestCase):
    media = ROOT / "tests" / "fixtures" / "single-audio-media.json"
    fixture_media = ROOT / "tests" / "fixtures" / "sample-media.wav"
    fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
    ffprobe = ROOT / "tests" / "fixtures" / "fake_ffprobe.py"
    ffmpeg = ROOT / "tests" / "fixtures" / "fake_ffmpeg.py"
    helper = ROOT / "tests" / "fixtures" / "fake_whisper_cli.py"

    def base_argv(
        self,
        output: Path,
        *,
        model: Path,
        whisper_cli: Path | None = None,
        model_id: str = "whisper.cpp:base@main",
        language: str = "auto",
        translate: bool = False,
        timeout: str = "30",
        machine: bool = False,
    ) -> list[str]:
        argv = [
            "package", "from-media", str(self.media),
            "--output", str(output),
            "--provider", "whisper-cpp",
            "--whisper-cli", str(whisper_cli or self.helper),
            "--whisper-model", str(model),
            "--whisper-model-id", model_id,
            "--whisper-language", language,
            "--whisper-timeout-seconds", timeout,
            "--ffprobe-command", str(self.ffprobe),
            "--ffmpeg-command", str(self.ffmpeg),
            "--title", "Whisper lesson", "--media-kind", "video",
            "--duration-ms", "2200", "--created-at-ms", "1786000000000",
        ]
        if translate:
            argv.append("--whisper-translate-to-english")
        if machine:
            argv.append("--machine-events")
        return argv

    def whisper_env(
        self,
        *,
        mode: str = "success",
        observed: Path | None = None,
        language: str | None = None,
    ) -> dict[str, str]:
        value = _env()
        value["LISTEN_GEN_FAKE_WHISPER_MODE"] = mode
        if observed is not None:
            value["LISTEN_GEN_FAKE_WHISPER_OBSERVED"] = str(observed)
        if language is not None:
            value["LISTEN_GEN_FAKE_WHISPER_LANGUAGE"] = language
        return value

    def write_model(self, directory: Path, name: str = "ggml-base.bin") -> Path:
        model = directory / name
        model.write_bytes(b"dummy-model-bytes")
        return model

    def assert_terminal(
        self, events: list[dict[str, object]]
    ) -> dict[str, object]:
        terminals = [
            event for event in events if event["event"] in TERMINAL_EVENTS
        ]
        self.assertEqual(len(terminals), 1)
        return terminals[0]

    def assert_pid_dead(self, pid: int) -> None:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
            except PermissionError:
                pass
            time.sleep(0.05)
        self.fail(f"process {pid} is still alive")

    def read_subtitle(self, output: Path) -> dict[str, object]:
        with zipfile.ZipFile(output) as archive:
            return json.loads(
                archive.read("resources/subtitle-text-track.json")
            )

    def test_ordinary_success_builds_subtitle_only_package(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            output = root / "lesson.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model),
                env=self.whisper_env(observed=root / "observed.json"),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(result["status"], "created")
            self.assertEqual(result["resource_count"], 1)
            self.assertTrue(output.is_file())
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(
                    archive.namelist(),
                    ["manifest.json", "resources/subtitle-text-track.json"],
                )
                manifest = json.loads(archive.read("manifest.json"))
                self.assertEqual(
                    [entry["kind"] for entry in manifest["resources"]],
                    ["subtitle_text_track"],
                )
                self.assertEqual(
                    [entry["required"] for entry in manifest["resources"]],
                    [True],
                )
            subtitle = self.read_subtitle(output)
            sentences = subtitle["payload"]["sentences"]
            self.assertEqual(len(sentences), 2)
            self.assertEqual(sentences[0]["start_ms"], 120)
            self.assertEqual(sentences[0]["end_ms"], 840)
            self.assertEqual(sentences[0]["original_text"], "Example text")
            self.assertEqual(sentences[0]["display_text"], "Example text")
            self.assertEqual(sentences[1]["start_ms"], 900)
            self.assertEqual(sentences[1]["end_ms"], 2100)
            self.assertEqual(sentences[1]["original_text"], "Second line.")

    def test_machine_success_phases_and_digests(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            output = root / "lesson.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model, machine=True),
                env=self.whisper_env(),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            self.assertEqual(
                [event["event"] for event in events],
                [
                    "protocol", "started",
                    "phase", "phase", "phase", "phase", "phase",
                    "completed",
                ],
            )
            self.assertEqual(
                [event["phase"] for event in events if event["event"] == "phase"],
                [
                    "validating",
                    "probing_media",
                    "normalizing_audio",
                    "transcribing",
                    "building_package",
                ],
            )
            self.assertEqual(
                [event["sequence"] for event in events],
                list(range(len(events))),
            )
            final = self.assert_terminal(events)
            self.assertEqual(final["event"], "completed")
            self.assertEqual(
                final["package_sha256"],
                f"sha256:{hashlib.sha256(output.read_bytes()).hexdigest()}",
            )
            self.assertEqual(
                final["media_fingerprint"],
                f"sha256:{hashlib.sha256(self.media.read_bytes()).hexdigest()}",
            )
            self.assertEqual(
                [entry["kind"] for entry in final["resources"]],
                ["subtitle_text_track"],
            )

    def test_provider_language_flows_into_subtitle_payload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            output = root / "lesson.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model, language="auto"),
                env=self.whisper_env(language="fr"),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            subtitle = self.read_subtitle(output)
            self.assertEqual(subtitle["payload"]["language"], "fr")

    def test_translation_pins_english_and_changes_config_identity(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            observed_plain = root / "observed-plain.json"
            observed_translated = root / "observed-translated.json"

            def run_once(translate: bool, observed: Path) -> Path:
                output = root / f"lesson-{translate}.listenpkg"
                completed = run_cli(
                    self.base_argv(output, model=model, translate=translate),
                    env=self.whisper_env(
                        mode="success",
                        observed=observed,
                        language="fr",
                    ),
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                return output

            plain_output = run_once(False, observed_plain)
            translated_output = run_once(True, observed_translated)
            subtitle = self.read_subtitle(translated_output)
            self.assertEqual(subtitle["payload"]["language"], "en")
            observation = json.loads(
                observed_translated.read_text(encoding="utf-8")
            )
            self.assertTrue(observation["translate"])
            self.assertEqual(observation["argv"][-1], "-tr")
            plain_config = self.read_subtitle(
                plain_output
            )["provenance"]["config_sha256"]
            translated_config = subtitle["provenance"]["config_sha256"]
            self.assertNotEqual(plain_config, translated_config)
            self.assertRegex(plain_config, r"^sha256:[0-9a-f]{64}$")
            self.assertRegex(translated_config, r"^sha256:[0-9a-f]{64}$")

    def test_exact_argv_to_whisper_cli(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            observed = root / "observed.json"
            output = root / "lesson.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model, language="en"),
                env=self.whisper_env(observed=observed),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            observation = json.loads(observed.read_text(encoding="utf-8"))
            self.assertEqual(
                observation["argv"],
                [
                    "-m", str(model),
                    "-f", observation["media_path"],
                    "-oj",
                    "-of", observation["output_prefix"],
                    "-l", "en",
                ],
            )
            self.assertNotIn("-ojf", observation["argv"])
            self.assertNotIn("-dtw", observation["argv"])
            self.assertNotIn("-osrt", observation["argv"])
            normalized = Path(observation["media_path"])
            whisper_prefix = Path(observation["output_prefix"])
            self.assertEqual(normalized.name, "normalized.wav")
            self.assertFalse(normalized.exists())
            self.assertFalse(normalized.parent.exists())
            self.assertFalse(whisper_prefix.parent.exists())

    def test_provenance_binds_runtime_and_model_bytes_without_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            output = root / "lesson.listenpkg"
            model_id = "whisper.cpp:base@main"
            completed = run_cli(
                self.base_argv(output, model=model, model_id=model_id),
                env=self.whisper_env(),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            subtitle = self.read_subtitle(output)
            provenance = subtitle["provenance"]
            self.assertEqual(provenance["provider"]["id"], "whisper.cpp")
            self.assertEqual(
                provenance["provider"]["version"],
                f"sha256:{hashlib.sha256(self.helper.read_bytes()).hexdigest()}",
            )
            self.assertEqual(provenance["model"]["id"], model_id)
            self.assertEqual(
                provenance["model"]["version"],
                f"sha256:{hashlib.sha256(model.read_bytes()).hexdigest()}",
            )
            self.assertRegex(
                provenance["config_sha256"], r"^sha256:[0-9a-f]{64}$"
            )
            package_bytes = output.read_bytes()
            for forbidden in (
                str(self.helper),
                str(model),
                str(self.media),
                str(self.ffprobe),
                str(self.ffmpeg),
            ):
                self.assertNotIn(forbidden.encode(), package_bytes)
            self.assertNotIn(b"listen-gen-whisper-", package_bytes)
            self.assertNotIn(b"listen-gen-audio-", package_bytes)
            self.assertNotIn(b"normalized.wav", package_bytes)
            self.assertNotIn(b"whisper-cli", package_bytes)

    def test_path_independent_determinism(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            packages: list[bytes] = []
            for index in (1, 2):
                run_dir = root / f"run-{index}"
                run_dir.mkdir()
                helper = run_dir / "whisper-cli"
                helper.write_bytes(self.helper.read_bytes())
                helper.chmod(0o755)
                model = self.write_model(run_dir, name="ggml-base.bin")
                output = run_dir / "lesson.listenpkg"
                completed = run_cli(
                    self.base_argv(output, model=model, whisper_cli=helper),
                    env=self.whisper_env(),
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                packages.append(output.read_bytes())
            self.assertEqual(packages[0], packages[1])

    def test_invalid_provider_output_maps_to_provider_output_invalid(self) -> None:
        for mode in ("invalid-json", "invalid-shape", "no-output"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                model = self.write_model(root)
                output = root / "lesson.listenpkg"
                completed = run_cli(
                    self.base_argv(output, model=model, machine=True),
                    env=self.whisper_env(
                        mode=mode,
                        observed=root / "observed.json",
                    ),
                )
                self.assertEqual(completed.returncode, 2)
                events = parse_events(completed.stdout)
                final = self.assert_terminal(events)
                self.assertEqual(final["code"], "provider_output_invalid")
                self.assertEqual(
                    final["message"],
                    "The transcription provider returned an invalid result.",
                )
                self.assertNotIn("must-not-leak", completed.stdout)
                self.assertNotIn("Traceback", completed.stdout)
                self.assertNotIn(str(model), completed.stdout)
                self.assertNotIn(str(self.media), completed.stdout)
                self.assertNotIn("listen-gen-whisper-", completed.stdout)
                self.assertNotIn("listen-gen-audio-", completed.stdout)
                self.assertFalse(output.exists())

    def test_nonzero_exit_maps_to_provider_failed_without_leaks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            output = root / "lesson.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model, machine=True),
                env=self.whisper_env(mode="fail"),
            )
            self.assertEqual(completed.returncode, 2)
            events = parse_events(completed.stdout)
            final = self.assert_terminal(events)
            self.assertEqual(final["code"], "provider_failed")
            self.assertNotIn("must-not-leak", completed.stdout)
            self.assertNotIn("must-not-leak", completed.stderr)
            self.assertFalse(output.exists())

    def test_timeout_maps_to_provider_timeout_and_kills_process(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            observed = root / "observed.json"
            output = root / "lesson.listenpkg"
            completed = run_cli(
                self.base_argv(
                    output, model=model, machine=True, timeout="0.5"
                ),
                env=self.whisper_env(mode="sleep", observed=observed),
            )
            self.assertEqual(completed.returncode, 2)
            events = parse_events(completed.stdout)
            final = self.assert_terminal(events)
            self.assertEqual(final["code"], "provider_timeout")
            self.assertFalse(output.exists())
            observation = json.loads(observed.read_text(encoding="utf-8"))
            self.assert_pid_dead(int(observation["pid"]))

    def test_model_deleted_during_transcription_maps_to_provider_failed(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            output = root / "lesson.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model, machine=True),
                env=self.whisper_env(
                    mode="delete-model",
                    observed=root / "observed.json",
                ),
            )
            self.assertEqual(completed.returncode, 2)
            self.assertFalse(model.exists())
            events = parse_events(completed.stdout)
            final = self.assert_terminal(events)
            self.assertEqual(final["event"], "failed")
            self.assertEqual(final["code"], "provider_failed")
            self.assertEqual(
                final["message"], "The transcription provider failed."
            )
            self.assertNotIn("input_not_found", completed.stdout)
            self.assertNotIn("package_write_failed", completed.stdout)
            self.assertNotIn("Traceback", completed.stdout)
            self.assertNotIn(str(model), completed.stdout)
            self.assertNotIn("listen-gen-whisper-", completed.stdout)
            self.assertNotIn("listen-gen-audio-", completed.stdout)
            self.assertFalse(output.exists())
            leftovers = [
                path.name
                for path in root.iterdir()
                if ".machine.tmp" in path.name
            ]
            self.assertEqual(leftovers, [])

    def test_invalid_arguments_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            missing = root / "missing.bin"
            cases = [
                (
                    self.base_argv(
                        root / "a.listenpkg", model=missing, machine=True
                    ),
                    "missing model",
                ),
                (
                    self.base_argv(
                        root / "b.listenpkg",
                        model=model,
                        model_id="   ",
                        machine=True,
                    ),
                    "blank model id",
                ),
                (
                    self.base_argv(
                        root / "c.listenpkg",
                        model=model,
                        language="en US",
                        machine=True,
                    ),
                    "invalid language",
                ),
                (
                    self.base_argv(
                        root / "d.listenpkg",
                        model=model,
                        timeout="0",
                        machine=True,
                    ),
                    "non-positive timeout",
                ),
            ]
            for argv, label in cases:
                with self.subTest(label=label):
                    completed = run_cli(argv, env=self.whisper_env())
                    self.assertEqual(completed.returncode, 2)
                    events = parse_events(completed.stdout)
                    self.assertEqual(
                        [event["event"] for event in events],
                        ["protocol", "started", "phase", "failed"],
                    )
                    final = self.assert_terminal(events)
                    self.assertEqual(final["code"], "invalid_arguments")

    def test_sigterm_cancels_and_kills_whole_process_group(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            observed = root / "observed.json"
            output = root / "lesson.listenpkg"
            output.write_bytes(b"sentinel-bytes-must-survive")
            process = subprocess.Popen(
                [sys.executable, "-m", "listen_gen", *self.base_argv(
                    output, model=model, machine=True, timeout="600"
                )],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=self.whisper_env(
                    mode="hang-with-child", observed=observed
                ),
            )
            deadline = time.monotonic() + 30
            while not observed.is_file() and time.monotonic() < deadline:
                if process.poll() is not None:
                    break
                time.sleep(0.05)
            self.assertTrue(
                observed.is_file(),
                "fake whisper provider did not start before the deadline",
            )
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=60)
            self.assertEqual(process.returncode, 130, stderr)
            events = parse_events(stdout)
            final = self.assert_terminal(events)
            self.assertEqual(final["event"], "cancelled")
            self.assertNotIn(
                "completed", [event["event"] for event in events]
            )
            self.assertNotIn("failed", [event["event"] for event in events])
            self.assertEqual(
                output.read_bytes(), b"sentinel-bytes-must-survive"
            )
            observation = json.loads(observed.read_text(encoding="utf-8"))
            self.assert_pid_dead(int(observation["pid"]))
            self.assert_pid_dead(int(observation["child_pid"]))
            whisper_directory = Path(observation["output_prefix"]).parent
            audio_directory = Path(observation["media_path"]).parent
            self.assertFalse(whisper_directory.exists())
            self.assertFalse(audio_directory.exists())
            leftovers = [
                path.name
                for path in root.iterdir()
                if ".machine.tmp" in path.name
            ]
            self.assertEqual(leftovers, [])

    def test_existing_providers_keep_word_timeline(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fixture_output = root / "fixture.listenpkg"
            code = main([
                "package", "from-media", str(self.fixture_media),
                "--output", str(fixture_output),
                "--provider", "fixture", "--fixture", str(self.fixture),
                "--title", "Fixture lesson", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1785542400000",
            ])
            self.assertEqual(code, 0)
            with zipfile.ZipFile(fixture_output) as archive:
                self.assertEqual(
                    archive.namelist(),
                    [
                        "manifest.json",
                        "resources/subtitle-text-track.json",
                        "resources/word-timeline.json",
                    ],
                )
            command_output = root / "command.listenpkg"
            observed = root / "observed.txt"
            code = main([
                "package", "from-media", str(self.media),
                "--output", str(command_output),
                "--provider", "command",
                "--command", sys.executable,
                "--command-arg", str(ROOT / "tests" / "fixtures" / "fake_asr_command.py"),
                "--command-arg", "success",
                "--command-arg", "{media}",
                "--command-arg", str(self.fixture),
                "--command-arg", str(observed),
                "--command-timeout-seconds", "5",
                "--ffprobe-command", str(self.ffprobe),
                "--ffmpeg-command", str(self.ffmpeg),
                "--title", "Command lesson", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1785542400000",
            ])
            self.assertEqual(code, 0)
            with zipfile.ZipFile(command_output) as archive:
                self.assertEqual(
                    archive.namelist(),
                    [
                        "manifest.json",
                        "resources/subtitle-text-track.json",
                        "resources/word-timeline.json",
                    ],
                )


if __name__ == "__main__":
    unittest.main()
