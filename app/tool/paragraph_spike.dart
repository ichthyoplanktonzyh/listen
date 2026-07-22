// Dev tool: run reading-paragraph derivation over real sentences dumped by
// `cargo run -p subtitle-core --example dump_sentences` and print the
// resulting paragraphs for manual QA.
//
// Usage: dart run tool/paragraph_spike.dart <sentences.jsonl>

// ignore_for_file: avoid_print — CLI dev tool, print is its output.

import 'dart:convert';
import 'dart:io';

import 'package:llplayer_next/models/reading.dart';
import 'package:llplayer_next/models/timeline.dart';

String _clock(Duration d) {
  final m = d.inMinutes;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '$m:$s';
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/paragraph_spike.dart <sentences.jsonl>');
    exit(2);
  }
  final cues = File(args.first)
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .map((line) {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final words = json['word_count'] as int;
        return Cue(
          id: json['id'] as String,
          index: json['index'] as int,
          start: Duration(milliseconds: json['start_ms'] as int),
          end: Duration(milliseconds: json['end_ms'] as int),
          text: json['text'] as String,
          tokens: List.generate(
            words,
            (i) => SubtitleToken(
              index: i,
              kind: 'word',
              text: 'w$i',
              normalized: 'w$i',
            ),
          ),
        );
      })
      .toList(growable: false);

  final paragraphs = deriveReadingParagraphs(cues);
  var speech = 0;
  var nonSpeech = 0;
  final wordCounts = <int>[];
  for (final paragraph in paragraphs) {
    if (paragraph.nonSpeech) {
      nonSpeech++;
      print('--- [${_clock(paragraph.start)}] ${paragraph.sentences.single.text}');
      continue;
    }
    speech++;
    wordCounts.add(paragraph.wordCount);
    print(
      '\n¶ [${_clock(paragraph.start)}–${_clock(paragraph.end)}] '
      '${paragraph.wordCount}w ${paragraph.sentences.length}s',
    );
    for (final sentence in paragraph.sentences) {
      print('   ${sentence.speakerTurn ? "» " : ""}${sentence.text}');
    }
  }
  wordCounts.sort();
  final median = wordCounts.isEmpty ? 0 : wordCounts[wordCounts.length ~/ 2];
  print(
    '\n== cues=${cues.length} paragraphs=$speech nonSpeech=$nonSpeech '
    'words/para median=$median max=${wordCounts.isEmpty ? 0 : wordCounts.last}',
  );
}
