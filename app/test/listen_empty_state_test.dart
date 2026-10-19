import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llplayer_next/theme/listen_theme.dart';
import 'package:llplayer_next/widgets/common/listen_empty_state.dart';

/// #46: the unified empty-state language — quiet icon, one sentence, optional
/// recovery action. Empty panels speak with one voice instead of bare
/// centered strings.
void main() {
  Widget app(Widget child) => MaterialApp(
    theme: ListenTheme.light(),
    darkTheme: ListenTheme.dark(),
    home: Scaffold(body: child),
  );

  testWidgets('renders the icon and the sentence, muted', (tester) async {
    await tester.pumpWidget(
      app(
        const ListenEmptyState(
          icon: Icons.inbox_outlined,
          message: 'Nothing captured yet',
        ),
      ),
    );

    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    expect(find.text('Nothing captured yet'), findsOneWidget);

    // Muted, not shouting: both icon and text sit in onSurfaceVariant
    // territory (charter principle 5).
    final context = tester.element(find.byType(ListenEmptyState));
    final variant = Theme.of(context).colorScheme.onSurfaceVariant;
    final icon = tester.widget<Icon>(find.byIcon(Icons.inbox_outlined));
    expect(icon.color, variant.withValues(alpha: 0.55));
    final text = tester.widget<Text>(find.text('Nothing captured yet'));
    expect(text.style?.color, variant);
  });

  testWidgets('shows the recovery action when the panel offers one', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      app(
        ListenEmptyState(
          icon: Icons.folder_open_outlined,
          message: 'No media open',
          action: OutlinedButton(
            onPressed: () => tapped = true,
            child: const Text('Open media'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open media'));
    expect(tapped, isTrue);
  });

  testWidgets('omits the action row when there is none', (tester) async {
    await tester.pumpWidget(
      app(const ListenEmptyState(icon: Icons.search_off, message: 'No hits')),
    );

    expect(find.byType(ButtonStyleButton), findsNothing);
  });
}
