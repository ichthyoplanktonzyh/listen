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
