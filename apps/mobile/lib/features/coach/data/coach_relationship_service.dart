import 'package:supabase_flutter/supabase_flutter.dart';

class CoachRelationshipService {
  final _db = Supabase.instance.client;

  // ── Client sends coach request (pending) ──────────────────
  Future<void> requestCoach(String coachId, {String? message}) async {
    final clientId = _db.auth.currentUser?.id;
    if (clientId == null) return;
    await _db.from('coach_client_relationships').upsert({
      'client_id': clientId,
      'coach_id': coachId,
      'status': 'pending',
      'initiated_by': 'client',
      'request_message': message,
      'pending_at': DateTime.now().toIso8601String(),
    }, onConflict: 'client_id,coach_id');
    // Notify coach
    await _db.from('notifications').insert({
      'recipient_id': coachId,
      'type': 'coach_request',
      'title': 'New Coaching Request',
      'body': 'A new client is requesting you as their coach.',
      'data': {'client_id': clientId},
      'read': false,
    });
  }

  // ── Coach approves a pending request ──────────────────────
  Future<void> approveRequest(String relationshipId, String clientId) async {
    await _db.from('coach_client_relationships').update({
      'status': 'active',
      'activated_at': DateTime.now().toIso8601String(),
    }).eq('id', relationshipId);
    // Notify client
    await _db.from('notifications').insert({
      'recipient_id': clientId,
      'type': 'request_approved',
      'title': 'Coach Request Approved',
      'body': 'Your coach has accepted your request. You can now start working together!',
      'read': false,
    });
  }

  // ── Coach declines a pending request ─────────────────────
  Future<void> declineRequest(String relationshipId, String clientId) async {
    await _db.from('coach_client_relationships').update({
      'status': 'rejected',
    }).eq('id', relationshipId);
    await _db.from('notifications').insert({
      'recipient_id': clientId,
      'type': 'request_declined',
      'title': 'Coach Request Update',
      'body': 'Your coaching request was not accepted. Browse other coaches to find your match.',
      'read': false,
    });
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
    final profiles = await _db
        .from('user_profiles')
        .select('id, first_name, last_name, email, avatar_url, fitness_goal, weight_kg')
        .inFilter('id', clientIds);
    final profileMap = {for (final p in (profiles as List)) p['id']: p};
    return rels.map((r) => {
      ...r,
      'profile': profileMap[r['client_id']] ?? {},
    }).toList();
  }

  // ── Send email invite to a client (creates row + sends the email) ─────────
  Future<String> sendInvite(String coachId, String email) async {
    final result = await _db.from('coach_invites').insert({
      'coach_id': coachId,
      'invitee_email': email,
    }).select().single();
    final token = result['token'] as String?;
    // Deliver the actual email.
    try {
      await _db.functions.invoke('send-invite-email',
          body: {'email': email, 'type': 'client', if (token != null) 'token': token});
    } catch (_) {}
    return token ?? '';
  }

  // ── Cancel as client (ends relationship + notifies the coach) ─────────────
  Future<void> cancelCoach(String coachId, String? reason, String? customReason) async {
    final clientId = _db.auth.currentUser?.id;
    if (clientId == null) return;
    await _db.from('coach_client_relationships').update({
      'status': 'cancelled',
      'cancelled_by': 'client',
      'cancel_reason': reason,
      'cancel_reason_custom': customReason,
      'cancelled_at': DateTime.now().toIso8601String(),
    }).eq('client_id', clientId).eq('coach_id', coachId).eq('status', 'active');
    // Notify the coach that the client has ended the relationship.
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
  }

  // ── Coach pricing ─────────────────────────────────────────
  /// Global monthly price shown in the marketplace and used by default.
  Future<void> setGlobalPrice(double price) async {
    final coachId = _db.auth.currentUser?.id;
    if (coachId == null) return;
    await _db.from('user_profiles').update({'pricing_monthly': price}).eq('id', coachId);
  }

  /// Per-client custom price (null clears the override → falls back to global).
  Future<void> setClientPrice(String clientId, double? price) async {
    final coachId = _db.auth.currentUser?.id;
    if (coachId == null) return;
    await _db
        .from('coach_client_relationships')
        .update({'monthly_price': price})
        .eq('coach_id', coachId)
        .eq('client_id', clientId);
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
    // H-06 / 3A-7: repointed at public_profiles. getPendingRequests() below is
    // the coach-facing half of H-06 and stays on user_profiles — blocked on
    // Q-H1, not touched here.
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
