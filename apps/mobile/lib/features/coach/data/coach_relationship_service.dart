import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/observability/app_failure.dart';

class CoachRelationshipService {
  final _db = Supabase.instance.client;

  // ── Client sends coach request (pending) ──────────────────
  Future<void> requestCoach(String coachId, {String? message}) async {
    final clientId = _requireSignedIn();
    // The upsert below rewrites `status` on an existing row. Over an ACTIVE row
    // that demotes the client's own coach to pending — off the coach's roster,
    // and the client off coach-guided access — and RLS allows it: 113 lets a
    // client amend their own row. A request is for a coach they are not with.
    final existing = await _db
        .from('coach_client_relationships')
        .select('status')
        .eq('client_id', clientId)
        .eq('coach_id', coachId);
    if ((existing as List).any((r) => r['status'] == 'active')) {
      throw StateError('This coach is already your coach.');
    }
    await _db.from('coach_client_relationships').upsert({
      'client_id': clientId,
      'coach_id': coachId,
      'status': 'pending',
      'initiated_by': 'client',
      'request_message': message,
      'pending_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'client_id,coach_id');
    // Notify coach
    // Best-effort, and reported: the change above is saved, and a failed
    // notification thrown from here read as a failed save (N3).
    try {
      await _db.from('notifications').insert({
        'recipient_id': coachId,
        'type': 'coach_request',
        'title': 'New Coaching Request',
        'body': 'A new client is requesting you as their coach.',
        'data': {'client_id': clientId},
        'read': false,
      });
    } catch (e) {
      reportError('CoachRelationshipService.requestCoach.notify', e);
    }
  }


  /// The signed-in user's id. Signed out, a relationship write writes nothing,
  /// and returning normally read as success: "Request sent!" / "Coaching
  /// ended." (P0-FL-1).
  String _requireSignedIn() {
    final id = _db.auth.currentUser?.id;
    if (id == null) {
      throw StateError('You are signed out — nothing was changed. Sign in and try again.');
    }
    return id;
  }

  /// A request answer that matched no row is not an answer (QAX-ERR-02): RLS
  /// filters out a relationship that is not this coach's, or one already
  /// answered, without an error — and the screen said "Client accepted!".
  void _requireAnswered(List<dynamic> rows) {
    if (rows.isEmpty) {
      throw StateError('That request is no longer pending — nothing was changed.');
    }
  }

  // ── Coach approves a pending request ──────────────────────
  Future<void> approveRequest(String relationshipId, String clientId) async {
    final rows = await _db.from('coach_client_relationships').update({
      'status': 'active',
      'activated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', relationshipId).eq('status', 'pending').select('id');
    _requireAnswered(rows);
    // Notify client
    // Best-effort, and reported: the change above is saved, and a failed
    // notification thrown from here read as a failed save (N3).
    try {
      await _db.from('notifications').insert({
        'recipient_id': clientId,
        'type': 'request_approved',
        'title': 'Coach Request Approved',
        'body': 'Your coach has accepted your request. You can now start working together!',
        'read': false,
      });
    } catch (e) {
      reportError('CoachRelationshipService.approveRequest.notify', e);
    }
  }

  // ── Coach declines a pending request ─────────────────────
  Future<void> declineRequest(String relationshipId, String clientId) async {
    final rows = await _db.from('coach_client_relationships').update({
      'status': 'rejected',
    }).eq('id', relationshipId).eq('status', 'pending').select('id');
    _requireAnswered(rows);
    // Best-effort, and reported: the change above is saved, and a failed
    // notification thrown from here read as a failed save (N3).
    try {
      await _db.from('notifications').insert({
        'recipient_id': clientId,
        'type': 'request_declined',
        'title': 'Coach Request Update',
        'body': 'Your coaching request was not accepted. Browse other coaches to find your match.',
        'read': false,
      });
    } catch (e) {
      reportError('CoachRelationshipService.declineRequest.notify', e);
    }
  }

  // ── Fetch pending requests for a coach ───────────────────
  Future<List<Map<String, dynamic>>> getPendingRequests(String coachId) async {
    final rels = await _db
        .from('coach_client_relationships')
        .select('id, client_id, request_message, pending_at, initiated_by')
        .eq('coach_id', coachId)
        .eq('status', 'pending')
        .order('pending_at', ascending: false);
    if ((rels as List).isEmpty) return [];
    final clientIds = rels.map((r) => r['client_id'] as String).toList();
    // P0-FL-38 / H-06. This read `user_profiles` for `email, fitness_goal,
    // weight_kg` too — health data for people who are not (yet) this coach's
    // clients. And it never arrived: user_profiles admits a coach only to an
    // ACTIVE client's row (`is_active_coach_of`), so every pending card had no
    // name ("New Client") and no avatar. Names and avatars come from
    // public_profiles, readable for any user and carrying no email, contact or
    // health column (migrations 101/110). No email is read: public_profiles has
    // none by design. Whether a coach may see more of a requester (goal,
    // email) is owner decision Q-H1 (QA_WORKSTREAM_H report §9) and would need
    // a new scoped path; this is the report's "minimum safe fix now".
    final profiles = await _db
        .from('public_profiles')
        .select('id, first_name, last_name, avatar_url')
        .inFilter('id', clientIds);
    final profileMap = {
      for (final p in (profiles as List))
        p['id']: Map<String, dynamic>.from(p as Map),
    };
    return rels.map((r) => {
      ...r,
      // Typed: an untyped `{}` here is a Map<dynamic, dynamic>, and the
      // Requests tab's `as Map<String, dynamic>?` threw on it while building —
      // which, under the live policy, was every pending request.
      'profile': profileMap[r['client_id']] ?? const <String, dynamic>{},
    }).toList();
  }

  // ── Send email invite to a client (creates row + sends the email) ─────────
  //
  // Throws if either step fails. The email is the invite — the client is sent
  // nothing else — so a failed send is a failed invite. It was swallowed, and
  // the coach was told "Invite sent!" for an email that never left.
  Future<String> sendInvite(String coachId, String email) async {
    final result = await _db.from('coach_invites').insert({
      'coach_id': coachId,
      'invitee_email': email,
    }).select().single();
    final token = result['token'] as String?;
    // Deliver the actual email.
    await _db.functions.invoke('send-invite-email',
        body: {'email': email, 'type': 'client', if (token != null) 'token': token});
    return token ?? '';
  }

  // ── End coaching as client ───────────────────────────────────────────────
  /// Ends the client's coaching with [coachId] -- the ONE policy every "end
  /// coaching" path uses (Profile's Cancel Coach, Settings' switch to Self/AI,
  /// Manage Subscription's Stop, the intake coach switch).
  ///
  /// OWNER DECISION 2, 2026-11-15 (Julia): a paid coaching subscription is
  /// cancelled at the END of the period already paid for, and coaching lasts
  /// until then -- no refund needed. So:
  ///   * a live paid coaching subscription with this coach (coach or monthly
  ///     package) is cancelled at period end through `cancel-subscription`, and
  ///     the relationship stays active; the Stripe webhook ends it when the
  ///     subscription does. Returns [CoachingEnd.at] that date.
  ///   * no paid subscription: the relationship ends now, as before.
  /// Before this, every path except one ended only the relationship and left
  /// the subscription billing -- and the one that cancelled missed monthly
  /// packages, the coaching subscription the app actually sells.
  ///
  /// Throws if a cancellation fails, if no active relationship was ended, or
  /// if no one is signed in; nothing is then changed locally.
  Future<CoachingEnd> cancelCoach(String coachId, String? reason, String? customReason) async {
    final clientId = _requireSignedIn();
    final paid = await _db
        .from('subscriptions')
        .select('id, current_period_end')
        .eq('user_id', clientId)
        .eq('coach_id', coachId)
        .inFilter('kind', const ['coach', 'package_monthly'])
        .inFilter('status', const ['active', 'trialing', 'past_due']);
    if ((paid as List).isNotEmpty) {
      DateTime? endsAt;
      for (final s in paid) {
        final res = await _db.functions
            .invoke('cancel-subscription', body: {'subscriptionId': s['id']});
        final d = res.data;
        if (d is! Map || d['ok'] != true) {
          throw StateError('Your coaching could not be ended. Try again.');
        }
        final at = DateTime.tryParse('${d['endsAt'] ?? s['current_period_end'] ?? ''}');
        if (at != null && (endsAt == null || at.isAfter(endsAt))) endsAt = at;
      }
      return CoachingEnd.at((endsAt ?? DateTime.now()).toLocal());
    }
    final ended = await _db.from('coach_client_relationships').update({
      'status': 'cancelled',
      'cancelled_by': 'client',
      'cancel_reason': reason,
      'cancel_reason_custom': customReason,
      'cancelled_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('client_id', clientId).eq('coach_id', coachId).eq('status', 'active').select('id');
    // A 0-row update ended nothing (RLS refusal, already ended, wrong coach):
    // it was reported as "Coaching ended." and the coach was told so (P0-FL-1).
    // Refuse it before the notification, as approve/decline do (QAX-ERR-02).
    if ((ended as List).isEmpty) {
      throw StateError('No active coaching with this coach — nothing was changed.');
    }
    // Notify the coach that the client has ended the relationship.
    // Best-effort, and reported: the change above is saved, and a failed
    // notification thrown from here read as a failed save (N3).
    try {
      final me = await _db
          .from('user_profiles')
          .select('first_name, last_name')
          .eq('id', clientId)
          .maybeSingle();
      final name = '${me?['first_name'] ?? ''} ${me?['last_name'] ?? ''}'.trim();
      await _db.from('notifications').insert({
        'recipient_id': coachId,
        'type': 'coaching_ended',
        'title': 'A client ended coaching',
        'body': '${name.isEmpty ? 'A client' : name} has stopped working with you.',
        'data': {'client_id': clientId},
        'read': false,
      });
    } catch (e) {
      reportError('CoachRelationshipService.cancelCoach.notify', e);
    }
    return const CoachingEnd.now();
  }

  // ── Coach pricing ─────────────────────────────────────────
  /// Global monthly price shown in the marketplace and used by default.
  ///
  /// Throws if no one is signed in or the update changed no row (P0-FL-3):
  /// both returned normally and the sheet said "Pricing updated." for a price
  /// that was never saved.
  Future<void> setGlobalPrice(double price) async {
    final coachId = _requireSignedIn();
    final rows = await _db
        .from('user_profiles')
        .update({'pricing_monthly': price})
        .eq('id', coachId)
        .select('id');
    if ((rows as List).isEmpty) {
      throw StateError(
          "Your price couldn't be saved. Nothing was changed — try again.");
    }
  }

  /// Per-client custom price (null clears the override → falls back to global).
  ///
  /// Throws if no one is signed in or the update changed no row (P0-FL-3): a
  /// 0-row update (no relationship with this client, RLS refusal) was reported
  /// as "Custom price set", while checkout kept charging the standard rate.
  Future<void> setClientPrice(String clientId, double? price) async {
    final coachId = _requireSignedIn();
    final rows = await _db
        .from('coach_client_relationships')
        .update({'monthly_price': price})
        .eq('coach_id', coachId)
        .eq('client_id', clientId)
        .select('id');
    if ((rows as List).isEmpty) {
      throw StateError(
          'No coaching relationship with this client — nothing was changed.');
    }
  }

  /// All of the client's active coaches (supports working with several at once).
  Future<List<Map<String, dynamic>>> getMyActiveCoaches() async {
    final clientId = _db.auth.currentUser?.id;
    if (clientId == null) return [];
    final rels = await _db
        .from('coach_client_relationships')
        .select('id, coach_id, status, specialty, monthly_price, activated_at')
        .eq('client_id', clientId)
        .eq('status', 'active');
    final list = List<Map<String, dynamic>>.from(rels);
    if (list.isEmpty) return [];
    final ids = list.map((r) => r['coach_id'] as String).toList();
    // H-06 / 3A-7: repointed at public_profiles. getPendingRequests() above,
    // the coach-facing half of H-06, followed in P0-FL-38.
    final profiles = await _db
        .from('public_profiles')
        .select('id, first_name, last_name, avatar_url, coach_title, specialties, pricing_monthly')
        .inFilter('id', ids);
    final byId = {for (final p in profiles as List) p['id'] as String: p};
    return [for (final r in list) {...r, 'coach': byId[r['coach_id']] ?? {}}];
  }

  // ── Get client's current relationship status ──────────────
  Future<Map<String, dynamic>?> getMyRelationship() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return null;
    return await _db
        .from('coach_client_relationships')
        .select('id, coach_id, status, pending_at, activated_at, request_message')
        .eq('client_id', userId)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }
}

/// What ending coaching did: ended now, or (a paid subscription) ends at
/// [endsAt], the end of the period already paid for.
class CoachingEnd {
  const CoachingEnd.now() : endsAt = null;
  const CoachingEnd.at(DateTime this.endsAt);
  final DateTime? endsAt;
  bool get scheduled => endsAt != null;

  /// One sentence for the client.
  String describe() {
    final at = endsAt;
    if (at == null) return 'Coaching ended. Your coach has been notified.';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return 'Your coaching continues until ${m[at.month - 1]} ${at.day}, the end of the '
        'period you have paid for, then ends. Your coach has been notified.';
  }
}
