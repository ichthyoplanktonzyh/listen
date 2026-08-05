import 'package:flutter/material.dart';

/// Remote cover art, decoded at the size it is actually drawn.
///
/// Podcast artwork is published at 3000×3000 because Apple requires it, and a
/// shelf renders it into a 168×94 box. `Image.network` with no cache hint
/// decodes the full bitmap — 3000×3000×4 bytes, about 36 MB per image — so a
/// first screen of twenty distinct covers asked for roughly 720 MB of decoded
/// pixels against a 100 MB image cache. The cache evicted constantly, every
/// eviction meant decoding a 9-megapixel JPEG again, and the covers appeared
/// slowly and then kept disappearing.
///
/// [cacheWidth] is in physical pixels, so the device pixel ratio has to be
/// part of it: on a 3× display a 168pt box is 504px, and decoding narrower
/// than that would look soft.
class DiscoveryCoverImage extends StatelessWidget {
  const DiscoveryCoverImage({
    super.key,
    required this.url,
    required this.width,
    required this.fallback,
    required this.tone,
  });

  final String url;

  /// The box width in logical pixels. Height follows from the aspect ratio, so
  /// constraining one axis is enough to bound the decode.
  final double width;

  /// Shown when the artwork cannot be loaded — the substitute content.
  final Widget fallback;

  /// Shown while it is still arriving: the plain tone, claiming nothing.
  ///
  /// Deliberately different from [fallback]. A cover that is on its way and a
  /// cover that will never arrive are different facts, and rendering the
  /// substitute immediately would say "there is no artwork" about something
  /// still downloading.
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    return Image.network(
      url,
      fit: BoxFit.cover,
      cacheWidth: (width * ratio).round(),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : ColoredBox(color: tone),
      errorBuilder: (context, error, stackTrace) => fallback,
    );
  }
}
