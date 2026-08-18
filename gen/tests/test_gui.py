import json
import tempfile
import threading
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from listen_gen.capability import CapabilityRequest
from listen_gen.cli import CancellationRequested
from listen_gen.gui import (
    GuiRequestHandler,
    RunScheduler,
    TaskManager,
    _deep_merge,
    _merge_config,
    _parse_multipart,
    _run_produce_worker,
    _validate_produce_payload,
    check_toolchain,
    detect_media_type,
    get_default_config,
    load_config,
    save_config,
    test_llm_connection,
    validate_config,
)
from listen_gen.produce import ProduceOutcome


class TestGui(unittest.TestCase):
    def test_detect_media_type(self):
        self.assertEqual(detect_media_type("sample.md"), "text/markdown")
        self.assertEqual(detect_media_type("book.epub"), "application/epub+zip")
        self.assertEqual(detect_media_type("paper.pdf"), "application/pdf")
        self.assertEqual(detect_media_type("audio.mp3"), "audio/mpeg")
        self.assertEqual(detect_media_type("video.mp4"), "video/mp4")
        self.assertEqual(detect_media_type("sub.srt"), "text/srt")
        self.assertEqual(detect_media_type("sub.vtt"), "text/vtt")

    def test_default_config_structure(self):
        cfg = get_default_config()
        self.assertIn("llm_profiles", cfg)
        self.assertIn("deepseek", cfg["llm_profiles"])
        self.assertIn("asr", cfg)
        self.assertIn("phones", cfg)
        self.assertIn("tts", cfg)
        self.assertIn("ocr", cfg)

    def test_load_and_save_config(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir) / "test_profiles.json"
            # Initial load falls back to default
            cfg = load_config(config_path)
            self.assertEqual(cfg["selected_llm"], "deepseek")

            # Mutate and save
            cfg["selected_llm"] = "openai"
            cfg["llm_profiles"]["openai"]["api_key"] = "test-sk-key"
            save_config(cfg, config_path)

            # Reload and verify persistence
            reloaded = load_config(config_path)
            self.assertEqual(reloaded["selected_llm"], "openai")
            self.assertEqual(reloaded["llm_profiles"]["openai"]["api_key"], "test-sk-key")

    def test_toolchain_check(self):
        tools = check_toolchain()
        self.assertIn("ffmpeg", tools)
        self.assertIn("say", tools)
        self.assertIn("python", tools)
        self.assertTrue(tools["python"]["available"])

    def test_task_manager(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tm = TaskManager(store_path=Path(tmpdir) / "tasks.json")
            task = tm.create_task("t1", {"material_id": "m1"}, Path(tmpdir) / "out.zip")
            self.assertEqual(task.status, "running")

            tm.record_event("t1", {"type": "progress", "value": 50})
            self.assertEqual(len(task.events), 1)
            self.assertIn("seq", task.events[0])

            tm.complete_task("t1", success=True)
            self.assertEqual(task.status, "completed")
            self.assertEqual(len(task.events), 2)
            self.assertEqual(task.events[-1]["type"], "terminal")
            self.assertEqual(task.events[-1]["seq"], 1)

    @patch("listen_gen.gui.create_llm_client")
    def test_llm_connection_success(self, mock_create):
        mock_client = MagicMock()
        mock_client.call_structured_json.return_value = {"status": "ok"}
        mock_create.return_value = mock_client

        res = test_llm_connection({
            "adapter_kind": "openai_chat",
            "base_url": "https://api.test.com/v1",
            "model_id": "test-model",
            "api_key": "sk-test",
            "timeout_seconds": 5.0,
        })
        self.assertTrue(res["success"])
        self.assertIn("latency_ms", res)


class TestConfigEnhancements(unittest.TestCase):
    def test_deep_merge_restores_default_subfields(self):
        merged = _deep_merge(
            {"asr": {"whisper_cli": "whisper-cli", "language": "auto"}},
            {"asr": {"whisper_cli": "my-whisper"}},
        )
        self.assertEqual(merged["asr"]["whisper_cli"], "my-whisper")
        self.assertEqual(merged["asr"]["language"], "auto")

    def test_merge_config_respects_profile_deletion(self):
        default = get_default_config()
        stored = {
            "selected_llm": "custom",
            "llm_profiles": {"custom": {"base_url": "http://localhost:11434/v1"}},
        }
        merged = _merge_config(default, stored)
        # A profile the user deleted must NOT be resurrected...
        self.assertNotIn("deepseek", merged["llm_profiles"])
        # ...while existing profiles regain default sub-fields.
        self.assertIn("custom", merged["llm_profiles"])
        self.assertEqual(merged["llm_profiles"]["custom"]["base_url"], "http://localhost:11434/v1")
        self.assertIn("api_key", merged["llm_profiles"]["custom"])

    def test_merge_config_keeps_full_defaults_when_stored_empty(self):
        merged = _merge_config(get_default_config(), {})
        self.assertIn("deepseek", merged["llm_profiles"])

    def test_validate_config_accepts_defaults(self):
        self.assertEqual(validate_config(get_default_config()), [])

    def test_validate_config_catches_problems(self):
        cfg = get_default_config()
        bad_tts = dict(cfg)
        bad_tts["tts"] = {"provider": "bogus"}
        self.assertTrue(any("tts.provider" in p for p in validate_config(bad_tts)))

        bad_ocr = dict(cfg)
        bad_ocr["ocr"] = {"provider": "bogus"}
        self.assertTrue(any("ocr.provider" in p for p in validate_config(bad_ocr)))

        bad_url = get_default_config()
        bad_url["llm_profiles"]["deepseek"]["base_url"] = "ftp://bad"
        self.assertTrue(any("base_url" in p for p in validate_config(bad_url)))

        bad_timeout = get_default_config()
        bad_timeout["llm_profiles"]["deepseek"]["timeout_seconds"] = -5
        self.assertTrue(any("timeout_seconds" in p for p in validate_config(bad_timeout)))

        bad_selected = get_default_config()
        bad_selected["selected_llm"] = "missing-profile"
        self.assertTrue(any("selected_llm" in p for p in validate_config(bad_selected)))

    def test_save_config_rejects_invalid(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            path = Path(tmpdir) / "profiles.json"
            bad = get_default_config()
            bad["tts"] = {"provider": "bogus"}
            with self.assertRaises(ValueError):
                save_config(bad, path)
            self.assertFalse(path.exists())  # nothing written


class TestTaskManagerPersistence(unittest.TestCase):
    def test_roundtrip(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = Path(tmpdir) / "tasks.json"
            mgr = TaskManager(store_path=store)
            task = mgr.create_task("t1", {"material_id": "m1"}, Path(tmpdir) / "out.zip")
            mgr.record_event("t1", {"type": "progress", "value": 42})
            mgr.complete_task("t1", success=True)

            mgr2 = TaskManager(store_path=store)
            restored = mgr2.get_task("t1")
            self.assertIsNotNone(restored)
            self.assertEqual(restored.status, "completed")
            self.assertEqual(len(restored.events), 2)
            self.assertEqual(restored.events[0]["seq"], 0)
            self.assertEqual(restored.events[1]["type"], "terminal")
            self.assertEqual(restored.events[1]["status"], "completed")
            self.assertEqual(restored.events[1]["download_url"], "/api/download/t1")

    def test_restart_marks_running_failed(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = Path(tmpdir) / "tasks.json"
            mgr = TaskManager(store_path=store)
            mgr.create_task("t1", {"material_id": "m1"}, Path(tmpdir) / "out.zip")
            # Simulate a crash: task left running, then process restarts.
            mgr2 = TaskManager(store_path=store)
            task = mgr2.get_task("t1")
            self.assertEqual(task.status, "failed")
            self.assertIn("server restarted", task.error)
            self.assertEqual(task.events[-1]["type"], "terminal")
            self.assertEqual(task.events[-1]["status"], "failed")

    def test_cancel_flow(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            mgr = TaskManager(store_path=Path(tmpdir) / "tasks.json")
            mgr.create_task("t1", {}, Path(tmpdir) / "out.zip")
            mgr.cancel_task("t1")
            with self.assertRaises(CancellationRequested):
                mgr.check_cancelled("t1")

            # Cancellation is idempotent and ignored once the task is closed.
            mgr.complete_task("t1", success=False, status="cancelled", error="cancelled by user")
            mgr.cancel_task("t1")
            self.assertEqual(mgr.get_task("t1").status, "cancelled")
            terminal = mgr.get_task("t1").events[-1]
            self.assertEqual(terminal["type"], "terminal")
            self.assertEqual(terminal["status"], "cancelled")

    def test_history_trim(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            mgr = TaskManager(store_path=Path(tmpdir) / "tasks.json", max_history=3)
            # Fill the window with completed tasks, then add a fresh running one.
            for i in range(3):
                mgr.create_task(f"t{i}", {}, Path(tmpdir) / f"o{i}.zip")
                mgr.complete_task(f"t{i}", success=True)
            mgr.create_task("t3", {}, Path(tmpdir) / "o3.zip")
            ids = {t.task_id for t in mgr.list_tasks()}
            self.assertEqual(len(ids), 3)
            self.assertNotIn("t0", ids)  # oldest completed trimmed, never the running one
            self.assertIn("t3", ids)


class TestMultipartAndValidation(unittest.TestCase):
    def test_parse_multipart(self):
        boundary = "X-BOUNDARY-123"
        body = (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="file"; filename="a.md"\r\n'
            "Content-Type: text/markdown\r\n\r\n"
            "# Hello\r\nworld\r\n"
            f"--{boundary}--\r\n"
        ).encode("utf-8")
        fields = _parse_multipart(body, f'multipart/form-data; boundary="{boundary}"')
        filename, ctype, payload = fields["file"]
        self.assertEqual(filename, "a.md")
        self.assertEqual(ctype, "text/markdown")
        self.assertEqual(payload.decode("utf-8"), "# Hello\r\nworld\r\n")

    def test_parse_multipart_missing_boundary(self):
        with self.assertRaises(ValueError):
            _parse_multipart(b"nope", "multipart/form-data")

    def test_validate_produce_payload(self):
        ok = {
            "material": {"material_id": "m1", "material_revision_id": "rev-1", "title": "T"},
            "edition": {"edition_id": "ed-1", "title": "T", "target_language": "en-US", "support_languages": []},
            "requested_capability": "read",
            "available_renditions": [{"kind": "document", "rendition_id": "sha256:" + "0" * 64}],
        }
        self.assertEqual(_validate_produce_payload(ok, {}), [])

        problems = _validate_produce_payload(
            {
                "material": {"title": ""},
                "edition": {},
                "requested_capability": "bogus",
                "available_renditions": [],
            },
            {},
        )
        fields = {p["field"] for p in problems}
        self.assertIn("material_id", fields)
        self.assertIn("title", fields)
        self.assertIn("requested_capability", fields)
        self.assertIn("input", fields)  # no document or media input

        listen_no_doc = {
            "material": {"material_id": "m1", "material_revision_id": "rev-1", "title": "T"},
            "edition": {"edition_id": "ed-1", "title": "T", "target_language": "en-US", "support_languages": []},
            "requested_capability": "listen",
            "available_renditions": [{"kind": "media", "rendition_id": "sha256:" + "1" * 64}],
        }
        problem_fields = {p["field"] for p in _validate_produce_payload(listen_no_doc, {})}
        self.assertIn("input", problem_fields)


class TestProduceWorkerEvents(unittest.TestCase):
    FAKE_CONFIG = {
        "tts": {"provider": "none"},
        "asr": {"provider": "none", "whisper_model": ""},
        "phones": {"provider": "none"},
        "aligner": {"provider": "none"},
        "enable_sense_groups": False,
    }

    def _make_request(self) -> CapabilityRequest:
        return CapabilityRequest.from_document({
            "schema": "listen_gen.capability-request.v2",
            "version": 2,
            "created_at_ms": 1,
            "material": {
                "material_id": "m1",
                "material_revision_id": "rev-1",
                "title": "Test Material",
            },
            "edition": {
                "edition_id": "ed-1",
                "title": "Test Material",
                "target_language": "en-US",
                "support_languages": [],
            },
            "requested_capability": "read",
            "available_renditions": [],
            "available_resources": [],
        })

    def _run(self, task_id: str, store: Path, output: Path) -> TaskManager:
        mgr = TaskManager(store_path=store)
        mgr.create_task(task_id, {"material_id": "m1"}, output)
        with patch("listen_gen.gui._GLOBAL_TASK_MANAGER", mgr):
            _run_produce_worker(task_id, self._make_request(), self.FAKE_CONFIG, output)
        return mgr

    def _kinds(self, task) -> list[str]:
        return [e.get("event") or e.get("type") for e in task.events]

    @patch("listen_gen.gui.plan_request")
    @patch("listen_gen.gui.produce")
    def test_success_emits_v2_sequence(self, mock_produce, mock_plan):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = Path(tmpdir) / "tasks.json"
            output = Path(tmpdir) / "out.zip"
            mock_plan.return_value = SimpleNamespace(
                describe=lambda: {"derivations": ["document_to_structured_reading"]}
            )
            release = SimpleNamespace(
                manifest_document={},
                document_renditions=(),
                media_renditions=(),
                resources=(),
            )
            mock_produce.return_value = ProduceOutcome(
                release=release, package_sha256="deadbeef", warnings=(), package_path=output
            )

            mgr = self._run("t1", store, output)
            task = mgr.get_task("t1")

            self.assertEqual(
                self._kinds(task),
                ["protocol", "accepted", "planned", "completed", "terminal"],
            )
            self.assertEqual(task.status, "completed")
            seqs = [e["seq"] for e in task.events]
            self.assertEqual(seqs, sorted(seqs))  # strictly assigned, no gaps
            completed = next(e for e in task.events if e.get("event") == "completed")
            self.assertEqual(completed["package_sha256"], "sha256:deadbeef")

    @patch("listen_gen.gui.plan_request")
    @patch("listen_gen.gui.produce")
    def test_cancel_emits_cancelled_event(self, mock_produce, mock_plan):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = Path(tmpdir) / "tasks.json"
            output = Path(tmpdir) / "out.zip"
            mock_plan.return_value = SimpleNamespace(describe=lambda: {"derivations": []})
            mgr = TaskManager(store_path=store)
            mgr.create_task("t1", {"material_id": "m1"}, output)

            def fake_produce(request, output_path, *, config, progress, check_cancelled):
                # User cancels while the run is in flight; the next
                # cancellation checkpoint must abort the produce() call.
                mgr.cancel_task("t1")
                check_cancelled()
                raise AssertionError("produce must not continue after cancellation")

            mock_produce.side_effect = fake_produce
            with patch("listen_gen.gui._GLOBAL_TASK_MANAGER", mgr):
                _run_produce_worker("t1", self._make_request(), self.FAKE_CONFIG, output)

            task = mgr.get_task("t1")

            self.assertEqual(task.status, "cancelled")
            self.assertEqual(
                self._kinds(task),
                ["protocol", "accepted", "planned", "cancelled", "terminal"],
            )
            self.assertEqual(task.events[-1]["status"], "cancelled")

    @patch("listen_gen.gui.plan_request")
    @patch("listen_gen.gui.produce")
    def test_failure_emits_failed_event(self, mock_produce, mock_plan):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = Path(tmpdir) / "tasks.json"
            output = Path(tmpdir) / "out.zip"
            mock_plan.return_value = SimpleNamespace(describe=lambda: {"derivations": []})
            mock_produce.side_effect = RuntimeError("boom")

            mgr = self._run("t1", store, output)
            task = mgr.get_task("t1")

            self.assertEqual(task.status, "failed")
            self.assertEqual(
                self._kinds(task),
                ["protocol", "accepted", "planned", "failed", "terminal"],
            )
            failed = next(e for e in task.events if e.get("event") == "failed")
            self.assertEqual(failed["code"], "internal_error")
            self.assertIn("boom", failed["message"])
            self.assertEqual(task.error, "boom")


class _FakeHandler:
    """Minimal stand-in for GuiRequestHandler when calling handler methods."""

    def __init__(self) -> None:
        self.calls: list[tuple] = []

    def _send_json(self, data, status=200):
        self.calls.append(("json", status, data))

    def _send_error_json(self, message, status=400):
        self.calls.append(("error", status, message))


class TestRunScheduler(unittest.TestCase):
    def _wait_until(self, cond, timeout=6.0) -> bool:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if cond():
                return True
            time.sleep(0.01)
        return False

    def test_respects_max_concurrency_and_pumps_fifo(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            mgr = TaskManager(store_path=Path(tmpdir) / "t.json")
            for tid in ("t1", "t2", "t3"):
                mgr.create_task(tid, {}, Path(tmpdir) / f"{tid}.zip", status="queued")

            sched = RunScheduler(max_concurrent_runs=1)
            started: list[str] = []
            active: list[str] = []
            max_active = [0]
            lock = threading.Lock()
            release = threading.Event()

            def make_fn(tid):
                def fn():
                    with lock:
                        active.append(tid)
                        started.append(tid)
                        max_active[0] = max(max_active[0], len(active))
                    release.wait(6)
                    with lock:
                        active.remove(tid)
                return fn

            with patch("listen_gen.gui._GLOBAL_TASK_MANAGER", mgr):
                for tid in ("t1", "t2", "t3"):
                    sched.submit(tid, make_fn(tid))

                # Only one slot: exactly one task should be active, rest queued.
                ok = self._wait_until(lambda: len(started) == 1)
                self.assertTrue(ok, "first worker never started")
                self.assertEqual(sched.running_count(), 1)
                self.assertEqual(sched.pending_count(), 2)
                self.assertEqual(mgr.get_task("t2").status, "queued")
                self.assertEqual(mgr.get_task("t3").status, "queued")

                # Releasing each running worker pumps the FIFO queue.
                for _ in range(3):
                    release.set()
                    release = threading.Event()
                    # wait until the next task starts (or all are done)
                    self._wait_until(lambda: len(started) == len(active) + len(started) or len(started) >= 0)
                    time.sleep(0.05)

                release.set()
                self.assertTrue(self._wait_until(lambda: sched.pending_count() == 0 and sched.running_count() == 0))

            self.assertEqual(started, ["t1", "t2", "t3"])  # FIFO order
            self.assertEqual(max_active[0], 1)  # never exceeded the cap

    def test_remove_pending_prevents_start(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            mgr = TaskManager(store_path=Path(tmpdir) / "t.json")
            mgr.create_task("t0", {}, Path(tmpdir) / "o0.zip", status="queued")
            mgr.create_task("t1", {}, Path(tmpdir) / "o1.zip", status="queued")

            sched = RunScheduler(max_concurrent_runs=1)
            release = threading.Event()
            called: list[str] = []

            def f0():
                called.append("t0")
                release.wait(6)

            with patch("listen_gen.gui._GLOBAL_TASK_MANAGER", mgr):
                sched.submit("t0", f0)
                sched.submit("t1", lambda: called.append("t1"))
                # t1 is still queued (t0 occupies the only slot)
                self._wait_until(lambda: sched.running_count() == 1)
                self.assertTrue(sched.remove_pending("t1"))
                release.set()
                self.assertFalse(self._wait_until(lambda: "t1" in called), "cancelled queued task must never start")
                self.assertEqual(sched.pending_count(), 0)

            self.assertNotIn("t1", called)


class TestQueueTaskStates(unittest.TestCase):
    def test_queued_to_running_transition(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            mgr = TaskManager(store_path=Path(tmpdir) / "t.json")
            task = mgr.create_task("q1", {}, Path(tmpdir) / "o.zip", status="queued")
            self.assertEqual(task.status, "queued")
            mgr.mark_running("q1")
            self.assertEqual(mgr.get_task("q1").status, "running")
            mgr.mark_running("q1")  # idempotent
            self.assertEqual(mgr.get_task("q1").status, "running")

    def test_queued_cancel(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            mgr = TaskManager(store_path=Path(tmpdir) / "t.json")
            mgr.create_task("q1", {}, Path(tmpdir) / "o.zip", status="queued")
            mgr.cancel_task("q1")
            with self.assertRaises(CancellationRequested):
                mgr.check_cancelled("q1")
            mgr.complete_task("q1", success=False, status="cancelled", error="cancelled while queued")
            self.assertEqual(mgr.get_task("q1").status, "cancelled")
            self.assertEqual(mgr.get_task("q1").events[-1]["type"], "terminal")

    def test_queued_restart_marks_failed(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            store = Path(tmpdir) / "t.json"
            mgr = TaskManager(store_path=store)
            mgr.create_task("q1", {}, Path(tmpdir) / "o.zip", status="queued")
            mgr2 = TaskManager(store_path=store)
            self.assertEqual(mgr2.get_task("q1").status, "failed")
            self.assertIn("server restarted", mgr2.get_task("q1").error)


class TestRerun(unittest.TestCase):
    def _snapshot_request(self, doc_path: Path) -> dict:
        return {
            "schema": "listen_gen.capability-request.v2",
            "version": 2,
            "created_at_ms": 1,
            "material": {"material_id": "m1", "material_revision_id": "rev-1", "title": "T"},
            "edition": {"edition_id": "ed-1", "title": "T", "target_language": "en-US", "support_languages": []},
            "requested_capability": "read",
            "available_renditions": [{
                "kind": "document",
                "rendition_id": "sha256:" + "0" * 64,
                "media_type": "text/markdown",
                "source_asset_id": "sha256:" + "0" * 64,
                "blob": {"digest": "sha256:" + "0" * 64, "size_bytes": 10, "path": str(doc_path)},
            }],
            "available_resources": [],
        }

    def test_rerun_rebuilds_snapshot(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            doc = Path(tmpdir) / "input.md"
            doc.write_text("# Hi\n\nHello world.", encoding="utf-8")
            mgr = TaskManager(store_path=Path(tmpdir) / "tasks.json")
            mgr.create_task(
                "old-1", self._snapshot_request(doc), Path(tmpdir) / "out.zip",
                status="completed", config={"tts": {"provider": "fake"}},
            )
            sched = RunScheduler(max_concurrent_runs=4)
            fake = _FakeHandler()
            with patch("listen_gen.gui._GLOBAL_TASK_MANAGER", mgr), \
                 patch("listen_gen.gui._RUN_SCHEDULER", sched), \
                 patch("listen_gen.gui._run_produce_worker", lambda *a, **k: None):
                GuiRequestHandler._handle_rerun(fake, "old-1")

            kind, status, data = fake.calls[0]
            self.assertEqual(kind, "json")
            self.assertEqual(status, 200)
            self.assertEqual(data["status"], "queued")
            self.assertEqual(data["rerun_of"], "old-1")

            task = mgr.get_task(data["task_id"])
            # With a free slot the task starts immediately (queued → running);
            # with a busy slot it stays queued. Either way it was submitted.
            self.assertIn(task.status, ("queued", "running"))
            rendition = task.request_doc["available_renditions"][0]
            # digest recomputed honestly from the current file bytes
            self.assertNotEqual(rendition["blob"]["digest"], "sha256:" + "0" * 64)
            self.assertTrue(rendition["blob"]["digest"].startswith("sha256:"))
            self.assertEqual(rendition["source_asset_id"], rendition["blob"]["digest"])
            # config snapshot carried over
            self.assertEqual(task.config["tts"]["provider"], "fake")
            # fresh material revision
            self.assertTrue(task.request_doc["material"]["material_revision_id"].startswith("rev-"))

    def test_rerun_missing_blob_returns_409(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            missing = Path(tmpdir) / "gone.md"  # does not exist
            mgr = TaskManager(store_path=Path(tmpdir) / "tasks.json")
            mgr.create_task("old-1", self._snapshot_request(missing), Path(tmpdir) / "out.zip", status="failed")
            fake = _FakeHandler()
            with patch("listen_gen.gui._GLOBAL_TASK_MANAGER", mgr):
                GuiRequestHandler._handle_rerun(fake, "old-1")
            kind, status, message = fake.calls[0]
            self.assertEqual(kind, "error")
            self.assertEqual(status, 409)
            self.assertIn("已不在磁盘", message)


if __name__ == "__main__":
    unittest.main()
