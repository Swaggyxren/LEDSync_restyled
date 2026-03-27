import 'package:flutter/material.dart';

/// Material 3 Loading Indicator — Contained variant.
/// M3 spec: 48dp container circle, ~38dp indicator, colorPrimary.
class M3LoadingContained extends StatelessWidget {
  final String? semanticLabel;
  final double size;
  const M3LoadingContained({this.semanticLabel, this.size = 48.0, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel ?? 'Loading',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: SizedBox(
            width: size * 0.79,
            height: size * 0.79,
            child: CircularProgressIndicator(color: cs.primary, strokeWidth: 3),
          ),
        ),
      ),
    );
  }
}

/// Material 3 Loading Indicator — Uncontained variant.
/// Minimal spinner that blends with the UI background.
class M3LoadingUncontained extends StatelessWidget {
  final String? semanticLabel;
  final double size;
  const M3LoadingUncontained({this.semanticLabel, this.size = 36.0, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel ?? 'Loading',
      child: SizedBox(
        width: size,
        height: size,
        child: CircularProgressIndicator(color: cs.primary, strokeWidth: 3),
      ),
    );
  }
}

/// Full-screen loading state with contained spinner + message.
/// Use as a drop-in for FutureBuilder loading states.
class M3LoadingScreen extends StatelessWidget {
  final String message;
  final double spinnerSize;
  const M3LoadingScreen({
    this.message = 'Loading…',
    this.spinnerSize = 56.0,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          M3LoadingContained(size: spinnerSize, semanticLabel: message),
          const SizedBox(height: 20),
          Text(
            message,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 14,
              fontFamily: 'SpaceGrotesk',
            ),
          ),
        ],
      ),
    );
  }
}
