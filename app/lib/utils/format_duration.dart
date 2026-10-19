/// Format a [Duration] as `HH:MM:SS`.
String formatDuration(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '${value.inHours.toString().padLeft(2, '0')}:$minutes:$seconds';
}
