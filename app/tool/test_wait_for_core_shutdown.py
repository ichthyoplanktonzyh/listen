import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("wait_for_core_shutdown.py")
LOCKING_CHILD = """
import fcntl
import sys
import time

lock = open(sys.argv[1], "r+")
fcntl.flock(lock, fcntl.LOCK_EX)
print("ready", flush=True)
time.sleep(float(sys.argv[2]))
"""


class WaitForCoreShutdownTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.lock_file = Path(self.temporary.name) / "smoke.sqlite.lock"
        self.lock_file.touch()
        self.child = None
        self.addCleanup(self.stop_child)

    def stop_child(self):
        if self.child is not None and self.child.poll() is None:
            self.child.kill()
        if self.child is not None:
            self.child.wait(timeout=3)
            self.child.stdout.close()
            self.child.stderr.close()

    def start_locking_child(self, delay):
        self.child = subprocess.Popen(
            [sys.executable, "-c", LOCKING_CHILD, str(self.lock_file), str(delay)],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.assertEqual(self.child.stdout.readline().strip(), "ready")

    def run_waiter(self, timeout):
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--lock-file",
                str(self.lock_file),
                "--pids",
                str(self.child.pid),
                "--timeout-seconds",
                str(timeout),
                "--interval-seconds",
                "0.02",
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=max(3, timeout + 2),
        )

    def test_waits_for_owned_child_exit_and_lock_release(self):
        self.start_locking_child(0.35)
        started = time.monotonic()

        result = self.run_waiter(timeout=2)

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("database lock is available", result.stdout)
        self.assertGreaterEqual(time.monotonic() - started, 0.3)

    def test_timeout_fails_while_child_still_holds_lock(self):
        self.start_locking_child(2)

        result = self.run_waiter(timeout=0.25)

        self.assertEqual(result.returncode, 1)
        self.assertIn("Timed out waiting for Core shutdown", result.stderr)
        self.assertIn("database_lock=held", result.stderr)


if __name__ == "__main__":
    unittest.main()
