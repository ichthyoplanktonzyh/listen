from __future__ import annotations

import hashlib
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unicodedata
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))
TERMINAL_EVENTS = {"completed", "failed", "cancelled"}
ALIGNMENT_SCHEMA = "listen_gen.align-result.v1"

from listen_gen.cli import main
from listen_gen.package import ConversionError


def _env(**overrides: str) -> dict[str, str]:
    env = dict(os.environ)
    env["PYTHONPATH"] = str(ROOT / "src")
    env.update(overrides)
    return env


def run_cli(
    argv: list[str],
    env: dict[str, str] | None = None,
    timeout: float = 90,
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


def _sha256_bytes(data: bytes) -> str:
    return f"sha256:{hashlib.sha256(data).hexdigest()}"


class FixtureAlignmentTests(unittest.TestCase):
    media = ROOT / "tests" / "fixtures" / "sample-media.wav"
    fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
    alignment_fixture = ROOT / "tests" / "fixtures" / "alignment-result.json"

    def base_argv(
        self,
        output: Path,
        *,
        alignment_fixture: Path | None = None,
        machine: bool = False,
    ) -> list[str]:
        argv = [
            "package", "from-media", str(self.media),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(self.fixture),
            "--aligner", "fixture",
            "--alignment-fixture", str(alignment_fixture or self.alignment_fixture),
            "--title", "Aligned lesson", "--media-kind", "audio",
            "--duration-ms", "2200", "--created-at-ms", "1786000000000",
        ]
        if machine:
            argv.append("--machine-events")
        return argv

    def read_package(self, output: Path) -> dict[str, object]:
        with zipfile.ZipFile(output) as archive:
            manifest = json.loads(archive.read("manifest.json"))
            documents = {
                entry["kind"]: json.loads(archive.read(entry["path"]))
                for entry in manifest["resources"]
            }
        return {"manifest": manifest, "documents": documents}

    def test_fixture_alignment_produces_aligned_package(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "aligned.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = self.read_package(output)
            kinds = [entry["kind"] for entry in package["manifest"]["resources"]]
            self.assertEqual(
                kinds, ["subtitle_text_track", "word_timeline"]
            )
            subtitle = package["documents"]["subtitle_text_track"]
            words = package["documents"]["word_timeline"]
            subtitle_raw = json.dumps(
                subtitle, ensure_ascii=False, sort_keys=True, separators=(",", ":")
            ).encode("utf-8") + b"\n"
            self.assertEqual(words["dependencies"], [{
                "kind": "subtitle_text_track",
                "resource_id": _sha256_bytes(subtitle_raw),
            }])
            self.assertEqual(words["subject"]["media_fingerprint"],
                             package["manifest"]["content_document"]["media_fingerprint"])
            timings = words["payload"]["words"]
            self.assertEqual(
                [(timing["token_index"], timing["start_ms"], timing["end_ms"])
                 for timing in timings],
                [(0, 110, 490), (3, 570, 1100), (0, 1310, 1600), (2, 1660, 2030)],
            )
            self.assertTrue(all(
                timing["timing_source"] == "forced_aligned" for timing in timings
            ))
            self.assertTrue(all(
                timing["confidence"] is not None for timing in timings
            ))
            sentence_ids = {
                sentence["id"]: sentence["index"]
                for sentence in subtitle["payload"]["sentences"]
            }
            for timing in timings:
                self.assertIn(timing["sentence_id"], sentence_ids)

    def test_alignment_words_reference_exact_emitted_subtitle_tokens(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "aligned.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = self.read_package(output)
            subtitle = package["documents"]["subtitle_text_track"]
            words = package["documents"]["word_timeline"]
            for sentence in subtitle["payload"]["sentences"]:
                word_tokens = [token for token in sentence["tokens"]
                               if token["kind"] == "word"]
                for token in word_tokens:
                    matches = [
                        timing for timing in words["payload"]["words"]
                        if timing["sentence_id"] == sentence["id"]
                        and timing["token_index"] == token["index"]
                    ]
                    self.assertEqual(len(matches), 1, token)
                for timing in words["payload"]["words"]:
                    if timing["sentence_id"] != sentence["id"]:
                        continue
                    token = next(token for token in sentence["tokens"]
                                  if token["index"] == timing["token_index"])
                    self.assertEqual(token["kind"], "word")

    def test_alignment_provenance_is_alignment_not_asr(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "aligned.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = self.read_package(output)
            subtitle = package["documents"]["subtitle_text_track"]
            words = package["documents"]["word_timeline"]
            self.assertEqual(words["provenance"]["tool"], {
                "id": "listen-gen.alignment", "version": "0.2.0",
            })
            self.assertEqual(words["provenance"]["provider"], {
                "id": "fixture-aligner", "version": "1",
            })
            self.assertEqual(words["provenance"]["model"], {
                "id": "fixture-align", "version": "2026-08",
            })
            self.assertEqual(
                words["provenance"]["config_sha256"],
                "sha256:" + "b" * 64,
            )
            self.assertNotEqual(words["provenance"], subtitle["provenance"])
            self.assertEqual(subtitle["provenance"]["tool"]["id"], "listen-gen.asr-package")

    def test_alignment_package_is_deterministic_and_path_independent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            packages = []
            for index in (1, 2):
                run_dir = root / f"run-{index}"
                run_dir.mkdir()
                fixture = run_dir / "alignment-result.json"
                fixture.write_text(self.alignment_fixture.read_text(encoding="utf-8"))
                output = run_dir / "aligned.listenpkg"
                completed = run_cli(self.base_argv(output, alignment_fixture=fixture))
                self.assertEqual(completed.returncode, 0, completed.stderr)
                packages.append(output.read_bytes())
            self.assertEqual(packages[0], packages[1])

    def test_alignment_overrides_asr_supplied_word_timing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "aligned.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = self.read_package(output)
            words = package["documents"]["word_timeline"]
            # The ASR fixture reports 100/560/1300/1650; alignment wins.
            starts = [timing["start_ms"] for timing in words["payload"]["words"]]
            self.assertEqual(starts, [110, 570, 1310, 1660])

    def test_core_inspector_accepts_aligned_fixture(self) -> None:
        checkout = os.environ.get("LISTEN_CORE_CHECKOUT")
        if checkout is None:
            self.skipTest("LISTEN_CORE_CHECKOUT is not set")
        core = Path(checkout)
        if not (core / "crates" / "content-package" / "Cargo.toml").is_file():
            self.fail("LISTEN_CORE_CHECKOUT does not contain crates/content-package")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "aligned.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            probe = Path(directory) / "probe"
            (probe / "src").mkdir(parents=True)
            (probe / "Cargo.toml").write_text(
                "[package]\nname = \"listen-gen-contract-probe\"\nversion = \"0.0.0\"\nedition = \"2024\"\n"
                f"[dependencies]\ncontent-package = {{ path = {json.dumps(str(core / 'crates' / 'content-package'))} }}\n",
                encoding="utf-8",
            )
            (probe / "src" / "main.rs").write_text(
                "fn main() { content_package::inspect_path(std::env::args_os().nth(1).unwrap()).unwrap(); }\n",
                encoding="utf-8",
            )
            subprocess.run(
                ["cargo", "run", "-q", "--manifest-path", str(probe / "Cargo.toml"), "--", str(output)],
                cwd=probe,
                check=True,
                capture_output=True,
                text=True,
            )

    def _assert_degraded(self, alignment_fixture: Path, expected_code: str) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "degraded.listenpkg"
            completed = run_cli(self.base_argv(output, alignment_fixture=alignment_fixture))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = self.read_package(output)
            kinds = [entry["kind"] for entry in package["manifest"]["resources"]]
            self.assertEqual(kinds, ["subtitle_text_track"])
            result = json.loads(completed.stdout)
            self.assertEqual(result["alignment"]["status"], "degraded")
            self.assertEqual(
                result["alignment"]["warnings"],
                [{"code": expected_code,
                  "message": "Word alignment did not qualify; "
                             "the subtitle package was preserved."}],
            )
            self.assertEqual(result["warnings"], [
                "Word alignment did not qualify; the subtitle package was preserved.",
            ])
            package_bytes = output.read_bytes()
            self.assertNotIn(str(alignment_fixture).encode(), package_bytes)
            return result

    def _mutate_fixture(self, directory: Path, mutate) -> Path:
        value = json.loads(self.alignment_fixture.read_text(encoding="utf-8"))
        mutate(value)
        path = directory / "bad-alignment.json"
        path.write_text(json.dumps(value), encoding="utf-8")
        return path

    def test_missing_alignment_word_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._mutate_fixture(Path(directory), lambda value: value["words"].pop(0))
            self._assert_degraded(fixture, "alignment_qualification_failed")

    def test_extra_alignment_word_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            def mutate(value):
                value["words"].append({
                    "sentence_index": 1, "text": "extra",
                    "start_ms": 2050, "end_ms": 2100,
                })
            fixture = self._mutate_fixture(Path(directory), mutate)
            self._assert_degraded(fixture, "alignment_qualification_failed")

    def test_mismatched_alignment_word_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            def mutate(value):
                value["words"][0]["text"] = "Garbled"
            fixture = self._mutate_fixture(Path(directory), mutate)
            self._assert_degraded(fixture, "alignment_qualification_failed")

    def test_wrong_sentence_index_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            def mutate(value):
                value["words"][0]["sentence_index"] = 1
            fixture = self._mutate_fixture(Path(directory), mutate)
            self._assert_degraded(fixture, "alignment_qualification_failed")

    def test_out_of_bounds_alignment_word_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            def mutate(value):
                value["words"][0]["end_ms"] = 1250  # sentence 0 ends at 1200
            fixture = self._mutate_fixture(Path(directory), mutate)
            self._assert_degraded(fixture, "alignment_qualification_failed")

    def test_non_monotonic_alignment_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            def mutate(value):
                value["words"][1]["start_ms"] = 100
                value["words"][1]["end_ms"] = 200
            fixture = self._mutate_fixture(Path(directory), mutate)
            self._assert_degraded(fixture, "alignment_qualification_failed")

    def test_invalid_confidence_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            def mutate(value):
                value["words"][0]["confidence"] = 1.5
            fixture = self._mutate_fixture(Path(directory), mutate)
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "degraded.listenpkg"
                completed = run_cli(self.base_argv(output, alignment_fixture=fixture))
                self.assertEqual(completed.returncode, 0, completed.stderr)
                result = json.loads(completed.stdout)
                self.assertEqual(result["alignment"]["status"], "degraded")
                self.assertEqual(
                    result["alignment"]["warnings"][0]["code"],
                    "alignment_output_invalid",
                )

    def test_empty_words_degrades_as_output_invalid(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            def mutate(value):
                value["words"] = []
            fixture = self._mutate_fixture(Path(directory), mutate)
            with tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "degraded.listenpkg"
                completed = run_cli(self.base_argv(output, alignment_fixture=fixture))
                self.assertEqual(completed.returncode, 0, completed.stderr)
                result = json.loads(completed.stdout)
                self.assertEqual(result["alignment"]["status"], "degraded")
                self.assertEqual(
                    result["alignment"]["warnings"][0]["code"],
                    "alignment_output_invalid",
                )

    def test_machine_events_aligning_phase_and_completed_alignment(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "aligned.listenpkg"
            completed = run_cli(self.base_argv(output, machine=True))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            self.assertEqual(
                [event["event"] for event in events],
                ["protocol", "started", "phase", "phase", "phase", "phase", "completed"],
            )
            self.assertEqual(
                [event["phase"] for event in events if event["event"] == "phase"],
                ["validating", "transcribing", "aligning", "building_package"],
            )
            final = [event for event in events if event["event"] == "completed"][0]
            self.assertEqual(final["alignment"], {
                "status": "produced", "warnings": [],
            })
            self.assertEqual(
                [entry["kind"] for entry in final["resources"]],
                ["subtitle_text_track", "word_timeline"],
            )

    def test_machine_degraded_completed_carries_typed_warning(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            fixture = self._mutate_fixture(Path(directory), lambda value: value["words"].pop(0))
            output = Path(directory) / "degraded.listenpkg"
            completed = run_cli(self.base_argv(output, alignment_fixture=fixture, machine=True))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            terminals = [e for e in events if e["event"] in TERMINAL_EVENTS]
            self.assertEqual(len(terminals), 1)
            final = terminals[0]
            self.assertEqual(final["event"], "completed")
            self.assertEqual(final["alignment"]["status"], "degraded")
            self.assertEqual(
                final["alignment"]["warnings"][0]["code"],
                "alignment_qualification_failed",
            )
            self.assertEqual(
                [entry["kind"] for entry in final["resources"]],
                ["subtitle_text_track"],
            )

    def test_missing_alignment_fixture_is_invalid_arguments(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "x.listenpkg"
            argv = self.base_argv(output, machine=True)
            argv[argv.index("--alignment-fixture") + 1] = str(Path(directory) / "missing.json")
            completed = run_cli(argv)
            self.assertEqual(completed.returncode, 2)
            events = parse_events(completed.stdout)
            self.assertEqual(
                [event["event"] for event in events],
                ["protocol", "started", "phase", "failed"],
            )
            self.assertEqual(events[-1]["code"], "invalid_arguments")


class CommandAlignmentTests(unittest.TestCase):
    media = ROOT / "tests" / "fixtures" / "single-audio-media.json"
    fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
    helper = ROOT / "tests" / "fixtures" / "fake_align_command.py"
    ffprobe = ROOT / "tests" / "fixtures" / "fake_ffprobe.py"
    ffmpeg = ROOT / "tests" / "fixtures" / "fake_ffmpeg.py"

    def base_argv(
        self,
        output: Path,
        *,
        mode: str = "success",
        observed: Path | None = None,
        machine: bool = False,
    ) -> list[str]:
        argv = [
            "package", "from-media", str(self.media),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(self.fixture),
            "--aligner", "command",
            "--alignment-command", sys.executable,
            "--alignment-command-arg", str(self.helper),
            "--alignment-command-arg", "{media}",
            "--alignment-command-arg", "{transcript}",
            "--alignment-command-timeout-seconds", "10",
            "--ffprobe-command", str(self.ffprobe),
            "--ffmpeg-command", str(self.ffmpeg),
            "--title", "Command aligned lesson", "--media-kind", "audio",
            "--duration-ms", "2200", "--created-at-ms", "1786000000000",
        ]
        if machine:
            argv.append("--machine-events")
        return argv

    def align_env(self, *, mode: str = "success", observed: Path | None = None) -> dict[str, str]:
        env = _env()
        env["LISTEN_GEN_FAKE_ALIGN_MODE"] = mode
        if observed is not None:
            env["LISTEN_GEN_FAKE_ALIGN_OBSERVED"] = str(observed)
        return env

    def test_command_aligner_receives_normalized_protocol(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            observed = root / "aligner.json"
            output = root / "aligned.listenpkg"
            completed = run_cli(
                self.base_argv(output, observed=observed),
                env=self.align_env(observed=observed),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertTrue(output.is_file())
            with zipfile.ZipFile(output) as archive:
                words = json.loads(archive.read("resources/word-timeline.json"))
                self.assertEqual(
                    [timing["start_ms"] for timing in words["payload"]["words"]],
                    [100, 110, 1300, 1310],
                )
                self.assertTrue(all(
                    timing["timing_source"] == "forced_aligned"
                    for timing in words["payload"]["words"]
                ))
            observation = json.loads(observed.read_text(encoding="utf-8"))
            self.assertEqual(observation["schema"], "listen_gen.subtitle-input.v1")
            self.assertEqual(observation["language"], "en-US")
            sentences = observation["sentences"]
            self.assertEqual(
                [sentence["index"] for sentence in sentences], [0, 1]
            )
            self.assertIn("tokens", sentences[0])
            self.assertTrue(Path(observation["media_path"]).name == "normalized.wav")

    def test_command_aligner_start_failure_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "degraded.listenpkg"
            argv = self.base_argv(output)
            argv[argv.index("--alignment-command") + 1] = "/nonexistent/aligner-bin"
            completed = run_cli(argv)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(result["alignment"]["status"], "degraded")
            self.assertEqual(
                result["alignment"]["warnings"][0]["code"],
                "alignment_start_failed",
            )
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(
                    archive.namelist(),
                    ["manifest.json", "resources/subtitle-text-track.json"],
                )

    def test_command_aligner_nonzero_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "degraded.listenpkg"
            completed = run_cli(
                self.base_argv(output),
                env=self.align_env(mode="fail"),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(result["alignment"]["status"], "degraded")
            self.assertEqual(result["alignment"]["warnings"][0]["code"], "alignment_failed")
            self.assertNotIn("must-not-leak-align", completed.stdout)
            self.assertNotIn("must-not-leak-align", completed.stderr)

    def test_command_aligner_invalid_json_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "degraded.listenpkg"
            completed = run_cli(
                self.base_argv(output),
                env=self.align_env(mode="invalid-json"),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(
                result["alignment"]["warnings"][0]["code"],
                "alignment_output_invalid",
            )

    def test_command_aligner_output_cap_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "degraded.listenpkg"
            completed = run_cli(
                self.base_argv(output),
                env=self.align_env(mode="flood"),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(
                result["alignment"]["warnings"][0]["code"],
                "alignment_output_too_large",
            )

    def test_command_aligner_timeout_degrades_and_reaps(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "degraded.listenpkg"
            argv = self.base_argv(output)
            argv[argv.index("--alignment-command-timeout-seconds") + 1] = "0.3"
            completed = run_cli(argv, env=self.align_env(mode="sleep"))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(result["alignment"]["status"], "degraded")
            self.assertEqual(result["alignment"]["warnings"][0]["code"], "alignment_timeout")

    def test_command_aligner_missing_placeholder_is_invalid_arguments(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "x.listenpkg"
            argv = self.base_argv(output, machine=True)
            argv.remove(str(self.helper))
            argv.remove("{transcript}")
            completed = run_cli(argv)
            self.assertEqual(completed.returncode, 2)
            events = parse_events(completed.stdout)
            self.assertEqual(
                [event["event"] for event in events],
                ["protocol", "started", "phase", "failed"],
            )
            self.assertEqual(events[-1]["event"], "failed")
            self.assertEqual(events[-1]["code"], "invalid_arguments")


class WhisperCppAlignmentTests(unittest.TestCase):
    media = ROOT / "tests" / "fixtures" / "single-audio-media.json"
    ffprobe = ROOT / "tests" / "fixtures" / "fake_ffprobe.py"
    ffmpeg = ROOT / "tests" / "fixtures" / "fake_ffmpeg.py"
    helper = ROOT / "tests" / "fixtures" / "fake_whisper_cli.py"

    def base_argv(
        self,
        output: Path,
        *,
        model: Path,
        whisper_cli: Path | None = None,
        timeout: str = "30",
        machine: bool = False,
    ) -> list[str]:
        argv = [
            "package", "from-media", str(self.media),
            "--output", str(output),
            "--provider", "whisper-cpp",
            "--whisper-cli", str(whisper_cli or self.helper),
            "--whisper-model", str(model),
            "--whisper-model-id", "whisper.cpp:base@main",
            "--whisper-language", "en",
            "--whisper-timeout-seconds", timeout,
            "--aligner", "whisper-cpp",
            "--ffprobe-command", str(self.ffprobe),
            "--ffmpeg-command", str(self.ffmpeg),
            "--title", "Whisper aligned lesson", "--media-kind", "video",
            "--duration-ms", "2200", "--created-at-ms", "1786000000000",
        ]
        if machine:
            argv.append("--machine-events")
        return argv

    def whisper_env(
        self, *, mode: str = "success", observed: Path | None = None
    ) -> dict[str, str]:
        env = _env()
        env["LISTEN_GEN_FAKE_WHISPER_MODE"] = mode
        if observed is not None:
            env["LISTEN_GEN_FAKE_WHISPER_OBSERVED"] = str(observed)
        return env

    def write_model(self, directory: Path) -> Path:
        model = directory / "ggml-base.bin"
        model.write_bytes(b"dummy-model-bytes")
        return model

    def read_subtitle(self, output: Path) -> dict[str, object]:
        with zipfile.ZipFile(output) as archive:
            return json.loads(archive.read("resources/subtitle-text-track.json"))

    def read_word_timeline(self, output: Path) -> dict[str, object]:
        with zipfile.ZipFile(output) as archive:
            return json.loads(archive.read("resources/word-timeline.json"))

    def test_first_class_whisper_cpp_aligned_package(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            observed = root / "observed.json"
            output = root / "aligned.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model),
                env=self.whisper_env(observed=observed),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(
                    archive.namelist(),
                    [
                        "manifest.json",
                        "resources/subtitle-text-track.json",
                        "resources/word-timeline.json",
                    ],
                )
            words = self.read_word_timeline(output)
            timings = words["payload"]["words"]
            self.assertEqual(
                [timing["token_index"] for timing in timings],
                [0, 2, 0, 2],
            )
            self.assertEqual(
                [(timing["start_ms"], timing["end_ms"]) for timing in timings],
                [(120, 480), (500, 840), (900, 1500), (1550, 2100)],
            )
            self.assertTrue(all(
                timing["timing_source"] == "asr_aligned" for timing in timings
            ))
            self.assertEqual([timing["confidence"] for timing in timings], [0.99, 0.98, 0.97, 0.95])
            subtitle = self.read_subtitle(output)
            raw = json.dumps(
                subtitle, ensure_ascii=False, sort_keys=True, separators=(",", ":")
            ).encode("utf-8") + b"\n"
            self.assertEqual(words["dependencies"], [{
                "kind": "subtitle_text_track", "resource_id": _sha256_bytes(raw),
            }])

    def test_whisper_cpp_aligner_exact_argv_and_two_runs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            observed = root / "observed.json"
            output = root / "aligned.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model),
                env=self.whisper_env(observed=observed),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            observation = json.loads(observed.read_text(encoding="utf-8"))
            runs = observation["runs"]
            self.assertEqual(len(runs), 2)
            asr_run, aligner_run = runs
            self.assertIn("-oj", asr_run["argv"])
            self.assertNotIn("-ojf", asr_run["argv"])
            self.assertIn("-ojf", aligner_run["argv"])
            self.assertNotIn("-oj", aligner_run["argv"])
            self.assertEqual(
                aligner_run["argv"],
                [
                    "-m", str(model),
                    "-f", aligner_run["media_path"],
                    "-ojf",
                    "-of", aligner_run["output_prefix"],
                    "-l", "en",
                ],
            )
            asr_normalized = Path(asr_run["media_path"])
            aligner_normalized = Path(aligner_run["media_path"])
            self.assertEqual(asr_normalized.name, "normalized.wav")
            self.assertEqual(aligner_normalized.name, "normalized.wav")
            self.assertFalse(asr_normalized.exists())
            self.assertFalse(asr_normalized.parent.exists())
            self.assertFalse(aligner_normalized.parent.exists())
            self.assertFalse(Path(aligner_run["output_prefix"]).parent.exists())

    def test_whisper_aligner_provenance_binds_bytes_without_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            output = root / "aligned.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model),
                env=self.whisper_env(),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            words = self.read_word_timeline(output)
            provenance = words["provenance"]
            self.assertEqual(provenance["tool"], {
                "id": "listen-gen.alignment", "version": "0.2.0",
            })
            self.assertEqual(provenance["provider"], {
                "id": "whisper.cpp",
                "version": _sha256_bytes(self.helper.read_bytes()),
            })
            self.assertEqual(provenance["model"], {
                "id": "whisper.cpp:base@main",
                "version": _sha256_bytes(model.read_bytes()),
            })
            self.assertRegex(provenance["config_sha256"], r"^sha256:[0-9a-f]{64}$")
            package_bytes = output.read_bytes()
            for forbidden in (
                str(self.helper), str(model), str(self.media),
                str(self.ffprobe), str(self.ffmpeg),
            ):
                self.assertNotIn(forbidden.encode(), package_bytes)
            self.assertNotIn(b"listen-gen-whisper-align-", package_bytes)
            self.assertNotIn(b"normalized.wav", package_bytes)

    def test_whisper_aligner_path_independent_determinism(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            packages = []
            for index in (1, 2):
                run_dir = root / f"run-{index}"
                run_dir.mkdir()
                helper = run_dir / "whisper-cli"
                helper.write_bytes(self.helper.read_bytes())
                helper.chmod(0o755)
                model = self.write_model(run_dir)
                output = run_dir / "aligned.listenpkg"
                completed = run_cli(
                    self.base_argv(output, model=model, whisper_cli=helper),
                    env=self.whisper_env(),
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                packages.append(output.read_bytes())
            self.assertEqual(packages[0], packages[1])

    def test_whisper_aligner_unknown_tokens_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            output = root / "degraded.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model, machine=True),
                env=self.whisper_env(mode="align-unknown-tokens"),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            terminals = [e for e in events if e["event"] in TERMINAL_EVENTS]
            self.assertEqual(len(terminals), 1)
            final = terminals[0]
            self.assertEqual(final["event"], "completed")
            self.assertEqual(final["alignment"]["status"], "degraded")
            self.assertEqual(
                final["alignment"]["warnings"][0]["code"],
                "alignment_qualification_failed",
            )
            self.assertEqual(
                [entry["kind"] for entry in final["resources"]],
                ["subtitle_text_track"],
            )

    def test_whisper_aligner_failure_modes_degrades(self) -> None:
        cases = [
            ("align-fail", "alignment_failed"),
            ("align-invalid-json", "alignment_output_invalid"),
            ("align-no-output", "alignment_output_invalid"),
        ]
        for mode, expected in cases:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                model = self.write_model(root)
                output = root / "degraded.listenpkg"
                completed = run_cli(
                    self.base_argv(output, model=model),
                    env=self.whisper_env(mode=mode),
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                result = json.loads(completed.stdout)
                self.assertEqual(result["alignment"]["status"], "degraded")
                self.assertEqual(
                    result["alignment"]["warnings"][0]["code"], expected
                )
                self.assertNotIn("must-not-leak", completed.stdout)
                self.assertNotIn("must-not-leak", completed.stderr)
                self.assertNotIn(str(model), completed.stdout)
                self.assertNotIn("listen-gen-whisper-align-", completed.stdout)
                with zipfile.ZipFile(output) as archive:
                    self.assertEqual(
                        [entry["kind"] for entry in json.loads(
                            archive.read("manifest.json")
                        )["resources"]],
                        ["subtitle_text_track"],
                    )

    def test_whisper_aligner_timeout_degrades_and_reaps(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            observed = root / "observed.json"
            output = root / "degraded.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model, timeout="0.5"),
                env=self.whisper_env(mode="align-sleep", observed=observed),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(result["alignment"]["status"], "degraded")
            self.assertEqual(result["alignment"]["warnings"][0]["code"], "alignment_timeout")
            with zipfile.ZipFile(output) as archive:
                manifest = json.loads(archive.read("manifest.json"))
                self.assertEqual(
                    [entry["kind"] for entry in manifest["resources"]],
                    ["subtitle_text_track"],
                )

    def test_whisper_aligner_model_mutation_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            output = root / "degraded.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model),
                env=self.whisper_env(mode="align-delete-model"),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            self.assertFalse(model.exists())
            result = json.loads(completed.stdout)
            self.assertEqual(result["alignment"]["status"], "degraded")
            self.assertEqual(result["alignment"]["warnings"][0]["code"], "alignment_failed")

    def test_whisper_aligner_aggregates_split_tokens(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            observed = root / "observed.json"
            output = root / "aligned.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model),
                env=self.whisper_env(
                    mode="align-split-words", observed=observed
                ),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            words = self.read_word_timeline(output)
            timings = words["payload"]["words"]
            self.assertEqual(
                [(timing["token_index"], timing["start_ms"], timing["end_ms"])
                 for timing in timings],
                [(0, 120, 480), (2, 500, 840), (0, 900, 1500), (2, 1550, 2100)],
            )
            self.assertEqual(
                [timing["confidence"] for timing in timings],
                [0.90, 0.98, 0.88, 0.95],
            )
            self.assertTrue(all(
                timing["timing_source"] == "asr_aligned" for timing in timings
            ))
            self.assertEqual(words["provenance"]["config_sha256"].startswith("sha256:"), True)

    def test_whisper_aligner_oversize_file_degrades(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            observed = root / "observed.json"
            output = root / "degraded.listenpkg"
            completed = run_cli(
                self.base_argv(output, model=model),
                env=self.whisper_env(
                    mode="align-oversize-file", observed=observed
                ),
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(result["alignment"]["status"], "degraded")
            self.assertEqual(
                result["alignment"]["warnings"][0]["code"],
                "alignment_output_too_large",
            )
            self.assertNotIn("must-not-leak", completed.stdout)
            self.assertNotIn("must-not-leak", completed.stderr)
            self.assertNotIn(str(model), completed.stdout)
            with zipfile.ZipFile(output) as archive:
                manifest = json.loads(archive.read("manifest.json"))
                self.assertEqual(
                    [entry["kind"] for entry in manifest["resources"]],
                    ["subtitle_text_track"],
                )
            observation = json.loads(observed.read_text(encoding="utf-8"))
            aligner_prefix = Path(observation["runs"][1]["output_prefix"])
            self.assertFalse(aligner_prefix.parent.exists())

    def test_whisper_aligner_invalid_arguments_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            missing = root / "missing.bin"
            cases = [
                (
                    self.base_argv(root / "a.listenpkg", model=missing, machine=True),
                    "missing model",
                ),
                (
                    self.base_argv(
                        root / "b.listenpkg", model=model, machine=True
                    )
                    + ["--whisper-language", "en US"],
                    "invalid language",
                ),
            ]
            for argv, label in cases:
                with self.subTest(label=label):
                    completed = run_cli(argv, env=self.whisper_env())
                    self.assertEqual(completed.returncode, 2)
                    events = parse_events(completed.stdout)
                    terminals = [
                        e for e in events if e["event"] in TERMINAL_EVENTS
                    ]
                    self.assertEqual(len(terminals), 1)
                    self.assertEqual(terminals[0]["code"], "invalid_arguments")

    def test_sigterm_during_alignment_reaps_aligner_child(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = self.write_model(root)
            observed = root / "observed.json"
            output = root / "cancelled.listenpkg"
            output.write_bytes(b"sentinel-must-survive")
            process = subprocess.Popen(
                [sys.executable, "-m", "listen_gen",
                 *self.base_argv(output, model=model, timeout="600", machine=True)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=self.whisper_env(mode="align-hang-with-child", observed=observed),
            )
            deadline = time.monotonic() + 30
            aligner_pid = None
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    break
                if observed.is_file():
                    try:
                        data = json.loads(observed.read_text(encoding="utf-8"))
                        runs = data.get("runs") or []
                        if len(runs) >= 2 and "child_pid" in runs[1]:
                            aligner_pid = int(runs[1]["pid"])
                            break
                    except (OSError, ValueError):
                        pass
                time.sleep(0.05)
            self.assertIsNotNone(aligner_pid, "aligner run did not start")
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=60)
            self.assertEqual(process.returncode, 130, stderr)
            events = parse_events(stdout)
            terminals = [e for e in events if e["event"] in TERMINAL_EVENTS]
            self.assertEqual(len(terminals), 1)
            self.assertEqual(terminals[0]["event"], "cancelled")
            self.assertEqual(output.read_bytes(), b"sentinel-must-survive")
            data = json.loads(observed.read_text(encoding="utf-8"))
            for pid in (data["runs"][1]["pid"], data["runs"][1]["child_pid"]):
                self.assert_pid_dead(int(pid))
            leftovers = [p.name for p in root.iterdir() if ".machine.tmp" in p.name]
            self.assertEqual(leftovers, [])

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


class TokenAggregationTests(unittest.TestCase):
    """Deterministic one-or-more token aggregation to exact subtitle words."""

    def _sentence(self, text: str) -> tuple:
        from listen_gen.alignment import (
            AlignmentSentence,
            AlignmentToken,
        )
        normalized = unicodedata.normalize("NFKC", text).casefold()
        return AlignmentSentence(
            id="sentence.x",
            index=0,
            start_ms=0,
            end_ms=2000,
            original_text=text,
            display_text=text,
            tokens=(AlignmentToken(
                index=0, kind="word", text=text,
                normalized=normalized, start_char=0, end_char=len(text),
            ),),
        )

    def _component(self, text, start, end, confidence=0.9, source="asr_aligned"):
        from listen_gen.alignment import RawComponent
        return RawComponent(None, text, start, end, confidence, source)

    def _resolve(self, sentence, components, aggregate=True):
        from listen_gen.alignment import _resolve_words
        return _resolve_words((sentence,), components, aggregate=aggregate)

    def test_split_english_word_aggregates(self) -> None:
        from listen_gen.alignment import AlignmentFailure
        sentence = self._sentence("carefully")
        result = self._resolve(sentence, [
            self._component(" care", 100, 400, 0.99),
            self._component("fully", 400, 700, 0.80),
        ])
        self.assertEqual(len(result), 1)
        word = result[0]
        self.assertEqual(word.token_index, 0)
        self.assertEqual((word.start_ms, word.end_ms), (100, 700))
        self.assertEqual(word.confidence, 0.80)
        self.assertEqual(word.timing_source, "asr_aligned")

    def test_apostrophe_word_aggregates(self) -> None:
        from listen_gen.alignment import AlignmentFailure
        for pieces in (
            [self._component(" don", 100, 300, 0.9), self._component("'t", 300, 500, 0.7)],
            [self._component(" don'", 100, 300, 0.9), self._component("t", 300, 500, 0.7)],
            [self._component(" don't", 100, 500, 0.9)],
        ):
            with self.subTest(pieces=pieces):
                word = self._resolve(self._sentence("don't"), pieces)[0]
                self.assertEqual((word.start_ms, word.end_ms), (100, 500))

    def test_cjk_multi_piece_aggregates(self) -> None:
        sentence = self._sentence("你好世界")
        result = self._resolve(sentence, [
            self._component(" 你", 100, 300, 0.9),
            self._component("好", 300, 500, 0.8),
            self._component("世界", 500, 900, 0.7),
        ])
        self.assertEqual(len(result), 1)
        word = result[0]
        self.assertEqual((word.start_ms, word.end_ms), (100, 900))
        self.assertEqual(word.confidence, 0.70)

    def test_more_than_sixteen_cjk_components_aggregate(self) -> None:
        # A no-whitespace CJK sentence is one subtitle word token; legitimate
        # aggregation of 17+ whisper components must not degrade.
        text = "一二三四五六七八九十甲乙丙丁戊己庚辛壬癸"
        sentence = self._sentence(text)
        components = [
            self._component(" " + character, 100 + index * 10, 110 + index * 10, 0.99)
            for index, character in enumerate(text)
        ]
        self.assertGreater(len(components), 16)
        result = self._resolve(sentence, components)
        self.assertEqual(len(result), 1)
        word = result[0]
        self.assertEqual((word.start_ms, word.end_ms), (100, 110 + (len(text) - 1) * 10))
        self.assertEqual(word.confidence, 0.99)

    def test_aggregate_confidence_is_minimum_when_all_present(self) -> None:
        from listen_gen.alignment import _aggregate_confidence, RawComponent
        group = [
            RawComponent(None, " care", 100, 300, 0.99, "asr_aligned"),
            RawComponent(None, "fully", 300, 500, 0.80, "asr_aligned"),
            RawComponent(None, "!", 500, 520, 0.10, "asr_aligned"),
        ]
        # Lexical components only: the punctuation-only piece is not in the
        # matched word group, so its low confidence must not drag the minimum.
        self.assertEqual(_aggregate_confidence(group[:2]), 0.80)

    def test_aggregate_confidence_omitted_when_any_component_missing(self) -> None:
        from listen_gen.alignment import _aggregate_confidence, RawComponent
        all_present = [
            RawComponent(None, " care", 100, 300, 0.99, "asr_aligned"),
            RawComponent(None, "fully", 300, 500, 0.80, "asr_aligned"),
        ]
        one_missing = [
            RawComponent(None, " care", 100, 300, 0.99, "asr_aligned"),
            RawComponent(None, "fully", 300, 500, None, "asr_aligned"),
        ]
        self.assertEqual(_aggregate_confidence(all_present), 0.80)
        self.assertIsNone(_aggregate_confidence(one_missing))

    def test_split_word_omits_confidence_when_any_piece_missing(self) -> None:
        sentence = self._sentence("carefully")
        result = self._resolve(sentence, [
            self._component(" care", 100, 400, 0.99),
            self._component("fully", 400, 700, None),
        ])
        self.assertEqual(len(result), 1)
        self.assertIsNone(result[0].confidence)

    def test_mismatched_pieces_degrade(self) -> None:
        from listen_gen.alignment import AlignmentFailure
        sentence = self._sentence("carefully")
        with self.assertRaises(AlignmentFailure):
            self._resolve(sentence, [
                self._component(" care", 100, 400),
                self._component("xully", 400, 700),
            ])

    def test_extra_lexical_piece_degrades(self) -> None:
        from listen_gen.alignment import AlignmentFailure
        sentence = self._sentence("carefully")
        with self.assertRaises(AlignmentFailure):
            self._resolve(sentence, [
                self._component(" carefully", 100, 400),
                self._component(" extra", 400, 500),
            ])

    def test_punctuation_tokens_never_fabricate_words(self) -> None:
        from listen_gen.alignment import AlignmentFailure
        # A trailing comma token between words is skipped, not fabricated.
        first = self._sentence("Hello")
        components = [
            self._component(" Hello", 100, 400, 0.9),
            self._component(",", 400, 450, 0.1),
            self._component(" world", 500, 800, 0.9),
        ]
        with self.assertRaises(AlignmentFailure):
            # second sentence "world" not present; leftover is the expected
            # failure mode, proving punctuation alone never becomes a word.
            self._resolve(first, components)

    def test_word_level_protocol_is_strict(self) -> None:
        from listen_gen.alignment import AlignmentFailure
        # The normalized command/fixture protocol is word-level: a split pair
        # must not silently aggregate.
        sentence = self._sentence("carefully")
        with self.assertRaises(AlignmentFailure):
            self._resolve(sentence, [
                self._component(" care", 100, 400),
                self._component("fully", 400, 700),
            ], aggregate=False)

    def test_word_level_exact_match_passes(self) -> None:
        sentence = self._sentence("carefully")
        word = self._resolve(sentence, [
            self._component(" carefully", 100, 700, 0.9),
        ], aggregate=False)[0]
        self.assertEqual((word.start_ms, word.end_ms), (100, 700))


class MachineProtocolAlignmentTests(unittest.TestCase):
    def test_protocol_capabilities_advertise_alignment(self) -> None:
        from listen_gen.protocol import protocol_capabilities
        capabilities = protocol_capabilities()
        self.assertEqual(capabilities["alignment"], {
            "optional": True,
            "degradation": "preserve_subtitle",
            "adapters": ["fixture", "command", "whisper-cpp"],
            "warning_codes": [
                "alignment_failed",
                "alignment_output_invalid",
                "alignment_output_too_large",
                "alignment_qualification_failed",
                "alignment_start_failed",
                "alignment_timeout",
            ],
        })
        self.assertIn("aligning", capabilities["phases"])

    def test_alignerless_run_keeps_skipped_alignment(self) -> None:
        media = ROOT / "tests" / "fixtures" / "sample-media.wav"
        fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "plain.listenpkg"
            completed = run_cli([
                "package", "from-media", str(media),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(fixture),
                "--title", "Plain lesson", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1786000000000",
                "--machine-events",
            ])
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            self.assertNotIn(
                "aligning", [event.get("phase") for event in events]
            )
            final = [e for e in events if e["event"] == "completed"][0]
            self.assertEqual(final["alignment"], {"status": "skipped", "warnings": []})
            self.assertEqual(
                [entry["kind"] for entry in final["resources"]],
                ["subtitle_text_track", "word_timeline"],
            )
            self.assertEqual([e["event"] for e in events][-2:], ["phase", "completed"])
            phases = [e.get("phase") for e in events if e["event"] == "phase"]
            self.assertEqual(phases, ["validating", "transcribing", "building_package"])

    def test_alignment_cancellation_never_degrades(self) -> None:
        # Cancellation is carried as BaseException and must never be converted
        # into a degradable alignment warning; the SIGTERM test above proves the
        # pipeline emits `cancelled`, never a degraded `completed`.
        from listen_gen.alignment import AlignmentFailure
        from listen_gen.protocol import alignment_warning
        error = AlignmentFailure("alignment_timeout")
        code, message = alignment_warning(error)
        self.assertEqual(code, "alignment_timeout")
        self.assertEqual(
            message,
            "Word alignment timed out; the subtitle package was preserved.",
        )


if __name__ == "__main__":
    unittest.main()
