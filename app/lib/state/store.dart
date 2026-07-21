import 'package:flutter/foundation.dart';

/// A reactive state container that provides fine-grained field-level
/// notifications through [select], while maintaining full-state snapshots
/// for serialization and cross-field operations.
///
/// ## Problem this solves
/// Traditional [ChangeNotifier] fires ALL listeners on ANY change, causing
/// widgets that only care about one field to rebuild unnecessarily.
///
/// ## Solution
/// - [select] creates a [ValueNotifier] that only fires when the selected
///   value actually changes (compared via `==`).
/// - [update] takes a transformer `T → T` and only notifies selectors whose
///   values actually changed.
/// - The aggregate [ChangeNotifier] is available via [ChangeNotifier.listen].
///
/// ## Usage
/// ```dart
/// final store = Store(MyState());
/// final name = store.select((s) => s.name);  // ValueNotifier<String>
/// store.update((s) => s.copyWith(name: 'new'));
/// ```
class Store<T> extends ChangeNotifier {
  T _state;
  final Map<Object, _Slot> _slots = {};

  Store(this._state);

  /// The current immutable state snapshot.
  T get state => _state;

  /// Number of registered selector slots. Slots live for the store's
  /// lifetime, so this must stay bounded — see [select].
  @visibleForTesting
  int get debugSlotCount => _slots.length;

  /// Create a [ValueNotifier] that tracks a specific derived value.
  /// The returned notifier only fires when [selector]'s result changes
  /// (compared via `==`).
  ///
  /// Slots are keyed by the *identity* of [selector] and are never removed
  /// before [dispose], so only pass long-lived selector references (e.g. a
  /// controller field or top-level function). Widgets must NOT call this
  /// with inline closures — use `StoreBuilder`, which evaluates its selector
  /// locally without registering a slot.
  ValueNotifier<R> select<R>(R Function(T) selector) {
    final key = _SlotKey(selector);
    if (_slots.containsKey(key)) {
      return _slots[key]!.notifier as ValueNotifier<R>;
    }
    final initial = selector(_state);
    final notifier = ValueNotifier<R>(initial);
    _slots[key] = _Slot(notifier, selector as dynamic);
    return notifier;
  }

  /// Update the state by applying [transformer]. Only selectors whose
  /// values actually changed will be notified. [ChangeNotifier] listeners
  /// are always notified.
  ///
  /// [transformer] receives the current state and should return the new state.
  /// Typically: `store.update((s) => s.copyWith(field: newValue))`.
  void update(T Function(T) transformer) {
    final newState = transformer(_state);
    if (newState == _state) return;
    _state = newState;

    // Notify field-level selectors
    for (final entry in _slots.entries) {
      final slot = entry.value;
      final fn = slot.selector as Object? Function(T);
      final newValue = fn(_state);
      if (newValue != slot.notifier.value) {
        slot.notifier.value = newValue;
      }
    }

    // Notify aggregate listeners
    notifyListeners();
  }

  @override
  void dispose() {
    for (final slot in _slots.values) {
      slot.notifier.dispose();
    }
    _slots.clear();
    super.dispose();
  }

  /// Replace state entirely (for initialization / reset).
  void replace(T newState) {
    _state = newState;
    // Update all selectors
    for (final entry in _slots.entries) {
      final slot = entry.value;
      final fn = slot.selector as Object? Function(T);
      final newValue = fn(_state);
      if (newValue != slot.notifier.value) {
        slot.notifier.value = newValue;
      }
    }
    notifyListeners();
  }
}

/// Wraps a [ValueNotifier] and its selector function.
class _Slot {
  _Slot(this.notifier, this.selector);
  final ValueNotifier<Object?> notifier;
  final Function selector;
}

/// Opaque key based on identity for selector functions.
class _SlotKey {
  _SlotKey(this._fn);
  final Function _fn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is _SlotKey && identical(_fn, other._fn);

  @override
  int get hashCode => identityHashCode(_fn);
}
