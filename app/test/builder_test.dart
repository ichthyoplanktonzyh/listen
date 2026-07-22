import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/state/builder.dart';
import 'package:llplayer_next/state/store.dart';

@immutable
class _S {
  const _S({required this.count, required this.label});

  final int count;
  final String label;

  _S copyWith({int? count, String? label}) =>
      _S(count: count ?? this.count, label: label ?? this.label);

  @override
  bool operator ==(Object other) =>
      other is _S && other.count == count && other.label == label;

  @override
  int get hashCode => Object.hash(count, label);
}

void main() {
  group('StoreBuilder', () {
    testWidgets('renders the selected slice and rebuilds only when it changes', (
      tester,
    ) async {
      final store = Store(const _S(count: 0, label: 'a'));
      var builds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: StoreBuilder<_S, int>(
            store: store,
            select: (s) => s.count,
            builder: (_, count) {
              builds++;
              return Text('count=$count');
            },
          ),
        ),
      );

      expect(builds, 1);
      expect(find.text('count=0'), findsOneWidget);

      // A change to an unrelated field must NOT rebuild this selector.
      store.update((s) => s.copyWith(label: 'b'));
      await tester.pump();
      expect(builds, 1, reason: 'unrelated field change should not rebuild');

      // A change to the selected field rebuilds with the new value.
      store.update((s) => s.copyWith(count: 5));
      await tester.pump();
      expect(builds, 2);
      expect(find.text('count=5'), findsOneWidget);
    });

    testWidgets('an equal-state update triggers no rebuild', (tester) async {
      final store = Store(const _S(count: 3, label: 'a'));
      var builds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: StoreBuilder<_S, int>(
            store: store,
            select: (s) => s.count,
            builder: (_, count) {
              builds++;
              return Text('count=$count');
            },
          ),
        ),
      );
      expect(builds, 1);

      store.update((s) => s.copyWith());
      await tester.pump();
      expect(builds, 1);
    });

    testWidgets('inline selector closures never register store slots', (
      tester,
    ) async {
      final store = Store(const _S(count: 0, label: 'a'));

      // Rebuild the parent repeatedly so StoreBuilder receives a freshly
      // created selector closure each time — the historical leak vector.
      for (var i = 0; i < 20; i++) {
        await tester.pumpWidget(
          MaterialApp(
            home: StoreBuilder<_S, int>(
              store: store,
              select: (s) => s.count + i - i,
              builder: (_, count) => Text('count=$count'),
            ),
          ),
        );
      }

      expect(
        store.debugSlotCount,
        0,
        reason: 'StoreBuilder must not accumulate slots across rebuilds',
      );
    });

    testWidgets('a freshly created selector still tracks updates', (
      tester,
    ) async {
      final store = Store(const _S(count: 0, label: 'a'));

      Widget host() => MaterialApp(
        home: StoreBuilder<_S, int>(
          store: store,
          select: (s) => s.count,
          builder: (_, count) => Text('count=$count'),
        ),
      );

      await tester.pumpWidget(host());
      // Parent rebuild swaps in a new closure; tracking must survive.
      await tester.pumpWidget(host());

      store.update((s) => s.copyWith(count: 7));
      await tester.pump();
      expect(find.text('count=7'), findsOneWidget);
    });

    testWidgets('swapping the store re-targets the listener', (tester) async {
      final storeA = Store(const _S(count: 1, label: 'a'));
      final storeB = Store(const _S(count: 2, label: 'b'));

      Widget host(Store<_S> store) => MaterialApp(
        home: StoreBuilder<_S, int>(
          store: store,
          select: (s) => s.count,
          builder: (_, count) => Text('count=$count'),
        ),
      );

      await tester.pumpWidget(host(storeA));
      expect(find.text('count=1'), findsOneWidget);

      await tester.pumpWidget(host(storeB));
      expect(find.text('count=2'), findsOneWidget);

      // Updates on the abandoned store must be ignored...
      storeA.update((s) => s.copyWith(count: 99));
      await tester.pump();
      expect(find.text('count=2'), findsOneWidget);

      // ...while the new store keeps driving rebuilds.
      storeB.update((s) => s.copyWith(count: 3));
      await tester.pump();
      expect(find.text('count=3'), findsOneWidget);
    });
  });

  group('StoreBuilder2', () {
    testWidgets('rebuilds when either selector changes', (tester) async {
      final store = Store(const _S(count: 0, label: 'a'));
      var builds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: StoreBuilder2<_S, int, String>(
            store: store,
            select1: (s) => s.count,
            select2: (s) => s.label,
            builder: (_, count, label) {
              builds++;
              return Text('$count/$label');
            },
          ),
        ),
      );

      expect(builds, 1);
      expect(find.text('0/a'), findsOneWidget);

      store.update((s) => s.copyWith(count: 1));
      await tester.pump();
      expect(builds, 2);

      store.update((s) => s.copyWith(label: 'z'));
      await tester.pump();
      expect(builds, 3);
      expect(find.text('1/z'), findsOneWidget);
    });

    testWidgets('an equal-state update triggers no rebuild', (tester) async {
      final store = Store(const _S(count: 0, label: 'a'));
      var builds = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: StoreBuilder2<_S, int, String>(
            store: store,
            select1: (s) => s.count,
            select2: (s) => s.label,
            builder: (_, count, label) {
              builds++;
              return Text('$count/$label');
            },
          ),
        ),
      );
      expect(builds, 1);

      store.update((s) => s.copyWith());
      await tester.pump();
      expect(builds, 1);
    });
  });
}
