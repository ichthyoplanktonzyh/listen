import 'package:flutter/material.dart';

class PronunciationButton extends StatelessWidget {
  const PronunciationButton({
    super.key,
    required this.onPressed,
    required this.tooltip,
    this.busy = false,
    this.synthetic = false,
  });

  final VoidCallback? onPressed;
  final String tooltip;
  final bool busy;
  final bool synthetic;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: busy ? null : onPressed,
    icon: busy
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(
            synthetic
                ? Icons.record_voice_over_outlined
                : Icons.volume_up_outlined,
          ),
  );
}
