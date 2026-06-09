# Flutter + media_kit M0 Spike

This spike validates local video and audio playback, position events, seeking,
rate, volume, track discovery, cue-range looping, and a clickable subtitle
overlay on macOS Apple Silicon.

```sh
./testdata/generate.sh
/Users/shadow/.local/share/flutter/bin/flutter run -d macos
```

Build and static verification:

```sh
/Users/shadow/.local/share/flutter/bin/flutter analyze
/Users/shadow/.local/share/flutter/bin/flutter test
/Users/shadow/.local/share/flutter/bin/flutter build macos
```

The M0 prototype disables App Sandbox so it can automatically load generated
fixtures from this repository. The product implementation must restore sandbox
access and use a file picker with security-scoped file access.

On launch, the prototype runs a short automated verification sequence and
writes evidence to `/tmp/llplayernext-flutter-m0.log`.
