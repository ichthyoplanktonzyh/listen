import 'package:flutter/material.dart';
import 'store.dart';

/// A widget that rebuilds only when the selected slice of state changes.
///
/// ## Usage
/// ```dart
/// StoreBuilder<PlayerState, bool>(
///   store: playerStore,
///   select: (s) => s.playing,
///   builder: (context, playing) => Icon(playing ? Icons.pause : Icons.play),
/// )
/// ```
class StoreBuilder<T, R> extends StatelessWidget {
  const StoreBuilder({
    super.key,
    required this.store,
    required this.select,
    required this.builder,
  });

  /// The [Store] to listen to.
  final Store<T> store;

  /// A function that extracts the relevant slice of state.
  /// The widget only rebuilds when this value changes.
  final R Function(T state) select;

  /// Builds the child widget given the selected state value.
  final Widget Function(BuildContext context, R value) builder;

  @override
  Widget build(BuildContext context) {
    return _StoreBuilderStateful<T, R>(
      store: store,
      select: select,
      builder: builder,
    );
  }
}

class _StoreBuilderStateful<T, R> extends StatefulWidget {
  const _StoreBuilderStateful({
    required this.store,
    required this.select,
    required this.builder,
  });

  final Store<T> store;
  final R Function(T) select;
  final Widget Function(BuildContext, R) builder;

  @override
  State<_StoreBuilderStateful<T, R>> createState() => _StoreBuilderState();
}

class _StoreBuilderState<T, R> extends State<_StoreBuilderStateful<T, R>> {
  late ValueNotifier<R> _notifier;
  late R _value;

  @override
  void initState() {
    super.initState();
    _notifier = widget.store.select(widget.select);
    _value = _notifier.value;
    _notifier.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(_StoreBuilderStateful<T, R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.select != widget.select) {
      _notifier.removeListener(_onChanged);
      _notifier = widget.store.select(widget.select);
      _value = _notifier.value;
      _notifier.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _notifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final newValue = _notifier.value;
    if (newValue != _value) {
      setState(() => _value = newValue);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// A widget that listens to multiple selectors and rebuilds when any changes.
class StoreBuilder2<T, R1, R2> extends StatelessWidget {
  const StoreBuilder2({
    super.key,
    required this.store,
    required this.select1,
    required this.select2,
    required this.builder,
  });

  final Store<T> store;
  final R1 Function(T) select1;
  final R2 Function(T) select2;
  final Widget Function(BuildContext context, R1, R2) builder;

  @override
  Widget build(BuildContext context) {
    return _StoreBuilder2Stateful<T, R1, R2>(
      store: store,
      select1: select1,
      select2: select2,
      builder: builder,
    );
  }
}

class _StoreBuilder2Stateful<T, R1, R2> extends StatefulWidget {
  const _StoreBuilder2Stateful({
    required this.store,
    required this.select1,
    required this.select2,
    required this.builder,
  });

  final Store<T> store;
  final R1 Function(T) select1;
  final R2 Function(T) select2;
  final Widget Function(BuildContext, R1, R2) builder;

  @override
  State<_StoreBuilder2Stateful<T, R1, R2>> createState() =>
      _StoreBuilder2State<T, R1, R2>();
}

class _StoreBuilder2State<T, R1, R2>
    extends State<_StoreBuilder2Stateful<T, R1, R2>> {
  late ValueNotifier<R1> _n1;
  late ValueNotifier<R2> _n2;

  @override
  void initState() {
    super.initState();
    _n1 = widget.store.select(widget.select1);
    _n2 = widget.store.select(widget.select2);
    _n1.addListener(_onChanged);
    _n2.addListener(_onChanged);
  }

  @override
  void dispose() {
    _n1.removeListener(_onChanged);
    _n2.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _n1.value, _n2.value);
}
