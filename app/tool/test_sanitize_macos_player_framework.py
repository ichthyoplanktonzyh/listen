import os
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("sanitize-macos-player-framework.sh")


class SanitizeMacOSPlayerFrameworkTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "listen.app"
        self.mdk = (
            self.app
            / "Contents/Frameworks/mdk.framework/Versions/A/mdk"
        )
        self.mdk.parent.mkdir(parents=True)
        self.mdk.write_bytes(b"fixture Mach-O")

        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.marker_dir = self.root / "rpaths"
        self.marker_dir.mkdir()
        self.install_log = self.root / "install-name-tool.log"

        otool = self.bin_dir / "otool"
        otool.write_text(
            "#!/usr/bin/env python3\n"
            "import os\n"
            "import sys\n"
            "from pathlib import Path\n"
            "marker_dir = Path(os.environ['RPATH_MARKER_DIR'])\n"
            "if os.environ.get('FAKE_OTOOL_FAIL') == '1':\n"
            "    sys.exit(31)\n"
            "install_log = Path(os.environ['INSTALL_NAME_TOOL_LOG'])\n"
            "if (os.environ.get('FAKE_OTOOL_FAIL_AFTER_INSTALL') == '1'\n"
            "        and install_log.exists()\n"
            "        and install_log.read_text().strip()):\n"
            "    sys.exit(32)\n"
            "lines = []\n"
            "for name, path in [('homebrew', '/opt/homebrew/lib'),\n"
            "                   ('usr-local', '/usr/local/lib')]:\n"
            "    if (marker_dir / name).exists():\n"
            "        lines.extend(['Load command 1', '          cmd LC_RPATH',\n"
            "                      f'         path {path} (offset 12)'])\n"
            # More than a pipe buffer, so grep -q's early close is observable.
            "lines.extend(['Load command filler'] * 30000)\n"
            "payload = ('\\n'.join(lines) + '\\n').encode()\n"
            "remaining = memoryview(payload)\n"
            "while remaining:\n"
            "    try:\n"
            "        written = os.write(1, remaining)\n"
            "    except BrokenPipeError:\n"
            "        os._exit(141)\n"
            "    remaining = remaining[written:]\n",
            encoding="utf-8",
        )
        install_name_tool = self.bin_dir / "install_name_tool"
        install_name_tool.write_text(
            "#!/bin/sh\n"
            "path=$2\n"
            "printf '%s\\n' \"$path\" >> \"$INSTALL_NAME_TOOL_LOG\"\n"
            "if [ \"${FAKE_INSTALL_FAIL:-0}\" = 1 ]; then exit 33; fi\n"
            "if [ \"${FAKE_INSTALL_NOOP:-0}\" = 1 ]; then exit 0; fi\n"
            "case \"$path\" in\n"
            "  /opt/homebrew/lib) rm -f \"$RPATH_MARKER_DIR/homebrew\" ;;\n"
            "  /usr/local/lib) rm -f \"$RPATH_MARKER_DIR/usr-local\" ;;\n"
            "  *) exit 34 ;;\n"
            "esac\n",
            encoding="utf-8",
        )
        otool.chmod(0o755)
        install_name_tool.chmod(0o755)
        (self.marker_dir / "homebrew").touch()
        (self.marker_dir / "usr-local").touch()
        self.env = {
            **os.environ,
            "PATH": f"{self.bin_dir}{os.pathsep}{os.environ['PATH']}",
            "RPATH_MARKER_DIR": str(self.marker_dir),
            "INSTALL_NAME_TOOL_LOG": str(self.install_log),
        }

    def run_sanitizer(self, **overrides):
        return subprocess.run(
            [str(SCRIPT), str(self.app)],
            capture_output=True,
            text=True,
            env={**self.env, **overrides},
        )

    def test_consumes_large_otool_output_and_removes_every_external_rpath(self):
        result = self.run_sanitizer()

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Sanitized bundled mdk", result.stdout)
        self.assertEqual(
            self.install_log.read_text(encoding="utf-8").splitlines(),
            ["/opt/homebrew/lib", "/usr/local/lib"],
        )
        self.assertFalse((self.marker_dir / "homebrew").exists())
        self.assertFalse((self.marker_dir / "usr-local").exists())

    def test_otool_failure_is_not_treated_as_a_clean_binary(self):
        result = self.run_sanitizer(FAKE_OTOOL_FAIL="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not inspect bundled mdk", result.stderr)
        self.assertNotIn("Sanitized bundled mdk", result.stdout)
        self.assertFalse(self.install_log.exists())

    def test_install_name_tool_failure_is_not_reported_as_sanitized(self):
        result = self.run_sanitizer(FAKE_INSTALL_FAIL="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not remove bundled mdk", result.stderr)
        self.assertNotIn("Sanitized bundled mdk", result.stdout)

    def test_a_tool_that_makes_no_progress_fails_closed(self):
        result = self.run_sanitizer(FAKE_INSTALL_NOOP="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("did not remove bundled mdk", result.stderr)
        self.assertNotIn("Sanitized bundled mdk", result.stdout)

    def test_otool_failure_after_edit_does_not_claim_success(self):
        result = self.run_sanitizer(FAKE_OTOOL_FAIL_AFTER_INSTALL="1")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Could not re-inspect bundled mdk", result.stderr)
        self.assertNotIn("Sanitized bundled mdk", result.stdout)


if __name__ == "__main__":
    unittest.main()
