import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_flutter_test_report import ReportError, verify_report

NAME = "pinned Gen bundle to Core import round trips as a candidate"


def events(*, name=NAME, result="success", skipped=False, runner_success=True):
    return [
        {"protocolVersion": "0.1.1"},
        {"type": "testStart", "test": {"id": 7, "name": name}},
        {"type": "testDone", "testID": 7, "result": result, "skipped": skipped},
        {"type": "done", "success": runner_success},
    ]


class ReportTests(unittest.TestCase):
    def verify(self, values):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "report.jsonl"
            path.write_text("\n".join(json.dumps(value) for value in values) + "\n")
            verify_report(path, NAME)

    def rejects(self, values, message):
        with self.assertRaisesRegex(ReportError, message):
            self.verify(values)

    def test_success(self):
        self.verify(events())

    def test_target_missing(self):
        self.rejects(events(name="some other test"), "exactly one execution")

    def test_target_skipped(self):
        self.rejects(events(result="success", skipped=True), "skipped")

    def test_target_failed(self):
        self.rejects(events(result="failure", runner_success=False), "not success")

    def test_malformed(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "bad.jsonl"
            path.write_text('{"type":\n')
            with self.assertRaisesRegex(ReportError, "malformed JSON"):
                verify_report(path, NAME)


if __name__ == "__main__":
    unittest.main()
