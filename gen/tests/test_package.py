from __future__ import annotations

import json
import hashlib
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "src"))

from listen_gen.cli import main
from listen_gen.package import package_from_lltimeline


class PackageFromLLTimelineTests(unittest.TestCase):
    fixture = ROOT / "tests" / "fixtures" / "sample.lltimeline.json"

    def test_build_is_deterministic_and_dependencies_are_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            first = Path(directory) / "first.listenpkg"
            second = Path(directory) / "second.listenpkg"
            one = package_from_lltimeline(self.fixture, first)
            two = package_from_lltimeline(self.fixture, second)
            self.assertEqual(first.read_bytes(), second.read_bytes())
            self.assertEqual(one["package_sha256"], two["package_sha256"])

            with zipfile.ZipFile(first) as archive:
                self.assertEqual(archive.namelist()[0], "manifest.json")
                self.assertEqual(archive.namelist()[1:], sorted(archive.namelist()[1:]))
                self.assertTrue(all(item.date_time == (1980, 1, 1, 0, 0, 0) for item in archive.infolist()))
                self.assertTrue(all(item.compress_type == zipfile.ZIP_STORED for item in archive.infolist()))
                manifest = json.loads(archive.read("manifest.json"))
                ids = {item["resource_id"] for item in manifest["resources"]}
                for item in manifest["resources"]:
                    body = archive.read(item["path"])
                    self.assertEqual(item["size_bytes"], len(body))
                    self.assertEqual(item["resource_id"], f"sha256:{hashlib.sha256(body).hexdigest()}")
                    envelope = json.loads(body)
                    for dependency in envelope["dependencies"]:
                        self.assertIn(dependency["resource_id"], ids)

    def test_strips_local_state_and_unknown_artifact_payloads(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson.listenpkg"
            result = package_from_lltimeline(self.fixture, output)
            package_bytes = output.read_bytes()
            self.assertNotIn(b"/private/user/video.mp4", package_bytes)
            self.assertNotIn(b"/private/tmp/audio.wav", package_bytes)
            self.assertNotIn(b"must-not-leak", package_bytes)
            self.assertNotIn(b'"status":"active"', package_bytes)
            self.assertTrue(any("unknown" in warning for warning in result["warnings"]))

            with zipfile.ZipFile(output) as archive:
                manifest = json.loads(archive.read("manifest.json"))
                kinds = [item["kind"] for item in manifest["resources"]]
                self.assertEqual(
                    kinds,
                    [
                        "subtitle_text_track",
                        "word_timeline",
                        "phone_timeline",
                        "sense_group_analysis",
                        "word_acoustics",
                    ],
                )
                subtitle = json.loads(archive.read("resources/subtitle-text-track.json"))
                generated_segment = subtitle["payload"]["sentences"][0]["id"]
                self.assertNotEqual(generated_segment, "core-sentence-id")
                words = json.loads(archive.read("resources/word-timeline.json"))
                self.assertEqual(words["payload"]["words"][0]["sentence_id"], generated_segment)
                groups = json.loads(archive.read("resources/sense-group-analysis.json"))
                self.assertEqual(groups["payload"]["groups"][0]["end_token_index_exclusive"], 3)

    def test_cli_creates_package(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "lesson.listenpkg"
            code = main(["package", "from-lltimeline", str(self.fixture), "--output", str(output)])
            self.assertEqual(code, 0)
            self.assertTrue(output.is_file())

    def test_missing_optional_active_resources_produces_subtitle_only(self) -> None:
        source = json.loads(self.fixture.read_text(encoding="utf-8"))
        source["word_timelines"] = []
        source["active_word_timeline_id"] = None
        source["phone_timelines"] = []
        source["active_phone_timeline_id"] = None
        source["sense_group_analyses"] = []
        source["active_sense_group_analysis_id"] = None
        source["artifacts"] = []
        with tempfile.TemporaryDirectory() as directory:
            input_path = Path(directory) / "minimal.lltimeline.json"
            output = Path(directory) / "minimal.listenpkg"
            input_path.write_text(json.dumps(source), encoding="utf-8")
            package_from_lltimeline(input_path, output)
            with zipfile.ZipFile(output) as archive:
                manifest = json.loads(archive.read("manifest.json"))
                self.assertEqual(len(manifest["resources"]), 1)
                self.assertEqual(manifest["resources"][0]["kind"], "subtitle_text_track")
                self.assertTrue(manifest["resources"][0]["required"])


if __name__ == "__main__":
    unittest.main()
