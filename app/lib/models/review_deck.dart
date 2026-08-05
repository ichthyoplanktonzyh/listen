import 'practice.dart';

/// The review surfaces contract 1.1.0 added around the card session: the deck
/// overview, the daily-limit budget, the FSRS interval prediction, custom
/// study, and Anki package interop.
///
/// These live apart from `practice.dart` because they are a different shape of
/// fact — counts, budgets and predictions *about* the queue rather than the
/// cards in it — and because none of them existed when the practice model was
/// written.

/// The global daily budget. Not a target and not a debt: the session reports
/// it so a finished round can say which of the two limits ended it.
class ReviewDailyLimits {
  const ReviewDailyLimits({required this.newCards, required this.reviews});

  factory ReviewDailyLimits.fromJson(Map<String, dynamic> json) =>
      ReviewDailyLimits(
        newCards: json['new_cards'] as int,
        reviews: json['reviews'] as int,
      );

  final int newCards;
  final int reviews;

  Map<String, dynamic> toJson() => {
    'new_cards': newCards,
    'reviews': reviews,
  };

  ReviewDailyLimits copyWith({int? newCards, int? reviews}) =>
      ReviewDailyLimits(
        newCards: newCards ?? this.newCards,
        reviews: reviews ?? this.reviews,
      );
}

/// How much of today's budget is spent, and whether either ceiling stopped the
/// queue. `new_limit_reached` is what separates "you are done for today" from
/// "there is genuinely nothing left" — two states the finished screen must
/// never conflate.
class ReviewLimitStatus {
  const ReviewLimitStatus({
    required this.limits,
    required this.newCompleted,
    required this.reviewsCompleted,
    required this.newLimitReached,
    required this.reviewLimitReached,
  });

  factory ReviewLimitStatus.fromJson(Map<String, dynamic> json) =>
      ReviewLimitStatus(
        limits: ReviewDailyLimits.fromJson(
          json['limits'] as Map<String, dynamic>,
        ),
        newCompleted: json['new_completed'] as int,
        reviewsCompleted: json['reviews_completed'] as int,
        newLimitReached: json['new_limit_reached'] as bool,
        reviewLimitReached: json['review_limit_reached'] as bool,
      );

  final ReviewDailyLimits limits;
  final int newCompleted;
  final int reviewsCompleted;
  final bool newLimitReached;
  final bool reviewLimitReached;

  bool get anyLimitReached => newLimitReached || reviewLimitReached;
}

/// The due queue after the backend has clipped it to today's budget.
class ReviewQueue {
  const ReviewQueue({required this.entries, required this.limitStatus});

  factory ReviewQueue.fromJson(Map<String, dynamic> json) => ReviewQueue(
    entries: ((json['entries'] as List<dynamic>?) ?? const [])
        .map((value) => ReviewQueueEntry.fromJson(value as Map<String, dynamic>))
        .toList(growable: false),
    limitStatus: ReviewLimitStatus.fromJson(
      json['limit_status'] as Map<String, dynamic>,
    ),
  );

  final List<ReviewQueueEntry> entries;
  final ReviewLimitStatus limitStatus;
}

/// Anki's three classic per-deck numbers.
class ReviewStateCounts {
  const ReviewStateCounts({
    required this.newCards,
    required this.learning,
    required this.due,
  });

  factory ReviewStateCounts.fromJson(Map<String, dynamic> json) =>
      ReviewStateCounts(
        newCards: json['new'] as int,
        learning: json['learning'] as int,
        due: json['due'] as int,
      );

  final int newCards;
  final int learning;
  final int due;

  int get total => newCards + learning + due;
}

/// A native deck: one of the four capability channels, faceted automatically
/// rather than filed by hand.
class ReviewChannelDeck {
  const ReviewChannelDeck({required this.channel, required this.counts});

  factory ReviewChannelDeck.fromJson(Map<String, dynamic> json) =>
      ReviewChannelDeck(
        channel: json['channel'] as String,
        counts: ReviewStateCounts.fromJson(
          json['counts'] as Map<String, dynamic>,
        ),
      );

  final String channel;
  final ReviewStateCounts counts;
}

/// A deck that came in from an `.apkg`, keeping the tree the learner already
/// built in Anki instead of being scattered across the four channels.
class ReviewImportedDeck {
  const ReviewImportedDeck({
    required this.deckId,
    required this.name,
    required this.parentDeckId,
    required this.counts,
  });

  factory ReviewImportedDeck.fromJson(Map<String, dynamic> json) =>
      ReviewImportedDeck(
        deckId: json['deck_id'] as String,
        name: json['name'] as String,
        parentDeckId: json['parent_deck_id'] as String?,
        counts: ReviewStateCounts.fromJson(
          json['counts'] as Map<String, dynamic>,
        ),
      );

  final String deckId;
  final String name;
  final String? parentDeckId;
  final ReviewStateCounts counts;
}

class ReviewDeckOverview {
  const ReviewDeckOverview({
    required this.channels,
    required this.importedDecks,
    required this.limitStatus,
  });

  factory ReviewDeckOverview.fromJson(Map<String, dynamic> json) =>
      ReviewDeckOverview(
        channels: ((json['channels'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  ReviewChannelDeck.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        importedDecks: ((json['imported_decks'] as List<dynamic>?) ?? const [])
            .map(
              (value) =>
                  ReviewImportedDeck.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        limitStatus: ReviewLimitStatus.fromJson(
          json['limit_status'] as Map<String, dynamic>,
        ),
      );

  final List<ReviewChannelDeck> channels;
  final List<ReviewImportedDeck> importedDecks;
  final ReviewLimitStatus limitStatus;

  int get dueTotal => nativeCounts.total + importedCounts.total;

  /// Every native card as one deck. The backend still files each card under a
  /// channel, and that stays useful for *picking* extra practice — but it is
  /// not how the review home is organised, because a channel has no scheduled
  /// queue of its own and so splitting the rows changed nothing a learner
  /// could act on.
  ReviewStateCounts get nativeCounts => _sum(channels.map((d) => d.counts));

  ReviewStateCounts get importedCounts =>
      _sum(importedDecks.map((d) => d.counts));

  static ReviewStateCounts _sum(Iterable<ReviewStateCounts> counts) =>
      counts.fold(
        const ReviewStateCounts(newCards: 0, learning: 0, due: 0),
        (total, next) => ReviewStateCounts(
          newCards: total.newCards + next.newCards,
          learning: total.learning + next.learning,
          due: total.due + next.due,
        ),
      );
}

/// What one rating would do to this card, predicted by FSRS without writing
/// anything. The learner sees these under the grade buttons.
class ReviewIntervalPreview {
  const ReviewIntervalPreview({
    required this.rating,
    required this.dueAtMs,
    required this.intervalDays,
    required this.state,
  });

  factory ReviewIntervalPreview.fromJson(Map<String, dynamic> json) =>
      ReviewIntervalPreview(
        rating: json['rating'] as String,
        dueAtMs: json['due_at_ms'] as int,
        intervalDays: (json['interval_days'] as num).toDouble(),
        state: ReviewCardState.fromJson(json['state'] as String),
      );

  final String rating;
  final int dueAtMs;
  final double intervalDays;
  final ReviewCardState state;
}

/// The four ways to practise beyond today's schedule.
enum CustomStudyKind {
  moreNew('more_new'),
  reviewAhead('review_ahead'),
  channel('channel'),
  forgotten('forgotten');

  const CustomStudyKind(this.wire);

  final String wire;
}

class CustomStudyRequest {
  const CustomStudyRequest({
    required this.kind,
    this.channel,
    this.minimumLapses,
    this.limit,
  });

  final CustomStudyKind kind;
  final String? channel;
  final int? minimumLapses;
  final int? limit;

  Map<String, dynamic> toJson() => {
    'kind': kind.wire,
    if (channel != null) 'channel': channel,
    if (minimumLapses != null) 'minimum_lapses': minimumLapses,
    if (limit != null) 'limit': limit,
  };
}

/// A one-shot extra queue. [advancesNormalSchedule] is the backend saying
/// whether grading these cards moves the real schedule — the learner is told
/// which it is before starting, not left to assume.
class CustomStudyQueue {
  const CustomStudyQueue({
    required this.entries,
    required this.advancesNormalSchedule,
  });

  factory CustomStudyQueue.fromJson(Map<String, dynamic> json) =>
      CustomStudyQueue(
        entries: ((json['entries'] as List<dynamic>?) ?? const [])
            .map(
              (value) => ReviewQueueEntry.fromJson(value as Map<String, dynamic>),
            )
            .toList(growable: false),
        advancesNormalSchedule: json['advances_normal_schedule'] as bool,
      );

  final List<ReviewQueueEntry> entries;
  final bool advancesNormalSchedule;
}

class AnkiPackageImportSummary {
  const AnkiPackageImportSummary({
    required this.importedCards,
    required this.updatedCards,
    required this.skippedCards,
    required this.importedDecks,
    required this.importedRevlogEntries,
    required this.importedMediaFiles,
    required this.warnings,
  });

  factory AnkiPackageImportSummary.fromJson(Map<String, dynamic> json) =>
      AnkiPackageImportSummary(
        importedCards: json['imported_cards'] as int,
        updatedCards: json['updated_cards'] as int,
        skippedCards: json['skipped_cards'] as int,
        importedDecks: json['imported_decks'] as int,
        importedRevlogEntries: json['imported_revlog_entries'] as int,
        importedMediaFiles: json['imported_media_files'] as int,
        warnings: ((json['warnings'] as List<dynamic>?) ?? const [])
            .cast<String>()
            .toList(growable: false),
      );

  final int importedCards;
  final int updatedCards;
  final int skippedCards;
  final int importedDecks;
  final int importedRevlogEntries;
  final int importedMediaFiles;
  final List<String> warnings;
}

/// What an export could not carry across. Every number here is measured by the
/// exporter, so the disclosure the learner confirms is the real boundary of
/// the file they are about to get, not a generic warning.
class AnkiExportFidelity {
  const AnkiExportFidelity({
    required this.cardsWithMediaSlices,
    required this.videoSlicesRenderedAsAudio,
    required this.mediaRenderFailures,
    required this.omittedCapabilities,
  });

  factory AnkiExportFidelity.fromJson(Map<String, dynamic> json) =>
      AnkiExportFidelity(
        cardsWithMediaSlices: json['cards_with_media_slices'] as int,
        videoSlicesRenderedAsAudio:
            json['video_slices_rendered_as_audio'] as int,
        mediaRenderFailures: json['media_render_failures'] as int,
        omittedCapabilities:
            ((json['omitted_capabilities'] as List<dynamic>?) ?? const [])
                .cast<String>()
                .toList(growable: false),
      );

  final int cardsWithMediaSlices;
  final int videoSlicesRenderedAsAudio;
  final int mediaRenderFailures;
  final List<String> omittedCapabilities;
}

class AnkiPackageExportRequest {
  const AnkiPackageExportRequest({
    required this.packagePath,
    this.deckIds = const [],
    this.channels = const [],
  });

  final String packagePath;
  final List<String> deckIds;
  final List<String> channels;

  Map<String, dynamic> toJson() => {
    'package_path': packagePath,
    if (deckIds.isNotEmpty) 'deck_ids': deckIds,
    if (channels.isNotEmpty) 'channels': channels,
  };
}

class AnkiPackageExportSummary {
  const AnkiPackageExportSummary({
    required this.exportedCards,
    required this.exportedRevlogEntries,
    required this.exportedMediaFiles,
    required this.fidelity,
    required this.warnings,
  });

  factory AnkiPackageExportSummary.fromJson(Map<String, dynamic> json) =>
      AnkiPackageExportSummary(
        exportedCards: json['exported_cards'] as int,
        exportedRevlogEntries: json['exported_revlog_entries'] as int,
        exportedMediaFiles: json['exported_media_files'] as int,
        fidelity: AnkiExportFidelity.fromJson(
          json['fidelity'] as Map<String, dynamic>,
        ),
        warnings: ((json['warnings'] as List<dynamic>?) ?? const [])
            .cast<String>()
            .toList(growable: false),
      );

  final int exportedCards;
  final int exportedRevlogEntries;
  final int exportedMediaFiles;
  final AnkiExportFidelity fidelity;
  final List<String> warnings;
}
