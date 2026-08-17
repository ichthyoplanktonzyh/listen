import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from listen_gen.gui import (
    TaskManager,
    check_toolchain,
    detect_media_type,
    get_default_config,
    load_config,
    save_config,
    test_llm_connection,
)


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
        tm = TaskManager()
        task = tm.create_task("t1", {"material_id": "m1"}, Path("/tmp/out.zip"))
        self.assertEqual(task.status, "running")

        tm.record_event("t1", {"type": "progress", "value": 50})
        self.assertEqual(len(task.events), 1)

        tm.complete_task("t1", success=True)
        self.assertEqual(task.status, "completed")
        self.assertEqual(len(task.events), 2)
        self.assertEqual(task.events[-1]["type"], "terminal")

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


if __name__ == "__main__":
    unittest.main()
