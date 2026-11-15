import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/observability/app_failure.dart';

/// What redeeming a remembered invite did.
enum InviteOutcome {
  /// No invite was waiting, or nobody is signed in yet.
  none,

  /// The client is now linked to the coach who invited them.
  linked,

  /// The invite is not valid for this account (expired, already used, sent to
  /// another email). It is forgotten.
  invalid,

  /// It could not be redeemed right now (network, or the server does not have
  /// the invite function yet). It is kept for the next sign-in.
  notYet,
}

/// A coach's invite, from the link in the invite email
/// (`/#/signup?invite=<token>`) to the moment the client is signed in.
///
/// OWNER DECISION 4, 2026-11-15 (Julia): signing up from the invite link --
/// matching email, unexpired, single use -- creates an active relationship
/// marked coach-invited (0% commission); paid access then follows decision 1.
///
/// Until now nothing read the token: an invite never linked anyone. The token
/// is remembered on the device when the link is opened (sign-up usually needs
/// an email confirmation in between) and redeemed through
/// `accept_coach_invite` (migration 194), which checks everything server-side
/// and tells both parties.
class PendingInvite {
  PendingInvite._();

  static const storageKey = 'pending_coach_invite';
  static Future<InviteOutcome>? _inFlight;

  /// Remembers [token] from an invite link. A blank token is ignored.
  static Future<void> capture(String? token) async {
    final t = token?.trim() ?? '';
    if (t.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, t);
  }

  /// Redeems the remembered invite for the signed-in account. Calls that
  /// overlap share one attempt: an invite is single use, so a second attempt
  /// would report the invite just used as invalid.
  static Future<InviteOutcome> redeem(SupabaseClient db) =>
      _inFlight ??= _redeem(db).whenComplete(() => _inFlight = null);

  static Future<InviteOutcome> _redeem(SupabaseClient db) async {
    if (db.auth.currentUser == null) return InviteOutcome.none;
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(storageKey);
    if (token == null || token.isEmpty) return InviteOutcome.none;
    try {
      await db.rpc('accept_coach_invite', params: {'p_token': token});
      await prefs.remove(storageKey);
      return InviteOutcome.linked;
    } on PostgrestException catch (e) {
      // 42501 is the server's one answer for "not valid for you".
      if (e.code == '42501') {
        await prefs.remove(storageKey);
        reportError('PendingInvite.redeem.invalid', e);
        return InviteOutcome.invalid;
      }
      reportError('PendingInvite.redeem', e);
      return InviteOutcome.notYet;
    } catch (e) {
      reportError('PendingInvite.redeem', e);
      return InviteOutcome.notYet;
    }
  }
}
