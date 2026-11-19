import 'package:flutter/material.dart';

import '../../../../core/observability/network_failure.dart';

/// "Couldn't load your profile — check your connection and try again."
const kProfileLoadOfflineMessage =
    "Couldn't load your profile — check your connection and try again.";

/// The non-network wording.
const kProfileLoadFailedMessage =
    "Couldn't load your profile — try again in a moment. "
    'If it keeps happening, contact support.';

/// The one wording for a failed `currentUserProfileProvider` read (P0-FL-16):
/// the connection hint only for a network failure.
String profileLoadFailedMessage(Object error) => isNetworkFailure(error)
    ? kProfileLoadOfflineMessage
    : kProfileLoadFailedMessage;

/// The signed-in member's profile could not be read: say so, say what is held
/// back because of it ([detail], optional) and offer Try again.
///
/// The message is a live region, so a screen reader announces it. Try again is busy-aware —
/// while [busy] (the re-read is in flight) it is disabled and reads "Loading…",
/// so it cannot fire twice — at least 44px tall, and labelled for a screen
/// reader.
class ProfileLoadFailedNotice extends StatelessWidget {
  const ProfileLoadFailedNotice({
    super.key,
    required this.error,
    required this.busy,
    required this.onRetry,
    this.detail,
  });

  final Object error;
  final bool busy;
  final VoidCallback onRetry;
  final String? detail;

  static const _red = Color(0xFFFFB4AB);
  static const _text = Color(0xFFE5E2E3);
  static const _muted = Color(0xFFCDC3D0);
  static const _brand = Color(0xFFDDB7FF);

  @override
  Widget build(BuildContext context) {
    // The live region covers the message only (UX-3): if it wrapped Try
    // again, the button's "Try again" ↔ "Loading…" flip would re-announce the
    // whole notice on every retry. The button keeps its own semantics.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _red.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.error_outline, color: _red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Text(profileLoadFailedMessage(error),
                  style: const TextStyle(
                      color: _text, fontSize: 13, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
        if (detail != null) ...[
          const SizedBox(height: 6),
          Text(detail!,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.4)),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: TextButton(
              onPressed: busy ? null : onRetry,
              child: Text(busy ? 'Loading…' : 'Try again',
                  semanticsLabel: busy
                      ? 'Loading your profile'
                      : 'Try again, load your profile',
                  style: const TextStyle(
                      color: _brand, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ]),
    );
  }
}
