from __future__ import annotations

import os
from pathlib import Path
import re
import signal
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).with_name("verify-macos-release.sh")


class PackagedAppLauncherTests(unittest.TestCase):
    def test_background_pid_is_app_pid_and_stop_reaps_it(self) -> None:
        source = SCRIPT.read_text(encoding="utf-8")
        match = re.search(
            r"(?ms)^launch_packaged_app\(\) \{\n.*?^\}", source
        )
        self.assertIsNotNone(match, "release verifier launcher function was not found")

        with tempfile.TemporaryDirectory(prefix="listen launcher pid ") as temp:
            root = Path(temp)
            app = root / "Mock App.app"
            executable = app / "Contents" / "MacOS" / "listen"
            executable.parent.mkdir(parents=True)
            support = root / "support"
            support.mkdir()
            home = root / "home"
            home.mkdir()
            executable.write_text(
                "#!/bin/bash\n"
                'printf \'%s\\n%s\\n%s\\n\' "$$" "$LLPLAYERNEXT_DB" '
                '"$LLPLAYERNEXT_SMOKE_MEDIA" > '
                '"$LLPLAYERNEXT_SUPPORT_DIR/mock.pid"\n'
                "exec /bin/sleep 30\n",
                encoding="utf-8",
            )
            executable.chmod(0o755)

            harness = f"""\
app="$TEST_APP"
tmp="$TEST_TMP"
isolated_home="$TEST_HOME"
isolated_support="$TEST_SUPPORT"
minimal_path="/usr/bin:/bin"
app_pid=""
mock_pid=""
cleanup() {{
  [[ -n "$app_pid" ]] && kill "$app_pid" 2>/dev/null || true
  [[ -n "$mock_pid" ]] && kill "$mock_pid" 2>/dev/null || true
  [[ -n "$app_pid" ]] && wait "$app_pid" 2>/dev/null || true
}}
trap cleanup EXIT
{match.group(0)}
launch_packaged_app "$TEST_DB" "$TEST_MEDIA" >"$TEST_LOG" 2>&1 &
app_pid=$!
printf '%s\\n' "$app_pid" >"$TEST_PID_FILE"
for attempt in {{1..100}}; do
  [[ -f "$isolated_support/mock.pid" ]] && break
  sleep 0.02
done
[[ -f "$isolated_support/mock.pid" ]] || {{
  echo "mock app did not start" >&2
  exit 1
}}
read -r mock_pid <"$isolated_support/mock.pid"
read -r actual_db < <(sed -n '2p' "$isolated_support/mock.pid")
read -r actual_media < <(sed -n '3p' "$isolated_support/mock.pid")
[[ "$app_pid" == "$mock_pid" ]] || {{
  echo "background PID $app_pid does not match App PID $mock_pid" >&2
  exit 1
}}
[[ "$actual_db" == "$TEST_DB" && "$actual_media" == "$TEST_MEDIA" ]] || {{
  echo "launcher did not pass the expected isolated environment" >&2
  exit 1
}}
expected_pid="$app_pid"
kill "$app_pid"
wait "$app_pid" 2>/dev/null || true
app_pid=""
mock_pid=""
if kill -0 "$expected_pid" 2>/dev/null; then
  echo "App PID $expected_pid remained alive after stop and wait" >&2
  kill -KILL "$expected_pid" 2>/dev/null || true
  exit 1
fi
"""
            env = os.environ.copy()
            env.update(
                {
                    "TEST_APP": str(app),
                    "TEST_TMP": str(root),
                    "TEST_HOME": str(home),
                    "TEST_SUPPORT": str(support),
                    "TEST_DB": str(root / "isolated.sqlite"),
                    "TEST_MEDIA": str(root / "fixture media.wav"),
                    "TEST_LOG": str(root / "app.log"),
                    "TEST_PID_FILE": str(root / "captured.pid"),
                }
            )
            process = subprocess.Popen(
                ["bash", "-c", harness],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                start_new_session=True,
            )
            try:
                stdout, stderr = process.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                stdout, stderr = process.communicate()
                self.fail(f"launcher harness timed out:\n{stdout}{stderr}")
            self.assertEqual(
                process.returncode,
                0,
                msg=f"launcher harness failed:\n{stdout}{stderr}",
            )


if __name__ == "__main__":
    unittest.main()
