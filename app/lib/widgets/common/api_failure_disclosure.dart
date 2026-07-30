import 'package:flutter/material.dart';

import '../../localization.dart';
import '../../models/api_failure.dart';
import '../../theme/icon_size.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import 'listen_error_state.dart';

/// The diagnostics disclosure: collapsed by default, and never [ApiFailure.raw].
///
/// #62's leak was a sentence with a caught exception interpolated into it. The
/// fix has two halves, and this is the second one: the sentence names what
/// failed, and everything the transport carried lives here, behind a tap.
///
/// What it shows, and why only this:
///
/// - the **reference id** ([ApiFailure.correlationId]) — the one field that
///   ties a user's report to a backend log line, which is the entire reason a
///   disclosure exists;
/// - the backend's own **message** — operator English, which
///   `ApiFailure`'s doc places behind a disclosure rather than in prose.
///
/// What it never shows: [ApiFailure.raw]. The response body and the URI the
/// exception's `toString` appended carry the sidecar's loopback port and an
/// internal route, and neither means anything to a learner — not in the main
/// flow, and not expanded either. [ApiFailure.code] is left out for the same
/// reason in miniature: `validation_error` says nothing the message does not.
class ApiFailureDisclosure extends StatefulWidget {
  const ApiFailureDisclosure({super.key, required this.failure});

  final ApiFailure failure;

  /// Whether [failure] has anything a disclosure could honestly show.
  ///
  /// Deliberately narrower than [ApiFailure.isStructured]: a failure with only
  /// a machine `code` has nothing to say here, and an empty "Details" panel is
  /// worse than no affordance at all.
  static bool hasDetail(ApiFailure? failure) =>
      failure != null &&
      (failure.correlationId != null || failure.message != null);

  @override
  State<ApiFailureDisclosure> createState() => _ApiFailureDisclosureState();
}

class _ApiFailureDisclosureState extends State<ApiFailureDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (!ApiFailureDisclosure.hasDetail(widget.failure)) {
      return const SizedBox.shrink();
    }
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _expanded = !_expanded),
            icon: Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              size: ListenIconSize.inline,
            ),
            label: Text(
              _expanded
                  ? l.text('failureDetailsHide')
                  : l.text('failureDetailsShow'),
              style: ListenType.caption,
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(
              left: ListenSpacing.gap8,
              bottom: ListenSpacing.gap4,
            ),
            child: ApiFailureDetail(failure: widget.failure),
          ),
      ],
    );
  }
}

/// The expanded body of a disclosure, on its own so the modal form
/// ([showApiFailureDetails]) and the inline form render the same fields.
class ApiFailureDetail extends StatelessWidget {
  const ApiFailureDetail({super.key, required this.failure});

  final ApiFailure failure;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final caption = ListenType.caption.copyWith(color: colors.onSurfaceVariant);
    final reference = failure.correlationId;
    final message = failure.message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reference != null)
          SelectableText(
            l.text('failureReference').replaceAll('{id}', reference),
            style: caption.copyWith(fontFamily: ListenFonts.mono),
          ),
        if (message != null)
          Padding(
            padding: EdgeInsets.only(top: reference == null ? 0 : 2),
            child: SelectableText(message, style: caption),
          ),
      ],
    );
  }
}

/// [ListenErrorNotice] — the repo's inline failure form — with the disclosure
/// under it.
///
/// [message] is already localized: callers hold a [NamedFailure]'s key and
/// resolve it, so this widget stays a pure renderer.
class ApiFailureNotice extends StatelessWidget {
  const ApiFailureNotice({super.key, required this.message, this.failure});

  final String message;
  final ApiFailure? failure;

  @override
  Widget build(BuildContext context) {
    final detail = failure;
    if (!ApiFailureDisclosure.hasDetail(detail)) {
      return ListenErrorNotice(message: message);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListenErrorNotice(message: message),
        ApiFailureDisclosure(failure: detail!),
      ],
    );
  }
}

/// A quiet "Details" button for surfaces with no room to expand in place — a
/// one-line status bar, a SnackBar action — that opens the same fields in a
/// dialog instead.
class ApiFailureDetailsButton extends StatelessWidget {
  const ApiFailureDetailsButton({super.key, required this.failure});

  final ApiFailure failure;

  @override
  Widget build(BuildContext context) => ApiFailureDisclosure.hasDetail(failure)
      ? TextButton(
          onPressed: () => showApiFailureDetails(context, failure),
          child: Text(AppLocalizations.of(context).text('failureDetailsShow')),
        )
      : const SizedBox.shrink();
}

/// Modal diagnostics for [failure]. Same fields as the inline disclosure, and
/// the same exclusion: [ApiFailure.raw] is not among them.
Future<void> showApiFailureDetails(
  BuildContext context,
  ApiFailure failure,
) async {
  final l = AppLocalizations.of(context);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l.text('failureDetailsTitle')),
      content: SizedBox(width: 420, child: ApiFailureDetail(failure: failure)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l.text('close')),
        ),
      ],
    ),
  );
}
