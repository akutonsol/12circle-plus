import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/domain/auth_provider.dart';
import '../../features/payments/presentation/paywall_gate.dart'
    show confirmedRoleRead;
import '../../features/profile/presentation/widgets/profile_load_failed_notice.dart';

// The role-gated internal tools all share this palette.
const _bg = Color(0xFF0A0A0B);
const _brand = Color(0xFFB76DFF);
const _text = Color(0xFFEDE7F3);

/// P0-FL-45a · the ONE role gate for the role-only screens (coach and
/// admin/content tools). Returns the widget to show INSTEAD of the screen, or
/// `null` when the signed-in member's role is confirmed and is in
/// [allowedRoles] — the screen then renders as before.
///
/// The role counts only when a profile read CONFIRMED it for the member
/// signed in now ([confirmedRoleRead], P0-FL-44): Riverpod keeps the previous
/// value through a re-read, so after a sign-out/sign-in the PREVIOUS member's
/// role used to open (or close) these screens. P0-FL-40's nine private copies
/// read `profileAsync.value?['role']` with no member check.
///
/// * role unknown, read failed → the shared FL-16 notice with a busy-aware Try
///   again (the failure is recorded by `currentUserProfileProvider` itself);
/// * role unknown, read in flight → a neutral spinner;
/// * confirmed, not in [allowedRoles] → [denied] (the screen's own
///   "… only." message, unchanged);
/// * confirmed and allowed → `null`.
///
/// A refresh that fails AFTER a confirmed read for the same member keeps that
/// role (a real answer), exactly as the paywall does.
///
/// Both unknown states keep the screen's own AppBar ([title], the normal back
/// control, no role-only actions) so there is always an in-app way out (UX-1).
Widget? roleGate(
  WidgetRef ref, {
  required String title,
  required Set<String> allowedRoles,
  required String detail,
  required Widget denied,
}) {
  final profile = ref.watch(currentUserProfileProvider);
  final confirmed = confirmedRoleRead(profile, ref.watch(currentUserProvider));
  if (confirmed != null) {
    return allowedRoles.contains(confirmed.role) ? null : denied;
  }
  final appBar = AppBar(
      backgroundColor: _bg,
      foregroundColor: _text,
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)));
  if (profile.hasError) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: appBar,
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ProfileLoadFailedNotice(
          error: profile.error!,
          busy: profile.isLoading,
          detail: detail,
          onRetry: () => ref.invalidate(currentUserProfileProvider),
        ),
      ))),
    );
  }
  return Scaffold(
    backgroundColor: _bg,
    appBar: appBar,
    body: const Center(
        child: CircularProgressIndicator(
            color: _brand, semanticsLabel: 'Loading your account')),
  );
}

/// P0-FL-45a · start a role-only screen's first read once [roleGate] has let
/// the member in, instead of in `initState` (before the role is known). Call
/// [start] from `build` after the gate returned `null`; the read runs once,
/// after that frame (it may `setState`).
class RoleConfirmedLoad {
  bool _started = false;

  /// Whether the first read has been scheduled.
  bool get started => _started;

  void start(State<StatefulWidget> state, VoidCallback load) {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.mounted) load();
    });
  }
}
