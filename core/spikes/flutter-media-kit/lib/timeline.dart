class Cue {
  const Cue(this.id, this.start, this.end);

  final String id;
  final Duration start;
  final Duration end;
}

Cue? currentCueAt(List<Cue> cues, Duration position) {
  Cue? selected;
  for (final cue in cues) {
    if (position >= cue.start && position <= cue.end) {
      if (selected == null || cue.start > selected.start) {
        selected = cue;
      }
    }
  }
  return selected;
}
