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

from listen_gen.asr import (
    AsrSegment,
    AsrTranscript,
    FixtureAsrAdapter,
    package_media,
)
from listen_gen.package import ConversionError
from listen_gen.protocol import protocol_capabilities

FIXTURE_SHA = {
    "sense": "d" * 64,
    "acoustics": "e" * 64,
    "prosody": "f" * 64,
}


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


def assert_process_reaped(test: unittest.TestCase, pid: int) -> None:
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            return
        time.sleep(0.05)
    test.fail(f"provider process {pid} is still alive")


def _sha256_bytes(data: bytes) -> str:
    return f"sha256:{hashlib.sha256(data).hexdigest()}"


def read_package(output: Path) -> dict[str, object]:
    with zipfile.ZipFile(output) as archive:
        manifest = json.loads(archive.read("manifest.json"))
        documents = {
            entry["kind"]: json.loads(archive.read(entry["path"]))
            for entry in manifest["resources"]
        }
        raw_by_path = {
            entry["path"]: archive.read(entry["path"])
            for entry in manifest["resources"]
        }
    return {
        "manifest": manifest,
        "documents": documents,
        "raw_by_path": raw_by_path,
    }


class FixtureRichResourceTests(unittest.TestCase):
    media = ROOT / "tests" / "fixtures" / "sample-media.wav"
    asr_fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
    alignment_fixture = ROOT / "tests" / "fixtures" / "alignment-result.json"
    sense_fixture = ROOT / "tests" / "fixtures" / "sense-group-result.json"
    acoustics_fixture = ROOT / "tests" / "fixtures" / "acoustics-result.json"
    prosody_fixture = ROOT / "tests" / "fixtures" / "prosody-result.json"

    def base_argv(
        self,
        output: Path,
        *,
        aligner: bool = True,
        sense_groups: bool = True,
        acoustics: bool = True,
        prosody: bool = True,
        machine: bool = False,
        overrides: dict[str, Path | str | None] | None = None,
    ) -> list[str]:
        argv = [
            "package", "from-media", str(self.media),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(self.asr_fixture),
            "--title", "Rich lesson", "--media-kind", "audio",
            "--duration-ms", "2200", "--created-at-ms", "1786000000000",
        ]
        if aligner:
            argv += [
                "--aligner", "fixture",
                "--alignment-fixture", str(self.alignment_fixture),
            ]
        if sense_groups:
            argv += [
                "--sense-groups", "fixture",
                "--sense-groups-fixture", str(self.sense_fixture),
            ]
        if acoustics:
            argv += [
                "--acoustics", "fixture",
                "--acoustics-fixture", str(self.acoustics_fixture),
            ]
        if prosody:
            argv += [
                "--prosody", "fixture",
                "--prosody-fixture", str(self.prosody_fixture),
            ]
        if machine:
            argv.append("--machine-events")
        if overrides:
            for flag, value in overrides.items():
                if value is None:
                    continue
                argv[argv.index(flag) + 1] = str(value)
        return argv

    def test_fixture_rich_package_produces_five_resources_in_dependency_order(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "rich.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = read_package(output)
            self.assertEqual(
                [entry["kind"] for entry in package["manifest"]["resources"]],
                [
                    "subtitle_text_track",
                    "word_timeline",
                    "sense_group_analysis",
                    "word_acoustics",
                    "prosody_analysis",
                ],
            )
            result = json.loads(completed.stdout)
            self.assertEqual(result["rich_resources"], {
                "sense_groups": {"status": "produced", "warnings": []},
                "acoustics": {"status": "produced", "warnings": []},
                "prosody": {"status": "produced", "warnings": []},
            })

    def test_every_rich_dependency_is_the_exact_upstream_resource_id(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "rich.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = read_package(output)
            raw_by_path = package["raw_by_path"]
            manifest = package["manifest"]
            for entry in manifest["resources"]:
                document = package["documents"][entry["kind"]]
                for dependency in document["dependencies"]:
                    upstream = next(
                        item for item in manifest["resources"]
                        if item["kind"] == dependency["kind"]
                    )
                    self.assertEqual(
                        dependency["resource_id"],
                        _sha256_bytes(raw_by_path[upstream["path"]]),
                        entry["kind"],
                    )
            sense = package["documents"]["sense_group_analysis"]
            self.assertEqual(
                [item["kind"] for item in sense["dependencies"]],
                ["subtitle_text_track"],
            )
            acoustics = package["documents"]["word_acoustics"]
            self.assertEqual(
                [item["kind"] for item in acoustics["dependencies"]],
                ["word_timeline"],
            )
            prosody = package["documents"]["prosody_analysis"]
            self.assertEqual(
                [item["kind"] for item in prosody["dependencies"]],
                ["word_timeline", "word_acoustics", "sense_group_analysis"],
            )
            self.assertEqual(
                prosody["subject"]["media_fingerprint"],
                manifest["content_document"]["media_fingerprint"],
            )

    def test_sense_groups_partition_every_emitted_sentence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "rich.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = read_package(output)
            subtitle = package["documents"]["subtitle_text_track"]
            sense = package["documents"]["sense_group_analysis"]
            by_sentence: dict[str, list[dict]] = {}
            for group in sense["payload"]["groups"]:
                by_sentence.setdefault(group["sentence_id"], []).append(group)
            for sentence in subtitle["payload"]["sentences"]:
                groups = by_sentence[sentence["id"]]
                self.assertEqual(
                    [group["group_index"] for group in groups],
                    list(range(len(groups))),
                )
                self.assertEqual(groups[0]["start_token_index"], 0)
                for position, group in enumerate(groups):
                    if position == 0:
                        continue
                    self.assertEqual(
                        group["start_token_index"],
                        groups[position - 1]["end_token_index_exclusive"],
                    )
                    self.assertLessEqual(
                        group["end_token_index_exclusive"], len(sentence["tokens"])
                    )
                self.assertEqual(
                    groups[-1]["end_token_index_exclusive"], len(sentence["tokens"])
                )
                self.assertTrue(all(
                    "punctuation" in group["sources"] or "rule" in group["sources"]
                    for group in groups
                ))

    def test_word_acoustics_measurements_exactly_cover_the_word_timeline(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "rich.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = read_package(output)
            words = package["documents"]["word_timeline"]["payload"]["words"]
            measurements = package["documents"]["word_acoustics"]["payload"]["measurements"]
            self.assertEqual(
                [(m["word_ref"]["sentence_id"], m["word_ref"]["token_index"])
                 for m in measurements],
                [(w["sentence_id"], w["token_index"]) for w in words],
            )
            self.assertEqual(
                package["documents"]["word_acoustics"]["payload"]["sample_rate_hz"],
                16000,
            )
            self.assertEqual(
                package["documents"]["word_acoustics"]["payload"]["energy_baseline"],
                "sentence_median_dbfs",
            )
            self.assertEqual(
                package["documents"]["word_acoustics"]["payload"]["pitch_baseline"],
                "sentence_median_f0_hz",
            )

    def test_prosody_declares_chunks_and_qualified_anchors(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "rich.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = read_package(output)
            prosody = package["documents"]["prosody_analysis"]["payload"]
            sense = package["documents"]["sense_group_analysis"]["payload"]
            self.assertEqual(
                [(c["sentence_id"], c["start_token_index"], c["end_token_index_exclusive"])
                 for c in prosody["chunks"]],
                [(g["sentence_id"], g["start_token_index"], g["end_token_index_exclusive"])
                 for g in sense["groups"]],
            )
            words = package["documents"]["word_timeline"]["payload"]["words"]
            measurements = package["documents"]["word_acoustics"]["payload"]["measurements"]
            word_refs = {(w["sentence_id"], w["token_index"]) for w in words}
            measured_refs = {
                (m["word_ref"]["sentence_id"], m["word_ref"]["token_index"])
                for m in measurements
            }
            self.assertTrue(prosody["chunks"])
            self.assertTrue(prosody["anchors"])
            for anchor in prosody["anchors"]:
                ref = (anchor["word_ref"]["sentence_id"], anchor["word_ref"]["token_index"])
                self.assertIn(ref, word_refs)
                self.assertIn(ref, measured_refs)
                self.assertTrue(anchor["evidence"])
                self.assertEqual(len(anchor["evidence"]), len(set(anchor["evidence"])))
                self.assertIn("energy", anchor["evidence"])
                self.assertTrue(0 <= anchor["confidence"] <= 1)
                self.assertTrue(0 <= anchor["realized_prominence"] <= 1)
                self.assertNotIn("syllable_index", anchor)

    def test_rich_provenance_is_stable_and_path_free(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "rich.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = read_package(output)
            sense = package["documents"]["sense_group_analysis"]
            acoustics = package["documents"]["word_acoustics"]
            prosody = package["documents"]["prosody_analysis"]
            self.assertEqual(sense["provenance"]["tool"], {
                "id": "listen-gen.sense-groups", "version": "0.3.0",
            })
            self.assertEqual(sense["provenance"]["provider"], {
                "id": "fixture-sense-groups", "version": "1",
            })
            self.assertEqual(sense["provenance"]["config_sha256"],
                             "sha256:" + FIXTURE_SHA["sense"])
            self.assertEqual(acoustics["provenance"]["tool"], {
                "id": "listen-gen.acoustics", "version": "0.3.0",
            })
            self.assertEqual(acoustics["provenance"]["config_sha256"],
                             "sha256:" + FIXTURE_SHA["acoustics"])
            self.assertEqual(prosody["provenance"]["tool"], {
                "id": "listen-gen.prosody", "version": "0.3.0",
            })
            self.assertEqual(prosody["provenance"]["config_sha256"],
                             "sha256:" + FIXTURE_SHA["prosody"])
            package_bytes = output.read_bytes()
            for forbidden in (
                str(self.media), str(self.asr_fixture),
                str(self.alignment_fixture), str(self.sense_fixture),
                str(self.acoustics_fixture), str(self.prosody_fixture),
            ):
                self.assertNotIn(forbidden.encode(), package_bytes)

    def test_rich_package_is_deterministic_and_path_independent(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            packages = []
            for index in (1, 2):
                run_dir = root / f"run-{index}"
                run_dir.mkdir()
                overrides = {}
                for flag, fixture, name in (
                    ("--alignment-fixture", self.alignment_fixture, "alignment.json"),
                    ("--sense-groups-fixture", self.sense_fixture, "sense.json"),
                    ("--acoustics-fixture", self.acoustics_fixture, "acoustics.json"),
                    ("--prosody-fixture", self.prosody_fixture, "prosody.json"),
                ):
                    copy = run_dir / name
                    copy.write_text(fixture.read_text(encoding="utf-8"))
                    overrides[flag] = copy
                output = run_dir / "rich.listenpkg"
                completed = run_cli(self.base_argv(output, overrides=overrides))
                self.assertEqual(completed.returncode, 0, completed.stderr)
                packages.append(output.read_bytes())
            self.assertEqual(packages[0], packages[1])

    def test_core_inspector_accepts_full_rich_fixture(self) -> None:
        checkout = os.environ.get("LISTEN_CORE_CHECKOUT")
        if checkout is None:
            self.skipTest("LISTEN_CORE_CHECKOUT is not set")
        core = Path(checkout)
        if not (core / "crates" / "content-package" / "Cargo.toml").is_file():
            self.fail("LISTEN_CORE_CHECKOUT does not contain crates/content-package")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "rich.listenpkg"
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

    def test_no_phone_resource_or_phone_evidence_is_emitted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "rich.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = read_package(output)
            kinds = [entry["kind"] for entry in package["manifest"]["resources"]]
            self.assertNotIn("phone_timeline", kinds)
            self.assertNotIn("phone-timeline.json", package["raw_by_path"])
            for document in package["documents"].values():
                self.assertNotIn("phones", json.dumps(document))
                self.assertNotIn("phone_set", json.dumps(document))
            self.assertNotIn(b"phone-timeline", output.read_bytes())

    def test_capabilities_advertise_rich_stages_and_optional_phone(self) -> None:
        capabilities = protocol_capabilities()
        rich = capabilities["rich_resources"]
        for stage in ("sense_groups", "acoustics", "prosody"):
            self.assertEqual(rich[stage]["optional"], True)
            self.assertEqual(rich[stage]["degradation"], "preserve_upstream")
            self.assertEqual(
                rich[stage]["adapters"], ["fixture", "command", "baseline"]
            )
            self.assertIn(f"{stage}_qualification_failed", rich[stage]["warning_codes"])
            self.assertIn(f"{stage}_upstream_missing", rich[stage]["warning_codes"])
        self.assertEqual(capabilities["phone"], {
            "production": "optional_audio_backed",
            "unselected": "abstain",
            "text_derived": False,
        })
        self.assertIn("analyzing_sense_groups", capabilities["phases"])
        self.assertIn("measuring_acoustics", capabilities["phases"])
        self.assertIn("analyzing_prosody", capabilities["phases"])
        self.assertIn("analyzing_phones", capabilities["phases"])


class RichDegradationTests(unittest.TestCase):
    media = ROOT / "tests" / "fixtures" / "sample-media.wav"
    asr_fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
    alignment_fixture = ROOT / "tests" / "fixtures" / "alignment-result.json"
    sense_fixture = ROOT / "tests" / "fixtures" / "sense-group-result.json"
    acoustics_fixture = ROOT / "tests" / "fixtures" / "acoustics-result.json"
    prosody_fixture = ROOT / "tests" / "fixtures" / "prosody-result.json"

    def write_fixture(self, directory: Path, name: str, document: object) -> Path:
        path = directory / name
        path.write_text(json.dumps(document), encoding="utf-8")
        return path

    def _mutate(self, fixture: Path, mutate) -> Path:
        value = json.loads(fixture.read_text(encoding="utf-8"))
        mutate(value)
        return self.write_fixture(Path(tempfile.mkdtemp()), fixture.name, value)

    def test_sense_group_failure_preserves_subtitle_and_word_timeline(self) -> None:
        fixture = self._mutate(self.sense_fixture, lambda value: value["groups"].pop(0))
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "degraded.listenpkg"
            argv = [
                "package", "from-media", str(self.media),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(self.asr_fixture),
                "--aligner", "fixture", "--alignment-fixture", str(self.alignment_fixture),
                "--sense-groups", "fixture", "--sense-groups-fixture", str(fixture),
                "--acoustics", "fixture", "--acoustics-fixture", str(self.acoustics_fixture),
                "--prosody", "fixture", "--prosody-fixture", str(self.prosody_fixture),
                "--title", "Degraded lesson", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1786000000000",
            ]
            completed = run_cli(argv)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(result["rich_resources"]["sense_groups"]["status"], "degraded")
            self.assertEqual(
                result["rich_resources"]["sense_groups"]["warnings"][0]["code"],
                "sense_groups_qualification_failed",
            )
            # The prosody fixture declares uses_sense_groups=true, so without
            # the exact Sense Group evidence prosody degrades as well.
            self.assertEqual(result["rich_resources"]["prosody"]["status"], "degraded")
            self.assertEqual(
                result["rich_resources"]["prosody"]["warnings"][0]["code"],
                "prosody_upstream_missing",
            )
            package = read_package(output)
            self.assertEqual(
                [entry["kind"] for entry in package["manifest"]["resources"]],
                ["subtitle_text_track", "word_timeline", "word_acoustics"],
            )
            self.assertNotIn(str(fixture).encode(), output.read_bytes())

    def test_acoustics_failure_degrades_prosody_and_preserves_upstream(self) -> None:
        fixture = self._mutate(
            self.acoustics_fixture, lambda value: value["measurements"].pop(0)
        )
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "degraded.listenpkg"
            argv = [
                "package", "from-media", str(self.media),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(self.asr_fixture),
                "--aligner", "fixture", "--alignment-fixture", str(self.alignment_fixture),
                "--sense-groups", "fixture", "--sense-groups-fixture", str(self.sense_fixture),
                "--acoustics", "fixture", "--acoustics-fixture", str(fixture),
                "--prosody", "fixture", "--prosody-fixture", str(self.prosody_fixture),
                "--title", "Degraded lesson", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1786000000000",
            ]
            completed = run_cli(argv)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(result["rich_resources"]["acoustics"]["status"], "degraded")
            self.assertEqual(
                result["rich_resources"]["acoustics"]["warnings"][0]["code"],
                "acoustics_qualification_failed",
            )
            self.assertEqual(result["rich_resources"]["prosody"]["status"], "degraded")
            self.assertEqual(
                result["rich_resources"]["prosody"]["warnings"][0]["code"],
                "prosody_upstream_missing",
            )
            package = read_package(output)
            self.assertEqual(
                [entry["kind"] for entry in package["manifest"]["resources"]],
                ["subtitle_text_track", "word_timeline", "sense_group_analysis"],
            )

    def test_prosody_declared_sense_group_use_without_groups_degrades(self) -> None:
        # The prosody fixture declares uses_sense_groups=true, but no
        # sense-group stage is selected, so the exact evidence is unavailable.
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "degraded.listenpkg"
            argv = [
                "package", "from-media", str(self.media),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(self.asr_fixture),
                "--aligner", "fixture", "--alignment-fixture", str(self.alignment_fixture),
                "--acoustics", "fixture", "--acoustics-fixture", str(self.acoustics_fixture),
                "--prosody", "fixture", "--prosody-fixture", str(self.prosody_fixture),
                "--title", "Degraded lesson", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1786000000000",
            ]
            completed = run_cli(argv)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(result["rich_resources"]["prosody"]["status"], "degraded")
            self.assertEqual(
                result["rich_resources"]["prosody"]["warnings"][0]["code"],
                "prosody_upstream_missing",
            )
            package = read_package(output)
            self.assertEqual(
                [entry["kind"] for entry in package["manifest"]["resources"]],
                ["subtitle_text_track", "word_timeline", "word_acoustics"],
            )

    def test_acoustics_without_word_timeline_degrades_honestly(self) -> None:
        class NoWordsAdapter:
            def transcribe(self, media_path: Path) -> AsrTranscript:
                segment = AsrSegment(100, 1200, "Listen carefully", "Listen carefully", ())
                return AsrTranscript(
                    "en-US", (segment,), "fixture-asr", "1",
                    "fixture-model", "2026-08", "sha256:" + "a" * 64,
                )

        from listen_gen.rich import FixtureAcousticsAdapter

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            media = root / "media.wav"
            media.write_bytes(self.media.read_bytes())
            output = root / "degraded.listenpkg"
            result = package_media(
                media,
                output,
                NoWordsAdapter(),
                title="No words",
                media_kind="audio",
                duration_ms=2200,
                created_at_ms=1786000000000,
                acoustics_extractor=FixtureAcousticsAdapter(self.acoustics_fixture),
            )
            self.assertEqual(result["rich_resources"]["acoustics"]["status"], "degraded")
            self.assertEqual(
                result["rich_resources"]["acoustics"]["warnings"][0]["code"],
                "acoustics_upstream_missing",
            )
            package = read_package(output)
            self.assertEqual(
                [entry["kind"] for entry in package["manifest"]["resources"]],
                ["subtitle_text_track"],
            )

    def test_sense_groups_still_produced_without_word_timeline(self) -> None:
        class NoWordsAdapter:
            def transcribe(self, media_path: Path) -> AsrTranscript:
                first = AsrSegment(
                    100, 1200, "Listen, carefully!", "Listen, carefully!", ()
                )
                second = AsrSegment(1300, 2100, "Words matter.", "Words matter.", ())
                return AsrTranscript(
                    "en-US", (first, second), "fixture-asr", "1", None, None, None,
                )

        from listen_gen.rich import FixtureSenseGroupAdapter

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            media = root / "media.wav"
            media.write_bytes(self.media.read_bytes())
            output = root / "sense-only.listenpkg"
            result = package_media(
                media,
                output,
                NoWordsAdapter(),
                title="Sense only",
                media_kind="audio",
                duration_ms=2200,
                created_at_ms=1786000000000,
                sense_analyzer=FixtureSenseGroupAdapter(self.sense_fixture),
            )
            self.assertEqual(
                result["rich_resources"]["sense_groups"]["status"], "produced"
            )
            package = read_package(output)
            self.assertEqual(
                [entry["kind"] for entry in package["manifest"]["resources"]],
                ["subtitle_text_track", "sense_group_analysis"],
            )

    def test_media_mutation_during_rich_stage_is_never_degradation(self) -> None:
        from listen_gen.rich import FixtureAcousticsAdapter

        class MutatingExtractor:
            def __init__(self, wrapped):
                self.wrapped = wrapped

            def measure(self, request):
                result = self.wrapped.measure(request)
                media = Path(request.audio_path)
                media.write_bytes(media.read_bytes() + b"changed")
                return result

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            media = root / "media.wav"
            media.write_bytes(self.media.read_bytes())
            output = root / "existing.listenpkg"
            original = b"existing-package-must-survive"
            output.write_bytes(original)
            with self.assertRaisesRegex(ConversionError, "changed during processing"):
                package_media(
                    media,
                    output,
                    FixtureAsrAdapter(self.asr_fixture),
                    title="Mutating",
                    media_kind="audio",
                    duration_ms=2200,
                    created_at_ms=1786000000000,
                    acoustics_extractor=MutatingExtractor(
                        FixtureAcousticsAdapter(self.acoustics_fixture)
                    ),
                )
            self.assertEqual(output.read_bytes(), original)


class CommandRichStageTests(unittest.TestCase):
    media = ROOT / "tests" / "fixtures" / "single-audio-media.json"
    asr_fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
    helper = ROOT / "tests" / "fixtures" / "fake_rich_command.py"
    ffprobe = ROOT / "tests" / "fixtures" / "fake_ffprobe.py"
    ffmpeg = ROOT / "tests" / "fixtures" / "fake_ffmpeg.py"

    def rich_env(
        self, stage: str, *, mode: str = "success", observed: Path | None = None
    ) -> dict[str, str]:
        env = _env()
        env["LISTEN_GEN_FAKE_RICH_STAGE"] = stage
        env["LISTEN_GEN_FAKE_RICH_MODE"] = mode
        if observed is not None:
            env["LISTEN_GEN_FAKE_RICH_OBSERVED"] = str(observed)
        return env

    def test_command_sense_groups_receives_exact_subtitle_payload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            observed = root / "observed.json"
            output = root / "sense.listenpkg"
            argv = [
                "package", "from-media", str(self.media),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(self.asr_fixture),
                "--sense-groups", "command",
                "--sense-groups-command", sys.executable,
                "--sense-groups-command-arg", str(self.helper),
                "--sense-groups-command-arg", "{input}",
                "--sense-groups-command-timeout-seconds", "10",
                "--title", "Command sense groups", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1786000000000",
            ]
            completed = run_cli(argv, env=self.rich_env("sense-groups", observed=observed))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = read_package(output)
            self.assertEqual(
                [entry["kind"] for entry in package["manifest"]["resources"]],
                ["subtitle_text_track", "word_timeline", "sense_group_analysis"],
            )
            sense = package["documents"]["sense_group_analysis"]
            self.assertEqual(sense["provenance"]["provider"], {
                "id": "command-sense-groups", "version": "1",
            })
            from listen_gen.command_identity import (
                command_identity_sha256,
                compose_config_sha256,
            )
            command_identity = command_identity_sha256(
                sys.executable, (str(self.helper), "{input}"),
                frozenset({"{input}"}), 10.0,
            )
            self.assertEqual(
                sense["provenance"]["config_sha256"],
                compose_config_sha256("sha256:" + "1" * 64, command_identity),
            )
            observation = json.loads(observed.read_text(encoding="utf-8"))
            self.assertEqual(observation["stage"], "sense-groups")

    def test_command_acoustics_receives_normalized_audio_and_timeline(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            observed = root / "observed.json"
            output = root / "acoustics.listenpkg"
            argv = [
                "package", "from-media", str(self.media),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(self.asr_fixture),
                "--acoustics", "command",
                "--acoustics-command", sys.executable,
                "--acoustics-command-arg", str(self.helper),
                "--acoustics-command-arg", "{media}",
                "--acoustics-command-arg", "{timeline}",
                "--acoustics-command-timeout-seconds", "10",
                "--ffprobe-command", str(self.ffprobe),
                "--ffmpeg-command", str(self.ffmpeg),
                "--title", "Command acoustics", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1786000000000",
            ]
            completed = run_cli(argv, env=self.rich_env("acoustics", observed=observed))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = read_package(output)
            self.assertEqual(
                [entry["kind"] for entry in package["manifest"]["resources"]],
                ["subtitle_text_track", "word_timeline", "word_acoustics"],
            )
            acoustics = package["documents"]["word_acoustics"]
            self.assertEqual(acoustics["provenance"]["provider"], {
                "id": "command-acoustics", "version": "1",
            })
            from listen_gen.command_identity import (
                command_identity_sha256,
                compose_config_sha256,
            )
            from listen_gen.rich import _compose_acoustics_config_sha256
            command_identity = command_identity_sha256(
                sys.executable,
                (str(self.helper), "{media}", "{timeline}"),
                frozenset({"{media}", "{timeline}"}),
                10.0,
            )
            provider_config = compose_config_sha256(
                "sha256:" + "2" * 64, command_identity
            )
            self.assertEqual(
                acoustics["provenance"]["config_sha256"],
                _compose_acoustics_config_sha256(provider_config, 1),
            )
            observation = json.loads(observed.read_text(encoding="utf-8"))
            self.assertEqual(observation["stage"], "acoustics")
            self.assertEqual(Path(observation["media_path"]).name, "normalized.wav")
            self.assertFalse(Path(observation["media_path"]).exists())
            self.assertNotIn(str(self.ffprobe), output.read_text("latin-1"))
            self.assertNotIn(str(self.ffmpeg), output.read_text("latin-1"))

    def test_command_prosody_receives_exact_evidence_input(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            observed = root / "observed.json"
            output = root / "prosody.listenpkg"
            argv = [
                "package", "from-media", str(self.media),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(self.asr_fixture),
                "--acoustics", "command",
                "--acoustics-command", sys.executable,
                "--acoustics-command-arg", str(self.helper),
                "--acoustics-command-arg", "{media}",
                "--acoustics-command-arg", "{timeline}",
                "--acoustics-command-timeout-seconds", "10",
                "--prosody", "command",
                "--prosody-command", sys.executable,
                "--prosody-command-arg", str(self.helper),
                "--prosody-command-arg", "{input}",
                "--prosody-command-timeout-seconds", "10",
                "--ffprobe-command", str(self.ffprobe),
                "--ffmpeg-command", str(self.ffmpeg),
                "--title", "Command prosody", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1786000000000",
            ]
            completed = run_cli(argv, env=self.rich_env("prosody", observed=observed))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            package = read_package(output)
            self.assertEqual(
                [entry["kind"] for entry in package["manifest"]["resources"]],
                ["subtitle_text_track", "word_timeline", "word_acoustics", "prosody_analysis"],
            )
            prosody = package["documents"]["prosody_analysis"]
            self.assertEqual(prosody["provenance"]["provider"], {
                "id": "command-prosody", "version": "1",
            })
            from listen_gen.command_identity import (
                command_identity_sha256,
                compose_config_sha256,
            )
            command_identity = command_identity_sha256(
                sys.executable, (str(self.helper), "{input}"),
                frozenset({"{input}"}), 10.0,
            )
            self.assertEqual(
                prosody["provenance"]["config_sha256"],
                compose_config_sha256("sha256:" + "3" * 64, command_identity),
            )

    def test_command_mutation_degrades_without_leaking_paths(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            helper = root / "provider.py"
            helper.write_bytes(self.helper.read_bytes())
            output = root / "mutated.listenpkg"
            argv = [
                "package", "from-media", str(self.media),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(self.asr_fixture),
                "--sense-groups", "command",
                "--sense-groups-command", sys.executable,
                "--sense-groups-command-arg", str(helper),
                "--sense-groups-command-arg", "{input}",
                "--sense-groups-command-timeout-seconds", "10",
                "--title", "Mutation", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1786000000000",
            ]
            completed = run_cli(
                argv, env=self.rich_env("sense-groups", mode="mutate-self")
            )
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            warning = result["rich_resources"]["sense_groups"]["warnings"][0]
            self.assertEqual(warning["code"], "sense_groups_failed")
            self.assertNotIn(str(helper), completed.stdout)

    def test_command_sense_groups_failure_modes_degrade(self) -> None:
        cases = [
            ("fail", "sense_groups_failed"),
            ("invalid-json", "sense_groups_output_invalid"),
            ("flood", "sense_groups_output_too_large"),
        ]
        for mode, expected in cases:
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                output = root / "degraded.listenpkg"
                argv = [
                    "package", "from-media", str(self.media),
                    "--output", str(output),
                    "--provider", "fixture", "--fixture", str(self.asr_fixture),
                    "--sense-groups", "command",
                    "--sense-groups-command", sys.executable,
                    "--sense-groups-command-arg", str(self.helper),
                    "--sense-groups-command-arg", "{input}",
                    "--sense-groups-command-timeout-seconds", "10",
                    "--title", "Command sense groups", "--media-kind", "audio",
                    "--duration-ms", "2200", "--created-at-ms", "1786000000000",
                ]
                completed = run_cli(argv, env=self.rich_env("sense-groups", mode=mode))
                self.assertEqual(completed.returncode, 0, completed.stderr)
                result = json.loads(completed.stdout)
                self.assertEqual(
                    result["rich_resources"]["sense_groups"]["warnings"][0]["code"],
                    expected,
                )
                self.assertNotIn("rich-secret-must-not-leak", completed.stdout)
                self.assertNotIn("rich-secret-must-not-leak", completed.stderr)
                self.assertNotIn("must-not-leak", completed.stdout)
                package = read_package(output)
                self.assertEqual(
                    [entry["kind"] for entry in package["manifest"]["resources"]],
                    ["subtitle_text_track", "word_timeline"],
                )

    def test_command_acoustics_timeout_degrades_and_reaps(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "degraded.listenpkg"
            argv = [
                "package", "from-media", str(self.media),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(self.asr_fixture),
                "--acoustics", "command",
                "--acoustics-command", sys.executable,
                "--acoustics-command-arg", str(self.helper),
                "--acoustics-command-arg", "{media}",
                "--acoustics-command-arg", "{timeline}",
                "--acoustics-command-timeout-seconds", "0.3",
                "--ffprobe-command", str(self.ffprobe),
                "--ffmpeg-command", str(self.ffmpeg),
                "--title", "Command acoustics", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1786000000000",
            ]
            completed = run_cli(argv, env=self.rich_env("acoustics", mode="sleep"))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(result["rich_resources"]["acoustics"]["status"], "degraded")
            self.assertEqual(
                result["rich_resources"]["acoustics"]["warnings"][0]["code"],
                "acoustics_timeout",
            )
            package = read_package(output)
            self.assertEqual(
                [entry["kind"] for entry in package["manifest"]["resources"]],
                ["subtitle_text_track", "word_timeline"],
            )

    def test_sense_group_and_prosody_timeouts_reap_and_redact(self) -> None:
        for stage in ("sense-groups", "prosody"):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                observed = root / "observed.json"
                output = root / f"{stage}.listenpkg"
                argv = [
                    "package", "from-media", str(self.media),
                    "--output", str(output),
                    "--provider", "fixture", "--fixture", str(self.asr_fixture),
                ]
                if stage == "sense-groups":
                    argv.extend([
                        "--sense-groups", "command",
                        "--sense-groups-command", sys.executable,
                        "--sense-groups-command-arg", str(self.helper),
                        "--sense-groups-command-arg", "{input}",
                        "--sense-groups-command-timeout-seconds", "0.3",
                    ])
                    outcome, code = "sense_groups", "sense_groups_timeout"
                else:
                    argv.extend([
                        "--acoustics", "fixture",
                        "--acoustics-fixture", str(ROOT / "tests/fixtures/acoustics-result.json"),
                        "--prosody", "command",
                        "--prosody-command", sys.executable,
                        "--prosody-command-arg", str(self.helper),
                        "--prosody-command-arg", "{input}",
                        "--prosody-command-timeout-seconds", "0.3",
                    ])
                    outcome, code = "prosody", "prosody_timeout"
                argv.extend([
                    "--title", "Timeout", "--media-kind", "audio",
                    "--duration-ms", "2200", "--created-at-ms", "1786000000000",
                ])
                completed = run_cli(
                    argv,
                    env=self.rich_env(stage, mode="hang", observed=observed),
                )
                self.assertEqual(completed.returncode, 0, completed.stderr)
                result = json.loads(completed.stdout)
                self.assertEqual(
                    result["rich_resources"][outcome]["warnings"][0]["code"], code
                )
                self.assertNotIn(str(self.helper), completed.stdout)
                pid = int(json.loads(observed.read_text(encoding="utf-8"))["pid"])
                assert_process_reaped(self, pid)

    def test_command_stage_missing_placeholder_is_invalid_arguments(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            output = root / "x.listenpkg"
            argv = [
                "package", "from-media", str(self.media),
                "--output", str(output),
                "--provider", "fixture", "--fixture", str(self.asr_fixture),
                "--acoustics", "command",
                "--acoustics-command", sys.executable,
                "--acoustics-command-arg", str(self.helper),
                "--acoustics-command-arg", "{media}",
                "--acoustics-command-timeout-seconds", "10",
                "--ffprobe-command", str(self.ffprobe),
                "--ffmpeg-command", str(self.ffmpeg),
                "--title", "Command acoustics", "--media-kind", "audio",
                "--duration-ms", "2200", "--created-at-ms", "1786000000000",
                "--machine-events",
            ]
            completed = run_cli(argv, env=self.rich_env("acoustics"))
            self.assertEqual(completed.returncode, 2)
            events = parse_events(completed.stdout)
            self.assertEqual(events[-1]["event"], "failed")
            self.assertEqual(events[-1]["code"], "invalid_arguments")


class MachineProtocolRichTests(unittest.TestCase):
    media = ROOT / "tests" / "fixtures" / "sample-media.wav"
    asr_fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
    alignment_fixture = ROOT / "tests" / "fixtures" / "alignment-result.json"
    sense_fixture = ROOT / "tests" / "fixtures" / "sense-group-result.json"
    acoustics_fixture = ROOT / "tests" / "fixtures" / "acoustics-result.json"
    prosody_fixture = ROOT / "tests" / "fixtures" / "prosody-result.json"

    def base_argv(self, output: Path) -> list[str]:
        return [
            "package", "from-media", str(self.media),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(self.asr_fixture),
            "--aligner", "fixture", "--alignment-fixture", str(self.alignment_fixture),
            "--sense-groups", "fixture", "--sense-groups-fixture", str(self.sense_fixture),
            "--acoustics", "fixture", "--acoustics-fixture", str(self.acoustics_fixture),
            "--prosody", "fixture", "--prosody-fixture", str(self.prosody_fixture),
            "--title", "Rich machine lesson", "--media-kind", "audio",
            "--duration-ms", "2200", "--created-at-ms", "1786000000000",
            "--machine-events",
        ]

    def test_machine_events_rich_phases_and_completed_payload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "rich.listenpkg"
            completed = run_cli(self.base_argv(output))
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            self.assertEqual(
                [event["event"] for event in events],
                ["protocol", "started", "phase", "phase", "phase", "phase",
                 "phase", "phase", "phase", "completed"],
            )
            self.assertEqual(
                [event["phase"] for event in events if event["event"] == "phase"],
                [
                    "validating", "transcribing", "aligning",
                    "analyzing_sense_groups", "measuring_acoustics",
                    "analyzing_prosody", "building_package",
                ],
            )
            final = [event for event in events if event["event"] == "completed"][0]
            self.assertEqual(final["rich_resources"], {
                "sense_groups": {"status": "produced", "warnings": []},
                "acoustics": {"status": "produced", "warnings": []},
                "prosody": {"status": "produced", "warnings": []},
            })
            self.assertEqual(
                [entry["kind"] for entry in final["resources"]],
                [
                    "subtitle_text_track", "word_timeline",
                    "sense_group_analysis", "word_acoustics", "prosody_analysis",
                ],
            )
            self.assertEqual(
                [event["sequence"] for event in events],
                list(range(len(events))),
            )

    def test_machine_degraded_completed_carries_typed_rich_warning(self) -> None:
        value = json.loads(self.prosody_fixture.read_text(encoding="utf-8"))
        # Token 1 of sentence 0 is punctuation, never a word-timeline word.
        value["anchors"][0]["token_index"] = 1
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bad_prosody = root / "bad-prosody.json"
            bad_prosody.write_text(json.dumps(value), encoding="utf-8")
            output = root / "degraded.listenpkg"
            argv = self.base_argv(output)
            argv[argv.index("--prosody-fixture") + 1] = str(bad_prosody)
            completed = run_cli(argv)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            events = parse_events(completed.stdout)
            terminals = [e for e in events if e["event"] in TERMINAL_EVENTS]
            self.assertEqual(len(terminals), 1)
            final = terminals[0]
            self.assertEqual(final["event"], "completed")
            self.assertEqual(final["rich_resources"]["prosody"]["status"], "degraded")
            self.assertEqual(
                final["rich_resources"]["prosody"]["warnings"][0]["code"],
                "prosody_qualification_failed",
            )
            self.assertEqual(
                [entry["kind"] for entry in final["resources"]],
                ["subtitle_text_track", "word_timeline", "sense_group_analysis", "word_acoustics"],
            )

    def test_missing_rich_fixture_is_invalid_arguments(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "x.listenpkg"
            argv = self.base_argv(output)
            argv[argv.index("--sense-groups-fixture") + 1] = str(
                Path(directory) / "missing.json"
            )
            completed = run_cli(argv)
            self.assertEqual(completed.returncode, 2)
            events = parse_events(completed.stdout)
            self.assertEqual(events[-1]["event"], "failed")
            self.assertEqual(events[-1]["code"], "invalid_arguments")
            self.assertNotIn("missing.json", completed.stdout)


class RichCancellationTests(unittest.TestCase):
    media = ROOT / "tests" / "fixtures" / "single-audio-media.json"
    asr_fixture = ROOT / "tests" / "fixtures" / "sample.asr.json"
    helper = ROOT / "tests" / "fixtures" / "fake_rich_command.py"
    ffprobe = ROOT / "tests" / "fixtures" / "fake_ffprobe.py"
    ffmpeg = ROOT / "tests" / "fixtures" / "fake_ffmpeg.py"

    def base_argv(self, output: Path, timeout: str = "600") -> list[str]:
        return [
            "package", "from-media", str(self.media),
            "--output", str(output),
            "--provider", "fixture", "--fixture", str(self.asr_fixture),
            "--acoustics", "command",
            "--acoustics-command", sys.executable,
            "--acoustics-command-arg", str(self.helper),
            "--acoustics-command-arg", "{media}",
            "--acoustics-command-arg", "{timeline}",
            "--acoustics-command-timeout-seconds", timeout,
            "--ffprobe-command", str(self.ffprobe),
            "--ffmpeg-command", str(self.ffmpeg),
            "--title", "Cancellation lesson", "--media-kind", "audio",
            "--duration-ms", "2200", "--created-at-ms", "1786000000000",
            "--machine-events",
        ]

    def test_sigterm_during_acoustics_cancels_and_preserves_upstream(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            observed = root / "observed.json"
            output = root / "cancelled.listenpkg"
            output.write_bytes(b"sentinel-must-survive")
            process = subprocess.Popen(
                [sys.executable, "-m", "listen_gen", *self.base_argv(output)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                env=_env(
                    LISTEN_GEN_FAKE_RICH_STAGE="acoustics",
                    LISTEN_GEN_FAKE_RICH_MODE="hang",
                    LISTEN_GEN_FAKE_RICH_OBSERVED=str(observed),
                ),
            )
            deadline = time.monotonic() + 30
            while not observed.is_file() and time.monotonic() < deadline:
                if process.poll() is not None:
                    break
                time.sleep(0.05)
            self.assertTrue(observed.is_file(), "acoustics stage did not start")
            data = json.loads(observed.read_text(encoding="utf-8"))
            acoustics_pid = int(data["pid"])
            process.send_signal(signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=60)
            self.assertEqual(process.returncode, 130, stderr)
            events = parse_events(stdout)
            terminals = [e for e in events if e["event"] in TERMINAL_EVENTS]
            self.assertEqual(len(terminals), 1)
            self.assertEqual(terminals[0]["event"], "cancelled")
            self.assertNotIn("completed", [e["event"] for e in events])
            self.assertNotIn("failed", [e["event"] for e in events])
            self.assertEqual(output.read_bytes(), b"sentinel-must-survive")
            assert_process_reaped(self, acoustics_pid)

    def test_sigterm_during_sense_groups_and_prosody_reaps_provider(self) -> None:
        for stage in ("sense-groups", "prosody"):
            with self.subTest(stage=stage), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                observed = root / "observed.json"
                output = root / "cancelled.listenpkg"
                output.write_bytes(b"sentinel-must-survive")
                argv = [
                    "package", "from-media", str(self.media),
                    "--output", str(output),
                    "--provider", "fixture", "--fixture", str(self.asr_fixture),
                ]
                if stage == "sense-groups":
                    argv.extend([
                        "--sense-groups", "command",
                        "--sense-groups-command", sys.executable,
                        "--sense-groups-command-arg", str(self.helper),
                        "--sense-groups-command-arg", "{input}",
                        "--sense-groups-command-timeout-seconds", "600",
                    ])
                else:
                    argv.extend([
                        "--acoustics", "fixture",
                        "--acoustics-fixture", str(ROOT / "tests/fixtures/acoustics-result.json"),
                        "--prosody", "command",
                        "--prosody-command", sys.executable,
                        "--prosody-command-arg", str(self.helper),
                        "--prosody-command-arg", "{input}",
                        "--prosody-command-timeout-seconds", "600",
                    ])
                argv.extend([
                    "--title", "Cancellation lesson", "--media-kind", "audio",
                    "--duration-ms", "2200", "--created-at-ms", "1786000000000",
                    "--machine-events",
                ])
                process = subprocess.Popen(
                    [sys.executable, "-m", "listen_gen", *argv],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    env=_env(
                        LISTEN_GEN_FAKE_RICH_STAGE=stage,
                        LISTEN_GEN_FAKE_RICH_MODE="hang",
                        LISTEN_GEN_FAKE_RICH_OBSERVED=str(observed),
                    ),
                )
                deadline = time.monotonic() + 30
                while not observed.is_file() and time.monotonic() < deadline:
                    if process.poll() is not None:
                        break
                    time.sleep(0.05)
                self.assertTrue(observed.is_file(), f"{stage} stage did not start")
                provider_pid = int(
                    json.loads(observed.read_text(encoding="utf-8"))["pid"]
                )
                process.send_signal(signal.SIGTERM)
                stdout, stderr = process.communicate(timeout=60)
                self.assertEqual(process.returncode, 130, stderr)
                terminals = [
                    event for event in parse_events(stdout)
                    if event["event"] in TERMINAL_EVENTS
                ]
                self.assertEqual([event["event"] for event in terminals], ["cancelled"])
                self.assertEqual(output.read_bytes(), b"sentinel-must-survive")
                assert_process_reaped(self, provider_pid)


class RichStageArgumentValidationTests(unittest.TestCase):
    def test_rich_command_constructor_validation(self) -> None:
        from listen_gen.package import ConversionError
        from listen_gen.rich import (
            CommandAcousticsAdapter,
            CommandProsodyAdapter,
            CommandSenseGroupAdapter,
        )
        with self.assertRaisesRegex(ConversionError, "non-empty"):
            CommandSenseGroupAdapter("", ["{input}"], 1)
        with self.assertRaisesRegex(ConversionError, "exactly one"):
            CommandSenseGroupAdapter("tool", [], 1)
        with self.assertRaisesRegex(ConversionError, "positive"):
            CommandSenseGroupAdapter("tool", ["{input}"], 0)
        with self.assertRaisesRegex(ConversionError, "exactly one"):
            CommandAcousticsAdapter("tool", ["{media}"], 1)
        with self.assertRaisesRegex(ConversionError, "exactly one"):
            CommandProsodyAdapter("tool", ["{input}", "{input}"], 1)

    def test_rich_warning_codes_are_stable(self) -> None:
        from listen_gen.protocol import RICH_WARNING_MESSAGES, RichStageFailure
        for stage in ("sense_groups", "acoustics", "prosody"):
            for code in (
                "start_failed", "timeout", "failed", "output_invalid",
                "output_too_large", "qualification_failed", "upstream_missing",
            ):
                full = f"{stage}_{code}"
                failure = RichStageFailure(stage, code)
                self.assertEqual(failure.code, full)
                self.assertEqual(str(failure), RICH_WARNING_MESSAGES[full])
                self.assertNotIn("path", str(failure))
                self.assertNotIn("command", str(failure))


if __name__ == "__main__":
    unittest.main()
