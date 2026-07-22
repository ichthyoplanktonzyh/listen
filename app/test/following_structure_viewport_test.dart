import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/widgets/subtitle/following_structure_viewport.dart';

void main() {
  testWidgets('long sentence follows its active item and exposes overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: FollowingStructureViewport(
                activeIndex: 10,
                children: [
                  for (var index = 0; index < 14; index += 1)
                    SizedBox(
                      key: ValueKey('item-$index'),
                      width: 70,
                      height: 28,
                      child: Text('word $index'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    final viewport = tester.getRect(find.byType(FollowingStructureViewport));
    final active = tester.getRect(find.byKey(const ValueKey('item-10')));
    expect(active.center.dx, inInclusiveRange(viewport.left, viewport.right));
    expect(find.byKey(const ValueKey('structure-edge-left')), findsOneWidget);
    expect(find.byKey(const ValueKey('structure-edge-right')), findsOneWidget);
  });

  testWidgets('expand action switches the lane to a wrapped full sentence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: FollowingStructureViewport(
              children: [
                for (var index = 0; index < 8; index += 1)
                  SizedBox(width: 80, child: Text('word $index')),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Wrap), findsNothing);
    await tester.tap(find.byKey(const ValueKey('structure-viewport-toggle')));
    await tester.pumpAndSettle();

    expect(find.byType(Wrap), findsOneWidget);
    expect(find.text('word 7'), findsOneWidget);
  });
}
