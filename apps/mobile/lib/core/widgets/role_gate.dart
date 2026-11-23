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
const _muted = Color(0xFF9A93A6);

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
/// * confirmed, not in [allowedRoles] → [deniedText] (the screen's own
///   "… only." message, unchanged);
/// * confirmed and allowed → `null`.
///
/// A refresh that fails AFTER a confirmed read for the same member keeps that
/// role (a real answer), exactly as the paywall does.
///
/// Every gate state keeps the screen's own AppBar ([title], the normal back
/// control, no role-only actions) so there is always an in-app way out (UX-1;
/// UX F1 for the denied state).
///
/// Screens normally go through [RoleConfirmedLoad.gate], which also keys their
/// loaded state to the member.
Widget? roleGate(
  WidgetRef ref, {
  required String title,
  required Set<String> allowedRoles,
  required String detail,
  required String deniedText,
}) {
  final profile = ref.watch(currentUserProfileProvider);
  final confirmed = confirmedRoleRead(profile, ref.watch(currentUserProvider));
  if (confirmed != null && allowedRoles.contains(confirmed.role)) return null;
  final appBar = AppBar(
      backgroundColor: _bg,
      foregroundColor: _text,
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)));
  if (confirmed != null) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: appBar,
      body: Center(
          child: Text(deniedText, style: const TextStyle(color: _muted))),
    );
  }
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

/// P0-FL-45a · a role-only screen's loaded state, keyed to the MEMBER the
/// gate let in.
///
/// The screen's first read starts once [roleGate] has admitted the member
/// (not in `initState`, before the role is known), and everything the screen
/// loaded or showed belongs to that member:
///
/// * while the gate is shut (role unknown, denied, nobody signed in) the
///   session is over — any read still in flight is stale ([isCurrent] turns
///   false);
/// * the next admit (a different member, or the same member after the gate
///   shut) first clears the screen's member-derived state (`reset`, run in
///   `build` before anything reads it) and then runs its first read once;
/// * while the gate stays open for the same member (a profile refresh, a
///   failed refresh that keeps the role) nothing is cleared or re-read.
///
/// Without this a same-role switch (coach A → coach B with the screen
/// mounted) showed A's loaded data to B with no new read, and A's late
/// answers landed on B's screen.
class RoleConfirmedLoad {
  String? _member;
  int _session = 0;

  /// Whether a member is admitted now (and their first read scheduled).
  bool get started => _member != null;

  /// The current session; capture it before an await and check it with
  /// [isCurrent] after.
  int get session => _session;

  /// Whether [session] (captured at the start of a read) is still the
  /// admitted member's session — `false` once the gate shut or another member
  /// was admitted.
  bool isCurrent(int session) => _member != null && session == _session;

  /// [roleGate] plus the member keying above. Returns the gate widget, or
  /// `null` when the member is admitted (the screen renders).
  Widget? gate(
    State<StatefulWidget> state,
    WidgetRef ref, {
    required String title,
    required Set<String> allowedRoles,
    required String detail,
    required String deniedText,
    required VoidCallback reset,
    VoidCallback? load,
  }) {
    final shut = roleGate(ref,
        title: title,
        allowedRoles: allowedRoles,
        detail: detail,
        deniedText: deniedText);
    if (shut != null) {
      if (_member != null) {
        _member = null;
        _session++;
      }
      return shut;
    }
    // Admitted: the confirmed read was for this (non-null) user.
    final member = ref.watch(currentUserProvider)!.id;
    if (_member != member) {
      _member = member;
      final s = ++_session;
      reset();
      if (load != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (state.mounted && isCurrent(s)) load();
        });
      }
    }
    return null;
  }
}
