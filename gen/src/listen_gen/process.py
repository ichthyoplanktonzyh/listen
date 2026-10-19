from __future__ import annotations

import os
import queue
import signal
import subprocess
import threading
import time
from dataclasses import dataclass
from typing import Sequence


class ProcessTimedOut(Exception):
    pass


class ProcessOutputTooLarge(Exception):
    pass


@dataclass(frozen=True)
class ProcessResult:
    returncode: int
    stdout: bytes


def _terminate_group(process: subprocess.Popen[bytes]) -> None:
    try:
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGKILL)
        elif process.poll() is None:
            process.kill()
    except OSError:
        if process.poll() is None:
            try:
                process.kill()
            except OSError:
                pass
    if process.poll() is None:
        process.wait()


def run_argv(
    argv: Sequence[str],
    *,
    timeout_seconds: float,
    stdout_limit_bytes: int | None,
    input_bytes: bytes | None = None,
) -> ProcessResult:
    """Run argv without a shell, bounding captured output and killing its process group."""
    capture_stdout = stdout_limit_bytes is not None
    if stdout_limit_bytes is not None and stdout_limit_bytes <= 0:
        raise ValueError("stdout limit must be positive")
    process = subprocess.Popen(
        list(argv),
        stdin=subprocess.PIPE if input_bytes is not None else subprocess.DEVNULL,
        stdout=subprocess.PIPE if capture_stdout else subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=os.name == "posix",
    )
    if input_bytes is not None:
        assert process.stdin is not None
        try:
            process.stdin.write(input_bytes)
        except BrokenPipeError:
            pass
        finally:
            process.stdin.close()
    deadline = time.monotonic() + timeout_seconds
    if not capture_stdout:
        try:
            return ProcessResult(process.wait(timeout=timeout_seconds), b"")
        except subprocess.TimeoutExpired as error:
            _terminate_group(process)
            raise ProcessTimedOut from error
        except BaseException:
            _terminate_group(process)
            raise

    assert process.stdout is not None
    chunks: queue.Queue[bytes | None] = queue.Queue(maxsize=2)

    def read_stdout() -> None:
        try:
            while chunk := process.stdout.read(64 * 1024):
                chunks.put(chunk)
        finally:
            chunks.put(None)

    reader = threading.Thread(target=read_stdout, daemon=True)
    reader.start()
    output = bytearray()
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ProcessTimedOut
            try:
                chunk = chunks.get(timeout=remaining)
            except queue.Empty as error:
                raise ProcessTimedOut from error
            if chunk is None:
                break
            if len(output) + len(chunk) > stdout_limit_bytes:
                raise ProcessOutputTooLarge
            output.extend(chunk)
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise ProcessTimedOut
        result = ProcessResult(process.wait(timeout=remaining), bytes(output))
        reader.join()
        return result
    except (ProcessTimedOut, ProcessOutputTooLarge):
        _terminate_group(process)
        raise
    except BaseException:
        _terminate_group(process)
        raise
    finally:
        process.stdout.close()
