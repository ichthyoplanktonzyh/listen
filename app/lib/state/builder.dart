import 'package:flutter/material.dart';

import 'store.dart';

/// A widget that rebuilds only when the selected slice of state changes.
///
/// Listens to the store's aggregate notifications and re-evaluates [select]
/// locally, so inline selector closures are safe: no per-selector slot is
/// registered on the [Store], and nothing accumulates when the parent
/// rebuilds with a fresh closure. ([Store.select] slots are reserved for
/// long-lived selectors owned by controllers.)
///
/// ## Usage
/// ```dart
/// StoreBuilder<PlayerState, bool>(
///   store: playerStore,
///   select: (s) => s.playing,
///   builder: (context, playing) => Icon(playing ? Icons.pause : Icons.play),
/// )
/// ```
class StoreBuilder<T, R> extends StatefulWidget {
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
  State<StoreBuilder<T, R>> createState() => _StoreBuilderState<T, R>();
}

class _StoreBuilderState<T, R> extends State<StoreBuilder<T, R>> {
  late R _value;

  @override
  void initState() {
    super.initState();
    _value = widget.select(widget.store.state);
    widget.store.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(StoreBuilder<T, R> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      oldWidget.store.removeListener(_onChanged);
      widget.store.addListener(_onChanged);
    }
    // The selector closure may be freshly created on every parent rebuild;
    // just re-evaluate it against the current state.
    _value = widget.select(widget.store.state);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final newValue = widget.select(widget.store.state);
    if (newValue != _value) {
      setState(() => _value = newValue);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

/// A widget that listens to two selectors and rebuilds when either changes.
class StoreBuilder2<T, R1, R2> extends StatefulWidget {
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
  State<StoreBuilder2<T, R1, R2>> createState() =>
      _StoreBuilder2State<T, R1, R2>();
}

class _StoreBuilder2State<T, R1, R2> extends State<StoreBuilder2<T, R1, R2>> {
  late R1 _v1;
  late R2 _v2;

  @override
  void initState() {
    super.initState();
    _v1 = widget.select1(widget.store.state);
    _v2 = widget.select2(widget.store.state);
    widget.store.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(StoreBuilder2<T, R1, R2> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.store, widget.store)) {
      oldWidget.store.removeListener(_onChanged);
      widget.store.addListener(_onChanged);
    }
    _v1 = widget.select1(widget.store.state);
    _v2 = widget.select2(widget.store.state);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final v1 = widget.select1(widget.store.state);
    final v2 = widget.select2(widget.store.state);
    if (v1 != _v1 || v2 != _v2) {
      setState(() {
        _v1 = v1;
        _v2 = v2;
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _v1, _v2);
}
