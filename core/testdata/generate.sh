#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
out="$root/generated"
mkdir -p "$out"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=960x540:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=10" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$out/sample-video.mp4"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "sine=frequency=660:sample_rate=48000:duration=10" \
  -c:a aac "$out/sample-audio.m4a"

ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=640x360:rate=30:duration=10" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=10" \
  -f lavfi -i "sine=frequency=880:sample_rate=48000:duration=10" \
  -map 0:v -map 1:a -map 2:a -metadata:s:a:0 language=eng \
  -metadata:s:a:1 language=jpn -c:v libx264 -pix_fmt yuv420p -c:a aac \
  -shortest "$out/multi-audio.mkv"

ffmpeg -hide_banner -loglevel error -y \
  -i "$out/sample-video.mp4" -i "$root/subtitles/timeline.srt" \
  -map 0:v -map 0:a -map 1:s -metadata:s:s:0 language=eng \
  -c:v copy -c:a copy -c:s srt "$out/embedded-text-subtitle.mkv"

awk 'BEGIN {
  for (i = 1; i <= 2100; i++) {
    start = i - 1;
    end = start + 0.8;
    printf "%d\n00:%02d:%02d,000 --> 00:%02d:%02d,800\nCue %d can'\''t re-enter.\n\n",
      i, int(start / 60) % 60, start % 60, int(end / 60) % 60, int(end) % 60, i;
  }
}' > "$out/long-timeline.srt"

shasum -a 256 "$out"/* > "$out/SHA256SUMS"
echo "Generated M0 fixtures in $out"
