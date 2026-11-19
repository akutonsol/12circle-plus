import 'package:flutter/material.dart';

import '../../../../core/observability/network_failure.dart';

/// P0-FL-18 · one section's read failed: say so, in the place of that section
/// only, with the next step and a busy-aware Try again.
///
/// A failed read is never the section's empty state ("No data yet", "No
/// personal records yet", "No sessions recorded"): those claim the member has
/// nothing, when the truth is the app could not find out. The connection hint
/// shows only for a failure that IS the connection ([isNetworkFailure]).
///
/// The message is announced when it appears (a live region labelled
/// `Couldn't load <what>. <hint>` — the button is not part of it); the retry
/// is >= 44px, named, and disabled while the retry is in flight so it cannot
/// double fire. Wraps the retry under the message at large text.
///
/// A consumer must keep showing this card, `busy: true`, while a retry or a
/// reload is in flight: `.when` takes the loading arm on a reload (a watched
/// dependency changed), so that arm must check `asyncValue.hasError` and show
/// this card, or the section blinks away and the busy state is never seen.
class SectionLoadFailure extends StatelessWidget {
  /// What could not be loaded, lower case: "your exercises" →
  /// "Couldn't load your exercises".
  final String what;
  final Object? error;
  final bool busy;
  final VoidCallback onRetry;
  final Color accent;
  final Color textColor;
  final Color mutedColor;

  const SectionLoadFailure({
    super.key,
    required this.what,
    required this.error,
    required this.busy,
    required this.onRetry,
    this.accent = const Color(0xFFDDB7FF),
    this.textColor = Colors.white,
    this.mutedColor = const Color(0xFFCFC2D6),
  });

  static const otherwiseHint =
      'Try again in a moment. If it keeps happening, contact support.';
  static const networkHint = 'Check your connection and try again.';

  @override
  Widget build(BuildContext context) {
    final hint = isNetworkFailure(error) ? networkHint : otherwiseHint;
    final retry = Semantics(
      button: true,
      label: busy ? 'Retrying' : 'Try again: load $what',
      excludeSemantics: true,
      child: TextButton(
        onPressed: busy ? null : onRetry,
        style: TextButton.styleFrom(
          foregroundColor: accent,
          backgroundColor: accent.withValues(alpha: 0.12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: const Size(48, 44),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
        child: busy
            ? SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: accent))
            : const Text('Try again',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
    final stacked = MediaQuery.textScalerOf(context).scale(12) > 12 * 1.3;
    // The live region is the MESSAGE only, with one explicit label, so the
    // announcement is the sentence itself. The retry keeps its own button
    // node outside it, and the icon is decorative.
    final message = Semantics(
      liveRegion: true,
      container: true,
      label: "Couldn't load $what. $hint",
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Couldn't load $what",
            style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(hint,
            style: TextStyle(color: mutedColor, fontSize: 12, height: 1.4)),
        ]),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        ExcludeSemantics(child: Icon(Icons.error_outline, color: accent, size: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            message,
            if (stacked) ...[const SizedBox(height: 10), retry],
          ])),
        if (!stacked) ...[const SizedBox(width: 8), retry],
      ]),
    );
  }
}
