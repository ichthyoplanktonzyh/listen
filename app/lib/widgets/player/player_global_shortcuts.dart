import 'package:flutter/material.dart';

class PlayerGlobalShortcuts extends StatefulWidget {
  const PlayerGlobalShortcuts({
    super.key,
    required this.bindings,
    required this.child,
  });

  final Map<ShortcutActivator, VoidCallback> bindings;
  final Widget child;

  @override
  State<PlayerGlobalShortcuts> createState() => _PlayerGlobalShortcutsState();
}

class _PlayerGlobalShortcutsState extends State<PlayerGlobalShortcuts> {
  bool _shortcutsEnabled = true;

  @override
  void initState() {
    super.initState();
    _shortcutsEnabled = !_primaryFocusIsTextInput();
    FocusManager.instance.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleFocusChanged);
    super.dispose();
  }

  void _handleFocusChanged() {
    final enabled = !_primaryFocusIsTextInput();
    if (enabled == _shortcutsEnabled || !mounted) return;
    setState(() => _shortcutsEnabled = enabled);
  }

  bool _primaryFocusIsTextInput() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: _shortcutsEnabled
        ? widget.bindings
        : const <ShortcutActivator, VoidCallback>{},
    child: widget.child,
  );
}
