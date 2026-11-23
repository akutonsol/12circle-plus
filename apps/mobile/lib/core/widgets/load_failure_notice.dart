import 'package:flutter/material.dart';

import '../observability/network_failure.dart';

/// `Couldn't <do X> — <next step>`: the one voice for a failure (P0-FL-50a).
/// The connection hint only for a failure that IS the connection; never the
/// exception's text.
String couldntMessage(String doWhat, Object? error) => isNetworkFailure(error)
    ? "Couldn't $doWhat — check your connection and try again."
    : "Couldn't $doWhat — try again in a moment. If it keeps happening, "
        'contact support.';

/// A failed read, said as one (a live region), with a busy-aware Retry.
///
/// [onRetry] is awaited; while it runs the button is disabled, so a double tap
/// never fires two reads. The button is at least 44px tall and labelled.
class LoadFailureNotice extends StatefulWidget {
  const LoadFailureNotice({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Try again',
    this.semanticLabel,
    this.textColor = const Color(0xFFFFB4AB),
    this.accent = const Color(0xFFB76DFF),
  });

  final String message;
  final Future<void> Function() onRetry;
  final String retryLabel;

  /// What a screen reader announces for the button (defaults to [retryLabel]).
  final String? semanticLabel;
  final Color textColor;
  final Color accent;

  @override
  State<LoadFailureNotice> createState() => _LoadFailureNoticeState();
}

class _LoadFailureNoticeState extends State<LoadFailureNotice> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        liveRegion: true,
        child: Text(widget.message,
            textAlign: TextAlign.center,
            style: TextStyle(color: widget.textColor, fontSize: 13, height: 1.4)),
      ),
      const SizedBox(height: 8),
      Semantics(
        button: true,
        enabled: !_busy,
        label: widget.semanticLabel ?? widget.retryLabel,
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: TextButton(
            onPressed: _busy ? null : _retry,
            style: TextButton.styleFrom(
                foregroundColor: widget.accent,
                minimumSize: const Size(44, 44)),
            child: _busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: widget.accent))
                : Text(widget.retryLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    ]);
  }
}
