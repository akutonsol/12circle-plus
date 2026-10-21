import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/auth_provider.dart';
import '../data/coach_relationship_service.dart';

final _db = Supabase.instance.client;
final _relSvc = CoachRelationshipService();

// ── Active coach for the current client (returns null if only pending) ────────
final assignedCoachProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  try {
    // A client may have several active coaches now; this returns the primary
    // (most recent) one for single-coach UI. Use myCoachesProvider for the list.
    final rel = await _db
        .from('coach_client_relationships')
        .select('coach_id, status')
        .eq('client_id', user.id)
        .eq('status', 'active')
        .order('activated_at', ascending: false, nullsFirst: false)
        .limit(1)
        .maybeSingle();
    final coachId = rel?['coach_id'] as String?;
    if (coachId == null) return null;
    // H-06 / 3A-7: repointed at public_profiles, which never carries email.
    return await _db
        .from('public_profiles')
        .select('id, first_name, last_name, avatar_url, coach_title, coach_bio, specialties, certifications, pricing_monthly, years_experience, rating_avg')
        .eq('id', coachId)
        .maybeSingle();
  } catch (_) { return null; }
});

// ── Pending coach request (for showing "Request Sent" state) ─────────────────
final pendingCoachProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  try {
    final rel = await _db
        .from('coach_client_relationships')
        .select('coach_id, status, pending_at')
        .eq('client_id', user.id)
        .eq('status', 'pending')
        .maybeSingle();
    final coachId = rel?['coach_id'] as String?;
    if (coachId == null) return null;
    // H-06 / 3A-7: repointed at public_profiles.
    final coach = await _db
        .from('public_profiles')
        .select('id, first_name, last_name, avatar_url, coach_title')
        .eq('id', coachId)
        .maybeSingle();
    if (coach == null) return null;
    return {...coach, 'pending_at': rel?['pending_at']};
  } catch (_) { return null; }
});

// ── Today's tip from the assigned coach (rotates daily) ──────────────────────
final coachTipProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final coach = ref.watch(assignedCoachProvider).valueOrNull;
  final coachId = coach?['id'] as String?;
  if (coachId == null) return null;
  try {
    final tips = await _db
        .from('coach_tips')
        .select('id, content, category')
        .eq('coach_id', coachId)
        .eq('active', true)
        .order('created_at');
    if (tips.isEmpty) return null;
    final idx = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    return tips[idx % tips.length];
  } catch (_) { return null; }
});

// ── All of the client's active coaches (multi-coach support) ──────────────────
final myCoachesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  ref.watch(currentUserProvider);
  return _relSvc.getMyActiveCoaches();
});

// ── Written reviews for a coach (newest first, with reviewer name) ────────────
final coachReviewsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, coachId) async {
  try {
    final rows = await _db
        .from('coach_reviews')
        .select('rating, review_text, created_at, client_id')
        .eq('coach_id', coachId)
        .order('created_at', ascending: false);
    final list = List<Map<String, dynamic>>.from(rows);
    if (list.isEmpty) return list;
    final ids = list.map((r) => r['client_id'] as String).toSet().toList();
    // H-06 / 3A-7: repointed at public_profiles.
    final profiles = await _db
        .from('public_profiles')
        .select('id, first_name, last_name, avatar_url')
        .inFilter('id', ids);
    final byId = {for (final p in profiles as List) p['id'] as String: p};
    return [
      for (final r in list) {...r, 'reviewer': byId[r['client_id']] ?? {}}
    ];
  } catch (_) {
    return [];
  }
});

// ── Coaches available to browse (accepting clients, not at capacity) ──────────
final availableCoachesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    final coaches = await _db
        .from('public_profiles')
        .select('id, first_name, last_name, avatar_url, coach_title, bio, coach_bio, tagline, max_clients, is_accepting_clients, specialties, certifications, pricing_monthly, years_experience, rating_avg, review_count, transformation_photo_urls')
        .eq('role', 'coach')
        .eq('is_accepting_clients', true);

    final coachIds = [for (final c in coaches) c['id'] as String];

    // Cheapest active monthly package per coach — used as a pricing fallback
    // when the coach hasn't set a monthly rate on their profile.
    final lowestMonthly = <String, double>{};
    // Active clients per coach, counted as DISTINCT client_ids (duplicate or
    // orphaned relationship rows would otherwise inflate the number and diverge
    // from the coach dashboard, which counts distinct clients).
    final activeByCoach = <String, int>{};
    if (coachIds.isNotEmpty) {
      final pkgs = await _db
          .from('coach_packages')
          .select('coach_id, price')
          .inFilter('coach_id', coachIds)
          .eq('type', 'monthly')
          .eq('active', true);
      for (final p in (pkgs as List)) {
        final cid = p['coach_id'] as String;
        final price = (p['price'] as num?)?.toDouble() ?? 0;
        if (price <= 0) continue;
        final cur = lowestMonthly[cid];
        if (cur == null || price < cur) lowestMonthly[cid] = price;
      }

      // Capacity comes from an aggregate RPC, not from reading the relationship
      // rows. coach_client_relationships is the authorization root and migration
      // 113 scopes it to the two parties, so a client browsing the marketplace
      // now sees zero rows for every coach but their own -- which would render
      // every full coach as available. coach_active_client_counts() returns the
      // DISTINCT active-client count per coach and nothing else.
      final counts = await _db.rpc('coach_active_client_counts',
          params: {'coach_ids': coachIds});
      for (final r in (counts as List)) {
        final coachId = r['coach_id'] as String?;
        if (coachId == null) continue;
        activeByCoach[coachId] = (r['active_clients'] as num?)?.toInt() ?? 0;
      }
    }

    // Filter out coaches at capacity
    final result = <Map<String, dynamic>>[];
    for (final c in coaches) {
      final cid = c['id'] as String;
      final active = activeByCoach[cid] ?? 0;
      final max = (c['max_clients'] as int?) ?? 20;
      // Profile rate wins; otherwise fall back to the cheapest monthly package.
      final profilePrice = (c['pricing_monthly'] as num?)?.toDouble() ?? 0;
      final effectivePrice =
          profilePrice > 0 ? profilePrice : (lowestMonthly[cid] ?? 0);
      // Bio lives in `bio` (Coach Business screen + marketplace); `coach_bio` is
      // the legacy column. Normalize to coach_bio so the UI reads one field.
      final newBio = (c['bio'] as String?)?.trim() ?? '';
      final legacyBio = (c['coach_bio'] as String?)?.trim() ?? '';
      result.add({
        ...c,
        'pricing_monthly': effectivePrice,
        'coach_bio': newBio.isNotEmpty ? newBio : legacyBio,
        'active_clients': active,
        'is_full': active >= max,
      });
    }
    return result;
  } catch (_) { return []; }
});

// ── Relationship status for the current client ────────────────────────────────
final clientRelationshipProvider = FutureProvider<Map<String, dynamic>?>((ref) async {
  final user = ref.watch(currentUserProvider);
  if (user == null) return null;
  try {
    return await _db
        .from('coach_client_relationships')
        .select('id, coach_id, status, created_at, activated_at')
        .eq('client_id', user.id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  } catch (_) { return null; }
});
