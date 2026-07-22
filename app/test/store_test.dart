import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/state/store.dart';

@immutable
class _CounterState {
  const _CounterState({required this.count, required this.label});

  final int count;
  final String label;

  _CounterState copyWith({int? count, String? label}) =>
      _CounterState(count: count ?? this.count, label: label ?? this.label);

  @override
  bool operator ==(Object other) =>
      other is _CounterState && other.count == count && other.label == label;

  @override
  int get hashCode => Object.hash(count, label);
}

void main() {
  group('Store', () {
    test('select exposes the initial derived value', () {
      final store = Store(const _CounterState(count: 3, label: 'a'));
      expect(store.select((s) => s.count).value, 3);
    });

    test('select memoizes one notifier per selector identity', () {
      final store = Store(const _CounterState(count: 0, label: 'a'));
      int select(_CounterState s) => s.count;
      expect(identical(store.select(select), store.select(select)), isTrue);
    });

    test('update notifies only selectors whose value changed', () {
      final store = Store(const _CounterState(count: 0, label: 'a'));
      final countNotifier = store.select((s) => s.count);
      final labelNotifier = store.select((s) => s.label);
      var countFires = 0;
      var labelFires = 0;
      countNotifier.addListener(() => countFires++);
      labelNotifier.addListener(() => labelFires++);

      store.update((s) => s.copyWith(count: 1));

      expect(store.state.count, 1);
      expect(countNotifier.value, 1);
      expect(countFires, 1);
      // The label was untouched, so its selector must stay silent.
      expect(labelNotifier.value, 'a');
      expect(labelFires, 0);
    });

    test('update to an equal state is a no-op', () {
      final store = Store(const _CounterState(count: 5, label: 'a'));
      var aggregateFires = 0;
      var countFires = 0;
      store.addListener(() => aggregateFires++);
      store.select((s) => s.count).addListener(() => countFires++);

      // copyWith with no overrides yields an equal state.
      store.update((s) => s.copyWith());

      expect(aggregateFires, 0);
      expect(countFires, 0);
      expect(store.state.count, 5);
    });

    test('aggregate listeners fire once per real update', () {
      final store = Store(const _CounterState(count: 0, label: 'a'));
      var aggregateFires = 0;
      store.addListener(() => aggregateFires++);

      store.update((s) => s.copyWith(count: 2));

      expect(aggregateFires, 1);
    });

    test('select memoization keeps the slot count bounded', () {
      final store = Store(const _CounterState(count: 0, label: 'a'));
      int selectCount(_CounterState s) => s.count;
      for (var i = 0; i < 100; i++) {
        store.select(selectCount);
      }
      expect(store.debugSlotCount, 1);
    });

    test('dispose disposes every slot notifier', () {
      final store = Store(const _CounterState(count: 0, label: 'a'));
      final notifier = store.select((s) => s.count);

      store.dispose();

      expect(store.debugSlotCount, 0);
      // A disposed ValueNotifier throws on listener registration.
      expect(() => notifier.addListener(() {}), throwsFlutterError);
    });

    test('replace refreshes every selector and notifies aggregate', () {
      final store = Store(const _CounterState(count: 0, label: 'a'));
      final countNotifier = store.select((s) => s.count);
      final labelNotifier = store.select((s) => s.label);
      var aggregateFires = 0;
      store.addListener(() => aggregateFires++);

      store.replace(const _CounterState(count: 9, label: 'z'));

      expect(countNotifier.value, 9);
      expect(labelNotifier.value, 'z');
      expect(store.state.count, 9);
      expect(aggregateFires, 1);
    });
  });
}
