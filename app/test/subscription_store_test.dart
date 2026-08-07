import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/models/discovery.dart';
import 'package:llplayer_next/services/subscription_store.dart';

/// A subscription has to survive the app closing.
///
/// The real incident: both discovery repositories kept their custom sources in
/// a plain in-memory list. Pasting a feed address added a channel that existed
/// until quit; on the next launch the built-in starters were back and
/// everything the person had subscribed to was gone. Silent data loss, and of
/// the kind that reads as "subscribing never worked".
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('subscriptions-'));
  tearDown(() => root.deleteSync(recursive: true));

  SubscriptionStore store() => SubscriptionStore(directory: root);

  MediaSource source(
    String id, {
    String name = 'Channel',
    MediaSourceType type = MediaSourceType.podcast,
  }) => MediaSource(
    id: id,
    name: name,
    language: 'en',
    description: 'A description',
    cover: ChannelCoverTone.slate,
    type: type,
    avatarUrl: 'https://cdn.example.com/cover.jpg',
  );

  test('a subscription survives into a new instance', () async {
    final first = store();
    await first.load();
    await first.add(source('https://feeds.npr.org/510318/podcast.xml'));

    final second = store();
    await second.load();

    final restored = second.of(MediaSourceType.podcast);
    expect(restored, hasLength(1));
    expect(restored.single.id, 'https://feeds.npr.org/510318/podcast.xml');
    expect(restored.single.name, 'Channel');
    expect(restored.single.avatarUrl, 'https://cdn.example.com/cover.jpg');
    expect(restored.single.cover, ChannelCoverTone.slate);
  });

  test('the two source kinds are kept apart', () async {
    final subject = store();
    await subject.load();
    await subject.add(source('https://feed.example/rss'));
    await subject.add(source('UC-channel', type: MediaSourceType.youtube));

    expect(
      subject.of(MediaSourceType.podcast).single.id,
      'https://feed.example/rss',
    );
    expect(subject.of(MediaSourceType.youtube).single.id, 'UC-channel');
  });

  test('re-subscribing refreshes rather than duplicates', () async {
    // A feed's title and artwork change; subscribing again should adopt them
    // without the channel appearing twice in the rail.
    final subject = store();
    await subject.load();
    await subject.add(source('https://feed.example/rss', name: 'Old name'));
    await subject.add(source('https://feed.example/rss', name: 'New name'));

    final stored = subject.of(MediaSourceType.podcast);
    expect(stored, hasLength(1));
    expect(stored.single.name, 'New name');
  });

  test('removing a subscription persists the removal', () async {
    final first = store();
    await first.load();
    await first.add(source('https://feed.example/rss'));
    await first.remove('https://feed.example/rss');

    final second = store();
    await second.load();

    expect(second.of(MediaSourceType.podcast), isEmpty);
  });

  test('an in-memory store keeps nothing on disk', () async {
    // The default for every caller that did not ask for persistence, so no
    // test touches the developer's own subscriptions.
    final subject = SubscriptionStore.inMemory();
    await subject.load();
    await subject.add(source('https://feed.example/rss'));

    expect(subject.of(MediaSourceType.podcast), hasLength(1));
    expect(root.listSync(), isEmpty);
  });

  test(
    'a corrupt file reads as empty rather than failing the launch',
    () async {
      File('${root.path}/subscriptions-v1.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{"subscriptions": [not json');

      final subject = store();
      await subject.load();

      expect(subject.of(MediaSourceType.podcast), isEmpty);
      expect(subject.isLoaded, isTrue);
    },
  );

  test('unreadable rows are dropped without discarding good ones', () async {
    // A row that cannot be reconstructed exactly is not one to reconstruct
    // approximately: a guessed type would file a podcast under YouTube and
    // send it down the wrong acquisition path entirely.
    File('${root.path}/subscriptions-v1.json')
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'version': 1,
          'subscriptions': [
            {
              'id': 'https://good.example/rss',
              'name': 'Good',
              'language': 'en',
              'description': '',
              'cover': 'slate',
              'type': 'podcast',
            },
            {'id': 'no-name', 'cover': 'slate', 'type': 'podcast'},
            {
              'id': 'unknown-type',
              'name': 'X',
              'cover': 'slate',
              'type': 'vimeo',
            },
            {
              'id': 'unknown-cover',
              'name': 'X',
              'cover': 'chartreuse',
              'type': 'podcast',
            },
          ],
        }),
      );

    final subject = store();
    await subject.load();

    final restored = subject.of(MediaSourceType.podcast);
    expect(restored, hasLength(1));
    expect(restored.single.id, 'https://good.example/rss');
  });

  test('an absent file is an empty store, not an error', () async {
    final subject = store();

    await subject.load();

    expect(subject.isLoaded, isTrue);
    expect(subject.of(MediaSourceType.podcast), isEmpty);
  });
}
