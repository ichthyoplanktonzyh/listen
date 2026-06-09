import { useEffect, useMemo, useState } from "react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import {
  command,
  getProperty,
  init,
  MpvObservableProperty,
  observeProperties,
  setProperty,
} from "tauri-plugin-libmpv-api";
import "./App.css";

const OBSERVED_PROPERTIES = [
  ["pause", "flag"],
  ["time-pos", "double", "none"],
  ["duration", "double", "none"],
  ["track-list", "node", "none"],
] as const satisfies MpvObservableProperty[];

const SAMPLE_VIDEO =
  "/Users/shadow/LLPlayerNext/testdata/generated/sample-video.mp4";
const SAMPLE_AUDIO =
  "/Users/shadow/LLPlayerNext/testdata/generated/sample-audio.m4a";

function seconds(value: number | null) {
  return `${(value ?? 0).toFixed(2)}s`;
}

function App() {
  const [ready, setReady] = useState(false);
  const [paused, setPaused] = useState(true);
  const [position, setPosition] = useState<number | null>(0);
  const [duration, setDuration] = useState<number | null>(0);
  const [tracks, setTracks] = useState<unknown>([]);
  const [looping, setLooping] = useState(false);
  const [message, setMessage] = useState("Initializing libmpv...");

  useEffect(() => {
    let unlisten: undefined | (() => void);
    init({
      initialOptions: {
        vo: "gpu-next",
        hwdec: "auto-safe",
        "keep-open": "yes",
        "force-window": "yes",
      },
      observedProperties: OBSERVED_PROPERTIES,
    })
      .then(async () => {
        unlisten = await observeProperties(OBSERVED_PROPERTIES, ({ name, data }) => {
          if (name === "pause") setPaused(Boolean(data));
          if (name === "time-pos") setPosition(data as number | null);
          if (name === "duration") setDuration(data as number | null);
          if (name === "track-list") setTracks(data ?? []);
        });
        setReady(true);
        await command("loadfile", [SAMPLE_VIDEO]);
        setMessage("libmpv ready; sample video loaded");
        await getCurrentWindow().setTitle("Tauri libmpv READY");
      })
      .catch((error) => {
        const text = `libmpv init failed: ${String(error)}`;
        setMessage(text);
        void getCurrentWindow().setTitle(`Tauri libmpv ERROR: ${String(error)}`);
      });

    return () => unlisten?.();
  }, []);

  useEffect(() => {
    if (!looping || position === null) return;
    if (position >= 4.8 || position < 3) {
      void command("seek", [3, "absolute+exact"]);
    }
  }, [looping, position]);

  const trackCount = useMemo(
    () => (Array.isArray(tracks) ? tracks.length : 0),
    [tracks],
  );

  async function load(path: string) {
    setMessage(`Opening ${path.split("/").slice(-1)[0]}`);
    await command("loadfile", [path]);
    setTracks(await getProperty("track-list", "node"));
  }

  async function toggleLoop() {
    const next = !looping;
    setLooping(next);
    if (next) await command("seek", [3, "absolute+exact"]);
  }

  return (
    <main>
      <section className="video-surface">
        <button
          className="subtitle-overlay"
          onClick={() => command("seek", [3, "absolute+exact"])}
          title="Click to seek to the cue start"
        >
          I can&apos;t re-enter. Click this subtitle to seek.
        </button>
      </section>

      <section className="panel">
        <h1>Tauri + libmpv M0</h1>
        <p className="status">{message}</p>
        <p>
          {paused ? "paused" : "playing"} | {seconds(position)} /{" "}
          {seconds(duration)} | {trackCount} tracks | loop{" "}
          {looping ? "on" : "off"}
        </p>
        <div className="controls">
          <button disabled={!ready} onClick={() => load(SAMPLE_VIDEO)}>
            Open video
          </button>
          <button disabled={!ready} onClick={() => load(SAMPLE_AUDIO)}>
            Open audio
          </button>
          <button disabled={!ready} onClick={() => setProperty("pause", !paused)}>
            {paused ? "Play" : "Pause"}
          </button>
          <button disabled={!ready} onClick={() => command("stop")}>
            Stop
          </button>
          <button disabled={!ready} onClick={() => command("seek", [1, "relative+exact"])}>
            +1s
          </button>
          <button disabled={!ready} onClick={() => command("seek", [-1, "relative+exact"])}>
            -1s
          </button>
          <button disabled={!ready} onClick={() => setProperty("speed", 0.75)}>
            0.75x
          </button>
          <button disabled={!ready} onClick={() => setProperty("speed", 1)}>
            1x
          </button>
          <button disabled={!ready} onClick={() => setProperty("volume", 50)}>
            Volume 50%
          </button>
          <button disabled={!ready} onClick={toggleLoop}>
            Toggle cue loop
          </button>
        </div>
      </section>
    </main>
  );
}

export default App;
