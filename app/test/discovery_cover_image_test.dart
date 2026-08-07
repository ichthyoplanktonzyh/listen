import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/services/cover_art_cache.dart';
import 'package:llplayer_next/widgets/discovery/cover_image.dart';

/// Cover art must be decoded at the size it is drawn.
///
/// The real incident: a shelf of podcast episodes appeared slowly and then
/// kept flickering. Apple requires podcast artwork at 3000×3000, so every
/// cover decoded to about 36 MB of bitmap while being drawn into a 168×94
/// box. Twenty distinct covers on the first screen asked for roughly 720 MB
/// against Flutter's 100 MB image cache, so it evicted constantly and every
/// eviction meant decoding a 9-megapixel JPEG again.
void main() {
  Future<void> pumpCover(
    WidgetTester tester, {
    required double width,
    double devicePixelRatio = 1,
  }) => tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(devicePixelRatio: devicePixelRatio),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: DiscoveryCoverImage(
          url: 'https://example.com/3000x3000/art.jpg',
          width: width,
          tone: const Color(0xFF102030),
          fallback: const Text('fallback'),
        ),
      ),
    ),
  );

  ResizeImage resizeProviderOf(WidgetTester tester) {
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      image.image,
      isA<ResizeImage>(),
      reason: 'without a cache hint the full source bitmap is decoded',
    );
    return image.image as ResizeImage;
  }

  testWidgets('the decode is bounded by the drawn width', (tester) async {
    await pumpCover(tester, width: 168);

    expect(resizeProviderOf(tester).width, 168);
  });

  testWidgets('the bound accounts for the device pixel ratio', (tester) async {
    // cacheWidth is in physical pixels. Decoding a 168pt box at 168px on a 3×
    // display would be visibly soft, so the ratio is part of the bound rather
    // than a fixed number.
    await pumpCover(tester, width: 168, devicePixelRatio: 3);

    expect(resizeProviderOf(tester).width, 504);
  });

  testWidgets('the two draw sizes share one fetch', (tester) async {
    // Bounding the decode fixed the flicker and none of the waiting: the bytes
    // were still the whole 3000×3000 file. Flutter's image cache is keyed by
    // decode size, so the detail panel at 380 missed what the card at 168 had
    // already downloaded and fetched the same half-megabyte again. The sharing
    // has to happen below the decode.
    await pumpCover(tester, width: 168);
    final card = resizeProviderOf(tester).imageProvider;

    await pumpCover(tester, width: 380);
    final hero = resizeProviderOf(tester).imageProvider;

    expect(card, isA<CoverArtImage>());
    expect(
      hero,
      card,
      reason: 'one URL is one cache entry regardless of who drew it',
    );
  });

  testWidgets('the loading state is not the unavailable state', (tester) async {
    // A cover on its way and one that will never arrive are different facts.
    // Rendering the substitute immediately would say "there is no artwork"
    // about something still downloading.
    //
    // The builders are exercised directly: the test binding answers every
    // image request with a failure, so a widget-tree assertion here would only
    // ever observe the error path.
    await pumpCover(tester, width: 168);
    final image = tester.widget<Image>(find.byType(Image));
    final context = tester.element(find.byType(Image));

    expect(image.loadingBuilder, isNotNull);
    expect(image.errorBuilder, isNotNull);

    final child = Container();
    final loading = image.loadingBuilder!(
      context,
      child,
      const ImageChunkEvent(cumulativeBytesLoaded: 1, expectedTotalBytes: 100),
    );
    final loaded = image.loadingBuilder!(context, child, null);
    final failed = image.errorBuilder!(context, 'boom', null);

    expect(loading, isA<ColoredBox>());
    // A finished load hands back the decoded image itself, not the tone.
    expect(loaded, same(child));
    expect(failed, isA<Text>());
  });
}
