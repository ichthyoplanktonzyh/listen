import sqlite3
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("wait_for_sqlite_value.py")


class WaitForSQLiteValueTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.database = Path(self.temporary.name) / "smoke.sqlite"
        with sqlite3.connect(self.database) as connection:
            connection.execute("CREATE TABLE media_items (id INTEGER PRIMARY KEY)")
            connection.execute("INSERT INTO media_items DEFAULT VALUES")

    def run_waiter(self, timeout, interval="0.02"):
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                str(self.database),
                "SELECT count(*) FROM media_items",
                "2",
                "--timeout-seconds",
                str(timeout),
                "--interval-seconds",
                interval,
                "--description",
                "audio media item count",
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=max(3, timeout + 2),
        )

    def test_waits_for_delayed_second_media_registration_readback(self):
        def register_media():
            with sqlite3.connect(self.database) as connection:
                connection.execute("INSERT INTO media_items DEFAULT VALUES")

        timer = threading.Timer(0.2, register_media)
        timer.start()
        self.addCleanup(timer.join)

        result = self.run_waiter(timeout=2)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("audio media item count reached 2", result.stdout)

    def test_missing_second_registration_times_out_with_last_readback(self):
        started = time.monotonic()
        result = self.run_waiter(timeout=0.3, interval="0.03")
        elapsed = time.monotonic() - started

        self.assertEqual(result.returncode, 1)
        self.assertIn("Timed out waiting for audio media item count", result.stderr)
        self.assertIn("last value: 1", result.stderr)
        self.assertGreaterEqual(elapsed, 0.25)
        self.assertLess(elapsed, 3)


if __name__ == "__main__":
    unittest.main()
