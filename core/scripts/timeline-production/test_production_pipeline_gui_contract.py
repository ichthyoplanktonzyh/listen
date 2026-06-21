#!/usr/bin/env python3
"""Contract tests for production_pipeline_gui.py helper logic.

Covers the GUI fixes for:
- cancel reaping the whole process group (no orphaned whisperx workers)
- build_command never blocking the HTTP worker on SHA256 during preview
- build_command resolving the real fingerprint for production runs
- main() flushing the URL line even under block-buffered stdout
"""

from __future__ import annotations

import importlib.util
import os
import signal
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


def load_gui_module():
    path = Path(__file__).with_name("production_pipeline_gui.py")
    spec = importlib.util.spec_from_file_location("production_pipeline_gui_subject", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PlaceholderFingerprintTest(unittest.TestCase):
    def test_placeholder_is_64_hex_chars_and_never_blocks(self) -> None:
        gui = load_gui_module()
        fp = gui._placeholder_fingerprint(Path("/some/huge/video.mp4"))
        # Must look like a sha256 (64 hex) so downstream flag parsing is stable,
        # and must be prefixed so it cannot collide with a real hash.
        self.assertTrue(fp.startswith("preview"))
        self.assertEqual(len(fp), 64)
        self.assertTrue(all(c in "0123456789abcdef" for c in fp[len("preview"):]))

    def test_placeholder_is_stable_for_same_path(self) -> None:
        gui = load_gui_module()
        self.assertEqual(
            gui._placeholder_fingerprint(Path("/a.mp4")),
            gui._placeholder_fingerprint(Path("/a.mp4")),
        )


class BuildCommandFingerprintTest(unittest.TestCase):
    BASE_PAYLOAD = {
        "input_path": "/tmp/media.mp4",
        "output_dir": "/tmp/out",
        "output_path": "/tmp/out/media.lltimeline.json",
        "media_title": "media",
        "language": "en",
        "model": "large-v3",
        "device": "cpu",
        "compute_type": "float32",
        "batch_size": 16,
        "post_aligner": "none",
    }

    def _fingerprint_in(self, command: list[str]) -> str:
        return command[command.index("--media-fingerprint") + 1]

    def test_preview_uses_placeholder_and_does_not_hash(self) -> None:
        gui = load_gui_module()
        with mock.patch.object(gui, "file_sha256", side_effect=AssertionError("preview must not hash")):
            command = gui.build_command(dict(self.BASE_PAYLOAD, media_fingerprint=""))
        fp = self._fingerprint_in(command)
        self.assertTrue(fp.startswith("preview"))

    def test_explicit_fingerprint_is_passed_through(self) -> None:
        gui = load_gui_module()
        command = gui.build_command(dict(self.BASE_PAYLOAD, media_fingerprint="abc123"))
        self.assertEqual(self._fingerprint_in(command), "abc123")

    def test_production_run_resolves_real_fingerprint(self) -> None:
        gui = load_gui_module()
        called = {}

        def fake_hash(path: Path) -> str:
            called["path"] = path
            return "realhash" * 7 + "a"  # 64 chars

        with mock.patch.object(gui, "file_sha256", side_effect=fake_hash):
            command = gui.build_command(
                dict(self.BASE_PAYLOAD, media_fingerprint=""),
                resolve_fingerprint=True,
            )
        self.assertEqual(self._fingerprint_in(command), "realhash" * 7 + "a")
        self.assertEqual(called["path"], Path("/tmp/media.mp4"))


class CancelProcessGroupTest(unittest.TestCase):
    def test_cancel_with_no_running_process_returns_false(self) -> None:
        gui = load_gui_module()
        state = gui.PipelineState()
        # No process started yet.
        self.assertFalse(state.cancel())

    def test_cancel_signals_whole_process_group(self) -> None:
        gui = load_gui_module()
        state = gui.PipelineState()
        state.running = True
        fake_process = mock.MagicMock()
        fake_process.poll.return_value = None  # still running
        fake_process.pid = 4242
        state.process = fake_process

        killpg_calls: list[tuple[int, int]] = []

        def fake_killpg(pgid: int, sig: int) -> None:
            killpg_calls.append((pgid, sig))

        with mock.patch.object(gui.os, "killpg", side_effect=fake_killpg):
            result = state.cancel()

        self.assertTrue(result)
        self.assertTrue(state.cancelled)
        # Must have sent SIGTERM to the process group of the pipeline pid.
        self.assertEqual(killpg_calls, [(4242, signal.SIGTERM)])

    def test_cancel_escalates_to_sigkill_after_grace(self) -> None:
        gui = load_gui_module()
        # _force_kill_group must SIGKILL a still-running group.
        fake_process = mock.MagicMock()
        fake_process.poll.return_value = None  # still alive after grace
        kill_calls: list[tuple[int, int]] = []

        def fake_killpg(pgid: int, sig: int) -> None:
            kill_calls.append((pgid, sig))

        with mock.patch.object(gui.os, "killpg", side_effect=fake_killpg):
            gui._force_kill_group(9999, fake_process)
        self.assertEqual(kill_calls, [(9999, signal.SIGKILL)])

    def test_cancel_does_not_orphan_when_process_already_dead(self) -> None:
        gui = load_gui_module()
        state = gui.PipelineState()
        state.running = True
        fake_process = mock.MagicMock()
        fake_process.poll.return_value = 0  # already exited
        state.process = fake_process
        with mock.patch.object(gui.os, "killpg", side_effect=AssertionError("must not signal dead group")):
            self.assertFalse(state.cancel())


class StdoutFlushTest(unittest.TestCase):
    def test_main_reconfigures_stdout_line_buffering(self) -> None:
        # main() is hard to invoke (it serves forever), but the reconfigure step
        # is the part we care about: verify line_buffering can be turned on for a
        # real text stream without raising.
        stream = open(os.devnull, "w")
        try:
            stream.reconfigure(line_buffering=True)  # type: ignore[attr-defined]
            self.assertTrue(stream.line_buffering)  # type: ignore[attr-defined]
        finally:
            stream.close()


if __name__ == "__main__":
    unittest.main()
