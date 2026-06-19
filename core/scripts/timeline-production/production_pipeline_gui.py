#!/usr/bin/env python3
"""Small Tk GUI for the local LLTimeline production pipeline."""

from __future__ import annotations

import hashlib
import json
import os
import queue
import shlex
import subprocess
import sys
import threading
from pathlib import Path
from tkinter import BooleanVar, IntVar, StringVar, Tk, filedialog, messagebox, ttk
from tkinter.scrolledtext import ScrolledText


REPO_ROOT = Path(__file__).resolve().parents[2]
PIPELINE = Path(__file__).with_name("production_pipeline.py")


def default_whisperx_bin() -> Path:
    production_root = Path(
        os.environ.get(
            "LLPLAYERNEXT_TIMELINE_PRODUCTION_DIR",
            str(Path.home() / "Library/Caches/LLPlayerNext/research/timeline-production"),
        )
    )
    return production_root / "venv" / "bin" / "whisperx"


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def default_output_dir(input_path: Path) -> Path:
    stem = input_path.stem or "timeline-production"
    return REPO_ROOT / ".tmp" / "timeline-production-gui" / stem


class TimelineProductionGui(Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title("LLTimeline Production")
        self.geometry("980x760")
        self.minsize(860, 620)

        self.input_path = StringVar()
        self.output_dir = StringVar()
        self.output_path = StringVar()
        self.media_title = StringVar()
        self.media_fingerprint = StringVar()
        self.language = StringVar(value="en")
        self.model = StringVar(value="large-v3")
        self.device = StringVar(value="cpu")
        self.compute_type = StringVar(value="float32")
        self.batch_size = IntVar(value=16)
        self.post_aligner = StringVar(value="auto")
        self.whisperx_bin = StringVar()
        self.whisperx_command = StringVar()
        self.vocal_isolation_command = StringVar()
        self.dry_run = BooleanVar(value=False)

        self.process: subprocess.Popen[str] | None = None
        self.events: queue.Queue[tuple[str, str | int | None]] = queue.Queue()
        self._build_ui()
        detected_whisperx = default_whisperx_bin()
        if detected_whisperx.exists():
            self.whisperx_bin.set(str(detected_whisperx))
            self.status.set("Detected timeline-production WhisperX venv")
        else:
            self.status.set("WhisperX not detected; run setup-venv.sh or fill WhisperX command")
        self.after(100, self._poll_events)

    def _build_ui(self) -> None:
        root = ttk.Frame(self, padding=12)
        root.pack(fill="both", expand=True)
        root.columnconfigure(0, weight=1)
        root.rowconfigure(2, weight=1)

        form = ttk.LabelFrame(root, text="Pipeline input", padding=10)
        form.grid(row=0, column=0, sticky="ew")
        form.columnconfigure(1, weight=1)

        self._file_row(form, 0, "Media file", self.input_path, self._browse_input)
        self._file_row(form, 1, "Output dir", self.output_dir, self._browse_output_dir)
        self._file_row(form, 2, "LLTimeline output", self.output_path, self._browse_output_file)
        self._entry_row(form, 3, "Media title", self.media_title)
        self._entry_row(form, 4, "Media fingerprint", self.media_fingerprint)
        ttk.Button(form, text="Compute SHA256", command=self._compute_fingerprint).grid(
            row=4, column=3, sticky="ew", padx=(8, 0)
        )

        options = ttk.LabelFrame(root, text="Options", padding=10)
        options.grid(row=1, column=0, sticky="ew", pady=(10, 10))
        for column in range(6):
            options.columnconfigure(column, weight=1)
        self._combo(options, 0, 0, "Post-aligner", self.post_aligner, ("auto", "mfa", "mms-fa", "none"))
        self._combo(options, 0, 2, "Device", self.device, ("cpu", "cuda", "mps"))
        self._combo(options, 0, 4, "Compute type", self.compute_type, ("float32", "float16", "int8"))
        self._entry_row(options, 1, "Language", self.language, column_span=1)
        self._entry_row(options, 1, "Model", self.model, label_column=2, value_column=3, column_span=1)
        ttk.Label(options, text="Batch size").grid(row=1, column=4, sticky="w", padx=(8, 6), pady=4)
        ttk.Spinbox(options, from_=1, to=128, textvariable=self.batch_size, width=8).grid(
            row=1, column=5, sticky="ew", pady=4
        )
        self._entry_row(options, 2, "WhisperX bin", self.whisperx_bin, column_span=5)
        self._entry_row(options, 3, "WhisperX command", self.whisperx_command, column_span=5)
        self._entry_row(options, 4, "Vocal isolation command", self.vocal_isolation_command, column_span=5)
        ttk.Checkbutton(options, text="Dry run only", variable=self.dry_run).grid(
            row=5, column=0, sticky="w", pady=(6, 0)
        )

        log_frame = ttk.LabelFrame(root, text="Run log", padding=10)
        log_frame.grid(row=2, column=0, sticky="nsew")
        log_frame.rowconfigure(0, weight=1)
        log_frame.columnconfigure(0, weight=1)
        self.log = ScrolledText(log_frame, height=20, wrap="word")
        self.log.grid(row=0, column=0, sticky="nsew")

        actions = ttk.Frame(root)
        actions.grid(row=3, column=0, sticky="ew", pady=(10, 0))
        actions.columnconfigure(0, weight=1)
        self.status = StringVar(value="Ready")
        ttk.Label(actions, textvariable=self.status).grid(row=0, column=0, sticky="w")
        self.copy_button = ttk.Button(actions, text="Copy command", command=self._copy_command)
        self.copy_button.grid(row=0, column=1, padx=(8, 0))
        ttk.Button(actions, text="Open output folder", command=self._open_output_folder).grid(
            row=0, column=2, padx=(8, 0)
        )
        self.cancel_button = ttk.Button(actions, text="Cancel", command=self._cancel, state="disabled")
        self.cancel_button.grid(row=0, column=3, padx=(8, 0))
        self.run_button = ttk.Button(actions, text="Run", command=self._run)
        self.run_button.grid(row=0, column=4, padx=(8, 0))

    def _file_row(self, parent: ttk.Frame, row: int, label: str, variable: StringVar, command) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=0, sticky="w", padx=(0, 6), pady=4)
        ttk.Entry(parent, textvariable=variable).grid(row=row, column=1, columnspan=2, sticky="ew", pady=4)
        ttk.Button(parent, text="Browse", command=command).grid(row=row, column=3, sticky="ew", padx=(8, 0))

    def _entry_row(
        self,
        parent: ttk.Frame,
        row: int,
        label: str,
        variable: StringVar,
        *,
        label_column: int = 0,
        value_column: int = 1,
        column_span: int = 2,
    ) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=label_column, sticky="w", padx=(0, 6), pady=4)
        ttk.Entry(parent, textvariable=variable).grid(
            row=row, column=value_column, columnspan=column_span, sticky="ew", pady=4
        )

    def _combo(
        self,
        parent: ttk.Frame,
        row: int,
        column: int,
        label: str,
        variable: StringVar,
        values: tuple[str, ...],
    ) -> None:
        ttk.Label(parent, text=label).grid(row=row, column=column, sticky="w", padx=(0, 6), pady=4)
        ttk.Combobox(parent, textvariable=variable, values=values, state="readonly").grid(
            row=row, column=column + 1, sticky="ew", padx=(0, 8), pady=4
        )

    def _browse_input(self) -> None:
        path = filedialog.askopenfilename(
            title="Select media",
            filetypes=[
                ("Media", "*.mp4 *.mkv *.mov *.webm *.m4a *.mp3 *.wav *.flac"),
                ("All files", "*"),
            ],
        )
        if not path:
            return
        media = Path(path)
        self.input_path.set(str(media))
        if not self.media_title.get().strip():
            self.media_title.set(media.stem)
        if not self.output_dir.get().strip():
            output_dir = default_output_dir(media)
            self.output_dir.set(str(output_dir))
            self.output_path.set(str(output_dir / f"{media.stem}.lltimeline.json"))

    def _browse_output_dir(self) -> None:
        path = filedialog.askdirectory(title="Select output directory")
        if not path:
            return
        self.output_dir.set(path)
        input_path = Path(self.input_path.get()) if self.input_path.get().strip() else None
        if input_path and not self.output_path.get().strip():
            self.output_path.set(str(Path(path) / f"{input_path.stem}.lltimeline.json"))

    def _browse_output_file(self) -> None:
        path = filedialog.asksaveasfilename(
            title="Save LLTimeline",
            defaultextension=".json",
            filetypes=[("LLTimeline JSON", "*.lltimeline.json *.json"), ("All files", "*")],
        )
        if path:
            self.output_path.set(path)

    def _compute_fingerprint(self) -> None:
        try:
            path = self._require_path(self.input_path.get(), "media file")
        except ValueError as error:
            messagebox.showerror("Missing input", str(error))
            return
        self.status.set("Computing media fingerprint...")
        self._append_log(f"Computing SHA256 for {path}\n")
        threading.Thread(target=self._fingerprint_worker, args=(path,), daemon=True).start()

    def _fingerprint_worker(self, path: Path) -> None:
        try:
            self.events.put(("fingerprint", file_sha256(path)))
        except Exception as error:  # pragma: no cover - surfaced in GUI
            self.events.put(("error", f"Fingerprint failed: {error}"))

    def _run(self) -> None:
        try:
            command = self._command()
        except ValueError as error:
            messagebox.showerror("Cannot run", str(error))
            return
        output_dir = Path(self.output_dir.get()).expanduser()
        output_dir.mkdir(parents=True, exist_ok=True)
        self.log.delete("1.0", "end")
        self._append_log("$ " + " ".join(_quote(part) for part in command) + "\n\n")
        self.run_button.configure(state="disabled")
        self.cancel_button.configure(state="normal")
        self.status.set("Running...")
        threading.Thread(target=self._run_worker, args=(command,), daemon=True).start()

    def _run_worker(self, command: list[str]) -> None:
        try:
            self.process = subprocess.Popen(
                command,
                cwd=REPO_ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )
            assert self.process.stdout is not None
            for line in self.process.stdout:
                self.events.put(("log", line))
            self.events.put(("done", self.process.wait()))
        except Exception as error:  # pragma: no cover - surfaced in GUI
            self.events.put(("error", f"Run failed: {error}"))

    def _cancel(self) -> None:
        if self.process and self.process.poll() is None:
            self.process.terminate()
            self.status.set("Cancelling...")

    def _copy_command(self) -> None:
        try:
            command = self._command()
        except ValueError as error:
            messagebox.showerror("Cannot build command", str(error))
            return
        text = " ".join(_quote(part) for part in command)
        self.clipboard_clear()
        self.clipboard_append(text)
        self.status.set("Command copied")

    def _open_output_folder(self) -> None:
        path = Path(self.output_dir.get() or ".").expanduser()
        path.mkdir(parents=True, exist_ok=True)
        if sys.platform == "darwin":
            subprocess.Popen(["open", str(path)])
        elif os.name == "nt":
            os.startfile(path)  # type: ignore[attr-defined]
        else:
            subprocess.Popen(["xdg-open", str(path)])

    def _command(self) -> list[str]:
        input_path = self._require_path(self.input_path.get(), "media file")
        output_dir = self._require_text(self.output_dir.get(), "output directory")
        output_path = self._require_text(self.output_path.get(), "LLTimeline output")
        title = self._require_text(self.media_title.get(), "media title")
        fingerprint = self.media_fingerprint.get().strip() or file_sha256(input_path)
        if not self.media_fingerprint.get().strip():
            self.media_fingerprint.set(fingerprint)
        command = [
            sys.executable,
            str(PIPELINE),
            "produce-whisperx",
            "--input",
            str(input_path),
            "--output-dir",
            output_dir,
            "--output",
            output_path,
            "--media-fingerprint",
            fingerprint,
            "--media-title",
            title,
            "--media-path",
            str(input_path),
            "--language",
            self.language.get().strip() or "en",
            "--model",
            self.model.get().strip() or "large-v3",
            "--device",
            self.device.get().strip() or "cpu",
            "--compute-type",
            self.compute_type.get().strip() or "float32",
            "--batch-size",
            str(self.batch_size.get()),
            "--post-aligner",
            self.post_aligner.get().strip() or "auto",
        ]
        self._append_optional(command, "--whisperx-bin", self.whisperx_bin.get())
        self._append_optional(command, "--whisperx-command", self.whisperx_command.get())
        self._append_optional(command, "--vocal-isolation-command", self.vocal_isolation_command.get())
        if self.dry_run.get():
            command.append("--dry-run")
        return command

    def _poll_events(self) -> None:
        while True:
            try:
                kind, payload = self.events.get_nowait()
            except queue.Empty:
                break
            if kind == "log":
                self._append_log(str(payload))
            elif kind == "fingerprint":
                self.media_fingerprint.set(str(payload))
                self.status.set("Fingerprint ready")
                self._append_log(f"SHA256: {payload}\n")
            elif kind == "done":
                code = int(payload)
                self.process = None
                self.run_button.configure(state="normal")
                self.cancel_button.configure(state="disabled")
                self.status.set("Completed" if code == 0 else f"Failed with exit code {code}")
                self._append_log(f"\nProcess exited with code {code}\n")
                self._summarize_last_json()
            elif kind == "error":
                self.process = None
                self.run_button.configure(state="normal")
                self.cancel_button.configure(state="disabled")
                self.status.set("Error")
                self._append_log(str(payload) + "\n")
        self.after(100, self._poll_events)

    def _summarize_last_json(self) -> None:
        for line in reversed(self.log.get("1.0", "end").splitlines()):
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(payload, dict):
                output = payload.get("output")
                ready = payload.get("ready_for_manual_review")
                if output:
                    self._append_log(f"LLTimeline output: {output}\n")
                if ready is not None:
                    self._append_log(f"Ready for manual review: {ready}\n")
            return

    def _append_log(self, text: str) -> None:
        self.log.insert("end", text)
        self.log.see("end")

    def _require_path(self, value: str, label: str) -> Path:
        text = self._require_text(value, label)
        path = Path(text).expanduser()
        if not path.exists():
            raise ValueError(f"{label} does not exist: {path}")
        return path

    def _require_text(self, value: str, label: str) -> str:
        text = value.strip()
        if not text:
            raise ValueError(f"{label} is required")
        return text

    def _append_optional(self, command: list[str], flag: str, value: str) -> None:
        text = value.strip()
        if text:
            command.extend([flag, text])


def _quote(value: str) -> str:
    return shlex.quote(value)


def main() -> int:
    app = TimelineProductionGui()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
