#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tarfile
import tempfile
import unittest
import wave
from pathlib import Path
from types import SimpleNamespace


SCRIPT_PATH = Path(__file__).with_name("prepare-helsinki-libritts-benchmark.py")
SPEC = importlib.util.spec_from_file_location("prepare_helsinki_libritts_benchmark", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
prepare_helsinki_libritts_benchmark = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prepare_helsinki_libritts_benchmark)


def write_wav(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)
        wav.setframerate(16000)
        wav.writeframes(b"\x00\x00" * 16000)


class PrepareHelsinkiLibriTtsBenchmarkTest(unittest.TestCase):
    def test_prepares_local_manifest_and_baseline_timeline(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            labels = root / "labels.txt"
            labels.write_text(
                "\n".join(
                    [
                        "<file>\t1272_128104_000001_000000.txt",
                        "A\t0\t0\t0.1\t0.0",
                        "market\t2\t2\t2.4\t2.0",
                        ".\tNA\tNA\tNA\tNA",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            audio = root / "LibriTTS" / "dev-clean" / "1272" / "128104" / "1272_128104_000001_000000.wav"
            write_wav(audio)
            output_dir = root / "out"

            args = SimpleNamespace(
                labels=str(labels),
                prosody_dir=str(root / "prosody"),
                libritts_dir=str(root / "LibriTTS"),
                libritts_archive=None,
                split="dev",
                limit=10,
                output_dir=str(output_dir),
            )

            result = prepare_helsinki_libritts_benchmark.prepare(args)

            self.assertEqual(result["prepared_count"], 1)
            self.assertEqual(result["missing_audio_count"], 0)
            manifest_path = Path(result["manifest_path"])
            rows = [
                json.loads(line)
                for line in manifest_path.read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            self.assertEqual(len(rows), 1)
            row = rows[0]
            self.assertEqual(row["benchmark_role"], "weak_prosody_regression")
            self.assertEqual(row["source_file"], "1272_128104_000001_000000.txt")
            self.assertEqual(row["media"]["duration_ms"], 1000)
            timeline_path = Path(row["lltimeline"]["local_path"])
            document = json.loads(timeline_path.read_text(encoding="utf-8"))
            self.assertEqual(document["schema"], "llplayer.timeline.v1")
            self.assertEqual(document["metadata"]["media"]["path"], str(audio))
            self.assertEqual(document["segments"][0]["text"], "A market.")
            self.assertEqual(document["phone_timelines"], [])

    def test_reports_missing_audio_without_failing_selected_batch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            labels = root / "labels.txt"
            labels.write_text(
                "<file>\tmissing_000001_000001_000000.txt\nHello\t2\t2\t1.0\t2.0\n",
                encoding="utf-8",
            )

            args = SimpleNamespace(
                labels=str(labels),
                prosody_dir=str(root / "prosody"),
                libritts_dir=str(root / "LibriTTS"),
                libritts_archive=None,
                split="dev",
                limit=10,
                output_dir=str(root / "out"),
            )

            result = prepare_helsinki_libritts_benchmark.prepare(args)

            self.assertEqual(result["prepared_count"], 0)
            self.assertEqual(result["missing_audio_count"], 1)

    def test_extracts_selected_audio_from_libritts_archive(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            labels = root / "labels.txt"
            labels.write_text(
                "\n".join(
                    [
                        "<file>\t2902_9008_000002_000000.txt",
                        "A\t0\t0\t0.1\t0.0",
                        "critic\t2\t2\t2.0\t2.0",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            source_wav = root / "source.wav"
            write_wav(source_wav)
            archive_path = root / "dev-clean.tar.gz"
            with tarfile.open(archive_path, "w:gz") as archive:
                archive.add(
                    source_wav,
                    arcname="./LibriTTS/dev-clean/2902/9008/2902_9008_000002_000000.wav",
                )
            output_dir = root / "out"
            args = SimpleNamespace(
                labels=str(labels),
                prosody_dir=str(root / "prosody"),
                libritts_dir=None,
                libritts_archive=str(archive_path),
                split="dev",
                limit=10,
                output_dir=str(output_dir),
            )

            result = prepare_helsinki_libritts_benchmark.prepare(args)

            self.assertEqual(result["prepared_count"], 1)
            rows = [
                json.loads(line)
                for line in Path(result["manifest_path"]).read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            extracted_audio = Path(rows[0]["media"]["local_path"])
            self.assertTrue(extracted_audio.is_file())
            self.assertIn("LibriTTS/dev-clean/2902/9008", str(extracted_audio))


if __name__ == "__main__":
    unittest.main()
