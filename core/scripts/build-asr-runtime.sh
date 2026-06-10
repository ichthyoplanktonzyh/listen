#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
build="$root/third_party/runtime/build"
output="$root/third_party/runtime/macos-arm64"
jobs="${JOBS:-$(sysctl -n hw.logicalcpu)}"
mkdir -p "$build" "$output"

whisper_commit="a8d002cfd879315632a579e73f0148d06959de36"
whisper="$build/whisper.cpp"
if [[ ! -d "$whisper/.git" ]]; then
  git clone https://github.com/ggml-org/whisper.cpp.git "$whisper"
fi
git -C "$whisper" fetch --tags
git -C "$whisper" checkout --detach "$whisper_commit"
cmake -S "$whisper" -B "$whisper/build-m17" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DWHISPER_METAL=ON \
  -DWHISPER_BUILD_TESTS=OFF \
  -DWHISPER_BUILD_EXAMPLES=ON
cmake --build "$whisper/build-m17" --config Release -j "$jobs"
cp "$whisper/build-m17/bin/whisper-cli" "$output/whisper-cli"

ffmpeg_archive="$build/ffmpeg-8.0.1.tar.xz"
ffmpeg_source="$build/ffmpeg-8.0.1"
if [[ ! -f "$ffmpeg_archive" ]]; then
  curl --fail --location --retry 3 \
    https://ffmpeg.org/releases/ffmpeg-8.0.1.tar.xz \
    -o "$ffmpeg_archive"
fi
echo "05ee0b03119b45c0bdb4df654b96802e909e0a752f72e4fe3794f487229e5a41  $ffmpeg_archive" | shasum -a 256 -c -
if [[ ! -d "$ffmpeg_source" ]]; then
  tar -xf "$ffmpeg_archive" -C "$build"
fi
(
  cd "$ffmpeg_source"
  ./configure \
    --prefix="$build/ffmpeg-install" \
    --arch=arm64 \
    --disable-gpl \
    --disable-nonfree \
    --disable-version3 \
    --disable-doc \
    --disable-debug \
    --disable-shared \
    --enable-static
  make -j "$jobs" ffmpeg ffprobe
)
cp "$ffmpeg_source/ffmpeg" "$ffmpeg_source/ffprobe" "$output/"
chmod +x "$output/whisper-cli" "$output/ffmpeg" "$output/ffprobe"

"$root/scripts/verify-asr-runtime.sh" "$output"
